# Flow Book

Modern Flutter audiobook player for Librivox, YouTube, 4read, and KnigaVaUhe streaming.

## Features

- Browse and search free Librivox, YouTube, 4read, and KnigaVaUhe audiobooks
- Smart caching for offline listening
- Background playback with notification controls
- No account required, no tracking, no ads

## Build Instructions

1. Install Flutter SDK (>=3.44.1)
2. Clone the repo:
   ```bash
   git clone https://github.com/everancii/Flow-Book.git
   ```
3. Build:
   ```bash
   cd Flow-Book
   flutter pub get
   flutter build apk --release --split-per-abi
   ```

## License

MIT
