// swift-tools-version:5.9
import PackageDescription

// After ./Scripts/build_xcframework.sh, see Artifacts/detected_minimum_ios.txt (max min-OS across slices).
let minimumIOS = "14.0"

let package = Package(
    name: "TensorFlowLiteC-SPM",
    platforms: [
        .iOS(minimumIOS),
    ],
    products: [
        .library(
            name: "TensorFlowLiteC",
            targets: ["TensorFlowLiteCSupport"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "TensorFlowLiteCBinary",
            path: "Artifacts/TensorFlowLiteC.xcframework"
        ),
        .target(
            name: "TensorFlowLiteCSupport",
            dependencies: ["TensorFlowLiteCBinary"],
            path: "Sources/TensorFlowLiteCSupport",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
