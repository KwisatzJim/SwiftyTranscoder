# Building from source

Use an Apple Silicon Mac, macOS 14 or later, Xcode 27 (the validated toolchain), and `curl`, `shasum`, `tar`, `cmake`, `make`, and `pkg-config`. Select the full Xcode developer directory before building:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/build-toolchain.sh
Scripts/stage-toolchain-bundle.sh
```

These scripts fetch checksum-pinned source archives and build the bundled FFmpeg/FFprobe helpers and subtitle libraries. Downloads and generated files remain under ignored `.build/`.

The app requires four prepared Core ML model packages. The published 1.5.0 installer contains the exact packages used by the validated release; copying those packages is the supported bootstrap for a fresh checkout. Download the installer from this repository's release page, verify its SHA-256 (`86c086d1f605b76969da2a6d75f9225ced40055440c12898c85a9e0ab0968cdc`), mount it, then run these commands from the source checkout:

```sh
research="$PWD/.build/restoration-evaluation"
resources="/Volumes/SwiftyTranscoder/SwiftyTranscoder.app/Contents/Resources"
mkdir -p "$research/converter/weights" "$research/sd-shape-experiment" \
  "$research/fast-candidate" "$research/fsrcnn-candidate" "$research/licenses"
ditto "$resources/Models/RealESRGAN_x2plus_522_fp16.mlpackage" "$research/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
ditto "$resources/Models/RealESRGAN_x2plus_656x384_fp16.mlpackage" "$research/sd-shape-experiment/RealESRGAN_x2plus_656x384_fp16.mlpackage"
ditto "$resources/Models/RealESRGAN_general_x2_522_fp16.mlpackage" "$research/fast-candidate/RealESRGAN_general_x2_522_fp16.mlpackage"
ditto "$resources/Models/FSRCNN_x2_RGB_522_fp16.mlpackage" "$research/fsrcnn-candidate/FSRCNN_x2_RGB_522_fp16.mlpackage"
cp "$resources/ThirdPartyNotices/Real-ESRGAN-LICENSE.txt" "$research/licenses/Real-ESRGAN-LICENSE.txt"
cp "$resources/ThirdPartyNotices/FSRCNN-LICENSE.txt" "$research/fsrcnn-candidate/LICENSE"
```

Adjust `resources` if macOS mounts the image under a different volume name. The build phase verifies every model's manifest, model definition, weights, and required licenses against pinned hashes. It refuses missing or changed assets.

Open `SwiftyTranscoder.xcodeproj`, select the SwiftyTranscoder scheme and My Mac, and run. A command-line build is:

```sh
xcodebuild -project SwiftyTranscoder.xcodeproj -scheme SwiftyTranscoder \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
swift test --no-parallel
```

Core ML integration tests use available prepared models; source-media fixture tests run only when their local fixtures exist. Test media is not distributed in this repository.

For model research, `Scripts/prepare-restoration-model.sh` prepares the original detailed and SD Real-ESRGAN models using Python 3.12 and pinned dependencies. The compact and FSRCNN conversion scripts are retained with checksum checks and their research notes in Milestones 110–111. They require their original downloaded weights/graph; running the original preparation script alone does not create all four release models. The binary-model bootstrap above avoids that research setup when developing the app.

`Scripts/build-release.sh` additionally runs the original model-preparation validation, builds an ad-hoc-signed app, validates its resources, and creates and checks a DMG. It requires Python 3.12 for that research validation step, even if the models were bootstrapped. Third-party license notices are included in every app bundle.

## Current development changes

The conversion assistant uses the Foundation Models framework with runtime checks for macOS 26 and Apple Intelligence availability. Building still requires the full Xcode 27 SDK or newer; ordinary conversion remains available on macOS 14 and later. Xcode-added `-NSDocumentRevisionsDebugMode YES/NO` and `-NSPersistenceIgnoreState YES/NO` launch arguments are filtered before choosing the GUI or CLI path. Unknown CLI options remain errors.

The Embed Toolchain phase runs with Xcode user-script sandboxing enabled. Its declared inputs include the script, all four model packages and their checksum-verified files, helpers, and licenses. Outputs include model files, license notices, and the temporary `.cstemp` files used when signing helpers. Model packages are copied as their three verified files instead of using `ditto`, which creates unpredictable temporary filenames during replacement. Both fresh builds and repeated signed Debug builds have been checked.

Run regression tests with `swift test --no-parallel` to avoid shared restoration-controller conflicts. The full suite passed 200 tests in 50 suites before the final inspection request-ID guard and explanatory-text updates; those final GUI changes are checked with a signed Debug build. Core ML and media-fixture coverage depends on local assets as described above.

The new GUI flows have been checked with real media: smaller-for-Plex sizing advice, three-point metadata inspection, saving and reloading an exact-file SDR confirmation, and Explain Error after a controlled missing-input failure. Changed-file invalidation is covered by tests, including changed contents with the same size and modification timestamp. These checks do not constitute a new notarized release.
