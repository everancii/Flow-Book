## 1. App-bar: Move Download Button

- [x] 1.1 In `audiobook_details.dart`, add `DownloadButton` as the first entry in `AppBar.actions`, wrapped in a `SizedBox(width: 48, height: 48)` to constrain it to icon-button size
- [x] 1.2 Verify `DownloadButton` renders correctly in app-bar for all states: not-downloaded, downloading (progress), downloaded
- [x] 1.3 Confirm download button appears on all book origins: Librivox, YouTube, 4Read, local, downloaded

## 2. Body: Circular Play Button

- [x] 2.1 Remove the orange `Card` action row widget block from the `Column` in the loaded state
- [x] 2.2 Add a circular play button widget inline in the `Column`, centred horizontally, between the metadata block and the chapter list
- [x] 2.3 Circular button: `Container` 72×72, `BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryColor)`, `InkWell` with circular `borderRadius`, `Icon(Ionicons.play, color: Colors.white, size: 36)` centred inside
- [x] 2.4 Wire the circular button's `onTap` to the existing play/resume logic (history check → `initSongs` → `play()` → `_weSlideController.show()`)

## 3. Cleanup & Polish

- [x] 3.1 Remove the `Container` divider widget that was between download and play in the old card
- [x] 3.2 Add a `SizedBox(height: 16)` above and below the circular play button for consistent spacing
- [x] 3.3 Run `flutter analyze` — confirm zero issues

## 4. Visual Verification

- [x] 4.1 Open a Librivox book — confirm download icon in app-bar, round play button in body, no orange card
- [x] 4.2 Open a YouTube search result — confirm same layout
- [x] 4.3 Open a downloaded book — confirm download button shows correct "already downloaded" state in app-bar
- [x] 4.4 Tap circular play button — confirm playback starts and mini-player slides up
