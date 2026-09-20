# TensorFlowLiteC-SPM

Swift Package Manager wrapper for the **official** [TensorFlowLiteC](https://cocoapods.org/pods/TensorFlowLiteC) **2.11.x** iOS binary from Google’s CocoaPods distribution.

## Why this package exists

An external document scanner SDK declares:

```ruby
pod 'TensorFlowLiteC', '~> 2.11.0'
```

Your host application uses **Swift Package Manager only**. This repository downloads the same official CocoaPods artifact (Google-hosted tarball referenced by the Trunk podspec), reuses or assembles `TensorFlowLiteC.xcframework`, validates it, and exposes it as an SPM **binary target** named `TensorFlowLiteC` — without adding CocoaPods to the consumer app.

```
Application
    |
    +-- External Scanner SDK
    |
    +-- TensorFlowLiteC-SPM
            |
            +-- official TensorFlowLiteC 2.11.0 binary (CocoaPods / dl.google.com)
```

## Version configuration

Edit **`Scripts/version.env`** (single obvious place):

```bash
TFLITE_VERSION="2.11.0"
```

Stay within **2.11.x** for vendor SDK compatibility. Do not upgrade to 2.12+ without vendor approval.

## Build the XCFramework

Requirements (maintainers only): macOS, Xcode command line tools, `curl`, `jq`, `zip`, `ditto`, `ruby`.

```bash
./Scripts/build_xcframework.sh
```

This will:

1. Clean prior staging output  
2. Resolve the official podspec on `cdn.cocoapods.org` and download the `dl.google.com` tarball  
3. Extract `Frameworks/TensorFlowLiteC.xcframework` (already present for 2.11.0)  
4. Validate slices, repair **framework** `Info.plist` only when missing (see `Artifacts/METADATA_MODIFICATIONS.log`)  
5. Install `Artifacts/TensorFlowLiteC.xcframework` and write `Artifacts/PROVENANCE.txt`

Optional CocoaPods download (packaging machines only):

```bash
USE_POD_DOWNLOAD=1 ./Scripts/download_tflite.sh
```

Consumer apps **do not** need CocoaPods.

## Add to an existing Xcode project

1. Run `./Scripts/build_xcframework.sh` and commit `Artifacts/` (or host the zip remotely — below).  
2. In Xcode: **File → Add Package Dependencies…**  
3. Click **Add Local…** and select this repository folder.  
4. Add the **TensorFlowLiteC** product to the app target (and ensure the scanner SDK also links against it only once).

If the scanner SDK is itself an SPM package, add this repo as a dependency in that package’s `Package.swift` or at the app level — avoid linking `TensorFlowLiteC` twice.

## Remote binary distribution (internal Git / release storage)

After building:

```bash
cd Artifacts
zip -rq TensorFlowLiteC.xcframework.zip TensorFlowLiteC.xcframework
swift package compute-checksum TensorFlowLiteC.xcframework.zip
```

Switch `Package.swift` to a remote binary target:

```swift
.binaryTarget(
    name: "TensorFlowLiteC",
    url: "https://your.internal.host/TensorFlowLiteC.xcframework.zip",
    checksum: "<output of swift package compute-checksum>"
)
```

Checksums for the current 2.11.0 build are recorded in `Artifacts/PROVENANCE.txt`.

## Reproducibility

| Item | Value |
|------|--------|
| Version | 2.11.0 |
| Podspec | `https://cdn.cocoapods.org/Specs/1/6/0/TensorFlowLiteC/2.11.0/TensorFlowLiteC.podspec.json` |
| Tarball | `https://dl.google.com/tflite-release/ios/prod/tensorflow/lite/release/ios/release/20/20221205-133425/TensorFlowLiteC/2.11.0/5f36dfd15a35e951/TensorFlowLiteC-2.11.0.tar.gz` |
| Tarball SHA-256 | See `Artifacts/PROVENANCE.txt` |
| XCFramework zip SHA-256 | See `Artifacts/PROVENANCE.txt` |

We do **not** use third-party repacks (e.g. kewlbear/TensorFlowLiteC). Sources are only the CocoaPods podspec URL and Google `dl.google.com` tarball.

## What the official pod contains (2.11.0)

The tarball includes prebuilt XCFrameworks under `Frameworks/`:

- `TensorFlowLiteC.xcframework` (Core — **this package**)
- `TensorFlowLiteCCoreML.xcframework`, `TensorFlowLiteCMetal.xcframework` (not packaged here)

Core layout:

- `ios-arm64` — device arm64 static framework  
- `ios-arm64_x86_64-simulator` — simulator arm64 + x86_64 static framework  

Module name remains **`TensorFlowLiteC`** (`Modules/module.modulemap` unchanged).

## Minimum iOS version

| Slice | Binary min OS (LC_VERSION_MIN_IPHONEOS / LC_BUILD_VERSION) |
|-------|---------------------------------------------------------------|
| `ios-arm64` (device) | **11.0** |
| `ios-arm64_x86_64-simulator` (arm64 sim) | **14.0** |
| `ios-arm64_x86_64-simulator` (x86_64 sim) | **11.0** |

SwiftPM `platforms` uses the **maximum** across slices (**14.0**) so arm64 Simulator builds match the binary. See `Artifacts/detected_minimum_ios.txt` after each build.

The official podspec lists `ios.deployment_target` **11.0**; the simulator arm64 slice in the prebuilt XCFramework is nonetheless **14.0** in the Mach-O load commands.

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| **Invalid MinimumOSVersion** (App Store) | Re-run `./Scripts/build_xcframework.sh`; ensure each framework slice has `Info.plist` with `MinimumOSVersion` matching the Mach-O (`validate_xcframework.sh` / `macho_min_os.rb`). |
| **Missing MinimumOSVersion** | Official 2.11.0 frameworks ship without `Info.plist`; the build script creates one from binary metadata. |
| **Missing CFBundleShortVersionString** | Same metadata repair; version set to `2.11.0`. |
| **Architecture mismatch** | Use the provided XCFramework slices; do not `lipo` device and simulator together. |
| **Missing arm64 simulator slice** | 2.11.0 includes `ios-arm64_x86_64-simulator` with arm64 + x86_64. |
| **Duplicate TensorFlowLiteC symbols** | Link this package only once; remove CocoaPods `TensorFlowLiteC` from the app. |
| **Module TensorFlowLiteC not found** | Add the **TensorFlowLiteC** product from this package; ensure scanner SDK sees the binary target. |

## Constraints (by design)

- No automatic upgrade beyond configured 2.11.x  
- No replacement with TensorFlowLiteSwift / TensorFlowLiteObjC  
- No module rename  
- No kewlbear binary  
- No CocoaPods in the consumer app  
- No patches to TensorFlow runtime — packaging and SPM exposure only  

## License

TensorFlow Lite is licensed under Apache 2.0 (see upstream TensorFlowLiteC distribution). This repo contains packaging scripts and redistributes the official binary unchanged except for documented framework `Info.plist` additions.
