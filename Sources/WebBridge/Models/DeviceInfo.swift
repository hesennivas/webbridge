import Foundation

struct InstalledApp: Identifiable, Sendable, Hashable {
    let id: String        // package name
    var package: String { id }
}

struct DeviceInfo: Sendable {
    var model: String?
    var androidVersion: String?
    var sdk: String?
    var abi: String?
    var buildNumber: String?
    var batteryLevel: Int?
    var batteryCharging: Bool?
    var batteryTemperature: Double?
    var screenResolution: String?
    var screenDensity: String?
    var foregroundApp: String?
    var webViewProvider: String?
    var packages: [InstalledApp] = []

    // iOS-only subset.
    var udid: String?
    var iosName: String?

    static let empty = DeviceInfo()
}
