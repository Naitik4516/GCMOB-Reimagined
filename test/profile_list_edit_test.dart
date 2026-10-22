import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcmob_reimagined/app/theme.dart';
import 'package:gcmob_reimagined/features/profiles/ui/profile_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

BorderSide _fabSide(WidgetTester tester) {
  final fab =
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
  return (fab.shape! as RoundedRectangleBorder).side;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'dvr_profiles_v1': jsonEncode([
        {
          'id': 'p1',
          'name': 'Home DVR',
          'host': '192.168.1.240',
          'rtspPort': 554,
          'username': 'admin',
          'channelCount': 8,
        },
      ]),
    });
  });

  // ProfileListPage owns its ProfilesCubit in a State field. The 3-dot
  // actions live in the sheet/dialog layer, outside the provider subtree, so
  // a `context.read` from the State's own context throws
  // ProviderNotFoundException. This pins the edit route (the reported bug).
  testWidgets('3-dot edit opens the form with the profile', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileListPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit DVR'), findsOneWidget);
    expect(find.text('Home DVR'), findsWidgets);
  });

  // TV D-Pad: the FAB must show the shared amber outline while focused,
  // otherwise the default Material focus overlay is invisible on the FAB.
  testWidgets('Add DVR FAB gains the focus outline when focused',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileListPage()));
    await tester.pumpAndSettle();

    expect(_fabSide(tester).color, Colors.transparent);

    final fab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    fab.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    final side = _fabSide(tester);
    expect(side.color, CctvTheme.focusColor);
    expect(side.width, 2);

    // Losing focus restores the plain FAB.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(_fabSide(tester).color, Colors.transparent);
  });
}
