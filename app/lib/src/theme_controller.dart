import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

const themePreferencesKey = 'tonyo_theme_v1';

/// Device appearance is stored separately from account, backup, and cloud data.
abstract interface class ThemePreferencesStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesThemeStore implements ThemePreferencesStore {
  @override
  Future<String?> read() async {
    final value = (await SharedPreferences.getInstance()).get(
      themePreferencesKey,
    );
    return value is String ? value : null;
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    try {
      if (!await preferences.setString(themePreferencesKey, value)) {
        throw StateError('Could not save appearance.');
      }
    } on Object {
      // Legacy SharedPreferences updates its cache before confirming the write.
      // Reload so a failed update is not presented as saved by the next reader.
      try {
        await preferences.reload();
      } on Object {
        // The controller still rolls back to its last confirmed selection.
      }
      rethrow;
    }
  }
}

@immutable
class ThemePreferences {
  const ThemePreferences({
    this.mode = ThemeMode.system,
    this.presetId = 'classic',
    this.customColors = defaultTonyoColors,
  });

  final ThemeMode mode;
  final String presetId;
  final TonyoColorPair customColors;

  TonyoColorPair get colors => presetId == 'custom'
      ? customColors
      : tonyoThemePresets.firstWhere((preset) => preset.id == presetId).colors;

  ThemePreferences copyWith({
    ThemeMode? mode,
    String? presetId,
    TonyoColorPair? customColors,
  }) => ThemePreferences(
    mode: mode ?? this.mode,
    presetId: presetId ?? this.presetId,
    customColors: customColors ?? this.customColors,
  );

  String encode() => jsonEncode({
    'version': 1,
    'mode': mode.name,
    'presetId': presetId,
    'customColors': {
      'main': customColors.main.toARGB32(),
      'secondary': customColors.secondary.toARGB32(),
    },
  });

  /// Reject the entire envelope if any field is invalid or from a newer schema.
  static ThemePreferences decode(String? source) {
    if (source == null) return const ThemePreferences();
    try {
      final value = jsonDecode(source);
      if (value is! Map<String, dynamic> || value['version'] != 1) {
        return const ThemePreferences();
      }
      final mode = ThemeMode.values.where((mode) => mode.name == value['mode']);
      final presetId = value['presetId'];
      final custom = value['customColors'];
      if (mode.isEmpty ||
          presetId is! String ||
          !_validPreset(presetId) ||
          custom is! Map<String, dynamic> ||
          !_opaqueColor(custom['main']) ||
          !_opaqueColor(custom['secondary'])) {
        return const ThemePreferences();
      }
      return ThemePreferences(
        mode: mode.single,
        presetId: presetId,
        customColors: TonyoColorPair(
          main: Color(custom['main'] as int),
          secondary: Color(custom['secondary'] as int),
        ),
      );
    } on Object {
      return const ThemePreferences();
    }
  }

  static bool _opaqueColor(Object? value) =>
      value is int && value >= 0xff000000 && value <= 0xffffffff;

  static bool _validPreset(String id) =>
      id == 'custom' || tonyoThemePresets.any((preset) => preset.id == id);

  @override
  bool operator ==(Object other) =>
      other is ThemePreferences &&
      mode == other.mode &&
      presetId == other.presetId &&
      customColors == other.customColors;

  @override
  int get hashCode => Object.hash(mode, presetId, customColors);
}

class ThemeController extends ChangeNotifier {
  ThemeController({
    ThemePreferencesStore? store,
    ThemePreferences initialPreferences = const ThemePreferences(),
  }) : _store = store ?? SharedPreferencesThemeStore(),
       _preferences = initialPreferences,
       _saved = initialPreferences;

  final ThemePreferencesStore _store;
  ThemePreferences _preferences;
  ThemePreferences _saved;
  ThemePreferences? _retryPreferences;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;
  int _pending = 0;
  int _revision = 0;
  bool _disposed = false;
  bool _loadFailed = false;
  String? _error;

  ThemePreferences get preferences => _preferences;
  bool get isSaving => _pending > 0;
  String? get error => _error;

  Future<void> load() async {
    final revision = _revision;
    try {
      await _tail;
      if (revision != _revision) return;
      final loaded = ThemePreferences.decode(await _store.read());
      if (revision != _revision) return;
      _preferences = loaded;
      _saved = loaded;
      _loadFailed = false;
      _error = null;
    } on Object {
      if (revision != _revision) return;
      _loadFailed = true;
      _error = 'Could not load appearance. Please retry.';
    }
    _notify();
  }

  Future<bool> setMode(ThemeMode mode) =>
      _save(_preferences.copyWith(mode: mode));

  Future<bool> setPreset(String presetId) {
    if (!ThemePreferences._validPreset(presetId)) {
      throw ArgumentError.value(presetId, 'presetId', 'Unknown theme.');
    }
    return _save(_preferences.copyWith(presetId: presetId));
  }

  Future<bool> setCustomColors(TonyoColorPair colors) => _save(
    _preferences.copyWith(
      presetId: 'custom',
      customColors: TonyoColorPair(
        main: colors.main.withAlpha(255),
        secondary: colors.secondary.withAlpha(255),
      ),
    ),
  );

  Future<bool> retry() async {
    final preferences = _retryPreferences;
    if (preferences != null) return _save(preferences);
    if (_loadFailed) {
      await load();
      return _error == null;
    }
    return _error == null;
  }

  Future<bool> _save(ThemePreferences target) {
    final epoch = _epoch;
    _revision++;
    _pending++;
    _preferences = target;
    _error = null;
    _loadFailed = false;
    _retryPreferences = null;
    final result = _tail.then((_) async {
      try {
        // A failed write invalidates everything queued from that optimistic
        // state. Retry submits the last requested complete selection instead.
        if (epoch != _epoch) return false;
        await _store.write(target.encode());
        _saved = target;
        return true;
      } on Object {
        _retryPreferences = _preferences;
        _preferences = _saved;
        _error = 'Could not save appearance. Please retry.';
        _epoch++;
        return false;
      } finally {
        _pending--;
        _notify();
      }
    });
    _tail = result.then<void>((_) {});
    _notify();
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found in the widget tree.');
    return scope!.notifier!;
  }
}
