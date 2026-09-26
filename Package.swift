// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftyTranscoderCoreTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SwiftyTranscoderCore",
            path: "SwiftyTranscoder/Models",
            exclude: [
                "ConversionPlan.swift",
                "MediaInspection.swift",
                "MediaSummary.swift",
                "SubtitleRecommendation.swift"
            ],
            sources: ["CanonicalOutputPath.swift", "QueueIndexRemapping.swift"]
        ),
        .testTarget(
            name: "SwiftyTranscoderCoreTests",
            dependencies: ["SwiftyTranscoderCore"]
        )
    ]
)
