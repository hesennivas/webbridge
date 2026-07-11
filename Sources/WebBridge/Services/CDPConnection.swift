import Foundation

enum CDPEvent: Sendable {
    case console(ConsoleEntry)
    case navigated(String)
    case network(NetworkSignal)
    case closed
}

/// A single live debugging session over a WebSocket.
///
/// Two dialects share this transport:
///   * **Chrome / Android** speak flat Chrome DevTools Protocol: `{id, method, params}` in,
///     replies and events straight back out.
///   * **iOS Safari / WebViews** speak WebKit's Web Inspector protocol, which multiplexes every
///     domain under the `Target` domain. The top-level connection only exposes `Target`; real
///     commands must be wrapped in `Target.sendMessageToTarget` addressed to a page target, and
///     their replies/events arrive wrapped in `Target.dispatchMessageFromTarget`. The page
///     `targetId` isn't known until the device emits `Target.targetCreated`, so commands issued
///     before then wait on `targetWaiters`. Console output also differs: WebKit emits
///     `Console.messageAdded` rather than `Runtime.consoleAPICalled`.
actor CDPConnection {
    let events: AsyncStream<CDPEvent>

    private let socket: URLSessionWebSocketTask
    private let ids: Sequence64
    private let eventContinuation: AsyncStream<CDPEvent>.Continuation
    private let webkit: Bool
    private var nextRequestID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var receiveTask: Task<Void, Never>?
    private var closed = false

    private var targetId: String?
    private var targetWaiters: [CheckedContinuation<Void, Never>] = []

    init(url: URL, ids: Sequence64, webkit: Bool) {
        self.ids = ids
        self.webkit = webkit
        self.socket = URLSession.shared.webSocketTask(with: url)
        var continuation: AsyncStream<CDPEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    func start() {
        socket.resume()
        receiveTask = Task { await self.receiveLoop() }
        if webkit {
            // Domains are enabled once the page target arrives (see dispatch). Guard against a
            // device that never announces one so commands don't wait forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                await self?.releaseTargetWaiters()
            }
        } else {
            Task { await self.enableDomains() }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        receiveTask?.cancel()
        socket.cancel(with: .goingAway, reason: nil)
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
        pending.removeAll()
        releaseTargetWaiters()
        eventContinuation.finish()
    }

    func evaluate(_ expression: String) async throws -> String {
        var params: [String: Any] = ["expression": expression, "returnByValue": true, "generatePreview": true]
        if webkit {
            params["includeCommandLineAPI"] = true
            params["emulateUserGesture"] = true
        } else {
            params["awaitPromise"] = true
            params["replMode"] = true
            params["userGesture"] = true
        }
        let data = try await command("Runtime.evaluate", params)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        // Chrome reports failures via exceptionDetails; WebKit sets wasThrown and puts the thrown
        // value in result.
        if let exception = object["exceptionDetails"] as? [String: Any] {
            return CDPFormat.exceptionText(exception)
        }
        if let result = object["result"] as? [String: Any] {
            if (object["wasThrown"] as? Bool) == true {
                let described = CDPFormat.remoteObject(result)
                return described.isEmpty ? "evaluation failed" : described
            }
            return CDPFormat.remoteObject(result)
        }
        return ""
    }

    func reload() async { _ = try? await command("Page.reload", ["ignoreCache": true]) }

    // MARK: - Storage & detection

    /// reads cookies plus local/session storage in one shot; used by the Storage pane.
    func fetchStorage() async -> StorageSnapshot {
        async let cookies = fetchCookies()
        async let local = storageItems("localStorage")
        async let session = storageItems("sessionStorage")
        return StorageSnapshot(cookies: await cookies, local: await local, session: await session)
    }

    /// evaluates the framework probe; returns a name or nil.
    func detectFramework() async -> String? {
        let result = ((try? await evaluate(FrameworkDetection.probe)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "undefined" ? nil : result
    }

    private func storageItems(_ which: String) async -> [StorageItem] {
        guard let value = await rawEvaluate("JSON.stringify(Object.entries(\(which)))") as? String,
              let data = value.data(using: .utf8),
              let pairs = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
        return pairs.compactMap { $0.count == 2 ? StorageItem(key: $0[0], value: $0[1]) : nil }
            .sorted { $0.key < $1.key }
    }

    private func fetchCookies() async -> [StorageCookie] {
        // Chrome exposes richer cookie metadata (httpOnly/secure) via Network.getCookies; WebKit
        // targets fall back to document.cookie, which omits httpOnly entries.
        if !webkit, let data = try? await command("Network.getCookies"),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = object["cookies"] as? [[String: Any]] {
            return raw.map {
                StorageCookie(
                    name: $0["name"] as? String ?? "",
                    value: $0["value"] as? String ?? "",
                    domain: $0["domain"] as? String ?? "",
                    path: $0["path"] as? String ?? "/",
                    secure: $0["secure"] as? Bool ?? false,
                    httpOnly: $0["httpOnly"] as? Bool ?? false)
            }.sorted { $0.name < $1.name }
        }
        guard let value = await rawEvaluate("document.cookie") as? String, !value.isEmpty else { return [] }
        return value.split(separator: ";").compactMap { pair in
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { return nil }
            return StorageCookie(name: kv[0], value: kv[1], domain: "", path: "/", secure: false, httpOnly: false)
        }.sorted { $0.name < $1.name }
    }

    /// like `evaluate` but returns the raw `result.value` instead of a display string.
    private func rawEvaluate(_ expression: String) async -> Any? {
        var params: [String: Any] = ["expression": expression, "returnByValue": true]
        if webkit { params["emulateUserGesture"] = true }
        guard let data = try? await command("Runtime.evaluate", params),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else { return nil }
        return result["value"]
    }

    // MARK: - Setup

    private func enableDomains() async {
        // WebKit has no Log domain and delivers console output through Console.enable; Chrome
        // uses Runtime + Log. Network is Chrome-only here.
        let domains = webkit ? ["Console.enable", "Runtime.enable", "Page.enable"]
                             : ["Runtime.enable", "Log.enable", "Page.enable", "Network.enable"]
        for domain in domains { _ = try? await command(domain) }
    }

    private func adoptTarget(_ id: String) {
        guard targetId == nil else { return }
        targetId = id
        releaseTargetWaiters()
        Task { await self.enableDomains() }
    }

    private func releaseTargetWaiters() {
        let waiters = targetWaiters
        targetWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func waitForTarget() async {
        guard webkit, targetId == nil, !closed else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if targetId != nil || closed { continuation.resume(); return }
            targetWaiters.append(continuation)
        }
    }

    // MARK: - Transport

    private func command(_ method: String, _ params: [String: Any] = [:]) async throws -> Data {
        guard !closed else { throw CancellationError() }
        await waitForTarget()
        guard !closed else { throw CancellationError() }

        nextRequestID += 1
        let requestID = nextRequestID
        let text = try encodeCommand(id: requestID, method: method, params: params)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[requestID] = continuation
            Task { await self.transmit(text, id: requestID) }
        }
    }

    /// Builds the wire text for a command, wrapping it for WebKit's Target domain when needed.
    /// The wrapper envelope gets its own id (from the same monotonic counter) so its bare ack is
    /// never mistaken for the inner reply that arrives via Target.dispatchMessageFromTarget.
    private func encodeCommand(id: Int, method: String, params: [String: Any]) throws -> String {
        var inner: [String: Any] = ["id": id, "method": method]
        if !params.isEmpty { inner["params"] = params }

        guard webkit, let targetId else {
            return String(decoding: try JSONSerialization.data(withJSONObject: inner), as: UTF8.self)
        }

        let innerText = String(decoding: try JSONSerialization.data(withJSONObject: inner), as: UTF8.self)
        nextRequestID += 1
        let envelope: [String: Any] = [
            "id": nextRequestID,
            "method": "Target.sendMessageToTarget",
            "params": ["targetId": targetId, "message": innerText]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
    }

    private func transmit(_ text: String, id: Int) async {
        do {
            try await socket.send(.string(text))
        } catch {
            if let continuation = pending.removeValue(forKey: id) { continuation.resume(throwing: error) }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let string): handle(Data(string.utf8))
                case .data(let data): handle(data)
                @unknown default: break
                }
            } catch {
                if !closed { eventContinuation.yield(.closed) }
                return
            }
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // WebKit target multiplexing: unwrap and reprocess the inner message. The wrapper's own
        // ack (a bare {result:{},id:<envelope>}) falls through to the id branch below and is
        // dropped there because no pending request was registered under the envelope id.
        if (object["method"] as? String) == "Target.dispatchMessageFromTarget",
           let params = object["params"] as? [String: Any],
           let inner = params["message"] as? String {
            handle(Data(inner.utf8))
            return
        }

        if let id = object["id"] as? Int {
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "CDP error"
                if let continuation = pending.removeValue(forKey: id) {
                    continuation.resume(throwing: ProcessError.launchFailed(message))
                }
            } else if let continuation = pending.removeValue(forKey: id) {
                let result = object["result"] as? [String: Any] ?? [:]
                let encoded = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
                continuation.resume(returning: encoded)
            }
            return
        }

        guard let method = object["method"] as? String,
              let params = object["params"] as? [String: Any] else { return }
        dispatch(method: method, params: params)
    }

    private func dispatch(method: String, params: [String: Any]) {
        switch method {
        case "Target.targetCreated":
            if let info = params["targetInfo"] as? [String: Any],
               (info["type"] as? String) == "page",
               let id = info["targetId"] as? String {
                adoptTarget(id)
            }

        case "Runtime.consoleAPICalled":
            let type = params["type"] as? String ?? "log"
            let args = params["args"] as? [[String: Any]] ?? []
            let stackTrace = params["stackTrace"] as? [String: Any]
            let entry = ConsoleEntry(
                id: ids.next(),
                level: CDPFormat.consoleLevel(type),
                kind: .message,
                text: CDPFormat.consoleArgs(args),
                source: CDPFormat.topSource(stackTrace),
                stack: CDPFormat.stack(stackTrace))
            eventContinuation.yield(.console(entry))

        case "Console.messageAdded":
            // WebKit's console channel. `parameters` mirrors Chrome's RemoteObject args; `text`
            // is the pre-rendered fallback. Line numbers here are already 1-based.
            let message = params["message"] as? [String: Any] ?? [:]
            let parameters = message["parameters"] as? [[String: Any]] ?? []
            let text = parameters.isEmpty ? (message["text"] as? String ?? "")
                                          : CDPFormat.consoleArgs(parameters)
            let stackTrace = message["stackTrace"] as? [String: Any]
            let source = CDPFormat.shortSource(message["url"] as? String ?? "",
                                               line: message["line"] as? Int)
            let level = (message["level"] as? String) ?? (message["type"] as? String) ?? "log"
            let entry = ConsoleEntry(
                id: ids.next(),
                level: CDPFormat.consoleLevel(level),
                kind: .message,
                text: text,
                source: source.isEmpty ? CDPFormat.topSource(stackTrace) : source,
                stack: CDPFormat.stack(stackTrace))
            eventContinuation.yield(.console(entry))

        case "Runtime.exceptionThrown":
            let details = params["exceptionDetails"] as? [String: Any] ?? [:]
            let stackTrace = details["stackTrace"] as? [String: Any]
            let source = CDPFormat.shortSource(
                details["url"] as? String ?? "",
                line: (details["lineNumber"] as? Int).map { $0 + 1 })
            let entry = ConsoleEntry(
                id: ids.next(),
                level: .error,
                kind: .exception,
                text: CDPFormat.exceptionText(details),
                source: source.isEmpty ? CDPFormat.topSource(stackTrace) : source,
                stack: CDPFormat.stack(stackTrace))
            eventContinuation.yield(.console(entry))

        case "Log.entryAdded":
            let entryObject = params["entry"] as? [String: Any] ?? [:]
            let source = CDPFormat.shortSource(
                entryObject["url"] as? String ?? "",
                line: (entryObject["lineNumber"] as? Int).map { $0 + 1 })
            let entry = ConsoleEntry(
                id: ids.next(),
                level: CDPFormat.logLevel(entryObject["level"] as? String ?? "info"),
                kind: .system,
                text: entryObject["text"] as? String ?? "",
                source: source.isEmpty ? nil : source)
            eventContinuation.yield(.console(entry))

        case "Page.frameNavigated":
            let frame = params["frame"] as? [String: Any] ?? [:]
            if frame["parentId"] == nil, let url = frame["url"] as? String, !url.isEmpty {
                eventContinuation.yield(.navigated(url))
            }

        case "Network.requestWillBeSent":
            guard let requestId = params["requestId"] as? String,
                  let request = params["request"] as? [String: Any] else { break }
            let start = NetworkRequestStart(
                id: requestId,
                method: request["method"] as? String ?? "GET",
                url: request["url"] as? String ?? "",
                resourceType: params["type"] as? String,
                headers: stringHeaders(request["headers"]),
                postData: request["postData"] as? String,
                monotonic: params["timestamp"] as? Double ?? 0,
                wallTime: (params["wallTime"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date())
            eventContinuation.yield(.network(.started(start)))

        case "Network.responseReceived":
            guard let requestId = params["requestId"] as? String,
                  let response = params["response"] as? [String: Any] else { break }
            let info = NetworkResponseInfo(
                id: requestId,
                status: response["status"] as? Int ?? 0,
                statusText: response["statusText"] as? String ?? "",
                mimeType: response["mimeType"] as? String ?? "",
                resourceType: params["type"] as? String,
                headers: stringHeaders(response["headers"]),
                monotonic: params["timestamp"] as? Double ?? 0)
            eventContinuation.yield(.network(.response(info)))

        case "Network.loadingFinished":
            guard let requestId = params["requestId"] as? String else { break }
            eventContinuation.yield(.network(.finished(
                id: requestId,
                encodedDataLength: (params["encodedDataLength"] as? Double).map { Int($0) },
                monotonic: params["timestamp"] as? Double ?? 0)))

        case "Network.loadingFailed":
            guard let requestId = params["requestId"] as? String else { break }
            eventContinuation.yield(.network(.failed(
                id: requestId,
                error: params["errorText"] as? String ?? "failed",
                monotonic: params["timestamp"] as? Double ?? 0)))

        default:
            break
        }
    }

    private func stringHeaders(_ value: Any?) -> [String: String] {
        (value as? [String: Any])?.mapValues { "\($0)" } ?? [:]
    }
}
