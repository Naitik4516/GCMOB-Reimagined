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
- **Tile border:** the outline lives on an `IgnorePointer` overlay at the TOP of the tile Stack, never on the outer container — Container paints decoration under its child, so full-bleed video covers border corners. Outer container carries only glow shadow; stack is `ClipRRect`ed.
- **Reshuffles must not recreate tiles:** `GridView.findChildIndexCallback` (`findTileIndex`) moves keyed tiles on sink/reorder — without it every shifted tile (and its working stream) reconnects, avalanching one failure across the grid.
- **TV / D-Pad:** the first list item is autofocused, tiles use `KeyboardListener` + focus glow (`CctvTheme.focusColor`); every interactive widget needs a focus path. `isTvCapable` is true for *all* Android builds (no Leanback check exists).
- **Single-camera view = spotlight 1x1, not a route.** Double-click / OK calls `GridCubit.focusChannel` (1x1, HD main-stream, audio on); exit via double-click / Esc / Back / Grid button restores layout+page. There is no fullscreen page (`wakelock_plus` removed).
- **First-frame gate:** `playing` is reported only after sized frames arrive (`stream.width > 0`) — `playing` alone precedes the first decoded frame and shows black. Same gate drives the fullscreen HD swap.
- **Load path (slow-stream fixes, do not regress):** load-critical mpv flags must be *awaited* before `open()` (`ensureFlags`, never fire-and-forget — otherwise tiles silently fall back to UDP); every `open()` goes through `RtspOpener` (max 3 concurrent handshakes, FIFO); `_fail` stops the player to release the decoder + DVR session.
- **Tile open gesture:** double click / double tap opens the single view (single tap only focuses); TV OK still toggles directly. Tiles carry a mute button when HD (`TileState.muted`, M key toggles). Desktop drag-and-drop uses slop-based `Draggable` with grab/grabbing cursors — not long-press.
- **App fullscreen:** `AppFullscreen` (`core/platform/`) — borderless window on desktop (window_manager, choice persisted), immersive bars on Android; F11 toggles from anywhere, plus a toggle button.
- **Zoom mechanics:** `InteractiveViewer` (pinch/pan) + manual wheel-zoom matrix in `CameraTileWidget._onWheel` — the viewer maps wheel to pan, so the wheel needs its own handler. Uses non-deprecated `translateByDouble`/`scaleByDouble`.
- **Grid metrics:** roomy padding/gaps (20/14) past phone widths — desktop always, or viewport ≥700px — else compact 8/8. The aspect fit math must subtract the same pad/gap it renders with.
- **Zoom everywhere:** all tiles zoomable (wheel + pinch); a tile zoomed past 1x reports via `onZoomChanged` and the grid drops its reorder wrapper so drags pan instead. Immersive landscape uses long-press drag (fling turns pages) for the same reason.
- **App frame:** `AdaptiveShell` — Windows gets `DesktopTitleBar` (draggable, min/max/close; native bar hidden in `AppFullscreen.init`); Linux keeps its native KWin frame (theme rounding included) with a regular `AppBar` inside; mobile/TV use `AppBar` + bottom bar (`hideChrome` drops both for immersive landscape). Windows title bar carries layout + SD/HD + shortcuts + fullscreen; phones keep title + fullscreen only. Pager chevrons hide at the ends, never sit disabled.
- **Phone landscape immersion:** `LivePage` enters ultra-immersive (bars hidden, fling pages, tap reveals floating bar + back button, 5s auto-hide) only after portrait was seen once — landscape-locked TVs never enter. The floating bar carries layout + SD/HD + paging + grid-exit. Rotation immersion never touches the persisted fullscreen pref; phones launch non-fullscreen by default.
- **Seek-error tolerance:** media_kit forwards all mpv error-level logs, so benign live-stream notes (`isBenignLiveError`, any `seek` substring — including the standalone `--force-seekable` hint) never fail a tile — they rearm a 10s stall watchdog that fails only if mpv is still stuck buffering.
- **Weak-SoC grid bring-up:** tile first-starts stagger 250ms per slot (`TileCubit.startDelay`) on top of the 3-wide `RtspOpener` — nine simultaneous MediaCodec sessions overwhelm low-end phones.
- **Rounded window (Windows-only):** transparent backdrop (`setBackgroundColor`) + `ClipRRect` radius 12 around every route via `MaterialApp.builder`, flattened while app-fullscreen. `window_rounded_corners` is Android-only — irrelevant. Linux keeps native KWin decorations instead.
- **Shortcuts (tile focused):** `1/2/3` layout, `[`/`]` or PgUp/PgDn (also ChUp/ChDown) paging, `M` mute, `Esc` cancel grab / exit single view, `F1` help dialog. `F11` app-fullscreen goes through a global `HardwareKeyboard` handler in `CctvApp` — Focus-bubble handlers miss keys when nothing is focused, do not use them for global keys.

## Testing quirks

- **No mocks are registered.** `SharedPreferences` / `FlutterSecureStorage` throw `MissingPluginException` under `flutter test`. Tests that need storage must call `SharedPreferences.setMockInitialValues({})` first; `GridCubit` tests avoid the problem entirely via the injected `saveOrder` callback.
- The boot test `'App boots to profile list'` passes *even though* profile loading fails — `ProfilesCubit.load()` swallows storage errors into an `error` state, and the AppBar renders in every state. Assert on `ProfilesState`, not on storage, if you need real coverage.
- No `integration_test/` directory exists.

## Tooling

- `opencode.json` registers the Dart MCP server (`dart mcp-server`).
- `.agents/skills/` + `skills-lock.json` pin agent skills (sources: `dart-lang/skills`, `flutter/agent-plugins`); the lock file stores content hashes, so don't hand-edit it.
- `.widget_preview/` is a generated, gitignored widget-preview scaffold — don't edit or commit it.
- No CI, Makefile, or task runner: the commands above are the whole verification story.
