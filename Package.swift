// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Flowtone",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "FlowtoneCore", targets: ["FlowtoneCore"]),
    .executable(name: "Flowtone", targets: ["FlowtoneApp"]),
    .executable(name: "flowtone-spike", targets: ["FlowtoneSpike"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/swiftlang/swift-testing.git",
      revision: "48d727cc1cf4eda667c858c501495f1018f69d21"
    )
  ],
  targets: [
    .target(name: "FlowtoneCore"),
    .executableTarget(
      name: "FlowtoneApp",
      dependencies: ["FlowtoneCore"]
    ),
    .executableTarget(
      name: "FlowtoneSpike",
      dependencies: ["FlowtoneCore"]
    ),
    .testTarget(
      name: "FlowtoneCoreTests",
      dependencies: [
        "FlowtoneCore",
        .product(name: "Testing", package: "swift-testing"),
      ],
      linkerSettings: [
        .unsafeFlags([
          "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
          "-Xlinker", "-rpath",
          "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
        ])
      ]
    ),
  ]
)
