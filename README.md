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

## Install

### TestFlight (recommended, no computer needed)

The TestFlight link is coming soon and will be posted here. When it's live:

1. Install [TestFlight](https://apps.apple.com/app/testflight/id899247664) from the App Store.
2. Open the Halcyon invite link on your iPhone and tap **Accept**, then **Install**.
3. To send feedback, take a screenshot in Halcyon and tap **Share Beta Feedback**, or use **Settings › Send feedback** in the app.

Needs an iPhone on iOS 18 or newer.

### Sideload (advanced, needs a computer once)

If you'd rather not wait, install [Halcyon.ipa](https://github.com/mrdebayanD/halcyon/raw/main/beta/Halcyon.ipa) with [AltStore](https://altstore.io) or [SideStore](https://sidestore.io), signed with your own free Apple ID. In AltStore or SideStore you can add this source for updates:
`https://raw.githubusercontent.com/mrdebayanD/halcyon/main/altstore-source.json`

Apps signed with a free Apple ID expire after 7 days; open AltStore or SideStore and tap **Refresh All** to renew. Your nights are kept.

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
