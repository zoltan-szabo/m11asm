// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "m11asm",
    products: [
        .library(name: "m11asmCore", targets: ["m11asmCore"]),
    ],
    targets: [
        .executableTarget(
            name: "m11asm",
            dependencies: ["m11asmCore"],
            path: "Sources/m11asm"
        ),
        .target(
            name: "m11asmCore",
            path: "Sources/m11asmCore"
        ),
        .testTarget(
            name: "m11asmTests",
            dependencies: ["m11asmCore"],
            path: "Tests/m11asmTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
