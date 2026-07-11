import Foundation

enum DevicePlatform: Hashable, Sendable {
    case android(serial: String)
    case ios(udid: String, port: Int)

    var isAndroid: Bool { if case .android = self { return true }; return false }
    var isIOS: Bool { if case .ios = self { return true }; return false }
}

enum DeviceState: String, Sendable {
    case online
    case unauthorized
    case offline
    case degraded

    var label: String {
        switch self {
        case .online: return "online"
        case .unauthorized: return "unauthorized"
        case .offline: return "offline"
        case .degraded: return "limited"
        }
    }
}

struct Device: Identifiable, Sendable, Hashable {
    let id: String
    var platform: DevicePlatform
    var name: String
    var model: String?
    var osVersion: String?
    var state: DeviceState
    var isWireless: Bool

    var isAndroid: Bool { platform.isAndroid }
    var isIOS: Bool { platform.isIOS }
    var isOnline: Bool { state == .online || state == .degraded }

    /// adb serial for Android devices, nil otherwise.
    var serial: String? {
        if case let .android(serial) = platform { return serial }
        return nil
    }

    /// iwdp-assigned local port for iOS devices, nil otherwise.
    var iosPort: Int? {
        if case let .ios(_, port) = platform { return port }
        return nil
    }
}
