# GCMOB Reimagined

Low-latency CCTV viewer for Dahua and CP Plus DVR/NVR devices over RTSP.
Browse a 1/4/9-camera wall, open any camera in a spotlight single view, and
drive the app with a TV remote, keyboard, or mouse.

## Requirements

- Flutter with Dart SDK `^3.13.5` and the toolchain for your target:
  Android SDK/NDK, Visual Studio for Windows, or the Linux desktop toolchain.
- Linux runtime: `libsecret-1-0` (used by `flutter_secure_storage` to keep DVR
  passwords out of SharedPreferences).

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id>
```

Do not run `dart format` across the repository; the code predates the current
tall-style formatter.

## Production builds

### Android signing

Release builds require a private `android/key.properties` file:

```properties
storeFile=/absolute/path/to/gcmob-release.jks
storePassword=...
keyAlias=gcmob
keyPassword=...
```

```sh
flutter build apk --release
```

Release builds fail by design when `android/key.properties` is missing. Never
commit that file or the keystore.

### Desktop builds

Linux release builds use `mold` when it is installed. Override with
`-DGCMOB_USE_MOLD=OFF` only when building on a system without `mold`:

```sh
flutter build linux --release
flutter build windows --release
```

## Plans

Implementation plans for the ongoing review work live in
[`plans/`](plans/README.md).

