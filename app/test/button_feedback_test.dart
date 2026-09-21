import 'package:app/src/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _buttonKey = ValueKey('feedback-button');

Future<void> _mount(
  WidgetTester tester,
  Widget button, {
  bool reduceMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildTonyoTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(body: Center(child: button)),
  ),
);

Finder get _feedbackSurface => find.descendant(
  of: find.byKey(_buttonKey),
  matching: find.byWidgetPredicate(
    (widget) => widget is AnimatedContainer && widget.child is AnimatedScale,
  ),
);

Color _feedbackColor(WidgetTester tester) =>
    (tester.widget<AnimatedContainer>(_feedbackSurface).decoration!
            as BoxDecoration)
        .color!;

double _paintedScale(WidgetTester tester) => tester
    .widget<ScaleTransition>(
      find.descendant(
        of: _feedbackSurface,
        matching: find.byType(ScaleTransition),
      ),
    )
    .scale
    .value;

void main() {
  final buttons = <String, Widget Function(VoidCallback?)>{
    'filled': (onPressed) => FilledButton(
      key: _buttonKey,
      onPressed: onPressed,
      child: const Text('Continue'),
    ),
    'tonal': (onPressed) => FilledButton.tonal(
      key: _buttonKey,
      onPressed: onPressed,
      child: const Text('Continue'),
    ),
    'elevated': (onPressed) => ElevatedButton(
      key: _buttonKey,
      onPressed: onPressed,
      child: const Text('Continue'),
    ),
    'outlined': (onPressed) => OutlinedButton(
      key: _buttonKey,
      onPressed: onPressed,
      child: const Text('Continue'),
    ),
    'text': (onPressed) => TextButton(
      key: _buttonKey,
      onPressed: onPressed,
      child: const Text('Continue'),
    ),
    'icon': (onPressed) => IconButton(
      key: _buttonKey,
      onPressed: onPressed,
      icon: const Icon(Icons.add),
    ),
    'filled icon': (onPressed) => IconButton.filled(
      key: _buttonKey,
      onPressed: onPressed,
      icon: const Icon(Icons.add),
    ),
  };

  for (final entry in buttons.entries) {
    testWidgets('${entry.key}: hover, press, release and disabled feedback', (
      tester,
    ) async {
      var taps = 0;
      await _mount(tester, entry.value(() => taps++));
      final button = find.byKey(_buttonKey);
      final restingSize = tester.getSize(button);
      expect(_feedbackColor(tester).a, 0);
      expect(_paintedScale(tester), 1);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pumpAndSettle();
      expect(_feedbackColor(tester).a, greaterThan(0));
      expect(tester.getSize(button), restingSize);

      final touch = await tester.startGesture(tester.getCenter(button));
      await tester.pumpAndSettle();
      expect(_paintedScale(tester), closeTo(.97, .001));
      expect(tester.getSize(button), restingSize);
      expect(taps, 0);
      await touch.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(_paintedScale(tester), 1);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_feedbackColor(tester).a, 0);
      await _mount(tester, entry.value(null));
      await mouse.moveTo(tester.getCenter(button));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(_feedbackColor(tester).a, 0);
      expect(_paintedScale(tester), 1);
      expect(taps, 1);
      await mouse.removePointer();
    });
  }

  testWidgets('feedback follows custom foreground without changing fill', (
    tester,
  ) async {
    const foreground = Color(0xFFB92331);
    const background = Color(0xFFFDE9EB);
    await _mount(
      tester,
      FilledButton(
        key: _buttonKey,
        style: FilledButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
        ),
        onPressed: () {},
        child: const Text('Remove'),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(_buttonKey)));
    await tester.pumpAndSettle();
    expect(_feedbackColor(tester), foreground.withValues(alpha: .07));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byKey(_buttonKey),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, background);
    await mouse.removePointer();
  });

  testWidgets('keyboard focus shows feedback and can activate the button', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var taps = 0;
    await _mount(
      tester,
      TextButton(
        key: _buttonKey,
        focusNode: focus,
        onPressed: () => taps++,
        child: const Text('Continue'),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(_feedbackColor(tester).a, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('reduced motion retains tint and taps without press movement', (
    tester,
  ) async {
    var taps = 0;
    await _mount(tester, buttons['filled']!(() => taps++), reduceMotion: true);
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(_buttonKey)),
    );
    await tester.pump();
    expect(_paintedScale(tester), 1);
    expect(_feedbackColor(tester).a, greaterThan(0));
    expect(
      tester.widget<AnimatedContainer>(_feedbackSurface).duration,
      Duration.zero,
    );
    await touch.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
