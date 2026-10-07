# Third-party components

SwiftyTranscoder's original code is MIT-licensed; bundled third-party software and models retain their own licenses. The app contains their full notices under `Contents/Resources/ThirdPartyNotices`.

| Component | Source | Notice in the app |
| --- | --- | --- |
| FFmpeg / FFprobe 9.0.2 | https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz | FFmpeg-COPYING.LGPLv2.1.txt, FFmpeg-LICENSE.md |
| FreeType 2.14.3 | https://freetype.org/ | FreeType-LICENSE.txt |
| FriBidi 1.0.17 | https://github.com/fribidi/fribidi | FriBidi-COPYING.txt |
| HarfBuzz 14.5.0 | https://github.com/harfbuzz/harfbuzz | HarfBuzz-COPYING.txt |
| libass 0.17.5 | https://github.com/libass/libass | libass-COPYING.txt |
| Real-ESRGAN detailed/SD/compact models | https://github.com/xinntao/Real-ESRGAN | Real-ESRGAN-LICENSE.txt |
| FSRCNN x2 weights | https://github.com/Saafke/FSRCNN_Tensorflow | FSRCNN-LICENSE.txt, FSRCNN-Attribution.txt |

The release includes `SwiftyTranscoder_1.7.0_ThirdPartySources.tar.gz`, containing the exact original FFmpeg and subtitle-library source archives and their notices, plus the build scripts used for the bundled media tools. Each original archive is checksum-pinned in `Scripts/build-toolchain.sh` or `Scripts/build-subtitle-dependencies.sh`. The scripts describe configuration and static subtitle-library linking; model preparation and bootstrap are described in [Building from source](Building.md).

The AI model packages are included in the installer rather than the Git repository. The lightweight model converts learned FSRCNN luminance output into the app's RGB contract; the compact model adapts general-x4v3 output to 2×. Model identities, licenses, conversion references, and validation are recorded in Milestones 62, 102, 110, and 111. Python conversion dependencies are development tools and are not included in the runtime app.
