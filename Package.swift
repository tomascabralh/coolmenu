// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoolMenu",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: geometry, cycling, grouping, history. No AppKit so it can be checked headless.
        .target(name: "CoolMenuCore"),
        .executableTarget(
            name: "CoolMenu",
            dependencies: ["CoolMenuCore"]
        ),
        // XCTest is not available with Command Line Tools only; `swift run CoolMenuChecks` instead.
        .executableTarget(
            name: "CoolMenuChecks",
            dependencies: ["CoolMenuCore"]
        ),
    ]
)
