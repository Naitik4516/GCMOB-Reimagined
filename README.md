# GCMOB Reimagined

CCTV viewer for Dahua and CP Plus DVR/NVR devices over RTSP.

## Production builds

The production application ID is `com.ns.gcmob_reimagined`. The Android
manifest includes both the standard launcher and Android TV Leanback launcher,
so the same release APK can be installed on phones and Android TV devices.

### Android signing

Release builds require a private `android/key.properties` file:

```properties
storeFile=/absolute/path/to/gcmob-release.jks
storePassword=...
keyAlias=gcmob
keyPassword=...
```

Do not commit this file or the keystore. Build phone/TV APKs with:

```sh
flutter build apk --release
```

### Desktop builds

Linux release builds use `mold` when it is installed. Override with
`-DGCMOB_USE_MOLD=OFF` only when building on a system without `mold`:

```sh
flutter build linux --release
flutter build windows --release
```

Windows uses the platform MSVC linker; Android uses the linker supplied by
the Android NDK. The Linux bundle is written to
`build/linux/x64/release/bundle/`, and the Windows bundle is written to
`build/windows/x64/runner/Release/`.

