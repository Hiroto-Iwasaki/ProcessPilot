# Privileged Helper Handoff Notes

Last updated: 2026-02-08

## Current decision
- Continue using ad-hoc packaging for now.
- Privileged helper flow has migrated from `SMJobBless` to `SMAppService.daemon(plistName:)`.
- With ad-hoc signing, root-required termination is not guaranteed and should be treated as unsupported.

## What is already implemented
- App-side XPC client:
  - `/Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/ProcessPilot/Services/PrivilegedHelperClient.swift`
- Helper contract:
  - `/Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/ProcessPilotCommon/PrivilegedHelperContract.swift`
- Helper executable:
  - `/Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/PrivilegedHelper/main.swift`
- Packaging sync (label/plist/template rendering for daemon registration):
  - `/Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/scripts/package_app.sh`

## Current local status (verified on 2026-02-08)
- Signing identity found: Apple Development only.
- Built app in `dist/` is ad-hoc signed.
- `spctl` assessment for current app: rejected.
- This is acceptable for local testing, but not for production privileged daemon distribution.
- Ad-hoc assumption: normal monitoring features are available; root process termination is out of scope until signed/notarized distribution is ready.

## SMAppService notes
- `SMJobBless` is deprecated and replaced by `SMAppService` daemon APIs.
- LaunchDaemon registration may require admin approval in System Settings.
- LaunchDaemon-based distribution requires proper code signing and notarization.

## Resume checklist (when moving to production)
1. Prepare Developer ID Application certificate and Team ID.
2. Package app bundle and daemon plist:
   - `BUNDLE_ID=<YOUR_BUNDLE_ID> VERSION=<VERSION> /Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/scripts/package_app.sh`
3. Sign app + helper + daemon plist with non-ad-hoc identity (Developer ID).
4. Notarize and staple.
5. Verify daemon registration flow (`SMAppService.daemon`) on a clean machine/user.

## Quick verification commands
- `security find-identity -v -p codesigning`
- `codesign -dv --verbose=4 /Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/dist/ProcessPilot.app`
- `codesign -dv --verbose=4 /Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/dist/ProcessPilot.app/Contents/Library/HelperTools/com.local.processpilot.privilegedhelper`
- `spctl -a -vv /Users/iwasakihiroto/Desktop/Working_for_codex/ProcessPilot/dist/ProcessPilot.app`
