// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NotchCurtain",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchCurtain", targets: ["NotchCurtain"])],
    targets: [
        .executableTarget(name: "NotchCurtain", resources: [.copy("en.lproj"), .copy("ru.lproj")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "NotchCurtainTests", dependencies: ["NotchCurtain"], resources: [.copy("Fixtures")])
    ]
)
