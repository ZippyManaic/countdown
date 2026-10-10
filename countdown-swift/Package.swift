// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "countdown",
    targets: [
        // Drop overflow and bounds checks in release builds since the solver reserves room for every write itself
        .target(name: "Solver", swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]),
        .executableTarget(name: "countdown", dependencies: ["Solver"]),
        .testTarget(name: "SolverTests", dependencies: ["Solver"]),
    ]
)
