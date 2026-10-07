# macOS and Apple Silicon

AnyPS5 Studio is a native SwiftUI front end for the [relinker](USAGE.md). It runs on macOS 14 or newer and is built for Apple Silicon (arm64); a universal build is optional.

## What works

| Step                                   | Status on macOS                                                                 |
|----------------------------------------|---------------------------------------------------------------------------------|
| Converting `eboot.bin` and its modules | Native. The relinker builds and runs as an arm64 binary.                        |
| Windows PE output                      | Written on the Mac. Running it needs Wine (CrossOver, Whisky or Homebrew Wine). |
| Linux ELF output                       | Written on the Mac. Running it needs a Linux x86-64 host.                       |
| System libraries (`libs/*.prx`)        | Not buildable on macOS. Build them on a Windows or Linux host for that target.  |
| Native macOS (Mach-O) output           | Not implemented.                                                                |

Converted titles are x86-64 programs. On Apple Silicon they execute through Rosetta 2, which implements Intel's instruction set, so keep `--to-intel` enabled (the app's default). Rosetta translates AVX2 from macOS 15 onward; PS5 code uses AVX2, so earlier macOS releases will fault on it.

Running Windows output through Wine on Apple Silicon has not been verified by the project. Expect failures around fixed-address memory reservation, direct memory commit (up to 13824 MiB per title), and Vulkan features that MoltenVK does not expose.

## Build

Requirements: Xcode 15 or newer (or the Command Line Tools with Swift 5.9+), CMake 3.20+. Ninja is used when present.

```sh
bash macos/scripts/build-app.sh
```

The script builds the relinker with `-DANYPS5_RELINKER_ONLY=ON`, builds the app with SwiftPM, assembles `build-macos/AnyPS5 Studio.app` with the relinker inside `Contents/MacOS/`, and signs both ad hoc.

| Variable              | Effect                                              |
|-----------------------|-----------------------------------------------------|
| `ARCHS="arm64 x86_64"`| Universal build. Default: `arm64`.                  |
| `DMG=1`               | Also write `build-macos/AnyPS5-Studio.dmg`.         |
| `BUILD_DIR=<path>`    | Build directory. Default: `build-macos`.            |

For development, `swift run --package-path macos` starts the app outside a bundle. It finds a relinker in `build-macos/relinker/core/relinker/` or `build/core/relinker/`, or the path set in Settings (⌘,).

The app is signed ad hoc, not notarized. A copy downloaded from the internet is quarantined; open it with Control-click → Open, or run `xattr -dr com.apple.quarantine "AnyPS5 Studio.app"`.

## Using the app

1. **Convert.** Drop a game folder or its decrypted `eboot.bin` onto the window. The app reads `sce_sys/param.json` for the title, checks the ELF magic, and applies the relinker's module folder rules (`sce_module` or `sce_modules`, optionally `prx`). Choose Windows or Linux output, adjust switches, and press Convert (⌘↩). The exact command is shown and can be copied.
2. **Console.** Relinker output streams live. Exit code `0` is success, `1` rejected arguments, `2` a failed conversion.
3. **Runtime layout.** Each title is written to `<output folder>/<name>/`. *Import libraries* copies `*.prx` files built on a Windows or Linux host into `libs/`. *Link game files* symlinks the game's resources into `app0/` without copying; module folders are skipped because the relinker writes converted modules there.
4. **Launch.** For Windows output with a Wine runtime installed, Launch runs the executable with the selected runtime from its own folder.

The System page lists the chip, macOS version, Rosetta and Wine status, and the known gaps above.
