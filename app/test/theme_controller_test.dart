import 'dart:async';
import 'dart:convert';

import 'package:app/src/theme.dart';
import 'package:app/src/theme_controller.dart';
import 'package:app/src/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements ThemePreferencesStore {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? blockedWrite;
  int concurrentWrites = 0;
  int maximumConcurrentWrites = 0;
  final writes = <ThemePreferences>[];

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read failed');
    return value;
  }

  @override
  Future<void> write(String value) async {
    concurrentWrites++;
    if (concurrentWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = concurrentWrites;
    }
    writes.add(ThemePreferences.decode(value));
    try {
      await blockedWrite?.future;
      if (failWrite) throw StateError('write failed');
      this.value = value;
    } finally {
      concurrentWrites--;
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('legacy and unknown fonts preserve the saved mode and colors', () {
    const saved = ThemePreferences(
      mode: ThemeMode.dark,
      presetId: 'custom',
      customColors: TonyoColorPair(
        main: Color(0xff123456),
        secondary: Color(0xff987654),
      ),
    );
    final legacy = jsonDecode(saved.encode()) as Map<String, dynamic>
      ..remove('font');
    expect(ThemePreferences.decode(jsonEncode(legacy)), saved);
    for (final invalid in <Object?>['unknown', '', null, 12, <String>[]]) {
      expect(
        ThemePreferences.decode(jsonEncode({...legacy, 'font': invalid})),
        saved,
        reason: 'An unsupported font must not discard valid appearance choices',
      );
    }
  });

  test(
    'every font persists across restart without changing other choices',
    () async {
      final store = _MemoryStore();
      final controller = ThemeController(store: store);
      addTearDown(controller.dispose);
      await controller.setMode(ThemeMode.dark);
      await controller.setPreset('forest');
      for (final font in [...TonyoFont.values.skip(1), TonyoFont.system]) {
        expect(await controller.setFont(font), isTrue);
        expect(controller.preferences.font, font);
        expect(controller.preferences.mode, ThemeMode.dark);
        expect(controller.preferences.presetId, 'forest');
        final encoded = jsonDecode(store.value!) as Map<String, dynamic>;
        expect(encoded['version'], 1);
        expect(encoded['font'], font.name);
        final restarted = ThemeController(store: store);
        addTearDown(restarted.dispose);
        await restarted.load();
        expect(restarted.preferences, controller.preferences);
        expect(restarted.preferences.font, font);
      }
    },
  );

  test('missing and malformed preferences fall back entirely', () async {
    const expected = ThemePreferences();
    final valid = jsonDecode(expected.encode()) as Map<String, dynamic>;
    for (final source in <String?>[
      null,
      '',
      'not json',
      '[]',
      '{}',
      jsonEncode({...valid, 'version': 2}),
      jsonEncode({...valid, 'mode': 'automatic'}),
      jsonEncode({...valid, 'presetId': 'missing'}),
      jsonEncode({
        ...valid,
        'customColors': {'main': 0, 'secondary': 0xffffffff},
      }),
      jsonEncode({
        ...valid,
        'customColors': {'main': '#2563EB', 'secondary': 0xffffffff},
      }),
      jsonEncode({
        ...valid,
        'customColors': {'main': 0xffffffff, 'secondary': 0x100000000},
      }),
    ]) {
      final store = _MemoryStore()..value = source;
      final controller = ThemeController(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.preferences, expected, reason: '$source');
      expect(controller.error, isNull);
    }
  });

  test(
    'custom pair round trips and remains saved while a preset is active',
    () async {
      final store = _MemoryStore();
      final controller = ThemeController(store: store);
      addTearDown(controller.dispose);
      const colors = TonyoColorPair(
        main: Colors.white,
        secondary: Colors.black,
      );
      expect(await controller.setCustomColors(colors), isTrue);
      expect(await controller.setMode(ThemeMode.dark), isTrue);
      expect(await controller.setPreset('forest'), isTrue);
      final restarted = ThemeController(store: store);
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.preferences.mode, ThemeMode.dark);
      expect(restarted.preferences.presetId, 'forest');
      expect(restarted.preferences.customColors, colors);
      expect(
        restarted.preferences.colors,
        tonyoThemePresets.firstWhere((p) => p.id == 'forest').colors,
      );
      await restarted.setPreset('custom');
      expect(restarted.preferences.colors, colors);
    },
  );

  test(
    'rapid updates apply immediately and writes remain serialized',
    () async {
      final blocked = Completer<void>();
      final store = _MemoryStore()..blockedWrite = blocked;
      final controller = ThemeController(store: store);
      addTearDown(controller.dispose);
      final first = controller.setMode(ThemeMode.dark);
      final second = controller.setPreset('ocean');
      final third = controller.setPreset('plum');
      final fourth = controller.setFont(TonyoFont.inter);
      await Future<void>.delayed(Duration.zero);
      expect(controller.preferences.mode, ThemeMode.dark);
      expect(controller.preferences.presetId, 'plum');
      expect(controller.preferences.font, TonyoFont.inter);
      expect(controller.isSaving, isTrue);
      expect(store.writes.length, 1);
      blocked.complete();
      expect(await Future.wait([first, second, third, fourth]), [
        true,
        true,
        true,
        true,
      ]);
      expect(store.maximumConcurrentWrites, 1);
      expect(ThemePreferences.decode(store.value), controller.preferences);
      expect(controller.isSaving, isFalse);
    },
  );

  test(
    'failure rolls back, cancels queued writes, and retries the latest choice',
    () async {
      final store = _MemoryStore();
      final controller = ThemeController(store: store);
      addTearDown(controller.dispose);
      await controller.setPreset('forest');
      await controller.setFont(TonyoFont.inter);
      final saved = controller.preferences;
      final blocked = Completer<void>();
      store.blockedWrite = blocked;
      store.failWrite = true;
      final first = controller.setMode(ThemeMode.dark);
      final second = controller.setPreset('sunset');
      final third = controller.setFont(TonyoFont.lato);
      final desired = controller.preferences;
      blocked.complete();
      expect(await Future.wait([first, second, third]), [false, false, false]);
      expect(controller.preferences, saved);
      expect(ThemePreferences.decode(store.value), saved);
      expect(controller.error, contains('Could not save'));
      expect(controller.isSaving, isFalse);
      expect(store.writes.length, 3);
      store.failWrite = false;
      expect(await controller.retry(), isTrue);
      expect(controller.preferences, desired);
      expect(ThemePreferences.decode(store.value), desired);
      expect(controller.error, isNull);
    },
  );

  test(
    'read failure can be retried and a new choice clears old retry state',
    () async {
      final store = _MemoryStore()..failRead = true;
      final controller = ThemeController(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.error, contains('Could not load'));
      store.failRead = false;
      store.value = const ThemePreferences(
        mode: ThemeMode.dark,
        presetId: 'clay',
      ).encode();
      expect(await controller.retry(), isTrue);
      expect(controller.preferences.presetId, 'clay');
      store.failWrite = true;
      expect(await controller.setPreset('sunset'), isFalse);
      store.failWrite = false;
      expect(await controller.setPreset('ocean'), isTrue);
      expect(await controller.retry(), isTrue);
      expect(controller.preferences.presetId, 'ocean');
    },
  );

  test('production storage has a separate versioned device key', () async {
    SharedPreferences.setMockInitialValues({'tonyo_account': 'retained'});
    final controller = ThemeController();
    addTearDown(controller.dispose);
    await controller.setMode(ThemeMode.light);
    await controller.setPreset('ocean');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('tonyo_account'), 'retained');
    expect(
      ThemePreferences.decode(preferences.getString(themePreferencesKey)),
      controller.preferences,
    );
    final restarted = ThemeController();
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.preferences, controller.preferences);
  });

  test('unknown selections are rejected without changing preferences', () {
    final controller = ThemeController(store: _MemoryStore());
    addTearDown(controller.dispose);
    expect(() => controller.setPreset('missing'), throwsArgumentError);
    expect(controller.preferences, const ThemePreferences());
  });

  test('loading during a pending save waits for its persisted value', () async {
    final blocked = Completer<void>();
    final store = _MemoryStore()..blockedWrite = blocked;
    final controller = ThemeController(store: store);
    addTearDown(controller.dispose);
    final save = controller.setPreset('ocean');
    final load = controller.load();
    blocked.complete();
    await save;
    await load;
    expect(controller.preferences.presetId, 'ocean');
  });

  test('listener-triggered updates preserve save order', () async {
    final store = _MemoryStore();
    final controller = ThemeController(store: store);
    addTearDown(controller.dispose);
    Future<bool>? later;
    controller.addListener(() {
      if (controller.preferences.presetId == 'ocean') {
        later = controller.setPreset('plum');
      }
    });
    final first = controller.setPreset('ocean');
    await first;
    await later;
    expect(store.maximumConcurrentWrites, 1);
    expect(ThemePreferences.decode(store.value).presetId, 'plum');
  });
}
