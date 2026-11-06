// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Pikaid",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "Pikaid", targets: ["Pikaid"])
  ],
  targets: [
    .target(name: "Pikaid"),
    .testTarget(
      name: "PikaidTests",
      dependencies: ["Pikaid"],
      // Copy the fixtures file by file: SwiftPM's directory copy uses a
      // FileManager directory copy that fails on Linux. Explicit file copies
      // land flat in the resource bundle on every platform.
      resources: [
        .copy("Fixtures/pikaid-v1.json"),
        .copy("Fixtures/pikaid-v1.schema.json"),
      ]
    ),
  ]
)
