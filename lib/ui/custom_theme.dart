import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/money.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Slot { accent, background }

const _accentPresets = [
  0xFFFF7A00, 0xFFF43F5E, 0xFFE879F9, 0xFF8B5CF6, 0xFF3B82F6, 0xFF06B6D4, 0xFF10B981, 0xFFFACC15,
];
const _backgroundPresets = [
  0xFF0B0B0F, 0xFF101828, 0xFF1F1033, 0xFF2A0F16, 0xFF0F2A24, 0xFFF8F5EE, 0xFFEFF3FA, 0xFFFFFFFF,
];

String _toHex(int color) =>
    (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

int? _parseHex(String text) {
  final clean = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(clean)) return null;
  return 0xFF000000 | int.parse(clean, radix: 16);
}

class CustomThemePage extends StatefulWidget {
  const CustomThemePage({super.key});

  @override
  State<CustomThemePage> createState() => _CustomThemePageState();
}

class _CustomThemePageState extends State<CustomThemePage> {
  late HSVColor _accent;
  late HSVColor _background;
  bool _ready = false;
  _Slot _slot = _Slot.accent;
  final _hex = TextEditingController();
  String? _hexError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final data = StoreScope.of(context).data;
    final current = resolveTheme(data);
    final saved = data.customColors;
    _accent = HSVColor.fromColor(saved == null ? current.accent : Color(saved.accent));
    _background =
        HSVColor.fromColor(saved == null ? current.background : Color(saved.background));
    _showHex();
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  HSVColor get _active => _slot == _Slot.accent ? _accent : _background;

  CustomColors get _colors => CustomColors(
        accent: _accent.toColor().toARGB32(),
        background: _background.toColor().toARGB32(),
      );

  void _showHex() {
    _hex.text = _toHex(_active.toColor().toARGB32());
    _hexError = null;
  }

  void _store(HSVColor color) {
    if (_slot == _Slot.accent) {
      _accent = color;
    } else {
      _background = color;
    }
  }

  void _pick(HSVColor color) {
    setState(() {
      _store(color);
      _showHex();
    });
  }

  void _setSlot(_Slot slot) {
    setState(() {
      _slot = slot;
      _showHex();
    });
  }

  /// Applies as soon as the code is complete, leaving the field untouched so
  /// the cursor stays where the user is typing.
  void _onHexChanged(String text) {
    final color = _parseHex(text);
    if (color == null) return;
    setState(() {
      _store(HSVColor.fromColor(Color(color)));
      _hexError = null;
    });
  }

  void _onHexSubmitted(String text) {
    if (_parseHex(text) == null) {
      setState(() => _hexError = '6 haneli renk kodu yaz. Örnek: FF7A00');
    }
  }

  void _save() {
    StoreScope.of(context).setCustomColors(_colors);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = deriveTheme(_colors);
    final presets = _slot == _Slot.accent ? _accentPresets : _backgroundPresets;
    return Theme(
      data: buildTheme(preview),
      child: Scaffold(
        appBar: AppBar(title: const Text('Özel tema')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            ExcludeSemantics(child: _Preview(theme: preview)),
            if (!accentIsLegible(_colors))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: preview.danger),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Vurgu rengi arka planda kayboluyor. Daha açık veya koyu bir renk seç.'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SegmentedButton<_Slot>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _Slot.accent,
                  label: const Text('Vurgu'),
                  icon: _Dot(_accent.toColor()),
                ),
                ButtonSegment(
                  value: _Slot.background,
                  label: const Text('Arka plan'),
                  icon: _Dot(_background.toColor()),
                ),
              ],
              selected: {_slot},
              onSelectionChanged: (slots) => _setSlot(slots.single),
            ),
            const SizedBox(height: 14),
            _SaturationValueBox(color: _active, onChanged: _pick),
            const SizedBox(height: 14),
            _HueBar(color: _active, onChanged: _pick),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final color in presets)
                  _Swatch(
                    color: Color(color),
                    selected: _active.toColor().toARGB32() == color,
                    label: _toHex(color),
                    onTap: () => _pick(HSVColor.fromColor(Color(color))),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _hex,
              maxLength: 7,
              decoration: InputDecoration(
                labelText: 'Renk kodu',
                prefixText: '#',
                counterText: '',
                errorText: _hexError,
              ),
              onChanged: _onHexChanged,
              onSubmitted: _onHexSubmitted,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Temayı kullan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Renk $label',
      child: InkResponse(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colors.onSurface : colors.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Drags are claimed on both axes so the page does not scroll under a finger
/// that is choosing a color.
class _DragArea extends StatelessWidget {
  const _DragArea({required this.onPosition, required this.child});

  final ValueChanged<Offset> onPosition;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (details) => onPosition(details.localPosition),
        onVerticalDragStart: (details) => onPosition(details.localPosition),
        onVerticalDragUpdate: (details) => onPosition(details.localPosition),
        onHorizontalDragStart: (details) => onPosition(details.localPosition),
        onHorizontalDragUpdate: (details) => onPosition(details.localPosition),
        child: child,
      );
}

class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({required this.color, required this.onChanged});

  static const height = 170.0;

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return _DragArea(
            onPosition: (position) => onChanged(
              color
                  .withSaturation((position.dx / width).clamp(0.0, 1.0))
                  .withValue(1 - (position.dy / height).clamp(0.0, 1.0)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.white,
                            HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
                          ]),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: color.saturation * width - 11,
                      top: (1 - color.value) * height - 11,
                      child: _Thumb(color.toColor()),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.color, required this.onChanged});

  static const height = 30.0;

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return _DragArea(
            onPosition: (position) => onChanged(
              // Black, white and gray have no hue of their own, so moving this
              // bar alone would appear to do nothing.
              color
                  .withHue((position.dx / width).clamp(0.0, 1.0) * 359.9)
                  .withSaturation(color.saturation < 0.05 ? 1 : color.saturation)
                  .withValue(color.value < 0.05 ? 1 : color.value),
            ),
            child: SizedBox(
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(colors: [
                          for (var hue = 0; hue <= 360; hue += 60)
                            HSVColor.fromAHSV(1, hue % 360, 1, 1).toColor(),
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: color.hue / 360 * width - 11,
                    child: _Thumb(HSVColor.fromAHSV(1, color.hue, 1, 1).toColor()),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
        ),
      );
}

/// A small copy of the home screen, in the colors being chosen.
class _Preview extends StatelessWidget {
  const _Preview({required this.theme});

  final KeseTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.inkSoft.withValues(alpha: 0.25)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bu ay kalan', style: TextStyle(color: theme.inkSoft, fontSize: 12.5)),
              Text(
                formatMoney(1245000),
                style: TextStyle(
                  color: theme.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabular,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: 0.62,
                        minHeight: 8,
                        color: theme.accent,
                        backgroundColor: theme.surfaceHigh,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Ödedim',
                      style: TextStyle(color: theme.onAccent, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
