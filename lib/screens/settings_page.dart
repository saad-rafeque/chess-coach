import 'package:fluent_ui/fluent_ui.dart';

import '../app/board_style.dart';
import '../app/refresh_rate.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../app/version.dart';
import '../widgets/board_picker.dart';
import '../widgets/common.dart';
import '../widgets/sync_settings.dart';
import '../widgets/update_ui.dart';
import '../widgets/voice_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    return PageFrame(
      title: 'Settings',
      subtitle: 'Make the app feel like yours',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Theme'),
          ResponsiveGrid(
            minItemWidth: 200,
            children: [
              for (final t in AppTheme.values)
                _ThemeCard(theme: t, selected: s.theme == t, onTap: () => s.theme = t),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle('Board and pieces'),
          const BoardPicker(),
          const SizedBox(height: 24),
          const SectionTitle('Board and coach'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(children: [
              _SwitchRow(
                icon: FluentIcons.grid_view_small,
                title: 'Show coordinates',
                subtitle: 'Letters and numbers around the board',
                value: s.showCoordinates,
                onChanged: (v) => s.showCoordinates = v,
              ),
              Divider(style: DividerThemeData(decoration: BoxDecoration(color: p.border))),
              _SwitchRow(
                icon: FluentIcons.chat,
                title: 'Live coach hints',
                subtitle: 'Warnings and tips during Training games',
                value: s.trainingHints,
                onChanged: (v) => s.trainingHints = v,
              ),
              Divider(style: DividerThemeData(decoration: BoxDecoration(color: p.border))),
              _SwitchRow(
                icon: FluentIcons.chart,
                title: 'Evaluation bar',
                subtitle: 'Who is winning, shown above the board in Training games',
                value: s.evalBar,
                onChanged: (v) => s.evalBar = v,
              ),
              Divider(style: DividerThemeData(decoration: BoxDecoration(color: p.border))),
              if (RefreshRate.adjustable) ...[
                const _RefreshRateRow(),
                Divider(style: DividerThemeData(decoration: BoxDecoration(color: p.border))),
              ],
              _SwitchRow(
                icon: FluentIcons.side_panel,
                title: 'Coach panel under the board',
                subtitle: 'Phones: always show the coach and details below the board, instead of behind a button',
                value: s.panelUnderBoard,
                onChanged: (v) => s.panelUnderBoard = v,
              ),
            ]),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Coach voice (optional)'),
          const VoiceSettings(),
          const SizedBox(height: 24),
          const SectionTitle('Sync'),
          const SyncSettings(),
          const SizedBox(height: 24),
          const SectionTitle('Updates'),
          const UpdateSettings(),
          const SizedBox(height: 24),
          Center(
            child: Text('Chess Coach $appVersion · GPL-3.0 · Stockfish 19',
                style: TextStyle(color: p.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tp = Palette.forTheme(theme);
    final board = BoardStyle.forTheme(theme);
    final (name, blurb) = switch (theme) {
      AppTheme.light => ('Light', 'Clean and bright'),
      AppTheme.dark => ('Dark', 'Easy on the eyes at night'),
      AppTheme.wooden => ('Wooden', 'Warm, classic club feel'),
    };
    return SurfaceCard(
      onTap: onTap,
      highlight: selected,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [tp.background, tp.backgroundEnd]),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(painter: _MiniBoard(board.lightSquare, board.darkSquare)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final w in [1.0, 0.7, 0.45])
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          height: 8,
                          width: 90 * w,
                          decoration: BoxDecoration(
                            color: w == 1 ? tp.accent : tp.surfaceAlt,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
                Text(blurb, style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
            if (selected) Icon(FluentIcons.completed_solid, color: p.accent, size: 18),
          ]),
        ],
      ),
    );
  }
}

class _MiniBoard extends CustomPainter {
  _MiniBoard(this.light, this.dark);

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final sq = size.width / n;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.clipRRect(rrect);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        canvas.drawRect(Rect.fromLTWH(c * sq, r * sq, sq, sq), Paint()..color = (r + c).isEven ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(_MiniBoard old) => old.light != light || old.dark != dark;
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(icon, color: p.muted, size: 18),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: p.text)),
            Text(subtitle, style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        ToggleSwitch(checked: value, onChanged: onChanged),
      ]),
    );
  }
}

/// Phones: choose between the smoothest refresh rate and battery-friendly 60 Hz.
class _RefreshRateRow extends StatefulWidget {
  const _RefreshRateRow();

  @override
  State<_RefreshRateRow> createState() => _RefreshRateRowState();
}

class _RefreshRateRowState extends State<_RefreshRateRow> {
  List<int> _rates = const [];

  @override
  void initState() {
    super.initState();
    RefreshRate.available().then((r) {
      if (mounted) setState(() => _rates = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final top = _rates.isEmpty ? null : _rates.last;
    String label(int hz) => hz == 0
        ? 'Smoothest${top == null ? '' : ' ($top Hz)'}'
        : hz <= 60
            ? '$hz Hz (saves battery)'
            : '$hz Hz';
    final options = [0, for (final r in _rates.reversed) r];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(FluentIcons.speed_high, color: p.muted, size: 18),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Screen refresh rate', style: TextStyle(color: p.text)),
            Text('Higher is smoother, lower uses less battery', style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        ComboBox<int>(
          value: options.contains(s.refreshRate) ? s.refreshRate : 0,
          items: [for (final hz in options) ComboBoxItem(value: hz, child: Text(label(hz)))],
          onChanged: (hz) {
            if (hz == null) return;
            s.refreshRate = hz;
            RefreshRate.apply(hz);
          },
        ),
      ]),
    );
  }
}
