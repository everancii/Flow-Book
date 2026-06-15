## Context

The audiobook details screen (`audiobook_details.dart`) currently has:
- **App-bar**: title text + favourite icon button (right).
- **Action card**: an orange card below the cover art containing a `DownloadButton` (left) + divider + `IconButton(Ionicons.play)` (right), all inside a `Row`.

The request is to:
1. Move `DownloadButton` from the orange action card into the app-bar actions (next to the favourite icon).
2. Replace the flat `IconButton(play)` with a large circular button centred on screen.

## Goals / Non-Goals

**Goals:**
- Download button accessible in app-bar on all book types (Librivox, YouTube, 4Read, local, downloaded).
- Play button visually dominant — large circular FAB-style button, centred below the cover art section.
- Orange action card simplified (may become play-only or removed entirely).
- No change to play/download business logic — only widget repositioning and restyling.

**Non-Goals:**
- Redesigning the cover art area, description, or chapter list.
- Changing download behaviour, progress states, or stream handling.
- Supporting a different layout on tablet/wide screen.

## Decisions

### 1. Download button in app-bar as `IconButton` wrapper

`DownloadButton` widget currently expects to be in a 60×60 `SizedBox`. In the app-bar it will be wrapped in an `IconButton`-sized space. Rather than refactoring `DownloadButton` itself, we wrap it directly in an `actions` entry — this is the smallest-footprint change. If `DownloadButton` draws its own icon+progress, it will naturally fit within `IconButton` bounds.

**Alternative considered**: Extract a compact variant prop on `DownloadButton`. Rejected — extra complexity for the same visual result.

### 2. Circular play button as a plain `Container` with `InkWell`, not `FloatingActionButton`

`FloatingActionButton` floats over the `Scaffold` body and requires `floatingActionButton` + `floatingActionButtonLocation`. This causes overlap with the mini-player (`WeSlide`). Instead: a `Container(decoration: BoxDecoration(shape: BoxShape.circle))` sized 72×72 centred in the column — same visual effect, no layout conflicts.

**Alternative considered**: `FloatingActionButton`. Rejected — conflicts with `WeSlide` bottom sheet.

### 3. Remove the orange action card entirely

With download in the app-bar and play replaced by the circular button inline, the orange `Card` row has no remaining items. It will be removed. The play logic currently in that card's `onPressed` is moved to the new circular button.

## Risks / Trade-offs

- [Risk] `DownloadButton` may have fixed sizing assumptions that cause visual clipping in the app-bar. → Mitigation: test on both small and large titles; add `SizedBox` constraints around it in the action slot if needed.
- [Risk] Play button placement might feel too low if there are many metadata lines above it. → Mitigation: keep it immediately after the metadata block and before the chapter list, with consistent padding.
- [Risk] Visual regression on books with `isDownload: true` (already-downloaded books) — `DownloadButton` shows different states (progress, done, etc.). → Mitigation: verify each state visually after implementation.
