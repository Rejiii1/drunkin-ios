# App Review information

App Store Connect → version page → App Review Information.

- **Sign-in required:** No (the app has no accounts).
- **Contact:** your name, phone and email (only Apple sees these).
- **Notes** (paste this):

> Drunkin has no accounts, servers or network backend. All data stays on the device.
>
> To review on a single device:
> 1. Confirm legal drinking age on the first screen.
> 2. Tap "Host a tasting", enter any name and your name, keep the "Bourbon basics" template, tap Create.
> 3. Open the flight and score each pour 1–5. With one taster at the table, each pour reveals
>    as soon as you score it, and results appear under "Bourbon Basics results" and "Leaderboard".
> 4. Host tools shows the join code, the roster, the menu editor and reveal controls.
>
> Multi-device: a second iPhone taps "Join a tasting nearby", selects the host's tasting and enters
> the 6-digit code shown on the host's screen. Devices connect directly with Apple's Multipeer
> Connectivity (Bluetooth / peer-to-peer Wi-Fi), which is why the app requests Local Network
> access. Scores from other players stay hidden on each phone until everyone has scored a pour.
>
> "Share tasting file" exports a .drunkin file through the share sheet; opening it in Drunkin on
> another device imports a read-only copy of the results.
>
> The app is rated 18+ and asks users to confirm legal drinking age. It does not sell alcohol
> or encourage excessive consumption; it is a scorecard for tastings.

## App Privacy ("nutrition label")

App Store Connect → App Privacy → Get Started → **No, we do not collect data from this app.**
This matches `Drunkin/Resources/PrivacyInfo.xcprivacy` (no collected data types, no tracking).

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is in Info.plist, so App Store Connect won't ask on each
build. The only encryption is Apple's built-in Multipeer Connectivity / Data Protection, which is
exempt.
