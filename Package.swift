// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatSTT",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FloatSTT", targets: ["FloatSTT"])
    ],
    targets: [
        .executableTarget(
            name: "FloatSTT",
            path: "Sources/MinimalSpeech"
        )
    ]
)
