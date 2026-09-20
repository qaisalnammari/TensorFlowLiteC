// swift-tools-version:5.9
import PackageDescription

// After ./Scripts/build_xcframework.sh, see Artifacts/detected_minimum_ios.txt (max min-OS across slices).
// TensorFlowLiteC 2.11.0 device arm64 is iOS 11.0; ios-arm64 simulator slice in the official XCFramework is iOS 14.0.
let minimumIOS = "14.0"

let package = Package(
    name: "TensorFlowLiteC-SPM",
    platforms: [
        .iOS(minimumIOS),
    ],
    products: [
        .library(
            name: "TensorFlowLiteC",
            targets: ["TensorFlowLiteC"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "TensorFlowLiteC",
            path: "Artifacts/TensorFlowLiteC.xcframework"
        ),
    ]
)
