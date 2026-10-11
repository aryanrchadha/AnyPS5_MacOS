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

## Performance

The System page reports each display's current resolution and maximum refresh rate, and the GPU's name and recommended working set, against a 4K, 120 Hz target. Meeting it is necessary but not sufficient:

- The runtime presents with vsync (`VK_PRESENT_MODE_FIFO_KHR`), so the frame rate never exceeds the display's refresh rate or the rate at which the title submits frames. Most titles pace themselves at 30 or 60 FPS, and the runtime does not unlock that.
- On Apple Silicon, titles run through Rosetta 2, Wine and MoltenVK on top of the runtime's shader recompilation; each layer costs CPU and GPU time.
- Whether a title starts at all depends on the system library coverage it needs. See [COMPATIBILITY.md](COMPATIBILITY.md) for verified titles.

Measure rather than assume: enable the Metal Performance HUD for the title and read the frame rate and frame time during play.

## Build

Requirements: Xcode 15 or newer (or the Command Line Tools with Swift 5.9+), CMake 3.20+. Ninja is used when present.

```sh
bash macos/scripts/build-app.sh
```

The script builds the relinker with `-DANYPS5_RELINKER_ONLY=ON`, builds the app with SwiftPM, assembles `build-macos/AnyPS5 Studio.app` with the relinker inside `Contents/MacOS/`, and signs both ad hoc.

`swift test --package-path macos` runs the app's model tests: launch profiles, launchers (run with a stand-in Wine), save backups, session logs, the Library store, links, storage cleanup and reports. They need Xcode, because the Command Line Tools may not include XCTest, and they run in CI on every change under `macos/`.

| Variable              | Effect                                              |
|-----------------------|-----------------------------------------------------|
| `ARCHS="arm64 x86_64"`| Universal build. Default: `arm64`.                  |
| `DMG=1`               | Also write `build-macos/AnyPS5-Studio.dmg`.         |
| `BUILD_DIR=<path>`    | Build directory. Default: `build-macos`.            |

For development, `swift run --package-path macos` starts the app outside a bundle. It finds a relinker in `build-macos/relinker/core/relinker/` or `build/core/relinker/`, or the path set in Settings (⌘,).

The app is signed ad hoc, not notarized. A copy downloaded from the internet is quarantined; open it with Control-click → Open, or run `xattr -dr com.apple.quarantine "AnyPS5 Studio.app"`.

## Using the app

1. **Convert.** Drop one or more game folders, or decrypted `eboot.bin` files, onto the window or the Dock icon. The app:
   - reads `sce_sys/param.json` for the title;
   - checks the ELF magic;
   - applies the relinker's module folder rules (`sce_module` or `sce_modules`, optionally `prx`).

   Choose Windows or Linux output, adjust the switches, and press Convert (⌘↩). The exact command is shown and can be copied. Switches are remembered between launches.
2. **Queue.** When several games are opened, the extra ones wait in a queue. Convert All (⇧⌘↩) converts the current title, then each queued title with the same switches. Titles that cannot be converted are skipped.
3. **Library.** Every conversion is recorded with its output, target and exit code. Cards reopen a title with its previous target and output folder, reveal it in Finder, or launch Windows output.
4. **Console.** Relinker output streams live and can be filtered by text or limited to warnings and errors. It can be copied or saved to a file. Exit code `0` is success, `1` rejected arguments, `2` a failed conversion.
5. **Runtime layout.** Each title is written to `<output folder>/<name>/`.
   - *Import libraries* copies `*.prx` files built on a Windows or Linux host into `libs/`.
   - *Link game files* symlinks the game's resources into `app0/` without copying. Module folders are skipped, because the relinker writes converted modules there.
6. **Launch.** For Windows output with a Wine runtime installed, Launch runs the executable with the selected runtime from its own folder. The environment passed to Wine is edited in Settings (⌘,).

   Every launch from Studio, the menu bar or a link is checked first. A missing executable, a missing or non-executable Wine runtime, Rosetta 2 not installed on Apple Silicon, or a read-only output folder stops the launch and the banner says why. A pinned runtime that is no longer installed, or less than 2 GB free on the output volume, is noted in the Console and the launch goes ahead. The Options panel shows the same checks at the top.

7. **Controls.** Edits [`anyps5-input.ini`](INPUT_MAPPING.md) beside a converted title.
   - Every action shows its current keyboard and mouse bindings, with the built-in defaults until changed.
   - *Key* records the next key press, modifier keys included. Mouse buttons and wheel directions come from the mouse menu.
   - The same rules as the runtime apply: `ToggleFullscreen` accepts keys only, the wheel maps only to pad buttons, and `#` and `;` cannot be bound because they start comments.
   - A binding shared by two actions is outlined in amber.
   - Lines the runtime would reject are listed before saving. Saving with no changes from the defaults removes the file.
8. **Add to Applications.** Creates `~/Applications/AnyPS5/<Title>.app` for Windows output. It launches the title through its Wine runtime with the Settings environment and the title's launch options, and uses the game's icon. Like a launch from Studio, it writes a session log and, when *Back up saves on launch* is on, backs up `_sd/` first. Standard output and standard error share the log, and its sessions are not counted in the Library's play time. Rebuild it after changing the runtime, the environment or the options.

9. **Launch options.** *Options* on a Library card, or beside Launch in the Console, sets per-title settings applied over the Settings environment:
   - the Wine runtime: *Default* follows the runtime chosen in the Console; picking an installed runtime pins it for this title. If a pinned runtime is uninstalled, the default is used and the pre-launch check warns about it;
   - the Metal Performance HUD (`MTL_HUD_ENABLED=1`), an on-screen frame rate and frame time overlay drawn by macOS;
   - disabling the shader cache (`ANYPS5_NO_SHADER_CACHE=1`);
   - quiet Wine logging (`WINEDEBUG=-all`), which turns off Wine's own debug channels. The title's output still appears; Wine's error messages do not, so leave it off when diagnosing a crash. A `WINEDEBUG` line in the extra variables takes precedence;
   - extra variables;
   - backing up saves on launch: before each launch from Studio, `_sd/` is archived as an `Auto` backup in the save backups folder. The newest 5 automatic backups are kept; manual backups are never removed.

   The panel shows the size of the title's `shader_cache/` folder, lets you clear it, and lists play sessions (count, total time, last exit code). Launchers created with *Add to Applications* use the same settings.

   Each launch from Studio writes its console output to `~/Library/Logs/AnyPS5 Studio/<Title>/Session <date>.log`, which Console.app can also open. Lines from standard error start with `!` and Studio's own notes with `#`. The newest 10 logs per title are kept. *Open last session log* is in the Options panel and the card's context menu.

10. **Title data.** *Data* on a Library card manages the title's runtime files:
    - **Status and notes:** your own record of how the title runs on this Mac. The status is one of *Doesn't start*, *Boots*, *Menus*, *In game* or *Playable*; it can also be set from the card's context menu. The status and the first line of the notes appear on the card. Both are searchable, kept when the title is re-converted, included in Library exports and diagnostics, and stay on this Mac; nothing is sent anywhere.
    - **Save data:** the runtime keeps saves in `_sd/` beside the executable, because guest paths resolve against the working directory. *Back up* writes a zip to `<save backups folder>/<Title>/`. *Restore* backs up the current saves first, then replaces them.
    - **Save backups folder:** `Documents/AnyPS5 Saves` unless changed in Settings (⌘,), where *Use iCloud Drive* picks `iCloud Drive/AnyPS5 Saves` when iCloud Drive is on. Changing it does not move existing backups; restore lists only the current folder. Rebuild *Add to Applications* launchers afterwards, because they store the folder when created.
    - **Owned add-ons:** edits `anyps5-entitlements.ini`, the entitlement labels of add-ons you own, which the runtime reports as installed. Labels are up to 15 characters; `#` and `;` start comments.
11. **Organise and clean up.**
    - The Library sorts by recent activity, title, play time or disk usage, and can be limited to one status (or titles without one). Pinned titles stay on top.
    - *Copy Compatibility Report* in a card's context menu copies a Markdown summary for an issue or pull request: title and ID, status, target, the Mac's chip, memory and macOS version, the Wine runtime, the relinker build, play time, the last exit code and the notes. It contains no file paths.
    - Once a title has been played, a card above the grid shows play time for the last 7 days: the total, the number of sessions, the most played titles, and a bar per day. Sessions count on the day they started. Launches from *Add to Applications* apps are not included.
    - *Move Conversion to Trash* removes a title's output folder, with the option to back up its saves first. It only acts on folders laid out by AnyPS5 Studio (`<name>/<name>.exe`).
    - *Export Library…* and *Import Library…* (the ⋯ menu above the grid) write and read a JSON file with every title, its launch options, play sessions and pins, for moving to another Mac or keeping a copy. Output folders, saves and game files are not included. Importing never removes anything: new titles are added, and titles already in the Library gain missing sessions and, if they have none, launch options. Titles whose output folder does not exist on this Mac are imported too and can be cleared with *Forget missing*.
    - If the Library file cannot be read at startup, it is moved aside as `library.unreadable-<date>.json` next to it in `~/Library/Application Support/AnyPS5 Studio/` instead of being overwritten, and the Library starts empty.
    - *Export Diagnostics*, from a card or the System page, writes a text report with system details, the title's conversion report and sessions, and the console log, for bug reports. It contains file paths; review it before sharing.
12. **Storage.** *Measure* on the System page totals the disk use of the Library's output folders, their shader caches and saves, the save backups folder and the session logs, with buttons to show the last two in Finder. Game files linked into `app0/` are symlinks and are not counted. After measuring, *Clear* deletes every title's `shader_cache/` (rebuilt on the next launch, with more stutter at first) and *Delete* removes the session logs; both ask first, and saves, backups and play times are never touched.
13. **Project updates.** `build-app.sh` records the commit and GitHub repository of each build. The System page compares that commit with `boykopovar:main`, where the relinker and runtime are developed, and lists the newer upstream commits. Each conversion remembers the relinker build that produced it. Titles converted with an older build are marked *Older relinker*, and *Re-convert outdated* queues them for Convert All.
14. **Menu bar.** A game controller icon in the menu bar lists launchable titles, shows conversion progress, and reopens the window. *Continue* at the top relaunches the most recently played title; *Launch Last Played* (⇧⌘L) in the Conversion menu does the same.
15. **Links.** AnyPS5 Studio handles `anyps5://` links, so Shortcuts (*Open URLs*), Raycast, Alfred or a terminal (`open 'anyps5://launch?title=PPSA02929'`) can start a title:
    - `anyps5://launch?title=<title ID or title>` or `anyps5://launch/<title ID>` launches a converted Windows title. Title IDs are matched first, then titles, ignoring case; if several conversions match, the most recently used one wins.
    - `anyps5://library` opens the Library.

    *Copy Launch Link* in a card's context menu copies the link for that title. Studio asks before launching from a link; choose *Launch from links without asking* in that dialog to skip the question later. Links never convert, delete or change anything.

The Controls page also lists connected game controllers. SDL uses the first one, with no configuration needed. While a controller is connected, *Controller test* shows that controller live as macOS reports it: every button lights up when pressed, and it shows both stick positions and how far L2 and R2 are pulled. A stick that stays at least 0.10 off centre while nothing is pressed is marked, because it can drift in games. Controllers that do not report a full gamepad profile to macOS cannot be tested there.

Each conversion also produces a report (target, guest modules, system imports, NID references, AMD-only rewrites, and the failure reason if any). It appears in the Console and on Library cards. *Import fonts* copies `.otf`, `.ttf` and `.ttc` files into `anyps5-fonts/` (see [System fonts](USAGE.md#system-fonts)). To use one set of fonts for every title, import them under *Shared fonts* in Settings (⌘,) instead: they are kept in `~/Library/Application Support/AnyPS5 Studio/Fonts`, and a title without its own `anyps5-fonts/` gets an `anyps5-fonts` link to that folder when it is launched or added to Applications. A title's own folder, or a link you made yourself, is never replaced; a link whose target is gone is. No link is made when the launch environment sets `ANYPS5_SYSTEM_FONTS`. When a title ID appears in [`COMPATIBILITY.md`](COMPATIBILITY.md), its tested status is shown on the Convert page.

When the app is in the background, it posts a notification when a conversion or batch finishes, or when a title launched from Studio exits with a non-zero code. The Dock icon shows how many titles remain.

The System page lists the chip, macOS version, Rosetta and Wine status, and the known gaps above.
