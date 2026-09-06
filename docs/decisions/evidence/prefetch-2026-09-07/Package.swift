// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "WalletCore",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "WalletCore", targets: ["WalletCore"]),
        .library(name: "WalletCoreSwiftProtobuf", targets: ["WalletCoreSwiftProtobuf"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "WalletCore",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.8.0/WalletCore.xcframework.zip",
            checksum: "0c79df1a901a3abfbccee5052229984b1e743696483176b3cfb68eaf90f400bc"
        ),
        .binaryTarget(
            name: "WalletCoreSwiftProtobuf",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.8.0/WalletCoreSwiftProtobuf.xcframework.zip",
            checksum: "6098237d99dc609cc1ee5a8fe9c9cf0b90fb06ae739f42a51e3dbdbb1f18ec37"
        )
    ]
)
