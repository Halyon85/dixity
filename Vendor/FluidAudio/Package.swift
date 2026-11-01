// swift-tools-version: 6.0
// Copia recortada de FluidAudio v0.17.7 (Apache 2.0, FluidInference): solo voz a texto (Parakeet) y lo que necesita.
// Sin CLI, pruebas, voz sintética (TTS), separador de voces (ni su FastCluster en C++) ni el normalizador binario NemoTextProcessing.
import PackageDescription

let package = Package(
    name: "FluidAudio",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FluidAudio", targets: ["FluidAudio"])],
    targets: [
        .target(name: "FluidAudio", dependencies: ["MachTaskSelfWrapper"],
                path: "Sources/FluidAudio", exclude: ["ASR/Parakeet/Unified/benchmark.md"]),
        .target(name: "MachTaskSelfWrapper", path: "Sources/MachTaskSelfWrapper", publicHeadersPath: "include"),
    ]
)
