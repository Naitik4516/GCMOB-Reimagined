# Test helpers

Shared fakes and harnesses used by the unit/widget suites.

## Conventions

- Any suite that reaches `SharedPreferences` must call
  `SharedPreferences.setMockInitialValues({})` in `setUp` (or at the top of
  the test) before touching the store. No plugins are registered under
  `flutter test`.
- Player tests use `FakeTilePlayer`; never initialize `media_kit` or libmpv.
- Storage fakes are deliberately configurable (`throwOn…` flags,
  `Completer` gates) instead of being copied per test file.
- Close the cubit/controller a test creates (`addTearDown(cubit.close)`) so
  timers and stream subscriptions cannot leak into the next test.
