import XCTest
@testable import WebBridge

final class ParsingTests: XCTestCase {

    func testAndroidDevicesParsesStatesAndModel() {
        let output = """
        List of devices attached
        4A21FDH0021  device product:cheetah model:Pixel_8_Pro device:cheetah transport_id:1
        emulator-5554  offline
        192.168.1.7:5555  device model:Galaxy_S23
        R58N90XYZ  unauthorized
        """
        let devices = Parsing.androidDevices(output)
        XCTAssertEqual(devices.count, 4)
        XCTAssertEqual(devices[0].serial, "4A21FDH0021")
        XCTAssertEqual(devices[0].state, .online)
        XCTAssertEqual(devices[0].model, "Pixel 8 Pro")
        XCTAssertEqual(devices[1].state, .offline)
        XCTAssertTrue(devices[2].isWireless)
        XCTAssertEqual(devices[3].state, .unauthorized)
    }

    func testDevtoolsSocketsExtractsNamesAndPid() {
        let output = """
        Num RefCount Protocol Flags Type St Inode Path
        0000 00000002 00000000 00010000 0001 01 12345 @webview_devtools_remote_2841
        0000 00000002 00000000 00010000 0001 01 12346 @chrome_devtools_remote
        0000 00000002 00000000 00010000 0001 01 12347 @com.example.app_devtools_remote
        0000 00000002 00000000 00010000 0001 01 99999 /dev/socket/other
        """
        let sockets = Parsing.devtoolsSockets(output)
        XCTAssertEqual(sockets.count, 3)
        XCTAssertEqual(sockets.first(where: { $0.name == "webview_devtools_remote_2841" })?.pid, 2841)
        XCTAssertTrue(sockets.contains { $0.name == "chrome_devtools_remote" })
    }

    func testPackageFromCmdline() {
        XCTAssertEqual(Parsing.packageFromCmdline("com.example.app\u{0}"), "com.example.app")
        XCTAssertEqual(Parsing.packageFromCmdline("com.example.app:sandboxed_process0\u{0}"), "com.example.app")
    }

    func testGetprops() {
        let output = "[ro.product.model]: [Pixel 8 Pro]\n[ro.build.version.sdk]: [34]"
        let props = Parsing.getprops(output)
        XCTAssertEqual(props["ro.product.model"], "Pixel 8 Pro")
        XCTAssertEqual(props["ro.build.version.sdk"], "34")
    }

    func testPackageList() {
        let output = "package:com.example.one\npackage:com.example.two"
        let apps = Parsing.packageList(output)
        XCTAssertEqual(apps.map(\.package), ["com.example.one", "com.example.two"])
    }
}

final class TargetParsingTests: XCTestCase {

    /// ios_webkit_debug_proxy's /json/list omits the top-level `id` that Chrome/Android emit;
    /// the page id lives in the debugger URL path. This payload is captured verbatim from an
    /// iPhone on iOS 26. The parser must not drop these targets.
    func testIOSTargetsDeriveIdFromWebSocketURL() {
        let json = """
        [
          {
            "devtoolsFrontendUrl": "",
            "title": "Google Maps",
            "url": "https://www.google.com/maps",
            "webSocketDebuggerUrl": "ws://localhost:9222/devtools/page/3",
            "appId": "PID:56288"
          },
          {
            "title": "ServiceWorker",
            "url": "https://www.google.com/maps",
            "webSocketDebuggerUrl": "ws://localhost:9222/devtools/page/4",
            "appId": "PID:56288"
          }
        ]
        """
        let targets = TargetService.parseTargets(Data(json.utf8), port: 9222, deviceID: "UDID",
                                                 engine: "Safari", appPackage: nil, appLabel: nil,
                                                 canOpenInSafari: true)
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].cdpId, "3")
        XCTAssertEqual(targets[0].id, "UDID#3")
        XCTAssertEqual(targets[1].cdpId, "4")
        XCTAssertTrue(targets[0].canOpenInSafari)
    }

    /// Chrome/Android still provide `id` explicitly; it must take precedence over the URL.
    func testAndroidTargetsUseExplicitId() {
        let json = """
        [{ "id": "ABC123", "type": "page", "title": "Home",
           "webSocketDebuggerUrl": "ws://127.0.0.1:9333/devtools/page/ABC123" }]
        """
        let targets = TargetService.parseTargets(Data(json.utf8), port: 9333, deviceID: "SER",
                                                 engine: "Chrome", appPackage: "com.x", appLabel: "X",
                                                 canOpenInSafari: false)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].cdpId, "ABC123")
    }

    /// A target with no debugger URL can't be inspected and must be skipped.
    func testTargetWithoutWebSocketURLIsDropped() {
        let json = #"[{ "id": "1", "title": "no ws" }]"#
        let targets = TargetService.parseTargets(Data(json.utf8), port: 9222, deviceID: "D",
                                                 engine: "Safari", appPackage: nil, appLabel: nil,
                                                 canOpenInSafari: true)
        XCTAssertTrue(targets.isEmpty)
    }
}

final class RingBufferTests: XCTestCase {
    func testDropsOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])
        XCTAssertEqual(buffer.elements, [3, 4, 5])
    }

    func testReplaceLast() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.replaceLast(9)
        XCTAssertEqual(buffer.elements, [9])
    }

    func testLogcatLineParsesFields() {
        let entry = Parsing.logcatLine("1620000000.123  1234  1256 I MyTag: hello: world")
        XCTAssertEqual(entry?.time, 1620000000.123)
        XCTAssertEqual(entry?.pid, 1234)
        XCTAssertEqual(entry?.level, "I")
        XCTAssertEqual(entry?.tag, "MyTag")
        XCTAssertEqual(entry?.message, "hello: world")
    }

    func testLogcatLineHandlesEmptyMessageAndLeadingSpace() {
        let entry = Parsing.logcatLine("   1620000000.500  42  42 E Boom:")
        XCTAssertEqual(entry?.level, "E")
        XCTAssertEqual(entry?.tag, "Boom")
        XCTAssertEqual(entry?.message, "")
    }

    func testLogcatLineRejectsSeparators() {
        XCTAssertNil(Parsing.logcatLine("--------- beginning of main"))
        XCTAssertNil(Parsing.logcatLine(""))
    }

    func testIOSSyslogLineParsesProcessLevelMessage() {
        let entry = Parsing.iosSyslogLine("Jul  5 10:15:32 Hesens-iPhone SpringBoard[62] <Notice>: hello: world")
        XCTAssertEqual(entry?.process, "SpringBoard")
        XCTAssertEqual(entry?.level, "Notice")
        XCTAssertEqual(entry?.message, "hello: world")
    }

    func testIOSSyslogLineKeepsSubsystemInProcess() {
        let entry = Parsing.iosSyslogLine("Jul  5 10:15:33 iPhone symptomsd(SymptomEvaluator)[95] <Error>: boom")
        XCTAssertEqual(entry?.process, "symptomsd(SymptomEvaluator)")
        XCTAssertEqual(entry?.level, "Error")
        XCTAssertEqual(entry?.message, "boom")
    }

    func testIOSSyslogLineRejectsNonLog() {
        XCTAssertNil(Parsing.iosSyslogLine("[connecting to device]"))
        XCTAssertNil(Parsing.iosSyslogLine(""))
    }

    func testIOSSyslogLineKeepsUnexpectedShape() {
        // a timestamped line that doesn't match the strict shape is still surfaced as a log
        let entry = Parsing.iosSyslogLine("Jul  5 10:15:32 iPhone free-form line without level")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.message, "free-form line without level")
        XCTAssertEqual(entry?.level, "")
    }
}
