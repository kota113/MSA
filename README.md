<img width="1198" height="963" alt="image" src="https://github.com/user-attachments/assets/7850eb0a-7316-4492-85b8-5ff716f9b0d0" />

# macOS Subsystem for Android (MSA)

Inspired by [WSA(Windows Subsystem for Android)](https://support.microsoft.com/en-US/Windows/Apps/MobileApps/apps-from-the-amazon-appstore), macOS Subsystem for Android (MSA) runs the official Android Emulator as a VM backend and
gives each Android app its own native macOS `NSWindow`. There is no full AOSP checkout or
build: a single platform-signed privileged host agent is added on top of the stock Android 16
AOSP `userdebug` emulator image.

**Status:** early-stage and actively developed. Core app streaming, input, and live window
resizing all work today — see [Known limitations](#known-limitations) for what's still
missing.

```text
macOS / AppKit NSWindow
  H.264 video ◀──── adb TCP forward ────▶ input events
                                             │
Android Emulator (unmodified AOSP framework) │
  MsaAgent priv-app                          │
    VirtualDevice                            │
      ├─ VirtualDisplay → MediaCodec H.264 ──┘
      ├─ VirtualTouchscreen
      ├─ VirtualMouse
      └─ VirtualKeyboard
            └─ target Activity on that display
```

## Features

- Creates a VirtualDevice/VirtualDisplay per app via Android 16's `VirtualDeviceManager`
- Launches the target Activity on that display with `ActivityOptions.setLaunchDisplayId()`
- Injects macOS input into VirtualTouchscreen / VirtualMouse / VirtualKeyboard
- Streams H.264 via MediaCodec and decodes/paints it in AppKit
- Routes Android playback and microphone input through macOS CoreAudio
- Maps selectable macOS cameras to Android's front and back cameras
- Resizes the VirtualDisplay, density, encoder, and touchscreen to match the `NSWindow`'s
  aspect ratio and size live
- Maps 1 connection → 1 VirtualDevice → 1 `NSWindow`
- Sets up the Companion Device app-streaming association and role automatically
- Forwards `FLAG_SECURE` authentication screens to macOS using a secure VirtualDisplay
- Packages any installed Android app as a double-clickable native macOS `.app`

## Known limitations

- Not yet implemented: clipboard sharing, system notifications, IME composition, and
  DRM-protected video.
- The wire protocol has no authentication and is only safe behind `adb forward`'s localhost
  connection — see [Security notes](#security-notes).
- The priv-app is signed with an AOSP development test key, not a production signing key.
- The Google Play / GMS setup requires a rooted emulator, which breaks Play Integrity, DRM,
  and Wallet-style features — see [Google Play and GMS setup](#google-play-and-gms-setup-rootavd).

## Requirements

- Apple Silicon Mac
- Android SDK + Emulator (scripts default to `~/Library/Android/sdk`; override with
  `ANDROID_SDK_ROOT`)
- Xcode Command Line Tools and Swift 6
- Java 17 or newer

### Setting up prerequisites

```sh
xcode-select --install                 # Xcode Command Line Tools (provides Swift 6)
brew install openjdk@17                # or use the JDK bundled with Android Studio
```

Install the Android SDK with Android Studio (simplest — its default SDK location matches
what these scripts expect) or with the command-line tools only. Either way, make sure these
SDK packages are installed before running anything below:

```sh
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" "emulator" "platforms;android-36" "build-tools;36.0.0"
```

(`scripts/install-system-image.sh` installs the actual emulator system image separately —
see [Initial setup](#initial-setup).)

Finally, put `platform-tools` on your `PATH` — a couple of scripts (`forward.sh`,
`smoke-test.sh`) call plain `adb` rather than the full SDK path:

```sh
echo 'export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"' >> ~/.zshrc
```

## Layout

- `android-agent/` — the Gradle-built, platform-signed priv-app
- `macos-host/` — the Swift Package / AppKit host (no Xcode project required)
- `scripts/` — SDK setup, AVD creation, priv-app install, launch, and verification
- `docs/protocol.md` — the wire protocol between the host and the agent
- `aosp/` — a fallback for building a full AOSP product later; not needed for normal use

## Disk usage
The bulk of the footprint is the
Android SDK's API 36 ARM64 system image, AVD data, and the Gradle cache — a few GB at first.
In testing, a setup consumed around 4GB.

## Initial setup

Run every command below from the repository root.

```sh
scripts/install-system-image.sh
scripts/fetch-android-prebuilts.sh
scripts/build-agent.sh
scripts/build-host.sh
```

`fetch-android-prebuilts.sh` only downloads the Android 16 system API stub and the AOSP test
platform key — never a full AOSP source tree. This key is for local development only; it
cannot be used to sign a build for distribution.

## Starting the emulator and installing the agent

```sh
scripts/start-emulator.sh
```

This starts the emulator with `-gpu host` to use the Apple Silicon Mac's GPU. The video
stream runs at a fixed 60 fps.

In a separate terminal, once boot finishes, run this once:

```sh
ANDROID_SERIAL=emulator-5556 scripts/install-priv-app.sh
```

This `adb root`/`adb remount`s the userdebug image, copies the APK and its priv-app
permission allowlist into `/system/priv-app`, and reboots. It then sets up the Companion
Device association, the app-streaming role, and the TCP forward.

## Launching an app

Opening Android Settings as a macOS window:

```sh
ANDROID_SERIAL=emulator-5556 scripts/forward.sh
scripts/run-host.sh com.android.settings
```

Swap in any other installed package name to open a different app. Launch two and you get two
independent VirtualDisplays and `NSWindow`s.

## Adding an Android app as a native macOS .app

Turn any app already installed on the emulator into a macOS app bundle you can launch from
Finder or Spotlight. The Android display name is read from the APK, and the bundle is added
to `~/Applications` by default. Icons are rendered from Android's `PackageManager` to PNG and
converted to `.icns`, so XML adaptive icons, vector drawables, and plain image icons all work.

Once the current Android agent and `MSA Emulator.app` are installed, newly installed launchable
Android packages are converted automatically. The agent keeps installation events across reboots,
and the manager acknowledges each event only after the `.app` has been signed and placed beside
the manager app. Existing bundles for the same package are replaced. The generated app contains
the smaller `MSAAppHost`; emulator control remains exclusively in `MSA Emulator.app`.

```sh
ANDROID_SERIAL=emulator-5558 scripts/create-macos-app.sh com.android.vending
```

Pass a display name as the second argument and an output directory as the third:

```sh
ANDROID_SERIAL=emulator-5558 scripts/create-macos-app.sh com.example.app "My Android App" "$HOME/Desktop"
```

Add `--replace` to update a bundle that was already created, with a fresh host binary and icon:

```sh
ANDROID_SERIAL=emulator-5558 scripts/create-macos-app.sh --replace com.android.vending
```

The generated `.app` embeds the package name along with the emulator configuration that was
active for `ANDROID_SERIAL` at creation time — it does not bundle the APK or any Google Play
code. A companion `MSA Emulator.app` is created in the same output directory at the same
time. Opening the app's `.app` asks the manager to start the emulator headlessly if needed,
then opens the target app once boot completes.

```sh
open "$HOME/Applications/Google Play Store.app"
```

`MSA Emulator.app` runs as a separate menu-bar process from any app-specific `.app`. Its
menu lets you start, restart, and stop the emulator, share the Mac's location, choose the macOS
cameras used for Android's front and back cameras, and choose its microphone input. Location
sharing is enabled by default and asks for macOS permission on first use. The manager injects an
initial location after starting the emulator, then keeps it updated only while an open Android app
declares coarse or fine location access in its manifest. It stops updates while the emulator is
paused or stopped; resuming does not unconditionally inject a location. Camera choices are saved
per emulator; changing one restarts the running emulator so the new device can be attached.
Microphone choices are also saved per emulator and applied as the macOS default input device because Android Emulator's
CoreAudio backend does not provide per-process device selection. The manager asks for confirmation
before changing the macOS default input device. Use **Refresh Media Devices** after connecting or
disconnecting a camera or microphone. Android playback and microphone input use macOS CoreAudio.
The manager is the only process that controls the emulator lifecycle. After the last Android app window closes, the manager pauses the VM
after 30 seconds to reduce idle CPU usage. After five minutes it
shuts down the emulator and saves its Quick Boot state while the menu-bar app remains available.

Each app-specific `.app` has an **Android** menu in the macOS menu bar. Use it to send **Back**
(also available as **Command-[**), **Volume Up**, **Volume Down**, or **Mute** to that Android app.
These volume controls change Android's volume, not the macOS system volume.
The menu shows the idle, paused, snapshot-saving, and stopped states. If a saved-state boot
fails, the manager automatically retries once with a cold boot.

You can also create or update just the manager app:

```sh
ANDROID_SERIAL=emulator-5558 scripts/create-emulator-manager-app.sh
open "$HOME/Applications/MSA Emulator.app"
```

By default, serial `emulator-5558` maps to AVD `msa-gms-api36`, and any other serial maps
to `msa-api36`. Point at a different AVD with `MSA_AVD_NAME`, and toggle
`-writable-system` with `MSA_WRITABLE_SYSTEM=1` or `0`:

```sh
ANDROID_SERIAL=emulator-5560 MSA_AVD_NAME=my-avd MSA_WRITABLE_SYSTEM=0 \
  scripts/create-macos-app.sh com.example.app
```

## Google Play and GMS setup (rootAVD)

The Google Play Store / GMS configuration lives in its own AVD, `msa-gms-api36`, separate
from the plain AOSP AVD. The SDK's Google Play system image is isolated with an APFS
copy-on-write copy, and rootAVD/Magisk only patches that copy's ramdisk, so the existing
Pixel AVD and the original system image are untouched.

Run once, the first time:

```sh
scripts/setup-gms-avd.sh
GMS_EMULATOR_WINDOW=1 scripts/start-gms-emulator.sh
```

In another terminal, run rootAVD. The emulator exits when it finishes:

```sh
ANDROID_SERIAL=emulator-5558 scripts/root-gms-emulator.sh
```

Start it again with `GMS_EMULATOR_WINDOW=1 scripts/start-gms-emulator.sh`, open Magisk, and
approve the additional setup. After the automatic reboot, enable **[SharedUID] Shell** on
Magisk's Superuser screen, then install the agent module:

```sh
ANDROID_SERIAL=emulator-5558 scripts/install-gms-agent.sh
```

Normal startup doesn't need a window:

```sh
scripts/start-gms-emulator.sh
ANDROID_SERIAL=emulator-5558 scripts/forward.sh
scripts/run-host.sh com.android.settings
scripts/run-host.sh com.android.vending
```

This configuration is for local use only. Do not bundle or redistribute the Google Play
image, GMS, Magisk, rootAVD, or the agent APK in any build artifact. Play Integrity, DRM, and
Wallet-style features may not work on a rooted emulator.

The agent uses role permission `CAPTURE_SECURE_VIDEO_OUTPUT` and a secure VirtualDisplay so
that `FLAG_SECURE` windows (like password confirmation) can also be shown on macOS. A
systemless RRO moves the `SYSTEM_AUTOMOTIVE_PROJECTION` holder from Android Auto to the
agent, so Android Auto is unusable inside the emulator while this override is active. Video is
transported as unauthenticated H.264 over localhost TCP — don't run this on a machine where
untrusted local processes might be listening.

To disable secure capture and hand the automotive-projection holder back to Android Auto, or
to re-enable it, use (both reboot the emulator):

```sh
ANDROID_SERIAL=emulator-5558 scripts/set-secure-capture.sh disable
ANDROID_SERIAL=emulator-5558 scripts/set-secure-capture.sh enable
```

To fully back the code out of the secure-capture state, run `disable` above first, then check
out commit `62be958`.

## Verifying it works

```sh
ANDROID_SERIAL=emulator-5556 scripts/smoke-test.sh com.android.settings

adb -s emulator-5556 shell dumpsys virtualdevice
adb -s emulator-5556 shell dumpsys display
adb -s emulator-5556 shell dumpsys input
adb -s emulator-5556 shell dumpsys activity activities
adb -s emulator-5556 logcat -s MsaAgent
```

On success you'll see the Virtual Device, an `MSA:<package>` display, Touch/Mouse/Keyboard devices,
and the target Activity's display ID. Closing the `NSWindow` tears down that connection's
encoder, virtual inputs, display, and device.

## Troubleshooting

- **`No CDM association; run scripts/provision-emulator.sh`** — this can happen if the
  agent's app data was wiped without reinstalling it. Run
  `ANDROID_SERIAL=<serial> scripts/provision-emulator.sh` to recreate the Companion Device
  association and app-streaming role, then retry.
- **`adb: command not found` when running `forward.sh` or `smoke-test.sh`** — these two
  scripts call `adb` directly rather than through `$ANDROID_SDK_ROOT`; make sure
  `platform-tools` is on your `PATH` (see [Setting up prerequisites](#setting-up-prerequisites)).
- **`aapt2`/`apksigner`/`android.jar` not found** — install `build-tools;36.0.0` and
  `platforms;android-36` through `sdkmanager` as shown above; `install-system-image.sh` only
  installs the emulator system image, not these packages.

## Security notes

The current wire protocol has no authentication, and the priv-app is signed with an AOSP
development test key rather than a production signing key. Never expose the agent's TCP port
to a LAN — only use it through `adb forward`'s localhost connection. Authenticated IPC, a real
signing key, an update mechanism, and tighter permission scoping are the main gaps before this
would be safe to run outside a trusted local machine; see [Known limitations](#known-limitations).

## Contributing

Issues and pull requests are welcome. This is a young project with a small surface area today
(one Android priv-app, one Swift host, and a handful of shell scripts) — the fastest way to
get oriented is to read [docs/protocol.md](docs/protocol.md) and skim `scripts/`.

## License

MIT — see [LICENSE](LICENSE).
