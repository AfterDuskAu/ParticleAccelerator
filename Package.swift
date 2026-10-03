// swift-tools-version: 6.0
// Particle Accelerator: visuals that move with the music.
//
// `ParticleAccelerator` is the library: hearing the music, the stage, the visuals. Every
// app that shows the visuals uses it, this project's own app and Music Organizer alike
// (docs/INTEGRATION.md). `ParticleAcceleratorApp` is the stand-alone Mac app, a thin
// shell over the library; scripts/build_app.sh makes "Particle Accelerator.app".
// `pa-bench` measures what a Mac's graphics card can draw (docs/OUTPUT.md).
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "ParticleAccelerator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ParticleAccelerator", targets: ["ParticleAccelerator"]),
        .executable(name: "ParticleAcceleratorApp", targets: ["ParticleAcceleratorApp"]),
        .executable(name: "pa-bench", targets: ["PABench"]),
    ],
    targets: [
        .target(name: "ParticleAccelerator", swiftSettings: settings),
        .executableTarget(
            name: "ParticleAcceleratorApp", dependencies: ["ParticleAccelerator"],
            swiftSettings: settings),
        .executableTarget(name: "PABench", swiftSettings: settings),
        .testTarget(
            name: "ParticleAcceleratorTests", dependencies: ["ParticleAccelerator"],
            swiftSettings: settings),
    ]
)
