// swift-tools-version:6.2
import PackageDescription
import Foundation

// test target only when its sources are present; release tarballs strip Tests/ (.gitattributes).
let includeTests = FileManager.default.fileExists(atPath: "Tests/WebBridgeTests")

var targets: [Target] = [
    .executableTarget(
        name: "WebBridge",
        path: "Sources/WebBridge",
        exclude: ["Info.plist"],
        swiftSettings: [
            .swiftLanguageMode(.v6)
        ],
        linkerSettings: [
            .unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Sources/WebBridge/Info.plist"
            ])
        ]
    )
]

if includeTests {
    targets.append(
        .testTarget(
            name: "WebBridgeTests",
            dependencies: ["WebBridge"],
            path: "Tests/WebBridgeTests"
        )
    )
}

let package = Package(
    name: "WebBridge",
    platforms: [.macOS(.v26)],
    targets: targets
)
