# Flow Book

**Summary:** Modern Flutter audiobook player for Librivox, YouTube, 4read, and knigavuhe streaming.

Flow Book is a modern audiobook player built with Flutter. Browse and play thousands of free Librivox audiobooks, stream audio from YouTube, 4read, knigavuhe, and manage your personal library — all in one clean, ad-free app.

## Features

- Browse and search Librivox, Youtube, 4read, knigavuhe audiobooks
- Smart caching for offline listening
- Background playback with notification controls
- No account required, no tracking, no ads

## Technical Details

### Network Security & Cleartext Traffic
This app enables `android:usesCleartextTraffic` because it streams content from third-party aggregators (4read, knigavuhe). While the app communicates with these services via HTTPS, the underlying audio streams provided by their various CDNs and third-party storage providers occasionally serve content over unencrypted HTTP. Cleartext traffic is enabled to ensure these streams can be played without interruption.

## Build Instructions

1. Install Flutter SDK (>=3.5.4)
2. Clone the repo:
   ```bash
   git clone https://github.com/everancii/Flow-Book.git
   ```
3. Build:
   ```bash
   cd Flow-Book
   flutter pub get
   flutter build apk --release
   ```

## AI Disclosure

- **Assistance Level:** Substantial – Used throughout development
- **AI Tool(s):** Claude
- **What did the tools help with?** Boilerplate generation, debugging, code architecture
- **AI Accountability:** The human developer(s) reviewed and edited all "AI"-generated outputs; the human developer(s) ran manual tests and manually verified all changes.

## License

MIT
