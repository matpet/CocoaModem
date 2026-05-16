# cocoaModem Current macOS Migration Plan

## Verdict

This project appears portable to current macOS, but it is not a straight project retarget.
The codebase is old enough that several API families and project settings need to be updated before a modern Xcode build will succeed.

The main positive sign is that the app target was already partially migrated to 64-bit settings, so this is not a PowerPC-only resurrection effort.

## Verified Constraints

- The main application target is the Xcode project in `cocoaModem 2.0/cocoaModem 2.0.xcodeproj`.
- The authoritative application source tree is the top-level `Sources` directory; the main Xcode project references it from `cocoaModem 2.0` as `../Sources`.
- The project format is from the Xcode 3 era and still contains some legacy build settings.
- `xcodebuild -list` has been verified with full Xcode 26.3. Full build validation and runtime hardware validation remain separate checks.
- The source tree contains direct CoreAudio HAL usage, legacy file and dialog APIs, Carbon includes, and older AudioUnit component APIs.
- The app includes hardware integration code for serial/PTT and microHAM router/keyer control, which will need runtime verification on current macOS.
- The original user documentation describes the plain RTTY panel as deprecated; Wideband RTTY and Dual RTTY should be treated as the supported RTTY paths for modernization and runtime verification.

## Highest-Risk Areas

### 1. Xcode project modernization

The project file still carries legacy structure and settings from the older Xcode project era, including `ONLY_ACTIVE_ARCH = YES` in all configurations.
This is usually the first mechanical blocker before source-level fixes can be validated.

Primary file:

- `cocoaModem 2.0/cocoaModem 2.0.xcodeproj/project.pbxproj`

Expected work:

- Open and let current Xcode upgrade the project format.
- Remove obsolete build settings.
- Set a current macOS deployment target.
- Confirm the app target still resolves all source groups and resources.

### 2. CoreAudio migration

This is the largest technical blocker.
The app uses older HAL property calls such as `AudioHardwareGetProperty`, `AudioDeviceGetProperty`, and `AudioDeviceSetProperty`.
Current macOS expects `AudioObject*` property APIs for this style of device enumeration and configuration.

Primary files:

- `Sources/Audio/audioutils.c`
- `Sources/Audio/audioutils.h`
- `Sources/Audio/AudioManager.m`
- `Sources/Audio/AudioPipes/ModemAudio.m`
- `cocoaModem 2.0/main.m`

Expected work:

- Replace device enumeration with `AudioObjectGetPropertyData` and related APIs.
- Replace device property reads and writes with `AudioObjectPropertyAddress` based calls.
- Remove `AudioHardwareUnload()` and any other no-longer-appropriate HAL startup assumptions.
- Re-test audio device selection, channel enumeration, source selection, sample-rate changes, and volume controls.

### 3. Legacy AppKit and file APIs

The app still uses older `NSOpenPanel` modal methods and `FSRef` based file opening.
Those should be replaced with URL-based APIs.

Primary files:

- `Sources/Audio/AIFFSource.m`
- `Sources/Interfaces/Contest/Cabrillo.m`
- `Sources/Interface Managers/Contest/ContestManager.m`

Expected work:

- Replace `runModalForDirectory:file:types:` with modern `runModal` plus URL-based configuration.
- Replace `filenames` access with `URL` or `URLs`.
- Replace `FSRef` and `FSPathMakeRef` usage with `CFURLRef` or modern AudioToolbox file-opening calls.

### 4. Legacy system and Carbon usage

Several files still include Carbon and use `Gestalt` for OS-version checks.
That code should be removed or replaced with Foundation/AppKit availability logic.

Primary files:

- `Sources/DSP/error.h`
- `Sources/Filters/CoreFilter/Sources/Filters/CMFFT.h`
- `Sources/Filters/CoreFilter/Sources/Filters/CMDSPWindow.h`
- `Sources/Filters/CoreFilter/Sources/Filters/CMFIR.h`
- `Sources/Interface Managers/Base/ModemManager.m`
- `Sources/Modems/PSK/PSKReceiver.m`
- `Sources/Audio/AudioPipes/ModemSource.m`

Expected work:

- Remove unnecessary Carbon imports where only basic types are needed.
- Replace `Gestalt` checks with runtime availability or remove them if they only guard ancient OS behavior.
- Replace `NSOnState` and `NSOffState` usages with `NSControlStateValueOn` and `NSControlStateValueOff` as cleanup after the build is stable.

### 5. AudioUnit component lookup migration

The NetAudio code still uses Component Manager style APIs such as `FindNextComponent` and `OpenAComponent`.
These should move to the `AudioComponent` APIs.

Primary files:

- `Sources/NetAudio/NetSend Class/NetSend.m`
- `Sources/NetAudio/NetReceive Class/NetReceive.m`

Expected work:

- Replace component lookup with `AudioComponentFindNext`.
- Replace opening with `AudioComponentInstanceNew`.
- Re-test AUNetSend and AUNetReceive service discovery and startup.

### 6. Hardware and automation compatibility

The project includes AppleScript support, serial IOKit access, and specialized router/keyer integration.
These may still compile but are the main runtime risk areas on current macOS, especially if they depend on vendor software or old device drivers.

Primary files:

- `Sources/Interfaces/FSK/FSKHub.m`
- `Sources/Preferences/Config.m`
- `Sources/Interfaces/Digital Interfaces/*`
- `cocoaModem 2.0/AppleScripts/*`

Expected work:

- Verify serial device discovery against current macOS IOKit behavior.
- Verify AppleScript dictionary loading and script execution.
- Verify microHAM router integration with currently available vendor software, if any.
- Expect some features to require feature flags or temporary disabling until runtime testing is complete.

## Recommended Port Order

### Phase 1. Make the project open cleanly in current Xcode

Goal:
Get the project upgraded and indexed by current Xcode without fixing every compile error yet.

Tasks:

- Select the full Xcode toolchain with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- Open the main `.xcodeproj` in current Xcode.
- Accept the project-format upgrade.
- Remove obsolete build settings that Xcode flags immediately.
- Confirm the target and resource graph are intact.

Success criteria:

- The project opens without structural upgrade errors.
- `xcodebuild -list` works.

### Phase 2. Get the first compile by reducing API breakage

Goal:
Get a modern compiler to produce a complete error list.

Tasks:

- Fix removed AppKit selectors and file APIs first.
- Remove Carbon-only imports where possible.
- Replace `Gestalt` checks.
- Fix type warnings that are now hard errors under modern Clang if they block compilation.

Success criteria:

- The project compiles far enough that remaining errors are mostly concentrated in audio and AudioUnit code.

### Phase 3. Migrate the audio subsystem

Goal:
Restore device enumeration and configuration on current macOS.

Tasks:

- Port `audioutils.c` and `ModemAudio.m` to `AudioObject` APIs.
- Validate input and output device selection.
- Validate buffer size, sample rate, stream enumeration, and data source menus.

Success criteria:

- The app launches and can enumerate audio hardware without crashing.

### Phase 4. Migrate NetAudio component code

Goal:
Replace deprecated component-instantiation paths.

Tasks:

- Port both NetSend and NetReceive setup paths to `AudioComponent` APIs.
- Verify network audio unit startup.

Success criteria:

- NetAudio units can be instantiated and initialized successfully.

### Phase 5. Runtime verification and feature triage

Goal:
Decide which features are fully portable now and which need targeted follow-up work.

Tasks:

- Test local audio modem operation.
- Test AppleScript support.
- Test serial/PTT and keyer integration on real hardware.
- Test on Apple Silicon and Intel if both are relevant.

Success criteria:

- Core modem functions work end-to-end.
- Non-core integrations are categorized as working, degraded, or blocked.

## Expected Outcome

The core application is likely salvageable.
The biggest uncertainty is not whether the code can be made to compile, but how much of the external hardware ecosystem is still available and behaves the same on current macOS.

If the goal is a practical modern release, the most realistic scope is:

- First restore the core audio modem application.
- Then re-enable AppleScript and hardware integrations one subsystem at a time.
- Be prepared to ship some integrations later than the core app if vendor dependencies have changed.

## Suggested Next Action

Start with Phase 2: capture a current modern compile-error list with the full Xcode toolchain.
That error list will tell you whether the first real code pass should begin in AppKit/file APIs or directly in CoreAudio.
