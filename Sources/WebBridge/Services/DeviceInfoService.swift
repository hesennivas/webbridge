import Foundation

/// Batched device/app property reads. Called on selection and on explicit refresh.
actor DeviceInfoService {
    private let adbPath: String

    init(adbPath: String) {
        self.adbPath = adbPath
    }

    func load(serial: String) async -> DeviceInfo {
        async let props = shell(serial, ["getprop"])
        async let battery = shell(serial, ["dumpsys", "battery"])
        async let size = shell(serial, ["wm", "size"])
        async let density = shell(serial, ["wm", "density"])
        async let activity = shell(serial, ["dumpsys", "activity", "activities"])
        async let webview = shell(serial, ["dumpsys", "webviewupdate"])
        async let packages = shell(serial, ["pm", "list", "packages", "-3"])

        var info = DeviceInfo()
        let propMap = Parsing.getprops(await props)
        info.model = propMap["ro.product.model"]
        info.androidVersion = propMap["ro.build.version.release"]
        info.sdk = propMap["ro.build.version.sdk"]
        info.abi = propMap["ro.product.cpu.abi"]
        info.buildNumber = propMap["ro.build.display.id"]

        let batteryText = await battery
        info.batteryLevel = Parsing.dumpsysInt(batteryText, key: "level")
        if let status = Parsing.dumpsysInt(batteryText, key: "status") { info.batteryCharging = status == 2 }
        if let temp = Parsing.dumpsysInt(batteryText, key: "temperature") { info.batteryTemperature = Double(temp) / 10.0 }

        info.screenResolution = Parsing.firstMatch(await size, prefix: "Physical size:")
        info.screenDensity = Parsing.firstMatch(await density, prefix: "Physical density:")
        info.foregroundApp = Parsing.foregroundActivity(await activity)
        info.webViewProvider = Parsing.webviewProvider(await webview)
        info.packages = Parsing.packageList(await packages)
        return info
    }

    func forceStop(serial: String, package: String) async {
        _ = try? await ProcessRunner.run(adbPath, ["-s", serial, "shell", "am", "force-stop", package])
    }

    func clearData(serial: String, package: String) async {
        _ = try? await ProcessRunner.run(adbPath, ["-s", serial, "shell", "pm", "clear", package])
    }

    func launch(serial: String, package: String) async {
        _ = try? await ProcessRunner.run(
            adbPath, ["-s", serial, "shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"])
    }

    private func shell(_ serial: String, _ command: [String]) async -> String {
        let arguments = ["-s", serial, "shell"] + command
        return (try? await ProcessRunner.output(adbPath, arguments)) ?? ""
    }
}
