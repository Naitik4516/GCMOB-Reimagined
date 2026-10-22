import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/core/platform/app_chrome.dart';

void main() {
  test('resolve is immersive when app fullscreen or page immersion is on', () {
    expect(
      AppChrome.resolve(appFullscreen: false, pageImmersive: false),
      SystemUiMode.edgeToEdge,
    );
    expect(
      AppChrome.resolve(appFullscreen: true, pageImmersive: false),
      SystemUiMode.immersiveSticky,
    );
    expect(
      AppChrome.resolve(appFullscreen: false, pageImmersive: true),
      SystemUiMode.immersiveSticky,
    );
    expect(
      AppChrome.resolve(appFullscreen: true, pageImmersive: true),
      SystemUiMode.immersiveSticky,
    );
  });
}
