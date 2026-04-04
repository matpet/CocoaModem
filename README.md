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
- This repository focuses on compatibility and maintenance updates, not a rewrite of the original application.
- The original plain RTTY panel is legacy/deprecated in the upstream design; use Wideband RTTY or Dual RTTY for supported RTTY operation.

## Repository Scope

- Compatibility fixes for current macOS releases.
- Preservation of the original application structure and behavior where practical.
- No large-scale rewrite or UI redesign.

## Building

- Open `cocoaModem 2.0/cocoaModem 2.0.xcodeproj` in Xcode.
- Build a universal binary when distributing to both Apple Silicon and Intel Macs.
- Current compatibility work has been validated on macOS 15.7.x.

## Release History

- Original cocoaModem created by W7AY, Kok Chen.
- Repository updated to restore compatibility with current macOS releases.
- Current modernization pass includes universal Apple Silicon and Intel builds, Intel launch fixes, and native system appearance behavior on modern macOS.
- 2.1rc1 adds external RTTY FSK keying and a fldigi-compatible XML-RPC interface for RumLogNG contest control.