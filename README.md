<p align="center"><img src="docs/icon.png" width="128" alt="Halcyon app icon"></p>

<h1 align="center">Halcyon</h1>
<p align="center">A free, private sleep tracker for iPhone. Put your phone down; Dusk keeps watch.</p>

<p align="center"><img src="docs/screens.png" alt="Bedtime, late-night nudge, Lock Screen, first night and morning alarm screens"></p>

> **Beta.** Thanks for testing. Please tell me what works, what doesn't and what feels off. See [Giving feedback](#giving-feedback).

## What it does

- **Notices sleep on its own.** Tap the bedtime reminder once. When the phone lies flat and still, Halcyon starts timing your sleep. Checking the time or a bathroom trip doesn't end the night; using your phone in the morning does.
- **A detailed morning report.** Minute-by-minute stages (Awake, REM, Core, Deep), when you fell asleep, wake-ups, and a timeline of what happened in the night.
- **A sleep score out of 100**, split into five parts: duration, unbroken sleep, regularity (Sleep Regularity Index), depth and how fast you fell asleep.
- **Snoring, sleep talk and coughs**, with short clips you can play back. Clips are kept for 30 days.
- **A gentle smart alarm** that wakes you in light sleep inside a window you choose.
- **A friendly nudge** if you said you were going to sleep and are still scrolling.
- **Apple Health.** It can save your nights to Health and read Apple Watch stages and heart rate if you have them.
- Trends, sleep debt, steady-bedtime streaks, light and dark mode.

## Privacy

Everything stays on your iPhone. There is no account, no server and no analytics. Sound is analysed on the device with Apple's built-in classifier, and the only clips saved are the short ones you see in the app. If you turn on Apple Health, nights are written to Health on your phone. Read more in [PRIVACY.md](PRIVACY.md).

## Install (free, no App Store)

Halcyon isn't on the App Store, so you install it with **SideStore** or **AltStore**. Both are free and sign the app with your own Apple ID. This needs a computer once, for setup.

**Needs:** iPhone on iOS 18 or newer, a free Apple ID.

### Option A: AltStore (easiest with a Mac or Windows PC)

1. Install **AltServer** on your computer from [altstore.io](https://altstore.io) and follow its steps to put **AltStore** on your iPhone.
2. On the iPhone, open **Settings › Privacy & Security › Developer Mode**, turn it on and restart when asked.
3. On the iPhone, open this page in Safari and download **Halcyon.ipa** from the [latest release](https://github.com/mrdebayanD/halcyon/releases/latest).
4. Open AltStore › **My Apps** › **+**, and pick **Halcyon.ipa**.
5. First launch: if iOS says the developer is untrusted, go to **Settings › General › VPN & Device Management**, tap your Apple ID and tap **Trust**.

**Get updates automatically:** in AltStore, go to **Browse › Sources › +** and add
`https://raw.githubusercontent.com/mrdebayanD/halcyon/main/altstore-source.json`

### Option B: SideStore (no computer after setup)

Follow the setup at [sidestore.io](https://sidestore.io), then add the same source above, or install **Halcyon.ipa** with **My Apps › +**.

A free Apple ID can have 3 sideloaded apps at a time. Halcyon counts as one app but uses 2 of your 10 weekly app IDs (the app and its Lock Screen widget).

### The 7-day refresh

Apps signed with a free Apple ID expire after 7 days. AltStore and SideStore refresh them for you in the background (AltStore needs your computer on the same Wi-Fi now and then). If Halcyon stops opening, open AltStore or SideStore and tap **Refresh All**. Your nights are kept.

### Build it yourself

Open `Nidra.xcodeproj` in a recent Xcode (built with Xcode 27), choose your team under **Signing & Capabilities** for both targets (Nidra and NidraWidgets), pick your iPhone and press Run. (The project folders still use the app's old working name, Nidra.)

## Using it

1. Allow microphone, motion, notifications and (optionally) Health when asked.
2. Set a bedtime reminder in **Settings**.
3. At bedtime, tap the reminder. Halcyon opens and starts listening.
4. Tap **I'm going to sleep** and put the phone down, ideally flat on the bed or nightstand and charging.
5. In the morning, pick up your phone. Your report is ready a minute later.

iOS only allows the microphone to start while the app is open, which is why you tap the reminder once each night. **Stay armed all day** in Settings removes that tap, at the cost of battery and the orange mic dot.

## Giving feedback

Inside the app: **Settings › Send feedback or report a bug**. Or go straight to [New issue](https://github.com/mrdebayanD/halcyon/issues/new/choose) and pick:

- **Bug report**: something broke or crashed.
- **Sleep accuracy**: the report didn't match your night.
- **Idea or feedback**: anything else, including how it feels to use.

GitHub issues are public. Don't paste anything private, and don't attach sound clips unless you're happy for others to hear them. A screenshot of the report is usually enough.

## License

[MIT](LICENSE) © 2026 Debayan Datta. Free to use, share and change.
