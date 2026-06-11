# App Store Release Guide

The path from this repo to other kids' iPads, in order. Steps marked 🧑 need
a human with the Apple account; everything else is already in the repo.

## 0. Prerequisites (🧑 one-time)

- Apple Developer Program membership ($99/yr) on your Apple ID.
- In App Store Connect: create the app record (bundle id
  `com.bolenton.Lantern`), and an **App Store Connect API key**
  (Users and Access → Integrations → App Store Connect API) with
  App Manager role. Download the `.p8` once and store it safely.
- Host the privacy policy: enable GitHub Pages on this repo (or any host) so
  `PRIVACY.md` has a public URL — App Review requires it, especially for Kids.

## 1. TestFlight (🧑 + automated)

Add three repository secrets (Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | the API key's Key ID |
| `ASC_ISSUER_ID` | the Issuer ID shown on the keys page |
| `ASC_KEY_P8` | full contents of the `.p8` file |

Then run the **Release → TestFlight** workflow (Actions tab →
"Release" → Run workflow). It archives, signs via cloud signing
(`-allowProvisioningUpdates` with the API key), and uploads the build.
First-time only: accept the export-compliance question in App Store Connect
(Lantern uses only exempt HTTPS encryption).

**Beta community**: invite testers from the AppleVis forum and
audiogames.net — both communities actively beta-test accessible apps and
give world-class feedback. Suggested post: what Lantern is, who it's for,
the story behind it, and a TestFlight public link.

## 2. Kids Category checklist (all already satisfied in-app)

- [x] Parental gate before settings/configuration (hold + math question)
- [x] No ads, no analytics, no tracking, no third-party SDKs
- [x] No external links reachable by the child (everything is behind the gate)
- [x] No in-app purchases
- [x] Privacy policy URL (host PRIVACY.md, paste the URL in App Store Connect)
- [x] Made for Kids age band: 9–11 (also fine under "Ages 6–8")
- 🧑 App Review notes: explain the optional parent-configured AI server —
  default off, behind the parental gate, parent-controlled endpoint; the
  game is fully functional offline without it. Reviewers will ask.

## 3. Listing draft

- **Name**: Lantern — A Listening Adventure
- **Subtitle**: An audio-first story for low-vision kids
- **Description** (draft):

  > Lantern is a story adventure where sound is the world. Choose a
  > companion — Ember the fox, Petal the butterfly, or Clover the bunny —
  > and explore a glowing forest, crystal caves, and a city of lanterns by
  > listening: every river, door, and secret has its own place in 3D sound.
  >
  > Built for visually impaired children, with love. Giant high-contrast
  > visuals confirm what your ears already know. Your companion speaks
  > everything aloud, answers your spoken questions, remembers your
  > choices, and never lets you fail: there are no game-overs in Lantern,
  > only curiosity.
  >
  > • Hold two fingers anywhere and your companion explains exactly where
  >   you are and what's around you.
  > • A spoken setup wizard tunes text size, contrast, narration speed,
  >   and how much help the game offers — for each child's eyes and pace.
  > • Each companion senses different secrets: finish the story with one
  >   friend and two more journeys are waiting.
  > • Sing solfège song-spells that grow as you do. Conflict is resolved
  >   with music, never violence.
  > • Works completely offline. Collects nothing. Free, forever.
  >
  > Lantern was built by a dad for his daughter, and is shared in her
  > honor with every kid who plays the world by ear.

- **Keywords**: `blind,low vision,accessible,audio game,kids,visually
  impaired,spatial audio,story,VoiceOver`
- **Category**: Kids / Games → Adventure
- **Price**: Free. No monetization, ever.

## 4. Release cadence

Ship chapters as updates — "A new region is waiting" is a wonderful update
note for a kid. Keep `ASSETS.md` ledgered and mirror any CC-BY attributions
into the in-app About screen before each release.
