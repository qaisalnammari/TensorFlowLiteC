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
            targets: ["TensorFlowLiteC", "TensorFlowLiteCSupport"]
        ),
    ],
    targets: [
        // Name must match the Clang module (TensorFlowLiteC) for import TensorFlowLiteC / EFR SDK.
        .binaryTarget(
            name: "TensorFlowLiteC",
            path: "Artifacts/TensorFlowLiteC.xcframework"
        ),
        // Applies libc++ like the official pod (s.library = 'c++').
        .target(
            name: "TensorFlowLiteCSupport",
            dependencies: ["TensorFlowLiteC"],
            path: "Sources/TensorFlowLiteCSupport",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
