# Releasing Drunkin to the App Store

Everything that builds and signs runs on GitHub's macOS runners, so no Mac is required. You do
need an iPhone to test on and an Apple Developer Program membership ($99/year, Apple's fee; there
is no hosting cost).

## One-time setup

### 1. Apple Developer Program
Enroll at <https://developer.apple.com/programs/enroll/> (individual is fine). Note your
**Team ID** (Membership details page, 10 characters).

### 2. Register the bundle ID and create the app
1. <https://developer.apple.com/account/resources/identifiers/list> → **+** → App IDs → App →
   Bundle ID **explicit** `fun.dunkin.drunkin`, description "Drunkin". No capabilities needed
   (Multipeer Connectivity needs no entitlement).
2. <https://appstoreconnect.apple.com/apps> → **+ New App** → iOS, name **Drunkin**, language
   English (U.S.), bundle ID `fun.dunkin.drunkin`, SKU `drunkin-ios-1`, Full Access.
   If the name is taken, use the fallback in [listing.md](app-store/listing.md).

### 3. App Store Connect API key (lets CI sign and upload)
App Store Connect → Users and Access → **Integrations** → App Store Connect API → Team Keys →
**+**. Name `GitHub Actions`, access **Admin** (needed so Xcode can create the distribution
certificate and profile in the cloud). Download the `.p8` once; note the **Key ID** and the
**Issuer ID**.

### 4. GitHub secrets
Repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 1 |
| `ASC_KEY_ID` | Key ID from step 3 |
| `ASC_ISSUER_ID` | Issuer ID from step 3 |
| `ASC_KEY_P8_BASE64` | the `.p8` file, base64: PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))` |

Then delete the `.p8` from your Downloads (keep a copy in your password manager).
Repo → Settings → Environments → `release` → add yourself as a required reviewer, so nobody can
upload a build without your approval.

### 5. Privacy policy and support pages (required)
Apple requires a public Privacy Policy URL and Support URL. They're in `docs/`.
1. Replace `SUPPORT_EMAIL` in `docs/privacy.html` and `docs/support.html` with a real address
   you'll answer (Apple and users will use it).
2. Publish `docs/` somewhere public and free:
   - **GitHub Pages** (Settings → Pages → Deploy from branch → `main` / `/docs`). Free for public
     repos; private repos need GitHub Pro. The app links to
     `https://rejiii1.github.io/drunkin-ios/privacy.html` and `.../support.html`.
   - If you host it elsewhere, update `AppLinks` in `Drunkin/Views/SettingsView.swift` and the
     URLs in [listing.md](app-store/listing.md).

## Every release

1. Bump nothing by hand: the build number is the workflow run number.
2. Actions → **TestFlight** → Run workflow (enter a version like `1.0.1` for updates, blank for
   1.0.0) → approve the `release` environment.
3. ~10 to 15 minutes later the build shows in App Store Connect → TestFlight. Answer nothing for
   export compliance (Info.plist already says no non-exempt encryption).
4. Install via the TestFlight app on two iPhones. Run through the
   [test plan](#test-plan-before-submitting).
5. App Store Connect → version page → pick the build, fill in [listing.md](app-store/listing.md),
   [review-notes.md](app-store/review-notes.md), [age-rating.md](app-store/age-rating.md),
   App Privacy = "Data Not Collected", upload screenshots → **Add for Review** → Submit.

## Screenshots

Need 3 to 10 at **6.9"** (1320 × 2868 or 1290 × 2796). Easiest without a Mac: on an iPhone 16/17
Pro Max (or Plus/Air at 1290 × 2796), install the TestFlight build, host a tasting with the
Bourbon basics template, score a few pours, and take screenshots (side + volume up). AirDrop them
to your PC and upload them as-is. Screenshots from a smaller iPhone are rejected for the 6.9" slot.

## Test plan before submitting

- [ ] Fresh install: age gate shows; "No" blocks; "Yes" continues and is remembered.
- [ ] Host a tasting on phone A; join code shows; phone A asks for Local Network once.
- [ ] Phone B: Join → sees the tasting → wrong code fails → right code joins → pick name.
- [ ] Both score a pour: hidden on B until A scores too, then reveals on both with a toast.
- [ ] Airplane mode with Bluetooth on (no Wi-Fi network): still syncs.
- [ ] B scores while A's app is in the background; reopen A; B's score arrives.
- [ ] Host tools: Reveal now / Hide again; remove from table; rename; bench; edit menu; clear scores.
- [ ] Add a profile photo on B; shows on A.
- [ ] Share tasting file from A → AirDrop to B → opens in Drunkin as a saved copy.
- [ ] Hand off hosting A → B; A rejoins as a guest automatically.
- [ ] Settings → Delete all data works.
- [ ] VoiceOver reads the score buttons and chips; Large text doesn't clip.

## If App Review pushes back

- **1.4.3 / alcohol**: point to the age gate, 18+ rating, and that the app is a scorecard. Don't
  add features that reward drinking more.
- **4.2 minimum functionality**: unlikely for a native app, but the review notes explain how to
  use every feature on one device.
- **2.1 can't test multi-device**: the review notes already cover single-device use; offer a
  video of two phones syncing if asked.
- **5.1.1 privacy**: the app collects nothing; the policy URL must load.
