<p align="center">
  <img src=".github/assets/logo-rounded.png" alt="Harbor logo" width="112" />
</p>

# Harbor

[![Latest Release](https://img.shields.io/github/v/release/tahseen-kakar/harbor?display_name=tag&label=release)](https://github.com/tahseen-kakar/harbor/releases/latest)
[![License](https://img.shields.io/github/license/tahseen-kakar/harbor)](https://github.com/tahseen-kakar/harbor/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2015.6%2B-111111)](https://github.com/tahseen-kakar/harbor/releases/latest)
[![Status](https://img.shields.io/badge/status-actively%20maintained-2ea043)](https://github.com/tahseen-kakar/harbor/commits/main)

Harbor is a beautiful, fully native macOS download manager built for real Mac workflows.

It is free, local-first, privacy-friendly, and designed to feel like a proper Mac app from day one. No accounts. No sign-in. No hosted backend. No subscription mechanics. Just a fast native downloader that runs on your Mac.

[Download the latest DMG](https://github.com/tahseen-kakar/harbor/releases/latest)

<p align="center">
  <img src=".github/assets/harbor-screenshot-rounded.png" alt="Harbor screenshot" />
</p>

## Why Harbor

Harbor exists to give macOS users a serious download manager without the usual tradeoffs. It combines a polished native SwiftUI interface with pragmatic download-engine separation, so the app feels clean and Mac-native while still handling direct downloads, magnet links, and `.torrent` files reliably.

If you want a downloader that respects the platform, respects your machine, and stays out of your way, Harbor is that app.

## Highlights

- Fully native macOS app built with SwiftUI
- Free and open source under GPL-3.0
- Local-first and privacy-friendly by design
- Direct HTTP and HTTPS downloads
- Magnet link and local `.torrent` support
- Queue persistence across launches
- Pause, resume, retry, cancel, and history flows
- Finder reveal and open-file actions
- Sidebar navigation, unified toolbar, and detail inspector
- Sparkle-based in-app updates for installed builds

## Download

The easiest way to get Harbor is from the latest GitHub release:

- Open the [latest release](https://github.com/tahseen-kakar/harbor/releases/latest)
- Download the `.dmg`
- Drag `Harbor.app` into `Applications`

Once installed, Harbor can check for new versions from the app menu and update through its built-in Sparkle updater.

## Philosophy

Harbor is opinionated about being a real macOS app:

- native look and feel over web-style chrome
- clear separation between UI, app state, persistence, and download engines
- pragmatic backend delegation where it makes sense
- no unnecessary cloud dependency for a local utility

## License

Harbor is licensed under [GPL-3.0](https://github.com/tahseen-kakar/harbor/blob/main/LICENSE).
