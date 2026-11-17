// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoliaIOSCompat",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "FoliaIOSCompat",
            targets: ["FoliaIOSCompat"]
        )
    ],
    targets: [
        .target(
            name: "FoliaIOSCompat",
            path: "compat/ios-bridge/ios",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("MediaToolbox"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("WebKit"),
                .linkedFramework("UIKit")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
