import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme_controller.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    final preferences = controller.preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Mode', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final (mode, label, icon) in const [
                    (
                      ThemeMode.system,
                      'Follow device',
                      Icons.brightness_auto_outlined,
                    ),
                    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                  ])
                    Semantics(
                      selected: preferences.mode == mode,
                      child: ListTile(
                        key: ValueKey('appearance-mode-${mode.name}'),
                        leading: Icon(icon),
                        title: Text(label),
                        trailing: preferences.mode == mode
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : const Icon(Icons.radio_button_unchecked),
                        onTap: () => _saveSelection(
                          context,
                          controller,
                          controller.setMode(mode),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 16),
              _SaveError(controller: controller),
            ],
            const SizedBox(height: 24),
            Text('Theme', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final preset in tonyoThemePresets) ...[
              _ThemeChoice(
                id: preset.id,
                label: preset.name,
                colors: preset.colors,
                selected: preferences.presetId == preset.id,
                onTap: () => _saveSelection(
                  context,
                  controller,
                  controller.setPreset(preset.id),
                ),
              ),
              const SizedBox(height: 10),
            ],
            _ThemeChoice(
              id: 'custom',
              label: 'Custom',
              colors: preferences.customColors,
              selected: preferences.presetId == 'custom',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => _CustomThemeScreen(controller: controller),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _ThemePreview(),
            if (controller.isSaving) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: const Text('Saving appearance…'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveSelection(
    BuildContext context,
    ThemeController controller,
    Future<bool> save,
  ) async {
    if (await save || !context.mounted || controller.error == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(controller.error!),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () =>
                _saveSelection(context, controller, controller.retry()),
          ),
        ),
      );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.id,
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final TonyoColorPair colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = buildTonyoTheme(
      brightness: Theme.of(context).brightness,
      colors: colors,
    );
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('appearance-preset-$id'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Swatch(color: colors.main),
                    const SizedBox(width: 6),
                    _Swatch(color: colors.secondary),
                    const SizedBox(width: 12),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outline),
                    ),
                    padding: const EdgeInsets.all(9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 46,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: CustomPaint(
                            key: ValueKey(
                              'appearance-preset-$id-preview-chart',
                            ),
                            painter: _PreviewChartPainter(
                              scheme.primary,
                              scheme.secondary,
                              scheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
  );
}

class _CustomThemeScreen extends StatefulWidget {
  const _CustomThemeScreen({required this.controller});
  final ThemeController controller;

  @override
  State<_CustomThemeScreen> createState() => _CustomThemeScreenState();
}

class _CustomThemeScreenState extends State<_CustomThemeScreen> {
  final _formKey = GlobalKey<FormState>();
  late TonyoColorPair _draft;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.preferences.customColors;
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final saved = await widget.controller.setCustomColors(_draft);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Custom theme')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ColorPicker(
                id: 'main',
                label: 'Main color',
                initialColor: _draft.main,
                enabled: !_saving,
                onChanged: (color) => setState(
                  () => _draft = TonyoColorPair(
                    main: color,
                    secondary: _draft.secondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ColorPicker(
                id: 'secondary',
                label: 'Secondary color',
                initialColor: _draft.secondary,
                enabled: !_saving,
                onChanged: (color) => setState(
                  () => _draft = TonyoColorPair(
                    main: _draft.main,
                    secondary: color,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Theme(
                data: buildTonyoTheme(
                  brightness: Theme.of(context).brightness,
                  colors: _draft,
                ),
                child: const _ThemePreview(),
              ),
              const SizedBox(height: 16),
              Text(
                'Colors are adjusted for readability in light and dark mode.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_saveFailed) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.controller.error ??
                        'Could not save appearance. Please retry.',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('appearance-custom-apply'),
                onPressed: _saving ? null : _apply,
                child: Text(
                  _saving
                      ? 'Saving…'
                      : _saveFailed
                      ? 'Retry'
                      : 'Apply',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('appearance-custom-cancel'),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({
    required this.id,
    required this.label,
    required this.initialColor,
    required this.onChanged,
    required this.enabled,
  });
  final String id;
  final String label;
  final Color initialColor;
  final ValueChanged<Color> onChanged;
  final bool enabled;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late Color _color;
  late TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
    _hex = TextEditingController(text: _toHex(_color));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _toHex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Color? _parse(String value) {
    final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(0xff000000 | int.parse(hex, radix: 16));
  }

  void _setChannel(int index, double value) {
    final channels = [
      (_color.r * 255).round(),
      (_color.g * 255).round(),
      (_color.b * 255).round(),
    ];
    channels[index] = value.round();
    setState(() {
      _color = Color.fromARGB(255, channels[0], channels[1], channels[2]);
      _hex.text = _toHex(_color);
    });
    widget.onChanged(_color);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              _Swatch(color: _color),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('appearance-${widget.id}-hex'),
            controller: _hex,
            enabled: widget.enabled,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '${widget.label} hex',
              hintText: '#2563EB',
              errorMaxLines: 3,
            ),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) => _parse(value ?? '') == null
                ? 'Enter six hex digits, such as #2563EB.'
                : null,
            onChanged: (value) {
              final color = _parse(value);
              if (color == null) return;
              setState(() => _color = color);
              widget.onChanged(color);
            },
          ),
          const SizedBox(height: 12),
          for (final (index, label, channel) in [
            (0, 'Red', _color.r),
            (1, 'Green', _color.g),
            (2, 'Blue', _color.b),
          ]) ...[
            Text('$label · ${(channel * 255).round()}'),
            Slider(
              key: ValueKey('appearance-${widget.id}-${label.toLowerCase()}'),
              value: (channel * 255).roundToDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: '${(channel * 255).round()}',
              semanticFormatterCallback: (value) =>
                  '${widget.label}, $label, ${value.round()} of 255',
              onChanged: widget.enabled
                  ? (value) => _setChannel(index, value)
                  : null,
            ),
          ],
        ],
      ),
    ),
  );
}

class _SaveError extends StatelessWidget {
  const _SaveError({required this.controller});
  final ThemeController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(controller.error!),
        TextButton(
          onPressed: controller.isSaving ? null : controller.retry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Preview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your day',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('A sample of your selected colors.'),
                const SizedBox(height: 16),
                Semantics(
                  image: true,
                  label:
                      'Sample chart. Main color: solid line. Secondary color: dashed line.',
                  child: SizedBox(
                    height: 72,
                    child: CustomPaint(
                      painter: _PreviewChartPainter(
                        scheme.primary,
                        scheme.secondary,
                        scheme.outline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      '— Main color',
                      style: TextStyle(color: scheme.primary),
                    ),
                    Text(
                      'Secondary color (dashed)',
                      style: TextStyle(color: scheme.secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Sample button'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewChartPainter extends CustomPainter {
  const _PreviewChartPainter(this.main, this.secondary, this.border);
  final Color main;
  final Color secondary;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = border,
    );
    final mainPath = Path()..moveTo(0, size.height * .7);
    final secondaryPath = Path()..moveTo(0, size.height * .4);
    const mainPoints = [.7, .5, .6, .2, .3, .1];
    const secondaryPoints = [.4, .6, .3, .5, .2, .45];
    for (var index = 1; index < mainPoints.length; index++) {
      final x = size.width * index / (mainPoints.length - 1);
      mainPath.lineTo(x, size.height * mainPoints[index]);
      secondaryPath.lineTo(x, size.height * secondaryPoints[index]);
    }
    canvas.drawPath(
      mainPath,
      Paint()
        ..color = main
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final paint = Paint()
      ..color = secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final metric in secondaryPath.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 9) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 5).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PreviewChartPainter oldDelegate) =>
      main != oldDelegate.main ||
      secondary != oldDelegate.secondary ||
      border != oldDelegate.border;
}
