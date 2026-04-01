cocoamodem
==========

cocoaModem is a macOS application that implements modems (modulator-demodulators) for several Amateur Radio digital modes. The name refers to the Cocoa framework used by the original application.

This public repository contains an updated build of cocoaModem that has been brought forward to run on macOS 15.7 and later.

## Credit

The original cocoaModem application was created by W7AY, Kok Chen.
This repository preserves that work and documents the compatibility updates needed to keep the application running on current macOS releases.

## Current Status

- Builds as a universal macOS application for Apple Silicon and Intel.
- Verified to launch and run on macOS 15.7.x.
- Keeps the existing cocoaModem functionality and structure while updating compatibility issues in the legacy codebase.

## Notes

- The main Xcode project is in `cocoaModem 2.0/cocoaModem 2.0.xcodeproj`.
- This repository focuses on compatibility and maintenance updates, not a rewrite of the original application.