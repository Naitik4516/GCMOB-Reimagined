# AGENTS.md

Single-package Flutter app: **gCMOB Reimagined** — a CCTV viewer for Dahua/CP Plus DVR/NVRs over RTSP. Not a monorepo; everything lives under one `pubspec.yaml`.

## Commands

- `flutter pub get` — after any `pubspec.yaml` change
- `flutter analyze` — the lint **and** typecheck gate (no separate typecheck step). Currently passes with 0 issues; keep it that way.
- `flutter test` — runs the only test file, `test/widget_test.dart`
  - single test: `flutter test --plain-name "GridCubit pages"` (substring match on the test name)
- `flutter run -d <device-id>` — no dev server; run on a device/emulator
- **Do not run `dart format` across the repo unless explicitly asked.** The code predates the current tall-style formatter: `dart format lib test` rewrites 12 of 19 files. Match surrounding style by hand instead.

Verification order: `flutter analyze` → `flutter test`.

`analysis_options.yaml` excludes `build/`, `android/`, `windows/`, `linux/`, so `flutter analyze` only checks `lib/` and `test/`.

## Architecture

- Entry: `lib/main.dart` → `MediaKit.ensureInitialized()` **must** run before `runApp` (media_kit native libs) → `lib/app/app.dart` (`CctvApp`, a plain `MaterialApp`).
- Feature-first layout, each feature self-contained as `ui/` + `bloc/` + `data/` + `models/`:
  - `lib/features/profiles/` — DVR profile list/form, persistence, home screen
  - `lib/features/live/` — live grid, tiles, fullscreen player
  - `lib/core/` — `rtsp/` (URL builder, mpv options), `platform/` (`is_tv.dart`)
- State: `flutter_bloc` **Cubits** with `equatable` states — no Bloc classes, no router package, no DI container; navigation is raw `Navigator.push`.
- Player: `media_kit` + `media_kit_video`. `MediaKitRTSPController` (`features/live/player/`) owns one `Player` per tile; low-latency mpv properties are set through the native `player.platform.setProperty` **before** `Player.open()`.
- Targets: Android (+ Android TV / Fire TV), Linux, Windows. **No iOS/macOS/Web runners exist.**

## Conventions that bite

- **Passwords never live in `DvrProfile` or SharedPreferences.** `ProfileStore` (`features/profiles/data/profile_store.dart`) splits storage: non-secrets in SharedPreferences (`dvr_profiles_v1`), passwords in `flutter_secure_storage` under `dvr_pass_<id>`.
- **RTSP indexing** (`lib/core/rtsp/rtsp_url.dart`): UI channels are 1-based, the Dahua `channel=` query param is 0-based; `subtype=1` = sub-stream (grid tiles, muted), `subtype=0` = main stream (fullscreen, audio on).
- **The grid never scrolls** — tile aspect ratio is derived from the viewport in `camera_grid_widget.dart`. Don't add scrolling or fixed aspect ratios.
- **Failure policy:** a failed tile is *sunk behind* working tiles (`GridCubit.markFailed`); retry is strictly user-initiated from the tile error overlay (`TileCubit.retry()` → `markRecovered`). Don't add an automatic reconnect loop at the cubit level.
- **TV / D-Pad:** the first list item is autofocused, tiles use `KeyboardListener` + focus glow (`CctvTheme.focusColor`); every interactive widget needs a focus path. `isTvCapable` is true for *all* Android builds (no Leanback check exists).
- **Fullscreen handoff:** `FullscreenPage` opens on the grid tile's live sub-stream and swaps to HD once it has frames (`TileCubit.suspend()` releases the sub decoder; `ensureSubPlaying()` restarts it on close). Don't dispose the tile's controller from fullscreen.
- **First-frame gate:** `playing` is reported only after sized frames arrive (`stream.width > 0`) — `playing` alone precedes the first decoded frame and shows black. Same gate drives the fullscreen HD swap.
- **Tile open gesture:** double click / double tap opens fullscreen (single tap only focuses); TV OK still opens directly. Desktop drag-and-drop uses slop-based `Draggable` with grab/grabbing cursors — not long-press.
- **App fullscreen:** `AppFullscreen` (`core/platform/`) — borderless window on desktop (window_manager, choice persisted), immersive bars on Android; F11 toggles from anywhere, plus a LivePage AppBar button.
- Fullscreen page enables `WakelockPlus` in `initState` and disables it in `dispose` — preserve that pairing.

## Testing quirks

- **No mocks are registered.** `SharedPreferences` / `FlutterSecureStorage` throw `MissingPluginException` under `flutter test`. Tests that need storage must call `SharedPreferences.setMockInitialValues({})` first; `GridCubit` tests avoid the problem entirely via the injected `saveOrder` callback.
- The boot test `'App boots to profile list'` passes *even though* profile loading fails — `ProfilesCubit.load()` swallows storage errors into an `error` state, and the AppBar renders in every state. Assert on `ProfilesState`, not on storage, if you need real coverage.
- No `integration_test/` directory exists.

## Tooling

- `opencode.json` registers the Dart MCP server (`dart mcp-server`).
- `.agents/skills/` + `skills-lock.json` pin agent skills (sources: `dart-lang/skills`, `flutter/agent-plugins`); the lock file stores content hashes, so don't hand-edit it.
- `.widget_preview/` is a generated, gitignored widget-preview scaffold — don't edit or commit it.
- No CI, Makefile, or task runner: the commands above are the whole verification story.
