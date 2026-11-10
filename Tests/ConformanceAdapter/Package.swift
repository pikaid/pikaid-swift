// swift-tools-version: 6.0
import PackageDescription

// Test-only bridge package for the official PikaID conformance suite.
//
// It is deliberately a separate package: the production `Pikaid` manifest gains
// no executable target, no test-only dependencies, and no Python/Node coupling.
// The bridge calls the real public `Pikaid` API through a local path dependency
// and never re-implements encoding, validation, generation, or ordering.
let package = Package(
  name: "PikaidConformanceAdapter",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "PikaidConformanceAdapter",
      dependencies: [
        .product(name: "Pikaid", package: "pikaid-swift")
      ]
    )
  ]
)
