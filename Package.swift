// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataPointSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "DataPointSDK",
            targets: ["DataPointSDK"]
        ),
    ],
    targets: [
        .target(
            name: "DataPointSDK",
            path: "datapoint"
        ),
    ]
)
