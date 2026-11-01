// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dixity",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Parakeet local (voz a texto sin internet). Copia de FluidAudio, Apache 2.0.
        .package(path: "Vendor/FluidAudio"),
        // Actualizaciones de las versiones publicadas (ver docs/PUBLICAR.md). La misma versión que usa Relevo.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Dixity",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Dixity",
            swiftSettings: [.unsafeFlags(["-Osize"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "DixityTests",
            dependencies: ["Dixity"],
            path: "Tests/DixityTests"
        ),
    ]
)
