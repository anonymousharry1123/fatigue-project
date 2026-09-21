import 'package:flutter/material.dart';

/// Adds feedback inside the button's existing Material and InkWell, keeping
/// layout, hit targets, keyboard handling, and the native ripple intact.
Widget buildTonyoButtonFeedback(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _ButtonFeedback(
  enabled: !states.contains(WidgetState.disabled),
  pressed: states.contains(WidgetState.pressed),
  hovered: states.contains(WidgetState.hovered),
  focused: states.contains(WidgetState.focused),
  child: child,
);

class _ButtonFeedback extends StatelessWidget {
  const _ButtonFeedback({
    required this.enabled,
    required this.pressed,
    required this.hovered,
    required this.focused,
    required this.child,
  });

  final bool enabled, pressed, hovered, focused;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final activePress = enabled && pressed;
    final duration = reduceMotion
        ? Duration.zero
        : Duration(milliseconds: activePress ? 90 : 160);
    // Resolve the actual button foreground here, below its Material. This also
    // follows tonal/filled icon variants and locally customized button colors.
    final foreground =
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.primary;
    final opacity = !enabled
        ? 0.0
        : activePress || focused
        ? .10
        : hovered
        ? .07
        : 0.0;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      color: foreground.withValues(alpha: opacity),
      child: AnimatedScale(
        scale: activePress && !reduceMotion ? .97 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
