# SoundSource Clone: every project file, verbatim

Generated from the files on disk. Each block below is the complete file, with nothing omitted.
Recreate the tree exactly as shown; the folder that holds `SoundSourceClone.xcodeproj` is the repository root.

## Directory structure

```text
SoundSourceClone/
├── .github/
│   └── workflows/
│       └── build.yml
├── Config/
│   ├── Info.plist
│   └── SoundSourceClone.entitlements
├── docs/
│   ├── panel-eq.png
│   └── panel.png
├── SoundSourceClone.xcodeproj/
│   ├── xcshareddata/
│   │   └── xcschemes/
│   │       └── SoundSourceClone.xcscheme
│   └── project.pbxproj
├── SoundSourceClone/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── Diagnostics.swift
│   │   ├── FloatingPanel.swift
│   │   ├── LoginItem.swift
│   │   ├── MenuBarController.swift
│   │   ├── SnapshotRenderer.swift
│   │   └── SoundSourceApp.swift
│   ├── Audio/
│   │   ├── AlertVolume.swift
│   │   ├── AppIdentityResolver.swift
│   │   ├── AudioDevice.swift
│   │   ├── AudioDeviceManager.swift
│   │   ├── AudioEngine.swift
│   │   ├── AudioProcessMonitor.swift
│   │   ├── CapturePermission.swift
│   │   ├── CoreAudioSupport.swift
│   │   ├── InputLevelMonitor.swift
│   │   ├── Log.swift
│   │   ├── ProcessTapSession.swift
│   │   └── StereoProcessor.swift
│   ├── Model/
│   │   ├── AppEntry.swift
│   │   ├── AudioSettings.swift
│   │   ├── EQPreset.swift
│   │   └── PreviewData.swift
│   └── UI/
│       ├── Components/
│       │   ├── Controls.swift
│       │   ├── PopUpMenuButton.swift
│       │   └── VolumeSlider.swift
│       ├── ApplicationsSectionView.swift
│       ├── AppRowView.swift
│       ├── BottomBarView.swift
│       ├── DetailPanels.swift
│       ├── EqualizerPanel.swift
│       ├── HeaderView.swift
│       ├── PopoverRootView.swift
│       ├── SettingsView.swift
│       ├── SystemSectionView.swift
│       └── Theme.swift
├── .gitignore
└── README.md
```

Binary files (screenshots used only by the README, not needed to build): `docs/panel-eq.png`, `docs/panel.png`

## Files

### `.github/workflows/build.yml`

````yaml
# Builds SoundSource Clone on a GitHub macOS runner, packages it as SoundSource-Clone.dmg and
# attaches the DMG to a GitHub Release.
#
# Run it from the browser: Actions tab › "Build DMG" › Run workflow. Pushing a tag such as v1.2.0
# also runs it.
#
# Signing:
#   • With no secrets set, the app is ad-hoc signed. It works, but macOS asks you once to approve it
#     (System Settings › Privacy & Security › Open Anyway).
#   • To get a DMG that opens with no warning at all, add these repository secrets (paid Apple
#     Developer Program account required); the workflow then signs with Developer ID and notarizes:
#       DEVELOPER_ID_CERTIFICATE_P12       base64 of your "Developer ID Application" .p12 export
#       DEVELOPER_ID_CERTIFICATE_PASSWORD  the password you set when exporting the .p12
#       APPLE_TEAM_ID                      your 10-character Team ID
#       NOTARY_API_KEY_P8                  contents of the App Store Connect API key (.p8) file
#       NOTARY_KEY_ID                      that key's Key ID
#       NOTARY_ISSUER_ID                   your App Store Connect Issuer ID

name: Build DMG

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Version number, e.g. 1.0.0 (leave empty to use the build number)"
        required: false
        default: ""
  push:
    tags:
      - "v*"

permissions:
  contents: write   # needed to create the release and upload the DMG

concurrency:
  group: build-dmg-${{ github.ref }}
  cancel-in-progress: false

defaults:
  run:
    shell: bash   # GitHub runs this as `bash -eo pipefail`, so any failing command stops the job

jobs:
  build:
    name: Build, package and release
    runs-on: macos-26
    timeout-minutes: 45
    env:
      APP_NAME: SoundSource Clone
      DMG_NAME: SoundSource-Clone.dmg
      SCHEME: SoundSourceClone
      HAS_DEVELOPER_ID: ${{ secrets.DEVELOPER_ID_CERTIFICATE_P12 != '' }}

    steps:
      - name: Check out the code
        uses: actions/checkout@v5

      - name: Find the Xcode project
        run: |
          # Works whether the project sits at the repository root or one folder down.
          PBXPROJ=$(find . -path ./build -prune -o -name project.pbxproj -path "*SoundSourceClone.xcodeproj/*" -print | head -n 1)
          if [[ -z "$PBXPROJ" ]]; then
            echo "::error::SoundSourceClone.xcodeproj was not found in the repository. Upload the whole project folder."
            exit 1
          fi
          PROJECT_DIR=$(cd "$(dirname "$PBXPROJ")/.." && pwd)
          echo "PROJECT_DIR=$PROJECT_DIR" >> "$GITHUB_ENV"
          echo "Project folder: $PROJECT_DIR"

      - name: Choose the version number
        env:
          INPUT_VERSION: ${{ github.event.inputs.version }}
        run: |
          if [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
            VERSION="${GITHUB_REF_NAME#v}"
            TAG="$GITHUB_REF_NAME"
          elif [[ -n "$INPUT_VERSION" ]]; then
            VERSION="${INPUT_VERSION#v}"
            TAG="v$VERSION"
          else
            VERSION="1.0.$GITHUB_RUN_NUMBER"
            TAG="build-$GITHUB_RUN_NUMBER"
          fi
          if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
            echo "::error::Version must look like 1.2 or 1.2.3 (got '$VERSION')."
            exit 1
          fi
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"
          echo "TAG=$TAG" >> "$GITHUB_ENV"
          echo "Building version $VERSION (release tag $TAG)"

      - name: Show the Xcode version
        run: xcodebuild -version

      - name: Import the Developer ID certificate
        if: env.HAS_DEVELOPER_ID == 'true'
        env:
          DEVELOPER_ID_CERTIFICATE_P12: ${{ secrets.DEVELOPER_ID_CERTIFICATE_P12 }}
          DEVELOPER_ID_CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
          KEYCHAIN_PASSWORD=$(uuidgen)
          echo "$DEVELOPER_ID_CERTIFICATE_P12" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security import "$RUNNER_TEMP/certificate.p12" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k "$KEYCHAIN"
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          rm -f "$RUNNER_TEMP/certificate.p12"
          echo "KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"

      - name: Build the app (universal, Release)
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          cd "$PROJECT_DIR"
          if [[ "$HAS_DEVELOPER_ID" == "true" ]]; then
            SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application"
                     "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" "OTHER_CODE_SIGN_FLAGS=--timestamp --keychain $KEYCHAIN")
          else
            # Ad-hoc ("Sign to Run Locally"): needs no Apple account, team or certificate.
            SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=-" "DEVELOPMENT_TEAM=")
          fi
          xcodebuild \
            -project SoundSourceClone.xcodeproj \
            -scheme "$SCHEME" \
            -configuration Release \
            -destination "generic/platform=macOS" \
            -derivedDataPath "$RUNNER_TEMP/DerivedData" \
            ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
            MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
            "${SIGNING[@]}" \
            -quiet build
          APP_PATH="$RUNNER_TEMP/DerivedData/Build/Products/Release/SoundSourceClone.app"
          codesign --verify --deep --strict --verbose=2 "$APP_PATH"
          echo "Architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/SoundSourceClone")"
          echo "APP_PATH=$APP_PATH" >> "$GITHUB_ENV"

      - name: Package SoundSource-Clone.dmg
        run: |
          STAGING="$RUNNER_TEMP/dmg"
          rm -rf "$STAGING" && mkdir -p "$STAGING" "$GITHUB_WORKSPACE/dist"
          ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
          ln -s /Applications "$STAGING/Applications"   # drag-to-install target
          DMG_PATH="$GITHUB_WORKSPACE/dist/$DMG_NAME"
          # hdiutil occasionally fails with "Resource busy" on CI machines; retry a few times.
          for attempt in 1 2 3 4; do
            if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG_PATH"; then
              break
            fi
            [[ $attempt == 4 ]] && exit 1
            echo "hdiutil failed, retrying in 5 seconds…"
            sleep 5
          done
          hdiutil verify "$DMG_PATH"
          echo "DMG_PATH=$DMG_PATH" >> "$GITHUB_ENV"

      - name: Sign and notarize the DMG
        if: env.HAS_DEVELOPER_ID == 'true'
        env:
          NOTARY_API_KEY_P8: ${{ secrets.NOTARY_API_KEY_P8 }}
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
        run: |
          codesign --force --timestamp --sign "Developer ID Application" --keychain "$KEYCHAIN" "$DMG_PATH"
          printf '%s\n' "$NOTARY_API_KEY_P8" > "$RUNNER_TEMP/notary-key.p8"
          xcrun notarytool submit "$DMG_PATH" \
            --key "$RUNNER_TEMP/notary-key.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
            --wait --timeout 30m
          xcrun stapler staple "$DMG_PATH"
          rm -f "$RUNNER_TEMP/notary-key.p8"

      - name: Write checksum and release notes
        run: |
          cd "$GITHUB_WORKSPACE/dist"
          shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
          if [[ "$HAS_DEVELOPER_ID" == "true" ]]; then
            FIRST_OPEN="Signed with Developer ID and notarized by Apple, so it opens normally."
          else
            FIRST_OPEN=$(printf '%s\n' \
              "This build is not notarized, so the first time you open it macOS blocks it:" \
              "1. Open the app once and click **Done** on the warning." \
              "2. Go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to SoundSource Clone, then confirm." \
              "You only do this once.")
          fi
          cat > release-notes.md <<EOF
          ## SoundSource Clone $VERSION

          **Install:** open \`$DMG_NAME\` and drag **$APP_NAME** onto **Applications**. Requires macOS 14.2 or later (Apple silicon and Intel).

          **First launch:** $FIRST_OPEN

          Then click **Allow** when macOS asks for System Audio Recording, which per-app volume needs. The app lives in the menu bar (speaker-cabinet icon); turn on *Launch at Login* from its gear menu.

          SHA-256: \`$(cut -d ' ' -f 1 "$DMG_NAME.sha256")\`
          EOF
          cat release-notes.md

      - name: Upload the DMG as a workflow artifact
        uses: actions/upload-artifact@v4
        with:
          name: SoundSource-Clone-${{ env.VERSION }}
          path: |
            dist/SoundSource-Clone.dmg
            dist/SoundSource-Clone.dmg.sha256
          if-no-files-found: error

      - name: Publish the GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          cd "$GITHUB_WORKSPACE/dist"
          if gh release view "$TAG" > /dev/null 2>&1; then
            gh release upload "$TAG" "$DMG_NAME" "$DMG_NAME.sha256" --clobber
          else
            gh release create "$TAG" "$DMG_NAME" "$DMG_NAME.sha256" \
              --title "$APP_NAME $VERSION" \
              --notes-file release-notes.md \
              --target "$GITHUB_SHA"
          fi
          echo "### Download: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/tag/$TAG" >> "$GITHUB_STEP_SUMMARY"

      - name: Remove the temporary keychain
        if: always() && env.HAS_DEVELOPER_ID == 'true'
        run: security delete-keychain "$RUNNER_TEMP/signing.keychain-db" || true
````

### `.gitignore`

````text
build/
DerivedData/
*.xcuserstate
xcuserdata/
.DS_Store
dist/
````

### `README.md`

````markdown
# SoundSource Clone

A native macOS menu bar app modelled on Rogue Amoeba's SoundSource: system output/input/alert
volume and device selection, plus **per-app volume (0–200 %), mute, balance, 10-band EQ and
per-app output routing**. Swift 5 language mode, SwiftUI + AppKit, no kernel extension or audio driver.

![Panel](docs/panel.png)

## How per-app audio works

macOS 14.2 added **Core Audio process taps** (`CATapDescription`, `AudioHardwareCreateProcessTap`).
For every app that plays audio, the engine builds this chain:

```
app processes ──▶ process tap (stereo mixdown, muteBehavior = .mutedWhenTapped)
                         │
private aggregate device = [target output device] + [tap]   (tap drift-compensated)
                         │  IOProc on the real-time thread:
                         │  tap input → gain → EQ → balance → soft clip → meter
                         ▼
                 target output device  (system default, the app's own device, or a chosen route)
```

* The tap mutes the app at its source **only while our IOProc is reading**. If this app stalls,
  quits or crashes, the HAL destroys the tap and the app's audio is untouched.
* Routing an app to another device only rebuilds the aggregate; the tap stays in place.
* Chrome/Electron helpers and Safari's WebKit GPU process are grouped under their app using the
  "responsible process" SPI (the one TCC uses), with an outermost-`.app`-bundle fallback.
* The DSP (`StereoProcessor`) never allocates or locks on the IO thread. Parameters cross threads
  through preallocated memory, and the EQ coefficients are double-buffered.

| Layer | Files |
|---|---|
| Entry point, status item, floating panel | `App/SoundSourceApp.swift`, `App/AppDelegate.swift`, `App/MenuBarController.swift`, `App/FloatingPanel.swift` |
| Core Audio helpers, devices, system volume | `Audio/CoreAudioSupport.swift`, `Audio/AudioDevice.swift`, `Audio/AudioDeviceManager.swift`, `Audio/AlertVolume.swift` |
| Per-app capture | `Audio/AudioProcessMonitor.swift`, `Audio/AppIdentityResolver.swift`, `Audio/ProcessTapSession.swift`, `Audio/StereoProcessor.swift`, `Audio/CapturePermission.swift` |
| Orchestration and persistence | `Audio/AudioEngine.swift`, `Model/*` |
| SwiftUI panel | `UI/*` (custom sliders and meters in `UI/Components/VolumeSlider.swift`, NSMenu-backed pickers in `UI/Components/PopUpMenuButton.swift`) |

## Get a ready-to-install DMG from GitHub (browser only, no Terminal)

`.github/workflows/build.yml` builds the app on GitHub's macOS 26 runner as a universal binary
(Apple silicon + Intel), packages `SoundSource-Clone.dmg` and attaches it to a GitHub Release.

1. **Upload the project.** On github.com click **+ › New repository**, name it, and create it
   with nothing added (no README). On the empty repository page click **uploading an existing
   file**. In Finder, open this folder and press **⌘⇧.** (Command-Shift-Period) so the hidden
   `.github` folder shows. Select everything (**⌘A**), drag it onto the page, wait for the file
   list, then click **Commit changes**. Check that `.github/workflows/build.yml` appears in the
   repository. If it doesn't, use **Add file › Create new file**, type
   `.github/workflows/build.yml` as the name, paste the file's contents, and commit.
2. **Build it.** Open the **Actions** tab. If asked, click the button to enable workflows. Choose
   **Build DMG** on the left, click **Run workflow** (you can type a version such as `1.0.0`), then
   the green **Run workflow** button. The run takes a few minutes and ends with a green check.
3. **Download it.** On the repository's **Code** tab, click **Releases** in the right sidebar,
   open the newest release, and click **SoundSource-Clone.dmg**. Open it and drag
   **SoundSource Clone** onto **Applications**.

**First launch.** Without signing secrets the build is ad-hoc signed, so macOS blocks the first
launch. Click **Done**, then open **System Settings › Privacy & Security** and click **Open
Anyway** (once). Then click **Allow** for System Audio Recording. To have it start by itself
from then on, turn on **Launch at Login** in the panel's gear menu.

Pushing a tag such as `v1.2.0` also builds and publishes a release. Every run also keeps the DMG
as a downloadable artifact on its run page. Releases in a public repository can be downloaded by
anyone. macOS runner minutes are free for public repositories; private repositories use the
plan's included minutes, which macOS jobs consume faster than Linux jobs.

### Optional: no security warning at all (Developer ID + notarization)

This needs a paid Apple Developer Program membership. Add these under the repository's
**Settings › Secrets and variables › Actions › New repository secret**. The workflow detects them
and signs, notarizes and staples the DMG:

| Secret | Where to get it (no Terminal) |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12` | Create a *Developer ID Application* certificate at developer.apple.com (Keychain Access › Certificate Assistant makes the request file), install it, then in Keychain Access › My Certificates right-click it › **Export** as `.p12`. Base64 it with the Shortcuts app: *Select File* → *Base64 Encode* (Line Breaks: None) → *Copy to Clipboard*. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password you chose during that export |
| `APPLE_TEAM_ID` | developer.apple.com › Account › Membership details |
| `NOTARY_API_KEY_P8` | appstoreconnect.apple.com › Users and Access › Integrations › App Store Connect API: generate a key, download the `.p8`, open it in TextEdit and copy everything |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Shown on that same API keys page |

## Requirements

* macOS **14.2** or later (14.4+ recommended; that's where the System Audio Recording permission exists)
* Xcode **16** or later (the project uses folder-synchronised groups)

## Run it (included project)

1. Open `SoundSourceClone.xcodeproj`.
2. Select the **SoundSourceClone** target › **Signing & Capabilities** › choose your **Team**.
   It builds without one ("Sign to Run Locally"), but then macOS forgets the audio permission
   after every rebuild because the ad-hoc signature changes.
3. Press **⌘R**. A speaker icon appears in the menu bar. There is no Dock icon (`LSUIElement`).
4. On first launch, allow **System Audio Recording**. If you dismissed the prompt, go to
   System Settings › Privacy & Security › Screen & System Audio Recording ›
   *System Audio Recording Only* and enable **SoundSource Clone**. The panel also shows a
   **Grant Access** button.
5. Play something (Spotify, a YouTube tab). It appears under **Applications** within a moment.

> Quit Rogue Amoeba's SoundSource and its Audio Routing Kit (`arkaudiod`) while you test.
> Two per-app audio engines intercepting the same apps will fight each other.

Command-line build:

```bash
xcodebuild -project SoundSourceClone.xcodeproj -scheme SoundSourceClone -configuration Release build
```

## Recreating the project from scratch in Xcode

If you'd rather start from Xcode's template:

1. **File › New › Project › macOS › App**. Interface *SwiftUI*, language *Swift*, product name
   `SoundSourceClone`.
2. Delete the generated `SoundSourceCloneApp.swift` and `ContentView.swift`. Drag the
   `SoundSourceClone/` source folder from this repo into the project ("Create folders").
   `App/SoundSourceApp.swift` contains the `@main` entry point.
3. **General** › Minimum Deployments: **macOS 14.2**.
4. **Build Settings**:
   * *Swift Language Version* → **Swift 5**
   * *Default Actor Isolation* → **nonisolated**. Xcode 26 templates default to MainActor, which
     would isolate the real-time render code to the main thread and break the IOProc.
   * *Info.plist File* → `Config/Info.plist`, and *Generate Info.plist File* → **No**
     (or add the keys below to the target's **Info** tab instead).
5. **Info.plist keys** (all already in `Config/Info.plist`):

   | Key | Value | Why |
   |---|---|---|
   | `LSUIElement` (Application is agent) | `YES` | Menu bar only, no Dock icon or main menu |
   | `NSAudioCaptureUsageDescription` | purpose string | Required for process taps. Without it, tap creation fails |
   | `NSMicrophoneUsageDescription` | purpose string | Only for the optional microphone level meter |

6. **Signing & Capabilities**:
   * Remove **App Sandbox**. Private aggregate devices and process taps are meant for
     non-sandboxed, Developer ID–distributed apps (SoundSource isn't on the Mac App Store either).
   * Keep **Hardened Runtime** and tick **Resource Access › Audio Input**
     (`com.apple.security.device.audio-input`, used by the optional mic meter).
   * Or point *Code Signing Entitlements* at `Config/SoundSourceClone.entitlements`.
7. Build & run.

## Using it

* **Header**: pin (keep the panel open when clicking elsewhere), routing toggle (show or hide the
  per-app device column), PRO / Trial Mode badge (cosmetic; switch it in Settings), microphone
  quick-mute, and a gear menu (Settings, Launch at Login, About, Quit).
* **System**
  * *Output*: hardware volume with a live meter (loudest captured app), system EQ (applied to
    every captured app), default output device, and a chevron for sample rate and balance.
  * *Input*: input gain and default input device. The level meter is opt-in in Settings, because
    reading the mic lights the orange indicator.
  * *Sound Effects*: alert volume (via Standard Additions) and the alert output device.
* **Applications**: star to favorite (favorites stay listed when not running), click the app icon
  to mute, slider 0–200 % with a detent at 100 % (the area past the tick is boost), EQ button,
  output route picker, and a chevron for balance, status, reset and Show in Finder. Double-click
  any slider to reset it.
* **Bottom bar**: *Add Favorite* (running apps or *Choose Application…*) and *Quick Configs*
  (save, apply or delete snapshots of app settings, system devices and volumes, and the system EQ).
* **Settings › Capture**: *All apps that play audio* (default; gives every app a meter) or
  *Only apps I adjust* (apps at 100 % with no EQ or route are left untouched).

Settings persist in `UserDefaults` under `SoundSourceClone.state.v1`.

## Debug helpers

```bash
# Read-only: list devices, default devices, volumes, permission state and process → app grouping
SoundSourceClone.app/Contents/MacOS/SoundSourceClone --diagnose

# Render the panel with sample data to a PNG (no Core Audio access)
SoundSourceClone.app/Contents/MacOS/SoundSourceClone --snapshot panel.png [--expanded]

# Launch with per-app peak levels logged every 2 s (while the panel is closed)
open -n SoundSourceClone.app --args --log-levels

# Open the panel at launch; --dump-panel also writes the live panel's view hierarchy to a PNG
open -n SoundSourceClone.app --args --show-panel
open -n SoundSourceClone.app --args --dump-panel /tmp/panel.png
```

Only one copy runs at a time. Launching a second one (another build, or Xcode while a copy is
already running) opens the running copy's panel and quits. Quit the running copy first if you
want to debug in Xcode.

Capture events (permission, start, reroute, stop, failures) and the stream layout of each
aggregate go to the unified log:

```bash
/usr/bin/log stream --style compact --predicate 'subsystem == "com.example.SoundSourceClone"'
```

Use `/usr/bin/log` in zsh, where a bare `log` is a shell builtin.

SwiftUI previews (`#Preview` in `PopoverRootView.swift`) use the same sample data.

## Known limitations

* System EQ only reaches captured apps. Audio from uncaptured processes (system sounds, daemons)
  bypasses it.
* Devices without hardware volume (many HDMI/DisplayPort outputs) show the system slider as
  unavailable. Per-app sliders still work on them.
* Output devices that also have microphones (USB or Bluetooth headsets) are added to the aggregate
  with their input streams disabled through `kAudioDevicePropertyIOProcStreamUsage`, so Bluetooth
  headsets shouldn't drop into hands-free mode. Test this with your own headset.
* If an app goes silent while captured (for example DRM-protected playback that a tap can't read),
  reset that app or switch Settings › Capture to *Only apps I adjust*.
* Capture permission is checked through the private TCC SPI, loaded with `dlopen` like
  insidegui/AudioCap does. If Apple removes the SPI, the app falls back to the system prompt
  that appears when the first tap is created.
* "SoundSource" is a Rogue Amoeba trademark. Rename the app before sharing or distributing it.
````

### `Config/Info.plist`

````xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>SoundSource Clone</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHumanReadableCopyright</key>
	<string>Personal project. Not affiliated with Rogue Amoeba.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>SoundSource Clone captures each app's audio so it can change that app's volume, apply effects and send it to a different output device.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>SoundSource Clone shows your microphone's input level when you turn on the input meter.</string>
</dict>
</plist>
````

### `Config/SoundSourceClone.entitlements`

````xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
````

### `SoundSourceClone.xcodeproj/project.pbxproj`

````text
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXFileReference section */
		5D0000000000000000000001 /* SoundSourceClone.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SoundSourceClone.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		5D0000000000000000000002 /* SoundSourceClone */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = SoundSourceClone;
			sourceTree = "<group>";
		};
		5D0000000000000000000003 /* Config */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Config;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		5D0000000000000000000004 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		5D0000000000000000000005 = {
			isa = PBXGroup;
			children = (
				5D0000000000000000000002 /* SoundSourceClone */,
				5D0000000000000000000003 /* Config */,
				5D0000000000000000000006 /* Products */,
			);
			sourceTree = "<group>";
		};
		5D0000000000000000000006 /* Products */ = {
			isa = PBXGroup;
			children = (
				5D0000000000000000000001 /* SoundSourceClone.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		5D0000000000000000000007 /* SoundSourceClone */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 5D000000000000000000000E /* Build configuration list for PBXNativeTarget "SoundSourceClone" */;
			buildPhases = (
				5D000000000000000000000A /* Sources */,
				5D0000000000000000000004 /* Frameworks */,
				5D0000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				5D0000000000000000000002 /* SoundSourceClone */,
			);
			name = SoundSourceClone;
			packageProductDependencies = (
			);
			productName = SoundSourceClone;
			productReference = 5D0000000000000000000001 /* SoundSourceClone.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		5D0000000000000000000008 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {
					5D0000000000000000000007 = {
						CreatedOnToolsVersion = 16.0;
					};
				};
			};
			buildConfigurationList = 5D000000000000000000000B /* Build configuration list for PBXProject "SoundSourceClone" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 5D0000000000000000000005;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = 5D0000000000000000000006 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				5D0000000000000000000007 /* SoundSourceClone */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		5D0000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		5D000000000000000000000A /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		5D000000000000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.2;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		5D000000000000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.2;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			};
			name = Release;
		};
		5D000000000000000000000F /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Config/SoundSourceClone.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Config/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.SoundSourceClone;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		5D0000000000000000000010 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Config/SoundSourceClone.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Config/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.SoundSourceClone;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		5D000000000000000000000B /* Build configuration list for PBXProject "SoundSourceClone" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				5D000000000000000000000C /* Debug */,
				5D000000000000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		5D000000000000000000000E /* Build configuration list for PBXNativeTarget "SoundSourceClone" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				5D000000000000000000000F /* Debug */,
				5D0000000000000000000010 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 5D0000000000000000000008 /* Project object */;
}
````

### `SoundSourceClone/App/AppDelegate.swift`

````swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: AudioEngine?
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `SoundSourceClone --snapshot out.png [--expanded]` renders the panel with sample data and exits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            SnapshotRenderer.render(to: URL(fileURLWithPath: arguments[index + 1]),
                                    expanded: arguments.contains("--expanded"))
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--diagnose") {
            Diagnostics.run()
            NSApp.terminate(nil)
            return
        }

        // One engine at a time: a second copy (another build, an Xcode run) asks the running one to
        // show its panel and quits, instead of capturing apps a second time.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ownPID }
        if !others.isEmpty {
            Log.ui.notice("Another copy is already running (pid \(others[0].processIdentifier, privacy: .public)); handing off")
            DistributedNotificationCenter.default().postNotificationName(Self.showPanelNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        let engine = AudioEngine()
        self.engine = engine
        engine.start()
        let menuBar = MenuBarController(engine: engine) { [weak self] in self?.showSettings() }
        self.menuBar = menuBar
        DistributedNotificationCenter.default().addObserver(forName: Self.showPanelNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuBar?.revealPanel() }
        }
    }

    private static let showPanelNotification = Notification.Name("com.example.SoundSourceClone.showPanel")

    /// Opening the app again (Finder, Spotlight, `open`) while it runs reveals the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.revealPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.shutdown()
    }

    private func showSettings() {
        guard let engine else { return }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(engine))
            let window = NSWindow(contentViewController: controller)
            window.title = "SoundSource Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
````

### `SoundSourceClone/App/Diagnostics.swift`

````swift
import AppKit
import CoreAudio

/// `SoundSourceClone --diagnose` prints what the engine would see, without creating any taps.
@MainActor
enum Diagnostics {
    static func run() {
        let devices = AudioDeviceManager()
        devices.start()
        print("== Devices ==")
        for device in devices.devices {
            var roles: [String] = []
            if device.id == devices.defaultOutputID { roles.append("default output") }
            if device.id == devices.defaultInputID { roles.append("default input") }
            if device.id == devices.systemOutputID { roles.append("sound effects") }
            print("  [\(device.id)] \(device.name)  in:\(device.inputChannels) out:\(device.outputChannels)  uid:\(device.uid)"
                  + (roles.isEmpty ? "" : "  <- \(roles.joined(separator: ", "))"))
        }
        print("Output volume: \(devices.outputVolumeAvailable ? Theme.percent(devices.outputVolume) : "n/a")"
              + (devices.outputMuted ? " (muted)" : "")
              + "  sample rate: \(devices.outputSampleRate) Hz  rates: \(devices.outputSampleRates)")
        print("Input volume:  \(devices.inputVolumeAvailable ? Theme.percent(devices.inputVolume) : "n/a")"
              + (devices.inputMuted ? " (muted)" : ""))
        print("Alert volume:  \(Theme.percent(devices.alertVolume))")

        let permission: String
        switch CapturePermission.status {
        case .authorized: permission = "authorized"
        case .denied: permission = "denied"
        case .unknown: permission = CapturePermission.canRequest ? "not determined" : "unknown (TCC SPI unavailable)"
        }
        print("System Audio Recording permission: \(permission)")

        let processIDs = AudioObjectID.system.readArray(.init(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        let resolver = AppIdentityResolver()
        var groups: [String: [String]] = [:]
        var unresolved: [String] = []
        for id in processIDs {
            guard let pid = id.read(.init(kAudioProcessPropertyPID), initial: pid_t(-1)), pid > 0 else { continue }
            let bundleID = id.readString(.init(kAudioProcessPropertyBundleID))
            let playing = (id.read(.init(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0)) ?? 0) != 0
            let process = AudioProcess(objectID: id, pid: pid, bundleID: bundleID, isRunningOutput: playing)
            let label = "pid \(pid) \(bundleID ?? "?")\(playing ? " ▶︎ playing" : "")"
            if let identity = resolver.identity(for: process) {
                groups["\(identity.name) (\(identity.id))", default: []].append(label)
            } else {
                unresolved.append(label)
            }
        }
        print("== Audio processes → apps (\(processIDs.count) process objects) ==")
        for (app, members) in groups.sorted(by: { $0.key < $1.key }) {
            print("  \(app)")
            members.forEach { print("      \($0)") }
        }
        print("  (not shown as apps: \(unresolved.count))")
        unresolved.prefix(12).forEach { print("      \($0)") }
    }
}
````

### `SoundSourceClone/App/FloatingPanel.swift`

````swift
import AppKit
import SwiftUI

/// Borderless, non-activating, dark translucent panel that hangs below the status item —
/// the same kind of overlay SoundSource uses instead of an `NSPopover`.
final class FloatingPanel: NSPanel {
    private let effectView = NSVisualEffectView()

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .darkAqua)

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: Theme.cornerRadius)
        contentView = effectView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var hostingController: NSViewController?
    private var sizeObservation: NSKeyValueObservation?

    /// Called with SwiftUI's ideal content height whenever it changes.
    var onContentHeightChange: ((CGFloat) -> Void)?

    func setRootView<Content: View>(_ view: Content) {
        let controller = NSHostingController(rootView: view)
        // SwiftUI publishes its ideal size as preferredContentSize; the menu bar controller turns that
        // into a top-anchored window frame. The hosting view itself adds no size constraints.
        controller.sizingOptions = [.preferredContentSize]
        let hosting = controller.view
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        hostingController = controller
        sizeObservation = controller.observe(\.preferredContentSize, options: [.initial, .new]) { [weak self] controller, _ in
            let height = controller.preferredContentSize.height
            DispatchQueue.main.async { self?.onContentHeightChange?(height) }
        }
    }

    var contentHeight: CGFloat { hostingController?.preferredContentSize.height ?? 0 }

    /// Renders the live SwiftUI content to a PNG (for `--dump-panel`; no screen-recording permission needed).
    func writeContentImage(to url: URL) -> Bool {
        guard let view = hostingController?.view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        // The blur isn't captured, so composite over a dark fill like the real panel's background.
        let image = NSImage(size: view.bounds.size, flipped: false) { rect in
            NSColor(white: 0.14, alpha: 1).setFill()
            rect.fill()
            rep.draw(in: rect)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Stretchable rounded-rect mask: the reliable way to round an NSVisualEffectView's corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
````

### `SoundSourceClone/App/LoginItem.swift`

````swift
import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SoundSourceClone: launch at login change failed: \(error.localizedDescription)")
        }
    }
}
````

### `SoundSourceClone/App/MenuBarController.swift`

````swift
import AppKit
import Observation
import SwiftUI

/// UI state shared between the panel's SwiftUI views and the controller that owns the window.
@MainActor @Observable
final class PanelState {
    var isPinned = false
    var maxScrollHeight: CGFloat = 560
    @ObservationIgnored var isSnapshot = false
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var close: () -> Void = {}
}

/// Owns the status item and toggles the floating panel beneath it.
@MainActor
final class MenuBarController: NSObject {
    private let engine: AudioEngine
    private let state = PanelState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 420))
    private var contentHeight: CGFloat = 420
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    init(engine: AudioEngine, openSettings: @escaping () -> Void) {
        self.engine = engine
        super.init()

        state.openSettings = { [weak self] in
            self?.hidePanel(force: true)
            openSettings()
        }
        state.close = { [weak self] in self?.hidePanel(force: true) }
        panel.onContentHeightChange = { [weak self] height in
            MainActor.assumeIsolated { self?.contentHeightChanged(height) }
        }
        panel.setRootView(PopoverRootView().environment(engine).environment(state))

        statusItem.autosaveName = "SoundSourceClone"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "SoundSource"
        }
        trackVolumeForIcon()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.logStatusItemPlacement()
                // `--show-panel` opens the panel at launch (handy when the menu bar icon is hidden).
                // `--dump-panel <path.png>` also renders the live panel to a file two seconds later.
                let arguments = CommandLine.arguments
                let dumpPath = arguments.firstIndex(of: "--dump-panel").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
                if arguments.contains("--show-panel") || dumpPath != nil { self.showPanel() }
                if let dumpPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        MainActor.assumeIsolated { self?.dumpPanel(to: URL(fileURLWithPath: dumpPath)) }
                    }
                }
            }
        }
    }

    private func dumpPanel(to url: URL) {
        let written = panel.writeContentImage(to: url)
        Log.ui.notice("Panel dump \(written ? "written" : "failed", privacy: .public): frame \(NSStringFromRect(self.panel.frame), privacy: .public), SwiftUI ideal height \(self.panel.contentHeight, privacy: .public), visible \(self.panel.isVisible, privacy: .public)")
    }

    private func logStatusItemPlacement() {
        let window = statusItem.button?.window
        let frame = window.map { NSStringFromRect($0.frame) } ?? "none"
        Log.ui.notice("Status item visible: \(self.statusItem.isVisible, privacy: .public), window frame: \(frame, privacy: .public), screen: \(window?.screen?.localizedName ?? "none", privacy: .public), on screen: \(window?.isOnActiveSpace ?? false, privacy: .public)")
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else if panel.isVisible {
            hidePanel(force: true)
        } else {
            showPanel()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = MenuBuilder.menu([
            .action("Open SoundSource", symbol: "slider.horizontal.3") { [weak self] in self?.showPanel() },
            .action("Settings…", symbol: "gearshape") { [weak self] in self?.state.openSettings() },
            .separator,
            .action("Quit SoundSource Clone", symbol: "power") { NSApp.terminate(nil) },
        ])
        MenuBuilder.popUp(menu, below: button)
    }

    /// Keeps the menu bar glyph in sync with the output volume using Observation.
    private func trackVolumeForIcon() {
        withObservationTracking {
            updateStatusIcon()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackVolumeForIcon() }
        }
    }

    /// A speaker cabinet rather than the speaker cone, so it can't be mistaken for macOS's own Sound menu.
    private func updateStatusIcon() {
        let devices = engine.devices
        let muted = devices.outputMuted || (devices.outputVolumeAvailable && devices.outputVolume < 0.01)
        let image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "hifispeaker.fill",
                            accessibilityDescription: "SoundSource")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = image == nil ? "SS" : ""
    }

    // MARK: Panel

    func revealPanel() {
        if !panel.isVisible { showPanel() }
    }

    private func showPanel() {
        engine.devices.refresh()
        engine.recheckPermission()
        engine.beginMetering()
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)
        installMonitors()
    }

    private func hidePanel(force: Bool = false) {
        guard panel.isVisible, force || !state.isPinned else { return }
        panel.orderOut(nil)
        engine.endMetering()
        statusItem.button?.highlight(false)
        removeMonitors()
    }

    /// Header + footer alone are ~85 pt; anything smaller is a layout pass before the content exists.
    private static let minimumHeight: CGFloat = 120

    private func contentHeightChanged(_ height: CGFloat) {
        let rounded = ceil(height)
        Log.ui.debug("Reported content height \(rounded, privacy: .public)")
        guard rounded >= 60, abs(rounded - contentHeight) > 0.5 else { return }
        contentHeight = rounded
        if panel.isVisible { positionPanel() }
    }

    /// Top edge stays pinned just below the menu bar; the panel grows downwards.
    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let chrome: CGFloat = 100   // header + footer + hairlines
        let maxScroll = max(visible.height - chrome - 24, 200)
        if abs(state.maxScrollHeight - maxScroll) > 0.5 { state.maxScrollHeight = maxScroll }

        let width = Theme.panelWidth
        // Never size to zero: a zero-area window never lays out, so it could never report its real height.
        let height = max(min(contentHeight, visible.height - 12), Self.minimumHeight)
        let x = min(max(buttonFrame.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let y = buttonFrame.minY - height - 6
        let frame = NSRect(x: x, y: y, width: width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            Log.ui.notice("Panel frame \(NSStringFromRect(frame), privacy: .public) (content height \(self.contentHeight, privacy: .public))")
        }
    }

    private func installMonitors() {
        removeMonitors()
        // Global monitors only see clicks delivered to other apps — exactly "clicked outside".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isKeyWindow else { return false }
                self.hidePanel(force: true)
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        outsideClickMonitor = nil
        keyMonitor = nil
    }
}
````

### `SoundSourceClone/App/SnapshotRenderer.swift`

````swift
import AppKit
import SwiftUI

/// Renders the panel with `PreviewData` to a PNG, without touching Core Audio.
@MainActor
enum SnapshotRenderer {
    static func render(to url: URL, expanded: Bool) {
        let engine = AudioEngine(preview: true)
        if expanded { engine.previewExpandedAppID = PreviewData.expandedAppID }
        let state = PanelState()
        state.isSnapshot = true

        let content = PopoverRootView()
            .environment(engine)
            .environment(state)
            .background(Theme.snapshotBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .padding(28)
            .background(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)],
                                       startPoint: .top, endPoint: .bottom))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        // On HDR displays ImageRenderer can produce a BT.2100 PQ image; flatten to 8-bit sRGB.
        guard let rendered = renderer.cgImage,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: rendered.width, height: rendered.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("Snapshot rendering failed")
            return
        }
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("Snapshot rendering failed")
            return
        }
        do {
            try data.write(to: url)
            print("Snapshot written to \(url.path)")
        } catch {
            print("Snapshot write failed: \(error.localizedDescription)")
        }
    }
}
````

### `SoundSourceClone/App/SoundSourceApp.swift`

````swift
import AppKit

/// Plain AppKit entry point: the app is a menu bar agent (LSUIElement) with no main window.
@main
enum SoundSourceMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
````

### `SoundSourceClone/Audio/AlertVolume.swift`

````swift
import Foundation

/// The alert ("sound effects") volume has no public Core Audio property. Standard Additions'
/// `volume settings` runs in-process, so it needs no Apple Events permission.
@MainActor
enum AlertVolume {
    static func read() -> Float? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "alert volume of (get volume settings)") else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return Float(result.int32Value) / 100
    }

    static func write(_ value: Float) {
        let percent = Int((min(max(value, 0), 1) * 100).rounded())
        var error: NSDictionary?
        NSAppleScript(source: "set volume alert volume \(percent)")?.executeAndReturnError(&error)
        if let error { NSLog("SoundSourceClone: alert volume write failed: \(error)") }
    }
}
````

### `SoundSourceClone/Audio/AppIdentityResolver.swift`

````swift
import AppKit
import Darwin

struct AppIdentity {
    let id: String
    let name: String
    let bundleID: String?
    let bundleURL: URL?
    let icon: NSImage
    /// A Dock app (not a menu bar agent or background helper).
    var isRegularApp = false
}

/// Maps audio processes to the app the user thinks of: Chrome's renderer/audio helpers become
/// "Google Chrome", Safari's WebKit GPU process becomes "Safari", and so on.
@MainActor
final class AppIdentityResolver {
    static let genericIcon = NSWorkspace.shared.icon(for: .application)

    /// Per-app audio engines, including every copy of this app (another build, an Xcode run).
    /// Tapping one would fight its interception; two copies tapping each other form a feedback loop.
    private static let excludedBundleIDs: Set<String> = [
        "com.rogueamoeba.arkaudiod",
        Bundle.main.bundleIdentifier ?? "com.example.SoundSourceClone",
    ]

    private var cache: [pid_t: AppIdentity] = [:]
    private let ownPID = getpid()

    func identity(for process: AudioProcess) -> AppIdentity? {
        if let cached = cache[process.pid] { return cached }
        // Negative results are not cached: a just-launched app may not be registered with LaunchServices yet.
        guard let resolved = resolve(process) else { return nil }
        cache[process.pid] = resolved
        return resolved
    }

    func retain(pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) }
    }

    private func resolve(_ process: AudioProcess) -> AppIdentity? {
        guard process.pid != ownPID, !Self.excludedBundleIDs.contains(process.bundleID ?? "") else { return nil }
        let responsible = Self.responsiblePID(for: process.pid)
        guard responsible != ownPID else { return nil }

        for pid in [responsible, process.pid] {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy != .prohibited,
               let bundleID = app.bundleIdentifier,
               !Self.excludedBundleIDs.contains(bundleID) {
                return AppIdentity(id: bundleID,
                                   name: Self.cleanName(app.localizedName) ?? bundleID,
                                   bundleID: bundleID,
                                   bundleURL: app.bundleURL,
                                   icon: app.icon ?? Self.genericIcon,
                                   isRegularApp: app.activationPolicy == .regular)
            }
        }

        // Helpers that are not registered apps: use the outermost .app bundle around the executable.
        guard let appURL = Self.outermostAppBundle(for: process.pid),
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier,
              !Self.excludedBundleIDs.contains(bundleID) else { return nil }
        let name = Self.cleanName(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? Self.cleanName(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return AppIdentity(id: bundleID, name: name, bundleID: bundleID, bundleURL: appURL,
                           icon: NSWorkspace.shared.icon(forFile: appURL.path))
    }

    /// Some apps (WhatsApp) prefix their name with a left-to-right mark.
    private static func cleanName(_ name: String?) -> String? {
        let invisible = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202C}"))
        guard let cleaned = name?.trimmingCharacters(in: invisible), !cleaned.isEmpty else { return nil }
        return cleaned
    }

    // `responsibility_get_pid_responsible_for_pid` is the SPI TCC uses to attribute helpers and
    // XPC services to their host app. Looked up dynamically so a missing symbol only disables grouping.
    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t
    private static let responsibilityFunction: ResponsibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let function = responsibilityFunction else { return pid }
        let responsible = function(pid)
        return responsible > 0 ? responsible : pid
    }

    private static func outermostAppBundle(for pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard !path.hasPrefix("/System/Library/"), !path.hasPrefix("/usr/"),
              let range = path.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.upperBound].dropLast()))
    }
}
````

### `SoundSourceClone/Audio/AudioDevice.swift`

````swift
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let inputChannels: Int
    let outputChannels: Int
    /// Number of input streams the device itself contributes when used as an aggregate sub-device.
    let inputStreamCount: Int

    var hasOutput: Bool { outputChannels > 0 }
    var hasInput: Bool { inputChannels > 0 }

    var outputSymbol: String { symbol(input: false) }
    var inputSymbol: String { symbol(input: true) }

    private func symbol(input: Bool) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("headphone") || lowered.contains("headset") { return "headphones" }
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return input ? "mic" : "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeVirtual:
            return "waveform"
        case kAudioDeviceTransportTypeAggregate:
            return "square.stack.3d.up"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI:
            return input ? "mic" : "hifispeaker"
        default:
            return input ? "mic" : "speaker.wave.2"
        }
    }
}

extension AudioDevice {
    static func load(_ id: AudioDeviceID) -> AudioDevice? {
        guard let uid = id.readString(.init(kAudioDevicePropertyDeviceUID)) else { return nil }
        if (id.read(.init(kAudioDevicePropertyIsHidden), initial: UInt32(0)) ?? 0) != 0 { return nil }
        let inputStreams = id.readArray(.init(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput),
                                        of: AudioStreamID.self)
        return AudioDevice(
            id: id,
            uid: uid,
            name: id.readString(.init(kAudioObjectPropertyName)) ?? uid,
            transportType: id.read(.init(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0,
            inputChannels: id.channelCount(scope: kAudioObjectPropertyScopeInput),
            outputChannels: id.channelCount(scope: kAudioObjectPropertyScopeOutput),
            inputStreamCount: inputStreams.count
        )
    }

    static func all() -> [AudioDevice] {
        AudioObjectID.system
            .readArray(.init(kAudioHardwarePropertyDevices), of: AudioDeviceID.self)
            .compactMap(load)
    }
}
````

### `SoundSourceClone/Audio/AudioDeviceManager.swift`

````swift
import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// System-level audio state: device lists, default devices, hardware volume/mute, alert volume.
@MainActor @Observable
final class AudioDeviceManager {
    enum Change { case deviceList, defaultOutput, defaultInput, systemOutput }

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID = AudioObjectID.unknown
    private(set) var defaultInputID = AudioObjectID.unknown
    private(set) var systemOutputID = AudioObjectID.unknown

    private(set) var outputVolume: Float = 0
    private(set) var outputMuted = false
    private(set) var outputVolumeAvailable = false
    private(set) var outputBalance: Float = 0
    private(set) var outputBalanceAvailable = false
    private(set) var outputSampleRate: Double = 0
    private(set) var outputSampleRates: [Double] = []

    private(set) var inputVolume: Float = 0
    private(set) var inputMuted = false
    private(set) var inputVolumeAvailable = false

    private(set) var alertVolume: Float = 1

    @ObservationIgnored var onChange: ((Change) -> Void)?
    let isPreview: Bool
    @ObservationIgnored private var systemListeners: [PropertyListener] = []
    @ObservationIgnored private var outputListeners: [PropertyListener] = []
    @ObservationIgnored private var inputListeners: [PropertyListener] = []
    @ObservationIgnored private var listenedOutputID = AudioObjectID.unknown
    @ObservationIgnored private var listenedInputID = AudioObjectID.unknown
    @ObservationIgnored private var inputVolumeBeforeSoftMute: Float?
    @ObservationIgnored private var alertWorkItem: DispatchWorkItem?

    var outputDevices: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputDevices: [AudioDevice] { devices.filter(\.hasInput) }
    var defaultOutput: AudioDevice? { devices.first { $0.id == defaultOutputID } }
    var defaultInput: AudioDevice? { devices.first { $0.id == defaultInputID } }
    var systemOutput: AudioDevice? { devices.first { $0.id == systemOutputID } }

    func device(uid: String) -> AudioDevice? { devices.first { $0.uid == uid } }
    func device(id: AudioObjectID) -> AudioDevice? { devices.first { $0.id == id } }

    init(preview: Bool = false) {
        isPreview = preview
        if preview { loadPreviewState() }
    }

    func start() {
        guard !isPreview else { return }
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]
        systemListeners = selectors.map { selector in
            PropertyListener(objectID: .system, address: .init(selector)) { [weak self] in
                self?.systemPropertyChanged(selector)
            }
        }
        reloadDevices()
        reloadDefaults()
        alertVolume = AlertVolume.read() ?? alertVolume
    }

    /// Re-reads values that have no reliable change notification (alert volume) or may have drifted.
    func refresh() {
        guard !isPreview else { return }
        refreshOutputState()
        refreshInputState()
        if let volume = AlertVolume.read() { alertVolume = volume }
    }

    // MARK: Default devices

    func setDefaultOutput(_ device: AudioDevice) {
        setSystemDevice(kAudioHardwarePropertyDefaultOutputDevice, to: device)
    }

    func setDefaultInput(_ device: AudioDevice) {
        setSystemDevice(kAudioHardwarePropertyDefaultInputDevice, to: device)
    }

    func setSoundEffectsOutput(_ device: AudioDevice) {
        setSystemDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, to: device)
    }

    private func setSystemDevice(_ selector: AudioObjectPropertySelector, to device: AudioDevice) {
        if isPreview {
            switch selector {
            case kAudioHardwarePropertyDefaultOutputDevice: defaultOutputID = device.id
            case kAudioHardwarePropertyDefaultInputDevice: defaultInputID = device.id
            default: systemOutputID = device.id
            }
            return
        }
        let status = AudioObjectID.system.write(.init(selector), value: device.id)
        if status != noErr { NSLog("SoundSourceClone: could not select \(device.name): \(status.fourCharCode)") }
        reloadDefaults()
    }

    // MARK: Output

    func setOutputVolume(_ value: Float) {
        let volume = min(max(value, 0), 1)
        outputVolume = volume
        guard !isPreview else { return }
        Self.writeVolume(defaultOutputID, scope: kAudioObjectPropertyScopeOutput, value: volume)
        if outputMuted, volume > 0 { setOutputMuted(false) }
    }

    func toggleOutputMute() { setOutputMuted(!outputMuted) }

    func setOutputMuted(_ muted: Bool) {
        outputMuted = muted
        guard !isPreview else { return }
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        defaultOutputID.write(address, value: UInt32(muted ? 1 : 0))
    }

    /// -1 (left) … 0 (centre) … +1 (right).
    func setOutputBalance(_ value: Float) {
        let balance = min(max(value, -1), 1)
        outputBalance = balance
        guard !isPreview else { return }
        let address = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainBalance,
                                                 kAudioObjectPropertyScopeOutput)
        defaultOutputID.write(address, value: Float32((balance + 1) / 2))
    }

    func setOutputSampleRate(_ rate: Double) {
        outputSampleRate = rate
        guard !isPreview else { return }
        defaultOutputID.write(.init(kAudioDevicePropertyNominalSampleRate), value: Float64(rate))
    }

    // MARK: Input

    func setInputVolume(_ value: Float) {
        let volume = min(max(value, 0), 1)
        inputVolume = volume
        guard !isPreview else { return }
        Self.writeVolume(defaultInputID, scope: kAudioObjectPropertyScopeInput, value: volume)
        if inputMuted, volume > 0 { setInputMuted(false) }
    }

    func toggleInputMute() { setInputMuted(!inputMuted) }

    func setInputMuted(_ muted: Bool) {
        inputMuted = muted
        guard !isPreview else { return }
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        if defaultInputID.isPropertySettable(address) {
            defaultInputID.write(address, value: UInt32(muted ? 1 : 0))
        } else if muted {
            // Many USB/Bluetooth mics have no mute control: fall back to zero gain and remember the level.
            inputVolumeBeforeSoftMute = inputVolume
            Self.writeVolume(defaultInputID, scope: kAudioObjectPropertyScopeInput, value: 0)
        } else {
            let restored = inputVolumeBeforeSoftMute ?? 0.5
            inputVolumeBeforeSoftMute = nil
            inputVolume = restored
            Self.writeVolume(defaultInputID, scope: kAudioObjectPropertyScopeInput, value: restored)
        }
    }

    // MARK: Alert (sound effects) volume

    func setAlertVolume(_ value: Float) {
        alertVolume = min(max(value, 0), 1)
        guard !isPreview else { return }
        // AppleScript round-trips are slow; coalesce slider drags.
        alertWorkItem?.cancel()
        let volume = alertVolume
        let item = DispatchWorkItem { AlertVolume.write(volume) }
        alertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    // MARK: Change handling

    private func systemPropertyChanged(_ selector: AudioObjectPropertySelector) {
        switch selector {
        case kAudioHardwarePropertyDevices:
            // Creating/destroying our own private aggregates also fires this; only real changes count.
            guard reloadDevices() else { return }
            reloadDefaults()
            onChange?(.deviceList)
        case kAudioHardwarePropertyDefaultOutputDevice:
            reloadDefaults()
            onChange?(.defaultOutput)
        case kAudioHardwarePropertyDefaultInputDevice:
            reloadDefaults()
            onChange?(.defaultInput)
        default:
            reloadDefaults()
            onChange?(.systemOutput)
        }
    }

    /// Returns whether the visible device list changed.
    @discardableResult
    private func reloadDevices() -> Bool {
        let visible = AudioDevice.all().filter { !$0.uid.hasPrefix(ProcessTapSession.aggregateUIDPrefix) }
        guard visible != devices else { return false }
        devices = visible
        return true
    }

    private func reloadDefaults() {
        let system = AudioObjectID.system
        defaultOutputID = system.read(.init(kAudioHardwarePropertyDefaultOutputDevice), initial: AudioObjectID.unknown) ?? .unknown
        defaultInputID = system.read(.init(kAudioHardwarePropertyDefaultInputDevice), initial: AudioObjectID.unknown) ?? .unknown
        systemOutputID = system.read(.init(kAudioHardwarePropertyDefaultSystemOutputDevice), initial: AudioObjectID.unknown) ?? .unknown

        if listenedOutputID != defaultOutputID {
            listenedOutputID = defaultOutputID
            outputListeners = listeners(on: defaultOutputID, scope: kAudioObjectPropertyScopeOutput, selectors: [
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioHardwareServiceDeviceProperty_VirtualMainBalance,
                kAudioDevicePropertyVolumeScalar,
                kAudioDevicePropertyMute,
                kAudioDevicePropertyNominalSampleRate,
            ]) { [weak self] in self?.refreshOutputState() }
        }
        if listenedInputID != defaultInputID {
            listenedInputID = defaultInputID
            inputVolumeBeforeSoftMute = nil
            inputListeners = listeners(on: defaultInputID, scope: kAudioObjectPropertyScopeInput, selectors: [
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioDevicePropertyVolumeScalar,
                kAudioDevicePropertyMute,
            ]) { [weak self] in self?.refreshInputState() }
        }
        refreshOutputState()
        refreshInputState()
    }

    private func listeners(on device: AudioObjectID,
                           scope: AudioObjectPropertyScope,
                           selectors: [AudioObjectPropertySelector],
                           handler: @escaping () -> Void) -> [PropertyListener] {
        guard device.isValid else { return [] }
        return selectors.compactMap { selector in
            let address = AudioObjectPropertyAddress(selector, scope)
            return device.hasProperty(address) ? PropertyListener(objectID: device, address: address, handler: handler) : nil
        }
    }

    private func refreshOutputState() {
        let device = defaultOutputID
        let scope = kAudioObjectPropertyScopeOutput
        outputVolumeAvailable = Self.isVolumeSettable(device, scope: scope)
        outputVolume = Self.readVolume(device, scope: scope) ?? 0
        outputMuted = (device.read(.init(kAudioDevicePropertyMute, scope), initial: UInt32(0)) ?? 0) != 0

        let balance = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainBalance, scope)
        outputBalanceAvailable = device.isPropertySettable(balance)
        outputBalance = (device.read(balance, initial: Float32(0.5)) ?? 0.5) * 2 - 1

        outputSampleRate = device.read(.init(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)) ?? 0
        let ranges = device.readArray(.init(kAudioDevicePropertyAvailableNominalSampleRates), of: AudioValueRange.self)
        let common: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        var rates = Set<Double>()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                common.filter { $0 >= range.mMinimum && $0 <= range.mMaximum }.forEach { rates.insert($0) }
            }
        }
        outputSampleRates = rates.sorted()
    }

    private func refreshInputState() {
        let device = defaultInputID
        let scope = kAudioObjectPropertyScopeInput
        inputVolumeAvailable = Self.isVolumeSettable(device, scope: scope)
        let volume = Self.readVolume(device, scope: scope) ?? 0
        let hardwareMute = (device.read(.init(kAudioDevicePropertyMute, scope), initial: UInt32(0)) ?? 0) != 0
        if inputVolumeBeforeSoftMute != nil {
            inputMuted = true
        } else {
            inputVolume = volume
            inputMuted = hardwareMute
        }
    }

    // MARK: Volume helpers (virtual main volume → main element → per-channel fallback)

    nonisolated static func readVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Float? {
        guard device.isValid else { return nil }
        let virtual = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if device.hasProperty(virtual), let value = device.read(virtual, initial: Float32(0)) { return value }
        let main = AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope)
        if device.hasProperty(main), let value = device.read(main, initial: Float32(0)) { return value }
        let channels = (1...2).compactMap { channel -> Float32? in
            let address = AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope, AudioObjectPropertyElement(channel))
            return device.hasProperty(address) ? device.read(address, initial: Float32(0)) : nil
        }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
    }

    nonisolated static func isVolumeSettable(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        guard device.isValid else { return false }
        return volumeAddresses(device, scope: scope).contains { device.isPropertySettable($0) }
    }

    nonisolated static func writeVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope, value: Float) {
        guard device.isValid else { return }
        for address in volumeAddresses(device, scope: scope) where device.isPropertySettable(address) {
            device.write(address, value: Float32(value))
            if address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume
                || address.mElement == kAudioObjectPropertyElementMain { return }
        }
    }

    nonisolated private static func volumeAddresses(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyAddress] {
        [
            AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope),
            AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope),
            AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope, 1),
            AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar, scope, 2),
        ].filter { device.hasProperty($0) }
    }

    // MARK: Preview

    private func loadPreviewState() {
        devices = PreviewData.devices
        defaultOutputID = 1
        defaultInputID = 2
        systemOutputID = 1
        outputVolume = 0.38
        outputVolumeAvailable = true
        outputBalanceAvailable = true
        outputSampleRate = 48_000
        outputSampleRates = [44_100, 48_000, 96_000]
        inputVolume = 0.2
        inputVolumeAvailable = true
        alertVolume = 1
    }
}
````

### `SoundSourceClone/Audio/AudioEngine.swift`

````swift
import AppKit
import CoreAudio
import Observation
import UniformTypeIdentifiers

/// Owns the app list and one `ProcessTapSession` per captured app, and turns user settings into
/// processor parameters. Everything here runs on the main thread; only `StereoProcessor.render`
/// runs on the audio IO threads.
@MainActor @Observable
final class AudioEngine {
    let devices: AudioDeviceManager
    let isPreview: Bool

    private(set) var apps: [AppEntry] = []
    private(set) var favorites: [FavoriteApp]
    private(set) var quickConfigs: [QuickConfig]
    private(set) var permission: CapturePermission.Status = .unknown
    /// Loudest captured app, 0…1 (used as the System Output meter).
    private(set) var outputLevel: Float = 0
    private(set) var inputLevel: Float = 0

    var prefs: Preferences {
        didSet { preferencesChanged(from: oldValue) }
    }

    /// Applied to every captured app, on top of its own EQ.
    var systemEQ: EQSettings {
        didSet {
            applyProcessingToAll()
            if systemEQ.isActive != oldValue.isActive { syncSessions() }
            persist()
        }
    }

    @ObservationIgnored var previewExpandedAppID: String?
    @ObservationIgnored private var appSettings: [String: AppAudioSettings]
    @ObservationIgnored private var entries: [String: AppEntry] = [:]
    @ObservationIgnored private var sessions: [String: ProcessTapSession] = [:]
    @ObservationIgnored private var failedStarts: [String: String] = [:]
    @ObservationIgnored private var heardThisSession: Set<String> = []
    private let processMonitor = AudioProcessMonitor()
    private let identities = AppIdentityResolver()
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var levelLogTimer: Timer?
    @ObservationIgnored private var inputMonitor: InputLevelMonitor?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    init(preview: Bool = false) {
        isPreview = preview
        let state = preview ? PreviewData.state : PersistedState.load()
        devices = AudioDeviceManager(preview: preview)
        appSettings = state.apps
        favorites = state.favorites
        quickConfigs = state.quickConfigs
        prefs = state.prefs
        systemEQ = state.systemEQ
        if preview {
            permission = .authorized
            loadPreviewApps()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !isPreview else { return }
        devices.onChange = { [weak self] change in self?.deviceConfigurationChanged(change) }
        devices.start()
        processMonitor.onChange = { [weak self] in self?.scheduleRefresh() }
        processMonitor.start()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }

        permission = CapturePermission.status
        Log.capture.notice("Started. System Audio Recording permission: \(String(describing: self.permission), privacy: .public)")
        if permission == .unknown, CapturePermission.canRequest {
            requestCapturePermission()
        }
        if CommandLine.arguments.contains("--log-levels") {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.logLevels() }
            }
            RunLoop.main.add(timer, forMode: .common)
            levelLogTimer = timer
        }
        refreshApps()
    }

    /// `--log-levels`: periodic per-app peak levels in the unified log (only while the panel is closed,
    /// since the panel's meters consume the same peaks).
    private func logLevels() {
        guard meterTimer == nil else { return }
        for (id, session) in sessions {
            let peaks = session.processor.takePeaks()
            let db = 20 * log10f(max(peaks.left, peaks.right, 0.000_001))
            Log.capture.notice("Level \(self.entries[id]?.name ?? id, privacy: .public): \(String(format: "%.1f", db), privacy: .public) dBFS peak")
        }
    }

    func shutdown() {
        for session in sessions.values { session.stop() }
        sessions.removeAll()
        saveWorkItem?.cancel()
        persistNow()
    }

    // MARK: Permission

    var canCapture: Bool {
        switch permission {
        case .authorized: true
        case .denied: false
        case .unknown: !CapturePermission.canRequest   // no SPI: let tap creation show the prompt
        }
    }

    func requestCapturePermission() {
        if permission == .denied {
            CapturePermission.openSystemSettings()
            return
        }
        CapturePermission.request { [weak self] granted in
            guard let self else { return }
            Log.capture.notice("System Audio Recording permission \(granted ? "granted" : "denied", privacy: .public)")
            self.permission = granted ? .authorized : .denied
            self.failedStarts.removeAll()
            self.syncSessions()
        }
    }

    /// The user may have granted access in System Settings since the last check.
    func recheckPermission() {
        guard !isPreview, CapturePermission.canRequest else { return }
        let status = CapturePermission.status
        if status != permission {
            permission = status
            failedStarts.removeAll()
            syncSessions()
        }
    }

    // MARK: App list

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refreshApps()
            }
        }
    }

    private func refreshApps() {
        guard !isPreview else { return rebuildList() }

        var groups: [String: (identity: AppIdentity, processes: [AudioProcess])] = [:]
        for process in processMonitor.processes {
            guard let identity = identities.identity(for: process) else { continue }
            groups[identity.id, default: (identity, [])].processes.append(process)
        }
        identities.retain(pids: Set(processMonitor.processes.map(\.pid)))

        for (id, group) in groups {
            let identity = group.identity
            let entry = entries[id] ?? makeEntry(id: id, name: identity.name, icon: identity.icon,
                                                 bundleID: identity.bundleID, bundleURL: identity.bundleURL)
            let objectIDs = group.processes.map(\.objectID).sorted()
            if entry.processObjectIDs != objectIDs { entry.processObjectIDs = objectIDs }
            entry.pids = Array(Set(group.processes.map(\.pid))).sorted()
            entry.isRegularApp = identity.isRegularApp
            entry.isRunning = true
            entry.isPlaying = group.processes.contains(where: \.isRunningOutput)
            let native = group.processes.filter(\.isRunningOutput).flatMap(\.outputDeviceIDs).first
                ?? group.processes.flatMap(\.outputDeviceIDs).first
            if entry.nativeOutputDeviceID != native { entry.nativeOutputDeviceID = native }
            if entry.isPlaying { heardThisSession.insert(id) }
        }

        for (id, entry) in entries where groups[id] == nil {
            entry.processObjectIDs = []
            entry.pids = []
            entry.nativeOutputDeviceID = nil
            entry.isPlaying = false
            entry.level = 0
            entry.isRunning = entry.bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
            if !entry.isRunning { heardThisSession.remove(id) }
        }

        for favorite in favorites where entries[favorite.id] == nil {
            let url = favorite.bundlePath.map { URL(fileURLWithPath: $0) }
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: favorite.id)
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? AppIdentityResolver.genericIcon
            let entry = makeEntry(id: favorite.id, name: favorite.name, icon: icon, bundleID: favorite.id, bundleURL: url)
            entry.isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: favorite.id).isEmpty
        }

        rebuildList()
        syncSessions()
    }

    private func makeEntry(id: String, name: String, icon: NSImage, bundleID: String?, bundleURL: URL?) -> AppEntry {
        let entry = AppEntry(id: id, name: name, icon: icon, bundleID: bundleID, bundleURL: bundleURL,
                             settings: appSettings[id] ?? AppAudioSettings())
        entries[id] = entry
        return entry
    }

    /// Favorites first (in the order they were added), then apps that played audio this session or
    /// are Dock apps with an open audio connection (shown dimmed until they play, so they can be
    /// adjusted ahead of time; capture still waits for sound or a change).
    private func rebuildList() {
        let favoriteIDs = favorites.map(\.id)
        let favoriteSet = Set(favoriteIDs)
        for entry in entries.values where entry.isFavorite != favoriteSet.contains(entry.id) {
            entry.isFavorite.toggle()
        }
        let pinned = favoriteIDs.compactMap { entries[$0] }
        let others = entries.values
            .filter { entry in
                !favoriteSet.contains(entry.id)
                    && (entry.isPlaying || heardThisSession.contains(entry.id)
                        || ((entry.settings.isAdjusted || entry.isRegularApp) && !entry.processObjectIDs.isEmpty))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let list = pinned + others
        if list.map(\.id) != apps.map(\.id) { apps = list }
    }

    // MARK: Capture sessions

    private func shouldCapture(_ entry: AppEntry) -> Bool {
        guard canCapture, !entry.processObjectIDs.isEmpty else { return false }
        switch prefs.captureMode {
        case .allActive:
            return heardThisSession.contains(entry.id) || entry.settings.isAdjusted
        case .adjustedOnly:
            return entry.settings.isAdjusted || (systemEQ.isActive && heardThisSession.contains(entry.id))
        }
    }

    /// Explicit route if set and connected; otherwise wherever the app itself is playing, so capturing
    /// an app that chose its own device (a call app on a headset) doesn't move it to the default output.
    func outputDevice(for entry: AppEntry) -> AudioDevice? {
        if let uid = entry.settings.outputDeviceUID, let device = devices.device(uid: uid), device.hasOutput {
            return device
        }
        if let native = entry.nativeOutputDeviceID, let device = devices.device(id: native), device.hasOutput {
            return device
        }
        return devices.defaultOutput
    }

    private func syncSessions() {
        guard !isPreview else { return }
        var wanted = Set<String>()
        for entry in entries.values where shouldCapture(entry) {
            guard let output = outputDevice(for: entry) else { continue }
            let signature = "\(entry.processObjectIDs)|\(output.uid)"
            if let session = sessions[entry.id] {
                wanted.insert(entry.id)
                do {
                    if session.processObjectIDs != entry.processObjectIDs {
                        do {
                            try session.updateProcesses(entry.processObjectIDs)
                        } catch {
                            try session.start(processes: entry.processObjectIDs, output: output)
                        }
                    }
                    if session.outputDeviceUID != output.uid {
                        try session.switchOutput(to: output)
                        Log.capture.notice("Rerouted \(entry.name, privacy: .public) → \(output.name, privacy: .public)")
                    }
                    entry.captureError = nil
                } catch {
                    record(error, for: entry, signature: signature)
                    session.stop()
                    sessions[entry.id] = nil
                    wanted.remove(entry.id)
                }
            } else if failedStarts[entry.id] != signature {
                let session = ProcessTapSession(appID: entry.id)
                applyProcessing(entry, to: session.processor)
                do {
                    try session.start(processes: entry.processObjectIDs, output: output)
                    sessions[entry.id] = session
                    failedStarts[entry.id] = nil
                    entry.captureError = nil
                    wanted.insert(entry.id)
                    Log.capture.notice("Capturing \(entry.name, privacy: .public) (\(entry.processObjectIDs.count) processes) → \(output.name, privacy: .public) [\(session.formatSummary, privacy: .public)]")
                } catch {
                    record(error, for: entry, signature: signature)
                }
            }
            entry.isCaptured = sessions[entry.id]?.isRunning ?? false
        }

        for (id, session) in sessions where !wanted.contains(id) {
            Log.capture.notice("Stopped capturing \(self.entries[id]?.name ?? id, privacy: .public)")
            session.stop()
            sessions[id] = nil
            entries[id]?.isCaptured = false
            entries[id]?.level = 0
        }
    }

    private func record(_ error: Error, for entry: AppEntry, signature: String) {
        failedStarts[entry.id] = signature   // don't retry the same configuration in a loop
        entry.captureError = error.localizedDescription
        entry.isCaptured = false
        Log.capture.error("Capturing \(entry.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    private func deviceConfigurationChanged(_ change: AudioDeviceManager.Change) {
        switch change {
        case .deviceList, .defaultOutput:
            failedStarts.removeAll()
            syncSessions()   // re-resolves "follow system output" and disconnected routes
        case .defaultInput, .systemOutput:
            break
        }
    }

    // MARK: Processing parameters

    /// Squared taper: 50 % ≈ −12 dB, 200 % ≈ +12 dB.
    nonisolated static func gain(forVolume volume: Float) -> Float {
        let clamped = max(volume, 0)
        return clamped * clamped
    }

    nonisolated static func meterPosition(_ peak: Float) -> Float {
        guard peak > 0.000_01 else { return 0 }
        return min(max((20 * log10f(peak) + 60) / 60, 0), 1)
    }

    private func applyProcessing(_ entry: AppEntry, to processor: StereoProcessor) {
        let settings = entry.settings
        processor.setGain(settings.isMuted ? 0 : Self.gain(forVolume: settings.volume))
        processor.setBalance(settings.balance)
        var gains = [Float](repeating: 0, count: EQBands.count)
        for band in gains.indices {
            if settings.eq.enabled, band < settings.eq.gains.count { gains[band] += settings.eq.gains[band] }
            if systemEQ.enabled, band < systemEQ.gains.count { gains[band] += systemEQ.gains[band] }
        }
        processor.setEQ(gains: gains.map { min(max($0, -24), 24) })
    }

    private func applyProcessingToAll() {
        for (id, session) in sessions {
            if let entry = entries[id] { applyProcessing(entry, to: session.processor) }
        }
    }

    // MARK: Per-app settings

    func setVolume(_ volume: Float, for entry: AppEntry) {
        update(entry) {
            $0.volume = min(max(volume, 0), 2)
            if volume > 0 { $0.isMuted = false }
        }
    }

    func toggleMute(_ entry: AppEntry) { update(entry) { $0.isMuted.toggle() } }

    func setBalance(_ balance: Float, for entry: AppEntry) { update(entry) { $0.balance = balance } }

    func setEQ(_ eq: EQSettings, for entry: AppEntry) { update(entry) { $0.eq = eq } }

    func setOutputDevice(_ device: AudioDevice?, for entry: AppEntry) {
        update(entry) {
            $0.outputDeviceUID = device?.uid
            $0.outputDeviceName = device?.name
        }
    }

    func reset(_ entry: AppEntry) { update(entry) { $0 = AppAudioSettings() } }

    func resetAllApps() {
        for entry in entries.values { reset(entry) }
        appSettings.removeAll()
        persist()
    }

    private func update(_ entry: AppEntry, _ change: (inout AppAudioSettings) -> Void) {
        let old = entry.settings
        var new = old
        change(&new)
        guard new != old else { return }
        entry.settings = new
        appSettings[entry.id] = new.isAdjusted ? new : nil
        if let session = sessions[entry.id] { applyProcessing(entry, to: session.processor) }
        if new.outputDeviceUID != old.outputDeviceUID || new.isAdjusted != old.isAdjusted {
            failedStarts[entry.id] = nil
            syncSessions()
            rebuildList()
        }
        persist()
    }

    // MARK: Favorites

    func toggleFavorite(_ entry: AppEntry) {
        if let index = favorites.firstIndex(where: { $0.id == entry.id }) {
            favorites.remove(at: index)
        } else {
            favorites.append(FavoriteApp(id: entry.id, name: entry.name, bundlePath: entry.bundleURL?.path))
        }
        refreshApps()
        persist()
    }

    func addFavorite(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, !favorites.contains(where: { $0.id == id }) else { return }
        favorites.append(FavoriteApp(id: id, name: app.localizedName ?? id, bundlePath: app.bundleURL?.path))
        refreshApps()
        persist()
    }

    func addFavorite(bundleURL: URL) {
        guard let bundle = Bundle(url: bundleURL), let id = bundle.bundleIdentifier,
              !favorites.contains(where: { $0.id == id }) else { return }
        let name = FileManager.default.displayName(atPath: bundleURL.path)
            .replacingOccurrences(of: ".app", with: "")
        favorites.append(FavoriteApp(id: id, name: name, bundlePath: bundleURL.path))
        refreshApps()
        persist()
    }

    /// Regular running apps that are not favorites yet, for the "Add Favorite" menu.
    func favoriteCandidates() -> [NSRunningApplication] {
        let favoriteIDs = Set(favorites.map(\.id))
        let ownPID = getpid()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, app.processIdentifier != ownPID,
                      let id = app.bundleIdentifier else { return false }
                return !favoriteIDs.contains(id)
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    func chooseFavoriteFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add Favorite"
        panel.message = "Choose apps to keep in the Applications list, even when they're not running."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addFavorite(bundleURL:))
    }

    // MARK: Quick Configs

    func saveQuickConfig(named name: String) {
        var snapshot = appSettings
        for entry in apps { snapshot[entry.id] = entry.settings }
        let config = QuickConfig(name: name,
                                 apps: snapshot,
                                 outputDeviceUID: devices.defaultOutput?.uid,
                                 inputDeviceUID: devices.defaultInput?.uid,
                                 soundEffectsDeviceUID: devices.systemOutput?.uid,
                                 outputVolume: devices.outputVolume,
                                 inputVolume: devices.inputVolume,
                                 systemEQ: systemEQ)
        quickConfigs.removeAll { $0.name == name }
        quickConfigs.append(config)
        persist()
    }

    func applyQuickConfig(_ config: QuickConfig) {
        if let uid = config.outputDeviceUID, let device = devices.device(uid: uid) { devices.setDefaultOutput(device) }
        if let uid = config.inputDeviceUID, let device = devices.device(uid: uid) { devices.setDefaultInput(device) }
        if let uid = config.soundEffectsDeviceUID, let device = devices.device(uid: uid) { devices.setSoundEffectsOutput(device) }
        if let volume = config.outputVolume { devices.setOutputVolume(volume) }
        if let volume = config.inputVolume { devices.setInputVolume(volume) }
        if let eq = config.systemEQ { systemEQ = eq }
        for (id, settings) in config.apps {
            if let entry = entries[id] {
                update(entry) { $0 = settings }
            } else {
                appSettings[id] = settings.isAdjusted ? settings : nil
            }
        }
        persist()
    }

    func deleteQuickConfig(_ config: QuickConfig) {
        quickConfigs.removeAll { $0.id == config.id }
        persist()
    }

    // MARK: Metering (runs only while the panel is visible)

    func beginMetering() {
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeters() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
        updateInputMonitor()
    }

    func endMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        for entry in apps where entry.level != 0 { entry.level = 0 }
        outputLevel = 0
        inputLevel = 0
        updateInputMonitor()
    }

    private func updateMeters() {
        let decay: Float = 0.035
        var loudest: Float = 0
        for (id, session) in sessions {
            guard let entry = entries[id] else { continue }
            let peaks = session.processor.takePeaks()
            let level = max(Self.meterPosition(max(peaks.left, peaks.right)), entry.level - decay, 0)
            if abs(level - entry.level) > 0.002 { entry.level = level }
            loudest = max(loudest, level)
        }
        if abs(loudest - outputLevel) > 0.002 { outputLevel = loudest }
        if let inputMonitor {
            let level = max(Self.meterPosition(inputMonitor.takePeak()), inputLevel - decay, 0)
            if abs(level - inputLevel) > 0.002 { inputLevel = level }
        }
    }

    private func updateInputMonitor() {
        let wanted = !isPreview && prefs.showInputLevel && meterTimer != nil
        if wanted, inputMonitor == nil {
            let monitor = InputLevelMonitor()
            if monitor.start() { inputMonitor = monitor }
        } else if !wanted, let monitor = inputMonitor {
            monitor.stop()
            inputMonitor = nil
            inputLevel = 0
        }
    }

    // MARK: Persistence

    private func preferencesChanged(from old: Preferences) {
        if prefs.captureMode != old.captureMode { syncSessions() }
        if prefs.showInputLevel != old.showInputLevel { updateInputMonitor() }
        persist()
    }

    private func persist() {
        guard !isPreview else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.persistNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func persistNow() {
        guard !isPreview else { return }
        PersistedState(apps: appSettings, favorites: favorites, quickConfigs: quickConfigs,
                       systemEQ: systemEQ, prefs: prefs).save()
    }

    // MARK: Preview

    private func loadPreviewApps() {
        for app in PreviewData.apps {
            var settings = AppAudioSettings()
            settings.volume = app.volume
            settings.isMuted = app.muted
            if let gains = app.eq {
                settings.eq = EQSettings(enabled: true, gains: gains, presetName: EQPreset.matching(gains)?.name)
            }
            if let uid = app.outputUID {
                settings.outputDeviceUID = uid
                settings.outputDeviceName = devices.device(uid: uid)?.name
            }
            let entry = makeEntry(id: app.id, name: app.name, icon: PreviewData.icon(for: app),
                                  bundleID: app.id, bundleURL: nil)
            entry.settings = settings
            entry.isRunning = app.running
            entry.isPlaying = app.playing
            entry.isCaptured = app.playing
            entry.level = app.level
            entry.pids = app.running ? [Int32(400 + app.name.count * 37)] : []
            if app.playing { heardThisSession.insert(app.id) }
        }
        outputLevel = PreviewData.apps.map(\.level).max() ?? 0
        rebuildList()
    }
}
````

### `SoundSourceClone/Audio/AudioProcessMonitor.swift`

````swift
import CoreAudio
import Foundation

/// A Core Audio process object: one OS process that has an audio client connection to the HAL.
struct AudioProcess: Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
    /// Devices the process is currently sending output to (an app may pick its own, e.g. Zoom → headset).
    var outputDeviceIDs: [AudioObjectID] = []
}

/// Tracks `kAudioHardwarePropertyProcessObjectList` (macOS 14+) and each process's output activity.
@MainActor
final class AudioProcessMonitor {
    private(set) var processes: [AudioProcess] = []
    var onChange: (() -> Void)?

    private var listListener: PropertyListener?
    private var activityListeners: [AudioObjectID: [PropertyListener]] = [:]
    private var reloadScheduled = false

    func start() {
        listListener = PropertyListener(objectID: .system, address: .init(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.scheduleReload()
        }
        reload()
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadScheduled = false
                self?.reload()
            }
        }
    }

    private func reload() {
        let ids = AudioObjectID.system.readArray(.init(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        var result: [AudioProcess] = []
        for id in ids {
            guard let pid = id.read(.init(kAudioProcessPropertyPID), initial: pid_t(-1)), pid > 0 else { continue }
            let running = (id.read(.init(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0)) ?? 0) != 0
            let devices = id.readArray(.init(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput),
                                       of: AudioObjectID.self)
            result.append(AudioProcess(objectID: id,
                                       pid: pid,
                                       bundleID: id.readString(.init(kAudioProcessPropertyBundleID)),
                                       isRunningOutput: running,
                                       outputDeviceIDs: devices))
            if activityListeners[id] == nil {
                activityListeners[id] = [
                    AudioObjectPropertyAddress(kAudioProcessPropertyIsRunningOutput),
                    AudioObjectPropertyAddress(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput),
                ].map { address in
                    PropertyListener(objectID: id, address: address) { [weak self] in self?.scheduleReload() }
                }
            }
        }
        let alive = Set(ids)
        for id in activityListeners.keys where !alive.contains(id) {
            activityListeners[id] = nil
        }
        if result != processes {
            processes = result
            onChange?()
        }
    }
}
````

### `SoundSourceClone/Audio/CapturePermission.swift`

````swift
import AppKit
import Foundation

/// "System Audio Recording" (kTCCServiceAudioCapture) permission, required for process taps on macOS 14.4+.
///
/// There is no public API to query it. Without it a tap delivers silence, and because taps here mute
/// the app at its source, starting one before access is granted would silence that app. So the state
/// is checked up front through the TCC SPI (loaded dynamically, the same way insidegui/AudioCap does).
enum CapturePermission {
    enum Status { case authorized, denied, unknown }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static let preflight: PreflightFunction? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()

    private static let requestAccess: RequestFunction? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(symbol, to: RequestFunction.self)
    }()

    /// False when the SPI is unavailable; the first tap creation then shows the system prompt itself.
    static var canRequest: Bool { preflight != nil && requestAccess != nil }

    static var status: Status {
        guard let preflight else { return .unknown }
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        guard let requestAccess else {
            completion(true)
            return
        }
        requestAccess(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
````

### `SoundSourceClone/Audio/CoreAudioSupport.swift`

````swift
import AudioToolbox
import CoreAudio
import Foundation

// Thin, typed wrappers over the AudioObject property C API.

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? { "\(operation) failed (\(status.fourCharCode))" }
}

func caCheck(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation()) }
}

extension OSStatus {
    /// Core Audio errors are usually four-character codes such as `'!obj'`.
    var fourCharCode: String {
        let value = UInt32(bitPattern: self)
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(self) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != AudioObjectID.unknown }

    func hasProperty(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(self, &address)
    }

    func isPropertySettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &address, &settable) == noErr && settable.boolValue
    }

    /// Reads a fixed-size (POD) property value.
    func read<T>(_ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    /// Reads a CFString property (the HAL hands back a +1 reference).
    func readString(_ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Reads a variable-length array of POD values.
    func readArray<T>(_ address: AudioObjectPropertyAddress, of _: T.Type) -> [T] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<T>.stride
        guard capacity > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, buffer) == noErr else { return [] }
        let count = Swift.min(Int(size) / MemoryLayout<T>.stride, capacity)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    /// Writes a property value. Pass a CF object (e.g. `uid as CFString`) to write an object reference.
    @discardableResult
    func write<T>(_ address: AudioObjectPropertyAddress, value: T) -> OSStatus {
        var address = address
        var value = value
        return withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
    }

    /// Total channel count across all streams in a scope (input or output).
    func channelCount(scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// Owns one `AudioObjectAddPropertyListenerBlock` registration and removes it on deinit.
final class PropertyListener {
    private let objectID: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private var block: AudioObjectPropertyListenerBlock?

    init(objectID: AudioObjectID,
         address: AudioObjectPropertyAddress,
         queue: DispatchQueue = .main,
         handler: @escaping () -> Void) {
        self.objectID = objectID
        self.address = address
        self.queue = queue
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(objectID, &self.address, queue, block) == noErr {
            self.block = block
        }
    }

    func invalidate() {
        guard let block else { return }
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        self.block = nil
    }

    deinit { invalidate() }
}
````

### `SoundSourceClone/Audio/InputLevelMonitor.swift`

````swift
import AVFoundation

/// Optional microphone meter. Opening the input lights the system's mic-in-use indicator, so the
/// engine only runs this while the panel is visible and the user has enabled it in Settings.
final class InputLevelMonitor {
    private let engine = AVAudioEngine()
    private let peak = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var configurationObserver: NSObjectProtocol?
    private var isRunning = false

    init() { peak.initialize(to: 0) }

    deinit {
        stop()
        peak.deallocate()
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning, AVCaptureDevice.authorizationStatus(for: .audio) != .denied else { return isRunning }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return false }
        let peak = self.peak
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            var loudest: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(samples[frame])) }
            }
            if loudest > peak.pointee { peak.pointee = loudest }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        isRunning = true
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The default input device changed: rebuild the tap with the new format.
            self?.stop()
            self?.start()
        }
        return true
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    func takePeak() -> Float {
        let value = peak.pointee
        peak.pointee = 0
        return value
    }
}
````

### `SoundSourceClone/Audio/Log.swift`

````swift
import os

/// Inspect with: log stream --predicate 'subsystem == "com.example.SoundSourceClone"'
enum Log {
    static let capture = Logger(subsystem: "com.example.SoundSourceClone", category: "capture")
    static let ui = Logger(subsystem: "com.example.SoundSourceClone", category: "ui")
}
````

### `SoundSourceClone/Audio/ProcessTapSession.swift`

````swift
import CoreAudio
import Foundation

/// Captures one app's audio with a Core Audio process tap (macOS 14.2+) and plays it back,
/// processed, on any output device:
///
///     app processes ──▶ CATapDescription (stereo mixdown, muted at the source while tapped)
///                                │
///     private aggregate device = [output device] + [tap]  (drift-compensated)
///                                │  IOProc: tap input ─▶ StereoProcessor ─▶ device output
///                                ▼
///                         chosen output device
///
/// If this process dies the HAL destroys the tap and the app's audio returns to normal untouched.
final class ProcessTapSession {
    static let aggregateUIDPrefix = "com.example.SoundSourceClone.tap."

    let appID: String
    let processor = StereoProcessor()
    private(set) var processObjectIDs: [AudioObjectID] = []
    private(set) var outputDeviceUID: String?
    /// Human-readable stream layout of the running aggregate, for logs.
    private(set) var formatSummary = ""

    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRateListener: PropertyListener?

    var isRunning: Bool { ioProcID != nil }

    init(appID: String) {
        self.appID = appID
    }

    deinit { stop() }

    func start(processes: [AudioObjectID], output: AudioDevice) throws {
        stop()
        try createTap(processes: processes)
        do {
            try startAggregate(output: output)
        } catch {
            destroyTap()
            throw error
        }
    }

    /// Re-targets the existing tap when an app spawns or loses audio helper processes.
    func updateProcesses(_ processes: [AudioObjectID]) throws {
        guard let description = tapDescription, tapID.isValid else {
            throw CoreAudioError(status: OSStatus(kAudioHardwareBadObjectError), operation: "Update tap")
        }
        description.processes = processes
        try caCheck(tapID.write(.init(kAudioTapPropertyDescription), value: description), "Update tap processes")
        processObjectIDs = processes
    }

    /// Rebuilds only the aggregate device; the tap (and the source mute) stays in place.
    func switchOutput(to output: AudioDevice) throws {
        guard tapID.isValid else {
            throw CoreAudioError(status: OSStatus(kAudioHardwareBadObjectError), operation: "Switch output")
        }
        stopAggregate()
        try startAggregate(output: output)
    }

    func stop() {
        stopAggregate()
        destroyTap()
    }

    // MARK: Tap

    private func createTap(processes: [AudioObjectID]) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "SoundSource Clone – \(appID)"
        description.isPrivate = true
        // Muted only while our IOProc is reading, so a stalled or crashed engine never silences the app.
        description.muteBehavior = .mutedWhenTapped
        var newTap = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateProcessTap(description, &newTap), "Create process tap")
        tapID = newTap
        tapDescription = description
        processObjectIDs = processes
    }

    private func destroyTap() {
        if tapID.isValid { AudioHardwareDestroyProcessTap(tapID) }
        tapID = .unknown
        tapDescription = nil
        processObjectIDs = []
    }

    // MARK: Aggregate device + IOProc

    private func startAggregate(output: AudioDevice) throws {
        guard let tapDescription else { return }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundSource Clone (\(appID))",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: output.uid],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]
        var newAggregate = AudioObjectID.unknown
        try caCheck(AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregate), "Create aggregate device")
        aggregateID = newAggregate

        let rate = newAggregate.read(.init(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)) ?? 0
        processor.prepare(sampleRate: rate > 0 ? rate : 48_000)

        let processor = self.processor
        var procID: AudioDeviceIOProcID?
        // A nil queue runs the block directly on the device's real-time IO thread.
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, newAggregate, nil) { _, inputData, _, outputData, _ in
            processor.render(input: inputData, output: outputData)
        }
        guard status == noErr, let procID else {
            destroyAggregateDevice()
            throw CoreAudioError(status: status, operation: "Create IO proc")
        }
        ioProcID = procID

        if output.inputStreamCount > 0 {
            disableSubDeviceInputStreams(procID: procID, subDeviceStreams: output.inputStreamCount)
        }

        let startStatus = AudioDeviceStart(newAggregate, procID)
        guard startStatus == noErr else {
            stopAggregate()
            throw CoreAudioError(status: startStatus, operation: "Start aggregate device")
        }
        outputDeviceUID = output.uid
        let tapFormat = tapID.read(.init(kAudioTapPropertyFormat), initial: AudioStreamBasicDescription())
        formatSummary = "aggregate \(newAggregate.channelCount(scope: kAudioObjectPropertyScopeInput)) in / "
            + "\(newAggregate.channelCount(scope: kAudioObjectPropertyScopeOutput)) out @ \(Int(processor.sampleRate)) Hz, "
            + "tap \(tapFormat.map { "\($0.mChannelsPerFrame) ch @ \(Int($0.mSampleRate)) Hz" } ?? "format unknown")"

        sampleRateListener = PropertyListener(objectID: newAggregate, address: .init(kAudioDevicePropertyNominalSampleRate)) { [weak self] in
            guard let self, self.aggregateID.isValid,
                  let rate = self.aggregateID.read(.init(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)),
                  rate > 0 else { return }
            self.processor.prepare(sampleRate: rate)
        }
    }

    /// Output devices that also have inputs (USB/Bluetooth headsets) would otherwise have their
    /// microphone opened by the aggregate — lighting the mic indicator and forcing Bluetooth
    /// headsets into low-quality hands-free mode. Only the tap's input stream is needed.
    private func disableSubDeviceInputStreams(procID: AudioDeviceIOProcID, subDeviceStreams: Int) {
        let streams = aggregateID.readArray(.init(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput),
                                            of: AudioStreamID.self)
        guard streams.count > subDeviceStreams else { return }
        // struct AudioHardwareIOProcStreamUsage { void *mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[]; }
        let header = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let byteCount = header + MemoryLayout<UInt32>.size * streams.count
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(streams.count), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for index in streams.indices {
            raw.storeBytes(of: UInt32(index < subDeviceStreams ? 0 : 1),
                           toByteOffset: header + index * MemoryLayout<UInt32>.size,
                           as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(byteCount), raw)
        if status != noErr { NSLog("SoundSourceClone: stream usage not applied (\(status.fourCharCode))") }
    }

    private func stopAggregate() {
        sampleRateListener?.invalidate()
        sampleRateListener = nil
        if let procID = ioProcID, aggregateID.isValid {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        destroyAggregateDevice()
        outputDeviceUID = nil
    }

    private func destroyAggregateDevice() {
        if aggregateID.isValid { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = .unknown
    }
}
````

### `SoundSourceClone/Audio/StereoProcessor.swift`

````swift
import AudioToolbox
import Darwin

/// Gain, balance, 10-band EQ, soft clipping and peak metering for one captured app.
///
/// `render` runs on the HAL's real-time IO thread, so it never allocates, locks or touches Swift
/// collections. The main thread talks to it through preallocated raw memory: plain 32-bit loads and
/// stores for scalars, and a double-buffered coefficient bank for the EQ.
final class StereoProcessor {
    static let bandCount = EQBands.count
    private static let bandQ = 1.41
    private static let stateCount = 2 * bandCount * 2

    // 0: target gain, 1: left balance gain, 2: right balance gain, 3: peak L, 4: peak R
    private let shared = UnsafeMutablePointer<Float>.allocate(capacity: 5)
    // Two banks × bands × (b0 b1 b2 a1 a2)
    private let coefficients = UnsafeMutablePointer<Float>.allocate(capacity: 2 * StereoProcessor.bandCount * 5)
    // 0: active bank, 1: bank-0 band mask, 2: bank-1 band mask
    private let bankInfo = UnsafeMutablePointer<Int32>.allocate(capacity: 3)
    // Two channels × bands × two TDF-II state values
    private let filterState = UnsafeMutablePointer<Float>.allocate(capacity: StereoProcessor.stateCount)
    private let smoothing = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    /// Touched only on the IO thread. Starts at 0 so a new tap fades in instead of popping.
    private var renderGain: Float = 0
    private var eqGains = [Float](repeating: 0, count: StereoProcessor.bandCount)
    private(set) var sampleRate: Double = 48_000

    init() {
        shared.initialize(repeating: 0, count: 5)
        shared[0] = 1
        shared[1] = 1
        shared[2] = 1
        coefficients.initialize(repeating: 0, count: 2 * Self.bandCount * 5)
        bankInfo.initialize(repeating: 0, count: 3)
        filterState.initialize(repeating: 0, count: Self.stateCount)
        smoothing.initialize(to: 0.002)
    }

    deinit {
        shared.deallocate()
        coefficients.deallocate()
        bankInfo.deallocate()
        filterState.deallocate()
        smoothing.deallocate()
    }

    // MARK: Main-thread API

    func setGain(_ gain: Float) { shared[0] = max(gain, 0) }

    /// -1 (left) … +1 (right); the far side is attenuated linearly.
    func setBalance(_ balance: Float) {
        let value = min(max(balance, -1), 1)
        shared[1] = value > 0 ? 1 - value : 1
        shared[2] = value < 0 ? 1 + value : 1
    }

    func setEQ(gains: [Float]) {
        eqGains = gains
        rebuildCoefficients()
    }

    func prepare(sampleRate: Double) {
        guard sampleRate > 0 else { return }
        self.sampleRate = sampleRate
        smoothing.pointee = Float(1 - exp(-1 / (0.012 * sampleRate)))   // ~12 ms gain glide
        rebuildCoefficients()
    }

    /// Returns and clears the peaks accumulated since the last call.
    func takePeaks() -> (left: Float, right: Float) {
        let peaks = (left: shared[3], right: shared[4])
        shared[3] = 0
        shared[4] = 0
        return peaks
    }

    private func rebuildCoefficients() {
        let next = 1 - Int(bankInfo[0])
        let bank = coefficients + next * Self.bandCount * 5
        var mask: Int32 = 0
        for (band, frequency) in EQBands.frequencies.enumerated() {
            let gainDB = Double(band < eqGains.count ? eqGains[band] : 0)
            guard abs(gainDB) > 0.05, frequency < sampleRate * 0.45 else { continue }
            // RBJ cookbook peaking filter.
            let a = pow(10, gainDB / 40)
            let w0 = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(w0) / (2 * Self.bandQ)
            let cosW0 = cos(w0)
            let a0 = 1 + alpha / a
            let c = bank + band * 5
            c[0] = Float((1 + alpha * a) / a0)
            c[1] = Float(-2 * cosW0 / a0)
            c[2] = Float((1 - alpha * a) / a0)
            c[3] = Float(-2 * cosW0 / a0)
            c[4] = Float((1 - alpha / a) / a0)
            mask |= 1 << Int32(band)
        }
        bankInfo[1 + next] = mask
        OSMemoryBarrier()   // publish the coefficients before flipping the bank
        bankInfo[0] = Int32(next)
    }

    // MARK: IO thread

    /// Reads the tap's stereo mix from `input` and writes the processed signal to `output`.
    /// The tap's channels are the last two input channels of the aggregate device (they follow any
    /// input channels the output sub-device contributes).
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inputChannels = Self.channelCount(inputs)
        guard inputChannels > 0,
              let inL = Self.channel(inputs, max(inputChannels - 2, 0)),
              let inR = Self.channel(inputs, inputChannels - 1),
              let outL = Self.channel(outputs, 0) else { return }
        let outR = Self.channel(outputs, 1)
        var frames = min(inL.frames, inR.frames, outL.frames)
        if let outR { frames = min(frames, outR.frames) }
        guard frames > 0 else { return }

        let bank = Int(bankInfo[0])
        let mask = bankInfo[1 + bank]
        let coeffs = coefficients + bank * Self.bandCount * 5
        let target = shared[0]
        let balanceL = shared[1]
        let balanceR = shared[2]
        let k = smoothing.pointee
        var gain = renderGain
        var peakL: Float = 0
        var peakR: Float = 0

        for frame in 0..<frames {
            gain += (target - gain) * k
            var left = inL.data[frame * inL.stride]
            var right = inR.data[frame * inR.stride]
            if mask != 0 {
                left = runEQ(left, channel: 0, coeffs: coeffs, mask: mask)
                right = runEQ(right, channel: 1, coeffs: coeffs, mask: mask)
            }
            left = Self.softClip(left * gain * balanceL)
            right = Self.softClip(right * gain * balanceR)
            peakL = max(peakL, abs(left))
            peakR = max(peakR, abs(right))
            if let outR {
                outL.data[frame * outL.stride] = left
                outR.data[frame * outR.stride] = right
            } else {
                outL.data[frame * outL.stride] = 0.5 * (left + right)
            }
        }

        renderGain = gain
        if mask != 0 { sanitizeFilterState() }
        if peakL > shared[3] { shared[3] = peakL }
        if peakR > shared[4] { shared[4] = peakR }
    }

    @inline(__always)
    private func runEQ(_ x: Float, channel: Int, coeffs: UnsafeMutablePointer<Float>, mask: Int32) -> Float {
        var y = x
        let state = filterState + channel * Self.bandCount * 2
        var band = 0
        while band < Self.bandCount {
            if mask & (1 << Int32(band)) != 0 {
                let c = coeffs + band * 5
                let s = state + band * 2
                let out = c[0] * y + s[0]
                s[0] = c[1] * y - c[3] * out + s[1]
                s[1] = c[2] * y - c[4] * out
                y = out
            }
            band += 1
        }
        return y
    }

    /// Flushes denormals and recovers from any non-finite state.
    @inline(__always)
    private func sanitizeFilterState() {
        var i = 0
        while i < Self.stateCount {
            let value = filterState[i]
            if !value.isFinite || abs(value) < 1e-25 { filterState[i] = 0 }
            i += 1
        }
    }

    /// Transparent below 0.85, then a tanh knee that never exceeds ±1 (keeps 100 %+ boost clean).
    @inline(__always)
    private static func softClip(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > 0.85 else { return x }
        let shaped = 0.85 + 0.15 * tanhf((magnitude - 0.85) / 0.15)
        return x < 0 ? -shaped : shaped
    }

    private struct Channel {
        let data: UnsafeMutablePointer<Float>
        let stride: Int
        let frames: Int
    }

    @inline(__always)
    private static func channelCount(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
        var total = 0
        for buffer in list { total += Int(buffer.mNumberChannels) }
        return total
    }

    /// Locates channel `index` across the (possibly interleaved, possibly multi-stream) buffer list.
    @inline(__always)
    private static func channel(_ list: UnsafeMutableAudioBufferListPointer, _ index: Int) -> Channel? {
        var first = 0
        for buffer in list {
            let count = Int(buffer.mNumberChannels)
            if index < first + count {
                guard let data = buffer.mData, count > 0 else { return nil }
                let frames = Int(buffer.mDataByteSize) / (count * MemoryLayout<Float>.size)
                return Channel(data: data.assumingMemoryBound(to: Float.self) + (index - first),
                               stride: count,
                               frames: frames)
            }
            first += count
        }
        return nil
    }
}
````

### `SoundSourceClone/Model/AppEntry.swift`

````swift
import AppKit
import CoreAudio
import Observation

/// One row in the Applications section: a running app (possibly several processes) or a favorite.
@MainActor @Observable
final class AppEntry: Identifiable {
    let id: String
    var name: String
    var icon: NSImage
    var bundleID: String?
    var bundleURL: URL?
    var settings: AppAudioSettings

    var isFavorite = false
    var isRegularApp = false
    var isRunning = false
    var isPlaying = false
    var isCaptured = false
    var captureError: String?
    /// Post-processing peak, mapped to 0…1 on a −60…0 dBFS scale.
    var level: Float = 0
    var processObjectIDs: [AudioObjectID] = []
    var pids: [pid_t] = []
    /// The device the app itself is playing to (usually the system default, unless the app picked one).
    var nativeOutputDeviceID: AudioObjectID?

    init(id: String, name: String, icon: NSImage, bundleID: String?, bundleURL: URL?, settings: AppAudioSettings) {
        self.id = id
        self.name = name
        self.icon = icon
        self.bundleID = bundleID
        self.bundleURL = bundleURL
        self.settings = settings
    }
}
````

### `SoundSourceClone/Model/AudioSettings.swift`

````swift
import Foundation

struct EQSettings: Codable, Equatable {
    var enabled = false
    var gains = [Float](repeating: 0, count: EQBands.count)
    var presetName: String? = "Flat"

    var isActive: Bool { enabled && gains.contains { abs($0) > 0.05 } }
}

/// Everything the user can change for one app. Stored per bundle identifier.
struct AppAudioSettings: Codable, Equatable {
    /// Slider position: 0 … 2 (1 = 100 %, above 1 is boost).
    var volume: Float = 1
    var isMuted = false
    /// -1 (left) … +1 (right)
    var balance: Float = 0
    var eq = EQSettings()
    /// nil follows the system default output device.
    var outputDeviceUID: String?
    var outputDeviceName: String?

    var isAdjusted: Bool {
        abs(volume - 1) > 0.001 || isMuted || abs(balance) > 0.001 || eq.isActive || outputDeviceUID != nil
    }
}

struct FavoriteApp: Codable, Hashable, Identifiable {
    var id: String          // bundle identifier
    var name: String
    var bundlePath: String?
}

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    /// Every app that plays audio is captured, which also powers its level meter.
    case allActive
    /// Only apps whose settings differ from the defaults are captured (no meters for the rest).
    case adjustedOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .allActive: "All apps that play audio"
        case .adjustedOnly: "Only apps I adjust"
        }
    }
}

enum Edition: String, Codable, CaseIterable, Identifiable {
    case pro, trial
    var id: String { rawValue }
    var title: String { self == .pro ? "Pro" : "Trial Mode" }
}

struct Preferences: Codable, Equatable {
    var systemExpanded = true
    var applicationsExpanded = true
    var showRouting = true
    var captureMode: CaptureMode = .allActive
    var showInputLevel = false
    var edition: Edition = .pro
}

struct QuickConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var created = Date()
    var apps: [String: AppAudioSettings]
    var outputDeviceUID: String?
    var inputDeviceUID: String?
    var soundEffectsDeviceUID: String?
    var outputVolume: Float?
    var inputVolume: Float?
    var systemEQ: EQSettings?
}

struct PersistedState: Codable {
    var apps: [String: AppAudioSettings] = [:]
    var favorites: [FavoriteApp] = []
    var quickConfigs: [QuickConfig] = []
    var systemEQ = EQSettings()
    var prefs = Preferences()

    private static let defaultsKey = "SoundSourceClone.state.v1"

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return PersistedState() }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
````

### `SoundSourceClone/Model/EQPreset.swift`

````swift
import Foundation

enum EQBands {
    static let count = 10
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let labels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let range: ClosedRange<Float> = -12...12
}

struct EQPreset: Identifiable {
    let name: String
    let gains: [Float]
    var id: String { name }

    static let all: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [6, 5, 4, 2, 0.5, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Reducer", gains: [-6, -5, -4, -2, -0.5, 0, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        EQPreset(name: "Treble Reducer", gains: [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]),
        EQPreset(name: "Vocal Boost", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        EQPreset(name: "Spoken Word", gains: [-4, -3, 0, 1, 3, 4, 4, 3, 1, -2]),
        EQPreset(name: "Loudness", gains: [6, 4, 0, 0, -2, 0, -1, -1, 4, 2]),
        EQPreset(name: "Electronic", gains: [4, 3.5, 1, 0, -2, 2, 1, 1.5, 4, 5]),
        EQPreset(name: "Rock", gains: [5, 4, 3, 1, -1, -1, 1, 2.5, 3.5, 4.5]),
        EQPreset(name: "Acoustic", gains: [4.5, 4.5, 3.5, 1, 2, 1.5, 3, 3.5, 3, 1.5]),
        EQPreset(name: "Late Night", gains: [-3, -2, -1, 0, 1, 2, 2, 1, -1, -3]),
    ]

    static func matching(_ gains: [Float]) -> EQPreset? {
        all.first { preset in zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.01 } }
    }
}
````

### `SoundSourceClone/Model/PreviewData.swift`

````swift
import AppKit
import CoreAudio

/// Static data for SwiftUI previews and `--snapshot` renders. No Core Audio calls are made with it.
enum PreviewData {
    static let devices: [AudioDevice] = [
        AudioDevice(id: 1, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers",
                    transportType: kAudioDeviceTransportTypeBuiltIn, inputChannels: 0, outputChannels: 2, inputStreamCount: 0),
        AudioDevice(id: 2, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone",
                    transportType: kAudioDeviceTransportTypeBuiltIn, inputChannels: 1, outputChannels: 0, inputStreamCount: 1),
        AudioDevice(id: 3, uid: "AirPodsPro", name: "AirPods Pro",
                    transportType: kAudioDeviceTransportTypeBluetooth, inputChannels: 1, outputChannels: 2, inputStreamCount: 1),
        AudioDevice(id: 4, uid: "LGUltraFine", name: "LG UltraFine Display Audio",
                    transportType: kAudioDeviceTransportTypeUSB, inputChannels: 0, outputChannels: 2, inputStreamCount: 0),
        AudioDevice(id: 5, uid: "BlackHole2ch", name: "BlackHole 2ch",
                    transportType: kAudioDeviceTransportTypeVirtual, inputChannels: 2, outputChannels: 2, inputStreamCount: 1),
    ]

    struct App {
        let id: String
        let name: String
        let symbol: String
        var volume: Float = 1
        var level: Float = 0
        var playing = true
        var favorite = false
        var running = true
        var eq: [Float]?
        var outputUID: String?
        var muted = false
    }

    static let apps: [App] = [
        App(id: "com.spotify.client", name: "Spotify", symbol: "music.note", volume: 0.75, level: 0.64, favorite: true),
        App(id: "com.google.Chrome", name: "Google Chrome", symbol: "globe", volume: 1, level: 0.41, favorite: true, outputUID: "AirPodsPro"),
        App(id: "net.whatsapp.WhatsApp", name: "WhatsApp", symbol: "message.fill", volume: 0.5, playing: false, favorite: true),
        App(id: "com.hnc.Discord", name: "Discord", symbol: "bubble.left.and.bubble.right.fill", volume: 1.25, level: 0.72,
            eq: [0, 0, 0, 1, 3, 4, 3, 1, 0, 0]),
        App(id: "com.valvesoftware.steam", name: "Steam", symbol: "gamecontroller.fill", volume: 0.3, level: 0.22),
        App(id: "com.apple.Music", name: "Music", symbol: "music.quarternote.3", playing: false, favorite: true, running: false),
    ]

    static let expandedAppID = "com.hnc.Discord"

    static var state: PersistedState {
        var state = PersistedState()
        state.favorites = apps.filter(\.favorite).map { FavoriteApp(id: $0.id, name: $0.name) }
        state.quickConfigs = [QuickConfig(name: "Gaming", apps: [:]), QuickConfig(name: "Calls", apps: [:])]
        return state
    }

    @MainActor
    static func icon(for app: App) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        let colors: [NSColor] = [.systemGreen, .systemBlue, .systemTeal, .systemIndigo, .systemGray, .systemPink]
        let color = colors[app.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count]
        return NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
            let size = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                   width: size.width, height: size.height))
            return true
        }
    }
}
````

### `SoundSourceClone/UI/AppRowView.swift`

````swift
import SwiftUI

struct AppRowView: View {
    @Environment(AudioEngine.self) private var engine
    let app: AppEntry
    @State private var expansion: RowExpansion?
    @State private var isHovering = false

    init(app: AppEntry, initialExpansion: RowExpansion? = nil) {
        self.app = app
        _expansion = State(initialValue: initialExpansion)
    }

    var body: some View {
        VStack(spacing: 0) {
            row
                .background(isHovering ? Theme.hover : Color.clear)
                .onHover { isHovering = $0 }
            switch expansion {
            case .effects:
                EqualizerPanel(title: "\(app.name) Equalizer", settings: app.settings.eq) {
                    engine.setEQ($0, for: app)
                }
            case .details:
                AppDetailsPanel(app: app)
            case nil:
                EmptyView()
            }
        }
    }

    private var row: some View {
        let settings = app.settings
        return MixerRow(
            title: app.name,
            isDimmed: !app.isPlaying,
            percentText: settings.isMuted ? "Muted" : Theme.percent(settings.volume),
            slider: VolumeSlider(
                value: Binding(get: { settings.isMuted ? 0 : settings.volume },
                               set: { engine.setVolume($0, for: app) }),
                maxValue: 2,
                defaultValue: 1,
                level: app.level,
                isDimmed: settings.isMuted || !app.isRunning)
        ) {
            StarButton(isOn: app.isFavorite) { engine.toggleFavorite(app) }
        } icon: {
            AppIconButton(icon: app.icon, isMuted: settings.isMuted) { engine.toggleMute(app) }
        } trailing: {
            IconButton(systemName: "slider.vertical.3",
                       isOn: expansion == .effects,
                       isActive: settings.eq.isActive,
                       help: "Equalizer & effects") { toggle(.effects) }
            if engine.prefs.showRouting {
                routingPicker
            }
            ChevronButton(isOpen: expansion == .details, help: "App details") { toggle(.details) }
        }
    }

    private var routingPicker: some View {
        let devices = engine.devices
        let settings = app.settings
        let routed = settings.outputDeviceUID.flatMap { devices.device(uid: $0) }
        let isMissing = settings.outputDeviceUID != nil && routed == nil
        // Not redirected: the app plays wherever it chose, normally the system default.
        let unrouted = app.nativeOutputDeviceID.flatMap { devices.device(id: $0) } ?? devices.defaultOutput
        let followsDefault = unrouted == nil || unrouted?.id == devices.defaultOutputID
        let title: String
        if let routed {
            title = routed.name
        } else if isMissing {
            title = "\(settings.outputDeviceName ?? "Device") (offline)"
        } else {
            title = followsDefault ? "Default Output" : (unrouted?.name ?? "Default Output")
        }
        let symbol = routed?.outputSymbol ?? (isMissing ? "exclamationmark.triangle.fill" : "arrow.uturn.right")
        let unroutedTitle = followsDefault
            ? "Default Output (\(devices.defaultOutput?.name ?? "none"))"
            : "App's Own Output (\(unrouted?.name ?? "unknown"))"

        return DevicePickerButton(title: title, symbol: symbol, isMissing: isMissing) {
            var items: [MenuItemSpec] = [
                .action(unroutedTitle,
                        symbol: "arrow.uturn.right",
                        checked: settings.outputDeviceUID == nil) { engine.setOutputDevice(nil, for: app) },
                .separator,
                .header("Route \(app.name) To"),
            ]
            items += devices.outputDevices.map { device in
                .action(device.name, symbol: device.outputSymbol, checked: device.uid == settings.outputDeviceUID) {
                    engine.setOutputDevice(device, for: app)
                }
            }
            if isMissing {
                items.append(.note("\(settings.outputDeviceName ?? "Previous device") — not connected",
                                   symbol: "exclamationmark.triangle"))
            }
            return items
        }
    }

    private func toggle(_ target: RowExpansion) {
        expansion = expansion == target ? nil : target
    }
}
````

### `SoundSourceClone/UI/ApplicationsSectionView.swift`

````swift
import SwiftUI

struct ApplicationsSectionView: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Applications", detail: detail, isExpanded: engine.prefs.applicationsExpanded) {
                engine.prefs.applicationsExpanded.toggle()
            }
            if engine.prefs.applicationsExpanded {
                if !engine.canCapture { PermissionBanner() }
                if engine.apps.isEmpty {
                    EmptyAppsView()
                } else {
                    ForEach(engine.apps) { app in
                        AppRowView(app: app,
                                   initialExpansion: engine.previewExpandedAppID == app.id ? .effects : nil)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var detail: String? {
        let playing = engine.apps.filter(\.isPlaying).count
        return playing > 0 ? "\(playing) playing" : nil
    }
}

private struct EmptyAppsView: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "music.note.list")
                .font(.system(size: 18))
                .foregroundStyle(Theme.tertiaryText)
            Text("No apps are playing audio")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text("Apps appear here as soon as they make sound. Star an app to keep it listed.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct PermissionBanner: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        let denied = engine.permission == .denied
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Per-app audio needs System Audio Recording access")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(denied
                     ? "Enable SoundSource Clone in System Settings › Privacy & Security › Screen & System Audio Recording."
                     : "Allow access to change app volumes, apply effects and route apps to other devices.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            CapsuleButton(denied ? "Open Settings" : "Grant Access", isProminent: true) {
                engine.requestCapturePermission()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.warning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.warning.opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
````

### `SoundSourceClone/UI/BottomBarView.swift`

````swift
import AppKit
import SwiftUI

struct BottomBarView: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        HStack(spacing: 8) {
            PopUpMenuButton(items: favoriteItems) {
                CapsuleLabel(title: "Add Favorite", symbol: "plus", showsChevron: true)
            }
            .help("Keep an app in the list, even when it isn't running")
            Spacer()
            PopUpMenuButton(items: quickConfigItems) {
                CapsuleLabel(title: "Quick Configs", symbol: "rectangle.stack", showsChevron: true)
            }
            .help("Save and restore sets of volumes, effects and routes")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private func favoriteItems() -> [MenuItemSpec] {
        var items: [MenuItemSpec] = [.header("Running Applications")]
        let candidates = engine.favoriteCandidates()
        if candidates.isEmpty { items.append(.note("No other running apps")) }
        items += candidates.map { app in
            .action(app.localizedName ?? app.bundleIdentifier ?? "App", image: app.icon?.resized(to: 16)) {
                engine.addFavorite(app)
            }
        }
        items += [
            .separator,
            .action("Choose Application…", symbol: "folder") { engine.chooseFavoriteFromDisk() },
        ]
        return items
    }

    private func quickConfigItems() -> [MenuItemSpec] {
        var items: [MenuItemSpec] = []
        if engine.quickConfigs.isEmpty {
            items.append(.note("No saved configurations"))
        } else {
            items.append(.header("Apply"))
            items += engine.quickConfigs.map { config in
                .action(config.name, symbol: "rectangle.stack") { engine.applyQuickConfig(config) }
            }
        }
        items += [
            .separator,
            .action("Save Current Configuration…", symbol: "square.and.arrow.down") {
                let suggestion = "Config \(engine.quickConfigs.count + 1)"
                if let name = TextPrompt.run(title: "Save Quick Config",
                                             message: "Saves app volumes, effects and routes plus the current system devices.",
                                             defaultValue: suggestion,
                                             confirmTitle: "Save") {
                    engine.saveQuickConfig(named: name)
                }
            },
            .submenu("Delete", symbol: "trash", engine.quickConfigs.map { config in
                .action(config.name) { engine.deleteQuickConfig(config) }
            }),
        ]
        return items
    }
}

@MainActor
enum TextPrompt {
    static func run(title: String, message: String, defaultValue: String, confirmTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
````

### `SoundSourceClone/UI/DetailPanels.swift`

````swift
import AppKit
import SwiftUI

/// Opened by an app row's chevron.
struct AppDetailsPanel: View {
    @Environment(AudioEngine.self) private var engine
    let app: AppEntry

    var body: some View {
        DetailCard {
            HStack(spacing: 8) {
                DetailLabel("Balance")
                Text("L").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                BalanceSlider(value: Binding(get: { app.settings.balance },
                                             set: { engine.setBalance($0, for: app) }))
                    .frame(width: 200)
                Text("R").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                Text(balanceText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, alignment: .leading)
                Spacer()
            }

            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            HStack(spacing: 8) {
                CapsuleButton(app.settings.isMuted ? "Unmute" : "Mute",
                              symbol: app.settings.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                    engine.toggleMute(app)
                }
                CapsuleButton("Reset", symbol: "arrow.counterclockwise") { engine.reset(app) }
                if let url = app.bundleURL {
                    CapsuleButton("Show in Finder", symbol: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Spacer()
                if let bundleID = app.bundleID {
                    Text(bundleID)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var balanceText: String {
        let balance = app.settings.balance
        if abs(balance) < 0.005 { return "Centre" }
        return "\(Int((abs(balance) * 100).rounded()))% \(balance < 0 ? "L" : "R")"
    }

    private var statusColor: Color {
        if app.captureError != nil { return Theme.danger }
        if app.isCaptured { return Color.green }
        return Theme.tertiaryText
    }

    private var statusText: String {
        if let error = app.captureError { return "Capture failed: \(error)" }
        if app.isCaptured {
            let count = app.pids.count
            let pids = app.pids.prefix(4).map(String.init).joined(separator: ", ")
            return "Processing via Core Audio process tap · \(count) process\(count == 1 ? "" : "es") (PID \(pids))"
        }
        if !app.isRunning { return "Not running — settings apply the next time it plays audio." }
        if !engine.canCapture { return "Waiting for System Audio Recording permission." }
        if app.processObjectIDs.isEmpty { return "Running, but it hasn't opened an audio connection yet." }
        return "Passthrough — change a setting to start processing this app."
    }
}

/// Opened by the System › Output chevron.
struct OutputDetailsPanel: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        let devices = engine.devices
        DetailCard {
            HStack(spacing: 8) {
                DetailLabel("Sample Rate")
                PopUpMenuButton(items: sampleRateItems) {
                    CapsuleLabel(title: Self.format(rate: devices.outputSampleRate), symbol: "waveform", showsChevron: true)
                }
                .disabled(devices.outputSampleRates.count < 2)
                Spacer()
                if let output = devices.defaultOutput {
                    Text("\(output.outputChannels) ch · \(output.uid)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                DetailLabel("Balance")
                Text("L").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                BalanceSlider(value: Binding(get: { devices.outputBalance }, set: { devices.setOutputBalance($0) }),
                              isEnabled: devices.outputBalanceAvailable)
                    .frame(width: 200)
                Text("R").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                if !devices.outputBalanceAvailable {
                    Text("Not supported by this device")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                CapsuleButton("Sound Settings…", symbol: "gear") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                CapsuleButton("Audio MIDI Setup", symbol: "pianokeys") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"),
                                                       configuration: NSWorkspace.OpenConfiguration())
                }
                Spacer()
            }
        }
    }

    private func sampleRateItems() -> [MenuItemSpec] {
        let devices = engine.devices
        return [.header("Sample Rate")] + devices.outputSampleRates.map { rate in
            .action(Self.format(rate: rate), checked: abs(rate - devices.outputSampleRate) < 1) {
                devices.setOutputSampleRate(rate)
            }
        }
    }

    static func format(rate: Double) -> String {
        guard rate > 0 else { return "—" }
        let khz = rate / 1000
        return khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz)
    }
}

private struct DetailLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 74, alignment: .leading)
    }
}
````

### `SoundSourceClone/UI/EqualizerPanel.swift`

````swift
import SwiftUI

/// Inline 10-band graphic EQ with presets, used for both apps and system-wide effects.
struct EqualizerPanel: View {
    let title: String
    let settings: EQSettings
    var note: String?
    let onChange: (EQSettings) -> Void

    init(title: String, settings: EQSettings, note: String? = nil, onChange: @escaping (EQSettings) -> Void) {
        self.title = title
        self.settings = settings
        self.note = note
        self.onChange = onChange
    }

    var body: some View {
        DetailCard {
            HStack(spacing: 10) {
                PillToggle(isOn: settings.enabled) {
                    var updated = settings
                    updated.enabled.toggle()
                    onChange(updated)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(settings.enabled ? "On" : "Bypassed")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                PopUpMenuButton(items: presetItems) {
                    CapsuleLabel(title: settings.presetName ?? "Custom", symbol: "slider.vertical.3", showsChevron: true)
                }
                CapsuleButton("Reset") {
                    var updated = settings
                    updated.gains = [Float](repeating: 0, count: EQBands.count)
                    updated.presetName = "Flat"
                    onChange(updated)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .trailing) {
                    Text("+12").frame(maxHeight: .infinity, alignment: .top)
                    Text("0")
                    Text("−12").frame(maxHeight: .infinity, alignment: .bottom)
                }
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 24, height: 96)
                .padding(.trailing, 6)

                ForEach(0..<EQBands.count, id: \.self) { band in
                    VStack(spacing: 5) {
                        EQBandSlider(value: gainBinding(band), isEnabled: settings.enabled)
                            .frame(height: 96)
                        Text(EQBands.labels[band])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        Text(gainLabel(band))
                            .font(.system(size: 8.5).monospacedDigit())
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let note {
                Text(note)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func gainBinding(_ band: Int) -> Binding<Float> {
        Binding(
            get: { band < settings.gains.count ? settings.gains[band] : 0 },
            set: { newValue in
                var updated = settings
                if updated.gains.count < EQBands.count {
                    updated.gains += [Float](repeating: 0, count: EQBands.count - updated.gains.count)
                }
                updated.gains[band] = newValue
                updated.enabled = true   // touching a band turns the EQ on
                updated.presetName = EQPreset.matching(updated.gains)?.name
                onChange(updated)
            })
    }

    private func gainLabel(_ band: Int) -> String {
        let gain = band < settings.gains.count ? settings.gains[band] : 0
        if abs(gain) < 0.05 { return "0" }
        return String(format: gain > 0 ? "+%.1f" : "%.1f", gain)
    }

    private func presetItems() -> [MenuItemSpec] {
        [.header("Presets")] + EQPreset.all.map { preset in
            .action(preset.name, checked: preset.name == settings.presetName) {
                var updated = settings
                updated.gains = preset.gains
                updated.presetName = preset.name
                updated.enabled = true
                onChange(updated)
            }
        }
    }
}
````

### `SoundSourceClone/UI/HeaderView.swift`

````swift
import SwiftUI

struct HeaderView: View {
    @Environment(AudioEngine.self) private var engine
    @Environment(PanelState.self) private var panel

    var body: some View {
        ZStack {
            Text("SoundSource")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            HStack(spacing: 4) {
                IconButton(systemName: panel.isPinned ? "pin.fill" : "pin",
                           isOn: panel.isPinned,
                           help: panel.isPinned ? "Unpin (close when clicking elsewhere)" : "Keep window open") {
                    panel.isPinned.toggle()
                }
                IconButton(systemName: "arrow.triangle.branch",
                           isOn: engine.prefs.showRouting,
                           help: "Show per-app audio routing") {
                    engine.prefs.showRouting.toggle()
                }

                Spacer()

                EditionBadge(edition: engine.prefs.edition)
                    .padding(.trailing, 4)
                IconButton(systemName: engine.devices.inputMuted ? "mic.slash.fill" : "mic.fill",
                           isOn: engine.devices.inputMuted,
                           tint: Theme.danger,
                           help: engine.devices.inputMuted ? "Unmute microphone" : "Mute microphone") {
                    engine.devices.toggleInputMute()
                }
                PopUpMenuButton(items: gearMenu) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .help("Settings")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func gearMenu() -> [MenuItemSpec] {
        [
            .action("Settings…", symbol: "gearshape") { panel.openSettings() },
            .action("Launch at Login", checked: LoginItem.isEnabled) { LoginItem.setEnabled(!LoginItem.isEnabled) },
            .separator,
            .action("About SoundSource Clone", symbol: "info.circle") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .action("Quit SoundSource Clone", symbol: "power") { NSApp.terminate(nil) },
        ]
    }
}

struct EditionBadge: View {
    let edition: Edition

    var body: some View {
        Text(edition == .pro ? "PRO" : "Trial Mode")
            .font(.system(size: 9.5, weight: .bold))
            .kerning(edition == .pro ? 0.8 : 0)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(edition == .pro ? Theme.proBadge : Theme.trialBadge))
            .help(edition == .pro ? "Pro" : "Trial Mode")
    }
}
````

### `SoundSourceClone/UI/PopoverRootView.swift`

````swift
import SwiftUI

/// The whole panel: header, scrollable System + Applications sections, bottom bar.
/// Its ideal height reaches the window through NSHostingController.preferredContentSize.
struct PopoverRootView: View {
    @Environment(AudioEngine.self) private var engine
    @Environment(PanelState.self) private var panel
    @State private var scrollContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Hairline()
            sections
            Hairline()
            BottomBarView()
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var sections: some View {
        let content = VStack(spacing: 0) {
            SystemSectionView()
            Hairline().padding(.horizontal, 12)
            ApplicationsSectionView()
        }
        .padding(.vertical, 4)

        if panel.isSnapshot {
            content   // ImageRenderer can't draw an NSScrollView
        } else {
            ScrollView(.vertical) {
                content.onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    scrollContentHeight = height
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(scrollContentHeight, 1), panel.maxScrollHeight))
        }
    }
}

#Preview {
    PopoverRootView()
        .environment(AudioEngine(preview: true))
        .environment(PanelState())
        .background(Theme.snapshotBackground)
}
````

### `SoundSourceClone/UI/SettingsView.swift`

````swift
import SwiftUI

struct SettingsView: View {
    @Environment(AudioEngine.self) private var engine
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
                Picker("Header badge", selection: preference(\.edition)) {
                    ForEach(Edition.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Picker("Capture", selection: preference(\.captureMode)) {
                    ForEach(CaptureMode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("System Audio Recording") {
                    HStack(spacing: 8) {
                        Text(permissionText).foregroundStyle(.secondary)
                        if engine.permission != .authorized {
                            Button(engine.permission == .denied ? "Open Settings" : "Request Access") {
                                engine.requestCapturePermission()
                            }
                        }
                    }
                }
                Toggle("Show microphone input level", isOn: preference(\.showInputLevel))
            } header: {
                Text("Per-App Audio")
            } footer: {
                Text("Apps are captured with Core Audio process taps (macOS 14.2+). Showing the microphone level keeps the input open while the panel is visible, which lights the mic indicator.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All App Settings…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 400)
        .confirmationDialog("Reset volume, effects and routing for every app?", isPresented: $confirmReset) {
            Button("Reset All", role: .destructive) { engine.resetAllApps() }
        }
        .onAppear { engine.recheckPermission() }
    }

    private var permissionText: String {
        switch engine.permission {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .unknown: "Not determined"
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { engine.prefs[keyPath: keyPath] },
                set: { engine.prefs[keyPath: keyPath] = $0 })
    }
}
````

### `SoundSourceClone/UI/SystemSectionView.swift`

````swift
import AppKit
import SwiftUI

struct SystemSectionView: View {
    @Environment(AudioEngine.self) private var engine
    @State private var expansion: RowExpansion?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "System", isExpanded: engine.prefs.systemExpanded) {
                engine.prefs.systemExpanded.toggle()
            }
            if engine.prefs.systemExpanded {
                outputRow
                switch expansion {
                case .effects:
                    EqualizerPanel(title: "System Effects",
                                   settings: engine.systemEQ,
                                   note: "Applied to every captured app, on top of each app's own EQ.") {
                        engine.systemEQ = $0
                    }
                case .details:
                    OutputDetailsPanel()
                case nil:
                    EmptyView()
                }
                inputRow
                soundEffectsRow
            }
        }
        .padding(.bottom, 4)
    }

    private func toggle(_ target: RowExpansion) {
        expansion = expansion == target ? nil : target
    }

    // MARK: Output

    private var outputRow: some View {
        let devices = engine.devices
        let output = devices.defaultOutput
        let percent = !devices.outputVolumeAvailable ? "—" : (devices.outputMuted ? "Muted" : Theme.percent(devices.outputVolume))
        return MixerRow(
            title: "Output",
            percentText: percent,
            slider: VolumeSlider(
                value: Binding(get: { devices.outputMuted ? 0 : devices.outputVolume },
                               set: { devices.setOutputVolume($0) }),
                defaultValue: 0.5,
                level: engine.outputLevel,
                isEnabled: devices.outputVolumeAvailable)
        ) {
            Color.clear
        } icon: {
            SymbolButton(systemName: devices.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         tint: devices.outputMuted ? Theme.danger : nil,
                         help: devices.outputMuted ? "Unmute output" : "Mute output") {
                devices.toggleOutputMute()
            }
        } trailing: {
            IconButton(systemName: "slider.vertical.3",
                       isOn: expansion == .effects,
                       isActive: engine.systemEQ.isActive,
                       help: "System effects") { toggle(.effects) }
            DevicePickerButton(title: output?.name ?? "No Output Device",
                               symbol: output?.outputSymbol ?? "speaker.slash") {
                DeviceMenus.devices(devices.outputDevices, selectedUID: output?.uid, header: "Output Device",
                                    symbol: \.outputSymbol) { devices.setDefaultOutput($0) }
            }
            ChevronButton(isOpen: expansion == .details, help: "Output device options") { toggle(.details) }
        }
    }

    // MARK: Input

    private var inputRow: some View {
        let devices = engine.devices
        let input = devices.defaultInput
        let percent = !devices.inputVolumeAvailable ? "—" : (devices.inputMuted ? "Muted" : Theme.percent(devices.inputVolume))
        return MixerRow(
            title: "Input",
            percentText: percent,
            slider: VolumeSlider(
                value: Binding(get: { devices.inputMuted ? 0 : devices.inputVolume },
                               set: { devices.setInputVolume($0) }),
                defaultValue: 0.5,
                level: engine.inputLevel,
                showsMeter: engine.prefs.showInputLevel,
                isEnabled: devices.inputVolumeAvailable)
        ) {
            Color.clear
        } icon: {
            SymbolButton(systemName: devices.inputMuted ? "mic.slash.fill" : "mic.fill",
                         tint: devices.inputMuted ? Theme.danger : nil,
                         help: devices.inputMuted ? "Unmute microphone" : "Mute microphone") {
                devices.toggleInputMute()
            }
        } trailing: {
            ColumnSpacer(width: 22)
            DevicePickerButton(title: input?.name ?? "No Input Device",
                               symbol: input?.inputSymbol ?? "mic.slash") {
                DeviceMenus.devices(devices.inputDevices, selectedUID: input?.uid, header: "Input Device",
                                    symbol: \.inputSymbol) { devices.setDefaultInput($0) }
            }
            ColumnSpacer(width: 18)
        }
    }

    // MARK: Sound effects

    private var soundEffectsRow: some View {
        let devices = engine.devices
        let effectsDevice = devices.systemOutput
        return MixerRow(
            title: "Sound Effects",
            percentText: Theme.percent(devices.alertVolume),
            slider: VolumeSlider(
                value: Binding(get: { devices.alertVolume }, set: { devices.setAlertVolume($0) }),
                showsMeter: false,
                onEditingEnded: { NSSound.beep() })
        ) {
            Color.clear
        } icon: {
            SymbolButton(systemName: "bell.fill", help: "Play alert sound") { NSSound.beep() }
        } trailing: {
            ColumnSpacer(width: 22)
            DevicePickerButton(title: effectsDevice?.name ?? "System Output",
                               symbol: effectsDevice?.outputSymbol ?? "bell") {
                DeviceMenus.devices(devices.outputDevices, selectedUID: effectsDevice?.uid,
                                    header: "Play Sound Effects Through",
                                    symbol: \.outputSymbol) { devices.setSoundEffectsOutput($0) }
            }
            ColumnSpacer(width: 18)
        }
    }
}

@MainActor
enum DeviceMenus {
    static func devices(_ devices: [AudioDevice],
                        selectedUID: String?,
                        header: String,
                        symbol: KeyPath<AudioDevice, String>,
                        onSelect: @escaping (AudioDevice) -> Void) -> [MenuItemSpec] {
        var items: [MenuItemSpec] = [.header(header)]
        if devices.isEmpty { items.append(.note("No devices available")) }
        items += devices.map { device in
            .action(device.name, symbol: device[keyPath: symbol], checked: device.uid == selectedUID) { onSelect(device) }
        }
        items += [
            .separator,
            .action("Sound Settings…", symbol: "gear") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            },
        ]
        return items
    }
}
````

### `SoundSourceClone/UI/Theme.swift`

````swift
import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 690
    static let cornerRadius: CGFloat = 12
    static let rowHeight: CGFloat = 34
    static let nameColumn: CGFloat = 112
    static let percentColumn: CGFloat = 40
    static let deviceColumn: CGFloat = 190

    static let accent = Color(red: 0.32, green: 0.60, blue: 1.0)
    static let favorite = Color(red: 1.0, green: 0.79, blue: 0.24)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.33)

    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)

    static let controlFill = Color.white.opacity(0.07)
    static let controlStroke = Color.white.opacity(0.11)
    static let separator = Color.white.opacity(0.08)
    static let hover = Color.white.opacity(0.045)
    static let cardFill = Color.black.opacity(0.22)
    static let track = Color.white.opacity(0.13)
    static let snapshotBackground = Color(red: 0.135, green: 0.135, blue: 0.15)

    static let meter = LinearGradient(
        stops: [
            .init(color: Color(red: 0.20, green: 0.82, blue: 0.43), location: 0),
            .init(color: Color(red: 0.50, green: 0.88, blue: 0.32), location: 0.62),
            .init(color: Color(red: 1.00, green: 0.80, blue: 0.22), location: 0.84),
            .init(color: Color(red: 1.00, green: 0.33, blue: 0.28), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    static let proBadge = LinearGradient(colors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.25, green: 0.55, blue: 1.0)],
                                         startPoint: .leading, endPoint: .trailing)
    static let trialBadge = LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.20), Color(red: 0.95, green: 0.38, blue: 0.25)],
                                           startPoint: .leading, endPoint: .trailing)

    static func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
}

enum RowExpansion: Equatable {
    case effects
    case details
}
````

### `SoundSourceClone.xcodeproj/xcshareddata/xcschemes/SoundSourceClone.xcscheme`

````xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "5D0000000000000000000007"
               BuildableName = "SoundSourceClone.app"
               BlueprintName = "SoundSourceClone"
               ReferencedContainer = "container:SoundSourceClone.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "5D0000000000000000000007"
            BuildableName = "SoundSourceClone.app"
            BlueprintName = "SoundSourceClone"
            ReferencedContainer = "container:SoundSourceClone.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "5D0000000000000000000007"
            BuildableName = "SoundSourceClone.app"
            BlueprintName = "SoundSourceClone"
            ReferencedContainer = "container:SoundSourceClone.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
````

### `SoundSourceClone/UI/Components/Controls.swift`

````swift
import SwiftUI

/// Small square icon button used in the header and in row accessories.
struct IconButton: View {
    let systemName: String
    var isOn = false
    /// Tints the glyph without the "pressed" background, e.g. EQ active while collapsed.
    var isActive = false
    var tint: Color = Theme.accent
    var size: CGFloat = 22
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn || isActive ? tint : Color.white.opacity(isHovering ? 0.9 : 0.6))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? tint.opacity(0.2) : (isHovering ? Color.white.opacity(0.08) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

struct ChevronButton: View {
    let isOpen: Bool
    var help: String = "Details"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen ? Theme.primaryText : Theme.tertiaryText)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct StarButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Theme.favorite : Theme.tertiaryText)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Remove from Favorites" : "Add to Favorites")
    }
}

/// System row glyph (speaker / mic / bell) that doubles as a mute toggle.
struct SymbolButton: View {
    let systemName: String
    var tint: Color?
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? Theme.primaryText.opacity(0.85))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// App icon that toggles mute when clicked.
struct AppIconButton: View {
    let icon: NSImage
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .opacity(isMuted ? 0.45 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Theme.danger))
                            .offset(x: 3, y: 3)
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute" : "Mute")
    }
}

struct PillToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.accent : Color.white.opacity(0.18))
                    .frame(width: 28, height: 16)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}

struct CapsuleButton: View {
    let title: String
    var symbol: String?
    var isProminent = false
    let action: () -> Void

    init(_ title: String, symbol: String? = nil, isProminent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CapsuleLabel(title: title, symbol: symbol, isProminent: isProminent)
        }
        .buttonStyle(.plain)
    }
}

struct CapsuleLabel: View {
    let title: String
    var symbol: String?
    var showsChevron = false
    var isProminent = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            }
            Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).opacity(0.6)
            }
        }
        .foregroundStyle(isProminent ? Color.white : Theme.primaryText.opacity(0.85))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(isProminent ? Theme.accent : Theme.controlFill))
        .overlay(Capsule().strokeBorder(isProminent ? Color.clear : Theme.controlStroke, lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

struct DevicePickerButton: View {
    let title: String
    let symbol: String
    var isMissing = false
    var width: CGFloat = Theme.deviceColumn
    let items: () -> [MenuItemSpec]

    var body: some View {
        PopUpMenuButton(items: items) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isMissing ? Theme.warning : Theme.secondaryText)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isMissing ? Theme.warning : Theme.primaryText.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.controlStroke, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .help("Output device")
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Fixed-column row shared by the System and Applications sections so sliders line up.
struct MixerRow<Leading: View, Icon: View, Trailing: View>: View {
    let title: String
    var isDimmed = false
    let percentText: String
    let slider: VolumeSlider
    let leading: Leading
    let icon: Icon
    let trailing: Trailing

    init(title: String,
         isDimmed: Bool = false,
         percentText: String,
         slider: VolumeSlider,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder icon: () -> Icon,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.isDimmed = isDimmed
        self.percentText = percentText
        self.slider = slider
        self.leading = leading()
        self.icon = icon()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading.frame(width: 16)
            icon.frame(width: 22, height: 22)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDimmed ? Theme.secondaryText : Theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Theme.nameColumn, alignment: .leading)
            slider
            Text(percentText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(width: Theme.percentColumn, alignment: .trailing)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.rowHeight)
    }
}

/// Container for the inline EQ and detail panels that open under a row.
struct DetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
            .padding(.leading, 36)
            .padding(.trailing, 12)
            .padding(.bottom, 8)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }
}

/// Keeps column alignment where a row has no control in that slot.
struct ColumnSpacer: View {
    let width: CGFloat
    var body: some View { Color.clear.frame(width: width, height: 1) }
}
````

### `SoundSourceClone/UI/Components/PopUpMenuButton.swift`

````swift
import AppKit
import SwiftUI

/// Declarative description of an NSMenu, so SwiftUI views can pop real menus with custom-styled buttons.
struct MenuItemSpec {
    enum Kind {
        case action(() -> Void)
        case header
        case separator
        case submenu([MenuItemSpec])
    }

    var title = ""
    var image: NSImage?
    var isChecked = false
    var isEnabled = true
    var kind: Kind

    static var separator: MenuItemSpec { MenuItemSpec(kind: .separator) }

    static func header(_ title: String) -> MenuItemSpec { MenuItemSpec(title: title, kind: .header) }

    static func note(_ title: String, symbol: String? = nil) -> MenuItemSpec {
        MenuItemSpec(title: title, image: symbol.flatMap(NSImage.menuSymbol), isEnabled: false, kind: .action {})
    }

    static func action(_ title: String,
                       image: NSImage? = nil,
                       symbol: String? = nil,
                       checked: Bool = false,
                       enabled: Bool = true,
                       _ handler: @escaping () -> Void) -> MenuItemSpec {
        MenuItemSpec(title: title, image: image ?? symbol.flatMap(NSImage.menuSymbol),
                     isChecked: checked, isEnabled: enabled, kind: .action(handler))
    }

    static func submenu(_ title: String, symbol: String? = nil, _ items: [MenuItemSpec]) -> MenuItemSpec {
        MenuItemSpec(title: title, image: symbol.flatMap(NSImage.menuSymbol), isEnabled: !items.isEmpty, kind: .submenu(items))
    }
}

@MainActor
enum MenuBuilder {
    static func menu(_ items: [MenuItemSpec]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        for spec in items { menu.addItem(item(spec)) }
        return menu
    }

    /// Pops `menu` with its top-left corner just below `view`.
    static func popUp(_ menu: NSMenu, below view: NSView) {
        let y: CGFloat = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    private static func item(_ spec: MenuItemSpec) -> NSMenuItem {
        let item: NSMenuItem
        switch spec.kind {
        case .separator:
            return .separator()
        case .header:
            return .sectionHeader(title: spec.title)
        case .action(let handler):
            item = ClosureMenuItem(title: spec.title, handler: handler)
        case .submenu(let children):
            item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: "")
            item.submenu = menu(children)
        }
        item.image = spec.image
        item.state = spec.isChecked ? .on : .off
        item.isEnabled = spec.isEnabled
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

extension NSImage {
    static func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    func resized(to side: CGFloat) -> NSImage {
        let copy = (self.copy() as? NSImage) ?? self
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}

/// A SwiftUI button with a fully custom label that pops an NSMenu anchored to itself.
struct PopUpMenuButton<Label: View>: View {
    private let items: () -> [MenuItemSpec]
    private let label: Label
    @Environment(PanelState.self) private var panel
    @State private var anchor = MenuAnchor.Box()

    init(items: @escaping () -> [MenuItemSpec], @ViewBuilder label: () -> Label) {
        self.items = items
        self.label = label()
    }

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            MenuBuilder.popUp(MenuBuilder.menu(items()), below: view)
        } label: {
            label
        }
        .buttonStyle(.plain)
        .background {
            // ImageRenderer draws placeholders for AppKit views, so snapshots skip the anchor.
            if !panel.isSnapshot { MenuAnchor(box: anchor) }
        }
    }
}

/// An invisible NSView that gives the menu a position in window coordinates.
struct MenuAnchor: NSViewRepresentable {
    final class Box {
        weak var view: NSView?
    }

    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}
````

### `SoundSourceClone/UI/Components/VolumeSlider.swift`

````swift
import SwiftUI

/// SoundSource-style horizontal slider: thin track, live level meter inside the track, white knob.
/// When `maxValue > 1` the last 20 % of the track is a boost zone with a detent at 100 %.
struct VolumeSlider: View {
    @Binding var value: Float
    var maxValue: Float = 1
    var defaultValue: Float = 1
    var level: Float = 0
    var showsMeter = true
    var isEnabled = true
    var isDimmed = false
    var onEditingEnded: (() -> Void)?

    private let knobSize: CGFloat = 13
    private let trackHeight: CGFloat = 6
    private let boostStart: CGFloat = 0.8

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knobSize, 1)
            let position = sliderPosition(of: value)
            ZStack(alignment: .leading) {
                track(width: travel, position: position)
                    .padding(.horizontal, knobSize / 2)
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.35))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .offset(x: position * travel)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        var newValue = sliderValue(at: (drag.location.x - knobSize / 2) / travel)
                        if maxValue > 1, abs(newValue - 1) < 0.04 { newValue = 1 }   // detent at 100 %
                        value = (newValue * 100).rounded() / 100
                    }
                    .onEnded { _ in onEditingEnded?() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                value = defaultValue
                onEditingEnded?()
            })
        }
        .frame(height: 18)
        .opacity(isDimmed ? 0.5 : 1)
        .allowsHitTesting(isEnabled)
    }

    private func track(width: CGFloat, position: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.track)
            if maxValue > 1 {
                Rectangle()
                    .fill(Theme.warning.opacity(0.16))
                    .frame(width: width * (1 - boostStart))
                    .offset(x: width * boostStart)
            }
            Rectangle()
                .fill(isEnabled ? Theme.accent.opacity(0.6) : Color.white.opacity(0.18))
                .frame(width: width * position)
            if showsMeter, level > 0.001 {
                Theme.meter
                    .frame(width: width)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * CGFloat(min(level, 1)))
                    }
                    .opacity(0.95)
            }
        }
        .frame(width: width, height: trackHeight)
        .clipShape(Capsule())
        .overlay(alignment: .leading) {
            if maxValue > 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 1, height: trackHeight + 5)
                    .offset(x: width * boostStart)
            }
        }
    }

    private func sliderPosition(of value: Float) -> CGFloat {
        guard maxValue > 1 else { return CGFloat(min(max(value / maxValue, 0), 1)) }
        if value <= 1 { return CGFloat(max(value, 0)) * boostStart }
        return boostStart + CGFloat(min((value - 1) / (maxValue - 1), 1)) * (1 - boostStart)
    }

    private func sliderValue(at position: CGFloat) -> Float {
        let p = min(max(position, 0), 1)
        guard maxValue > 1 else { return Float(p) * maxValue }
        if p <= boostStart { return Float(p / boostStart) }
        return 1 + Float((p - boostStart) / (1 - boostStart)) * (maxValue - 1)
    }
}

/// Centre-detented slider for balance (-1 … +1).
struct BalanceSlider: View {
    @Binding var value: Float
    var isEnabled = true

    private let knobSize: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knobSize, 1)
            let position = CGFloat((min(max(value, -1), 1) + 1) / 2)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Rectangle()
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: abs(position - 0.5) * travel)
                        .offset(x: min(position, 0.5) * travel)
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1)
                        .offset(x: travel / 2)
                }
                .frame(width: travel, height: 4)
                .clipShape(Capsule())
                .padding(.horizontal, knobSize / 2)
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.35))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .offset(x: position * travel)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let p = Float(min(max((drag.location.x - knobSize / 2) / travel, 0), 1))
                var newValue = p * 2 - 1
                if abs(newValue) < 0.06 { newValue = 0 }
                value = (newValue * 100).rounded() / 100
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
        .frame(height: 16)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Vertical EQ band slider (-12 … +12 dB) with a fill from the 0 dB line.
struct EQBandSlider: View {
    @Binding var value: Float
    var isEnabled = true

    private let knobSize: CGFloat = 11
    private let range = EQBands.range

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.height - knobSize, 1)
            let span = range.upperBound - range.lowerBound
            let position = CGFloat(1 - (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span)
            let knobY = position * travel
            let midY = travel / 2
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Theme.track)
                    .frame(width: 4, height: travel)
                    .offset(y: knobSize / 2)
                Rectangle()
                    .fill(isEnabled ? Theme.accent : Color.white.opacity(0.3))
                    .frame(width: 4, height: abs(knobY - midY))
                    .offset(y: min(knobY, midY) + knobSize / 2)
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 12, height: 1)
                    .offset(y: midY + knobSize / 2)
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.55))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .offset(y: knobY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let p = Float(1 - min(max((drag.location.y - knobSize / 2) / travel, 0), 1))
                var newValue = range.lowerBound + p * span
                newValue = (newValue * 2).rounded() / 2      // 0.5 dB steps
                if abs(newValue) < 0.4 { newValue = 0 }
                value = newValue
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}
````

