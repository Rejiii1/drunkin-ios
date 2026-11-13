# Drunkin (iOS) — Project Guide for Claude

Native SwiftUI iPhone app for blind-scored tastings. Ported from the Deer Camp PWA
(`Home_Server/deer-camp`), but with **no server**: phones sync peer-to-peer. Read README.md first.

## Build

- The user is on Windows. There is no local Swift toolchain: **CI is the compiler.** Push and
  check `gh run list -w CI` / `gh run view <id> --log-failed`. Keep changes compiling.
- `project.yml` is the source of truth (XcodeGen). `Drunkin.xcodeproj` and `Drunkin/Info.plist`
  are generated and gitignored. Info.plist keys go in `project.yml` → `targets.Drunkin.info`.
- Swift 5 language mode, minimal concurrency checking. `AppModel`, `HostService`,
  `GuestService` are `@MainActor`; Multipeer delegate methods are `nonisolated` and hop to main
  with `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` (keeps message order).
- Release: `.github/workflows/release.yml` (manual) → TestFlight. See docs/RELEASING.md.

## Invariants

- **Hidden scores never leave the host** until revealed. `Tasting.snapshot(for:)` is the only
  thing sent to guests; `TastingFile.results` the only thing in share files. Tests in
  `EngineTests`/`SharingTests` guard this. Don't add fields to either without checking.
- Each phone only writes its own entries. Host applies guest edits only for the taster bound to
  that phone (`Member.tasterID`), only for known pours, only at the current reset generation,
  and only if `rev` is newer. Scores lock once revealed; notes don't.
- Everything from a peer or file goes through `Sanitize` / `sanitizedImport` / `ImageTools`.
  New fields need the same treatment.
- Store only token **hashes** on the host. Tokens live in the guest's Keychain.
- App Review 1.4.3: never add features that encourage drinking more (no drinking games, no
  volume counters). The app is a scorecard. Age gate + 18+ rating stay.
- No third-party dependencies, no network calls, no analytics. If that ever changes, update
  `PrivacyInfo.xcprivacy`, `docs/privacy.html`, and the App Privacy answers.
- `NSBonjourServices` must match `Wire.serviceType` (`drunkin-tst`).
- Bump `Wire.version` for incompatible message changes; `TastingFile.currentVersion` for file
  format changes (older apps refuse newer files with a clear message).
