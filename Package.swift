// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Rydool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rydool", targets: ["Rydool"])
    ],
    targets: [
        .executableTarget(
            name: "Rydool",
            path: "Rydool",
            exclude: ["Resources/Info.plist", "Resources/en.lproj", "Resources/vi.lproj", "Resources/zh-Hans.lproj"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(name: "RydoolTests", dependencies: ["Rydool"], path: "Tests/RydoolTests")
    ]
)
