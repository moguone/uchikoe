// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Uchikoe",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Uchikoe", targets: ["Uchikoe"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "UchikoeCore"),
        .executableTarget(
            name: "Uchikoe",
            dependencies: ["UchikoeCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "UchikoeCoreTests", dependencies: ["UchikoeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
