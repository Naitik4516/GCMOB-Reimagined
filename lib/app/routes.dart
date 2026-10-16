import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared fade+scale page transition for profile / fullscreen navigation.
/// Keeps TV D-Pad focus working: no staggered hero flight, short duration.
class CctvPageRoute<T> extends PageRouteBuilder<T> {
  CctvPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: CctvTheme.durMed,
          reverseTransitionDuration: CctvTheme.durShort,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: CctvTheme.curveEmphasized,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}
