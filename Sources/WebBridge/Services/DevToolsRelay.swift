import Foundation
import Network

/// A loopback WebSocket reverse-proxy for one device debug port.
///
/// Android WebView / Chrome 111+ reject debugger WebSocket handshakes whose `Origin` header
/// isn't allowlisted, which is why DevTools loaded from the hosted frontend disconnects. This
/// relay terminates the browser's WebSocket and re-originates it to the device with a
/// non-browser client (URLSession sends no `Origin`), so the device accepts it. Debug traffic
/// stays entirely on 127.0.0.1.
final class DevToolsRelay: @unchecked Sendable {
    let devicePort: Int
    let token = UUID().uuidString
    private(set) var localPort: Int = 0

    private let queue = DispatchQueue(label: "webbridge.relay")
    private var listener: NWListener?
    private let lock = NSLock()
    private var connections: Set<RelayConnection> = []

    init(devicePort: Int) { self.devicePort = devicePort }

    func start() async -> Int? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let box = LockedBox<CheckedContinuation<Int?, Never>?>(continuation)
            let finish: @Sendable (Int?) -> Void = { value in
                let pending = box.withLock { held -> CheckedContinuation<Int?, Never>? in
                    let taken = held
                    held = nil
                    return taken
                }
                pending?.resume(returning: value)
            }

            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 0)
                let listener = try NWListener(using: params)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        if let port = self?.listener?.port?.rawValue {
                            self?.localPort = Int(port)
                            finish(Int(port))
                        } else {
                            finish(nil)
                        }
                    case .failed, .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            } catch {
                finish(nil)
            }
        }
    }

    func stop() {
        listener?.cancel()
        lock.lock()
        let active = connections
        connections.removeAll()
        lock.unlock()
        for connection in active { connection.close() }
    }

    private func accept(_ connection: NWConnection) {
        let relay = RelayConnection(browser: connection, devicePort: devicePort, token: token, queue: queue) { [weak self] finished in
            self?.remove(finished)
        }
        lock.lock(); connections.insert(relay); lock.unlock()
        relay.start()
    }

    private func remove(_ connection: RelayConnection) {
        lock.lock(); connections.remove(connection); lock.unlock()
    }
}

/// One browser WebSocket bridged to one device WebSocket. All state is confined to the relay's
/// serial queue; URLSession callbacks hop back onto it.
private final class RelayConnection: Hashable, @unchecked Sendable {
    private let browser: NWConnection
    private let devicePort: Int
    private let token: String
    private let queue: DispatchQueue
    private let onClose: (RelayConnection) -> Void

    private var deviceTask: URLSessionWebSocketTask?
    private var buffer = Data()
    private var upgraded = false
    private var closed = false
    private var fragmentOpcode: UInt8 = 0
    private var fragmentData = Data()

    private static let separator = Data("\r\n\r\n".utf8)

    init(browser: NWConnection, devicePort: Int, token: String, queue: DispatchQueue,
         onClose: @escaping (RelayConnection) -> Void) {
        self.browser = browser
        self.devicePort = devicePort
        self.token = token
        self.queue = queue
        self.onClose = onClose
    }

    static func == (lhs: RelayConnection, rhs: RelayConnection) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    func start() {
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        browser.start(queue: queue)
        receiveFromBrowser()
    }

    func close() {
        queue.async { [weak self] in self?.closeNow() }
    }

    private func closeNow() {
        guard !closed else { return }
        closed = true
        deviceTask?.cancel(with: .goingAway, reason: nil)
        browser.cancel()
        onClose(self)
    }

    // MARK: Browser side

    private func receiveFromBrowser() {
        browser.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if error != nil || isComplete { self.closeNow(); return }
            if !self.closed { self.receiveFromBrowser() }
        }
    }

    private func processBuffer() {
        if !upgraded {
            guard let range = buffer.range(of: Self.separator) else { return }
            let header = buffer.subdata(in: 0..<range.upperBound)
            buffer.removeSubrange(0..<range.upperBound)
            performHandshake(header)
            if !upgraded { return }
        }
        parseFrames()
    }

    private func performHandshake(_ header: Data) {
        guard let text = String(data: header, encoding: .utf8) else { closeNow(); return }

        // only our own frontend URL carries the token; reject any other local client that finds the port.
        let (path, requestToken) = RelayHandshake.splitToken(RelayHandshake.requestPath(from: text))
        guard requestToken == token else { closeNow(); return }
        guard let key = RelayHandshake.webSocketKey(from: text) else { closeNow(); return }

        let accept = WebSocketFrame.acceptKey(key)
        let response = "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        browser.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
        upgraded = true
        connectDevice(path: path)
    }

    private func sendToBrowser(opcode: UInt8, payload: Data) {
        guard !closed else { return }
        browser.send(content: WebSocketFrame.encode(opcode: opcode, payload: payload),
                     completion: .contentProcessed { _ in })
    }

    // MARK: Frame decoding (browser → device)

    private func parseFrames() {
        while let frame = WebSocketFrame.decode(&buffer) {
            handle(opcode: frame.opcode, fin: frame.fin, payload: frame.payload)
            if closed { return }
        }
    }

    private func handle(opcode: UInt8, fin: Bool, payload: Data) {
        switch opcode {
        case 0x0:
            fragmentData.append(payload)
            if fin { forwardToDevice(opcode: fragmentOpcode, data: fragmentData); fragmentData.removeAll(); fragmentOpcode = 0 }
        case 0x1, 0x2:
            if fin {
                forwardToDevice(opcode: opcode, data: payload)
            } else {
                fragmentOpcode = opcode
                fragmentData = payload
            }
        case 0x8:
            closeNow()
        case 0x9:
            sendToBrowser(opcode: 0xA, payload: payload)
        default:
            break
        }
    }

    // MARK: Device side

    private func connectDevice(path: String) {
        guard let url = URL(string: "ws://127.0.0.1:\(devicePort)\(path)") else { closeNow(); return }
        let task = URLSession.shared.webSocketTask(with: url)
        deviceTask = task
        task.resume()
        receiveFromDevice()
    }

    private func forwardToDevice(opcode: UInt8, data: Data) {
        guard let task = deviceTask else { return }
        if opcode == 0x1 {
            task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
        } else {
            task.send(.data(data)) { _ in }
        }
    }

    private func receiveFromDevice() {
        deviceTask?.receive { [weak self] result in
            guard let self else { return }
            self.queue.async { self.onDeviceMessage(result) }
        }
    }

    private func onDeviceMessage(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        guard !closed else { return }
        switch result {
        case .failure:
            closeNow()
        case .success(let message):
            switch message {
            case .string(let string): sendToBrowser(opcode: 0x1, payload: Data(string.utf8))
            case .data(let data): sendToBrowser(opcode: 0x2, payload: data)
            @unknown default: break
            }
            receiveFromDevice()
        }
    }
}
