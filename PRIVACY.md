# Halcyon privacy

Halcyon is built so that your sleep data stays on your iPhone.

- **No servers.** Halcyon has no backend, no account and no analytics or crash-reporting SDKs. It makes no network requests of its own.
- **Microphone.** While listening, audio is analysed on the device by Apple's built-in Sound Analysis classifier to detect snoring, sleep talk and coughs. Raw audio is not stored. Only short clips (about 9 seconds) around detected sounds are saved, at most 30 a night, and they are deleted after 30 days. You can turn clips off in Settings.
- **Motion.** Accelerometer and gyroscope readings are used to tell when the phone is put down or picked up. They are reduced to per-minute summaries stored with each night.
- **Apple Health.** Only if you allow it: Halcyon writes your sleep stages to Health and reads Apple Watch sleep stages, heart rate and HRV to improve the report. Health data stays in Apple Health on your device.
- **Notifications** are local, scheduled on the phone.
- **Deleting.** Settings › Delete all data removes every night and clip. Deleting the app removes everything it stored (except anything you saved to Apple Health).
- **Feedback** you send through GitHub Issues is public and goes to GitHub, not to the app. Share only what you are comfortable sharing.
