cocoamodem
==========

cocoaModem is a macOS application that implements modems (modulator-demodulators) for several Amateur Radio digital modes. The name refers to the Cocoa framework used by the original application.

This public repository contains an updated build of cocoaModem that has been brought forward to run on macOS 15.7 and later.

## Credit

The original cocoaModem application was created by W7AY, Kok Chen.
This repository preserves that work and documents the compatibility updates needed to keep the application running on current macOS releases.

See ATTRIBUTION.md for project provenance and attribution notes.

## Current Status

- Builds as a universal macOS application for Apple Silicon and Intel.
- Verified to launch and run on macOS 15.7.x.
- Keeps the existing cocoaModem functionality and structure while updating compatibility issues in the legacy codebase.
- Adds external FSK keying support for RTTY operation.
- Adds fldigi-compatible XML-RPC support for RumLogNG contest integration.

## Notes

- The main Xcode project is in `cocoaModem 2.0/cocoaModem 2.0.xcodeproj`.
- The live application source tree is the top-level `Sources` directory; the main Xcode project references it from `cocoaModem 2.0` as `../Sources`.
- This repository focuses on compatibility and maintenance updates, not a rewrite of the original application.
- The original plain RTTY panel is legacy/deprecated in the upstream design; use Wideband RTTY or Dual RTTY for supported RTTY operation.

## Repository Scope

- Compatibility fixes for current macOS releases.
- Preservation of the original application structure and behavior where practical.
- No large-scale rewrite or UI redesign.

## Building

- Open `cocoaModem 2.0/cocoaModem 2.0.xcodeproj` in Xcode.
- Build products are written to `Builds/<Configuration>/`, for example `Builds/Release/cocoaModem 2.1rc5.app`.
- Put packaged release archives in `Builds/Packages/`.
- Build a universal binary when distributing to both Apple Silicon and Intel Macs.
- Current compatibility work has been validated on macOS 15.7.x.

## Release History

- Original cocoaModem created by W7AY, Kok Chen.
- Repository updated to restore compatibility with current macOS releases.
- Current modernization pass includes universal Apple Silicon and Intel builds, Intel launch fixes, and native system appearance behavior on modern macOS.
- 2.1rc5 labels the app bundle and visible app identity as RC5, clarifies the PSK table UI as PSK31-only, and sanitizes unsupported transmit text punctuation to avoid keyboard encoding alerts.
- 2.1rc4 restores functional external FSK RTTY transmit behavior, aligns ext-FSK keying with the AFSK path, and includes related Wideband/Dual RTTY UI-runtime corrections on current macOS.
