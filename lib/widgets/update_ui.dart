import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import '../app/updater.dart';
import '../app/version.dart';
import 'common.dart';

/// Gives widgets the app's [Updater].
class UpdateScope extends InheritedNotifier<Updater> {
  const UpdateScope({super.key, required Updater updater, required super.child}) : super(notifier: updater);

  static Updater of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<UpdateScope>()!.notifier!;
}

/// Offers a new version as soon as one is found: at every start until it's installed, unless the
/// player taps "Later" (then again on the next start).
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  Updater? _updater;
  bool _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = UpdateScope.of(context);
    if (!identical(u, _updater)) {
      _updater?.removeListener(_changed);
      _updater = u..addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    final u = _updater!;
    if (_open || u.dismissed || u.available == null || u.status == UpdateStatus.checking) return;
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => UpdateDialog(updater: u));
      u.dismissed = true;
      _open = false;
    });
  }

  @override
  void dispose() {
    _updater?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Update available" with what's new, the download progress and any error.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.updater});

  final Updater updater;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final r = updater.available;
        if (r == null) return const SizedBox.shrink();
        final busy = updater.status == UpdateStatus.downloading || updater.status == UpdateStatus.installing;
        return ContentDialog(
          title: const Text('Update available'),
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chess Coach ${r.version} is ready. You have $appVersion.', style: TextStyle(color: p.text)),
            const SizedBox(height: 12),
            if (r.notes.isNotEmpty)
              Flexible(child: SingleChildScrollView(child: ReleaseNotes(r.notes))),
            if (busy) ...[
              const SizedBox(height: 16),
              ProgressBar(value: updater.status == UpdateStatus.installing ? null : updater.progress * 100),
              const SizedBox(height: 6),
              Text(
                updater.status == UpdateStatus.installing
                    ? 'Installing…'
                    : 'Downloading… ${(updater.progress * 100).round()}%',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ],
            if (updater.error != null) ...[
              const SizedBox(height: 12),
              Text(updater.error!, style: TextStyle(color: p.danger)),
            ],
          ]),
          actions: [
            Button(onPressed: busy ? null : () => Navigator.of(context).pop(), child: const Text('Later')),
            FilledButton(
              onPressed: busy ? null : updater.install,
              child: Text(r.asset == null ? 'Open download page' : 'Update now'),
            ),
          ],
        );
      },
    );
  }
}

/// Release notes from GitHub (Markdown), shown as plain headings and bullets.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    String clean(String s) => s.replaceAll(RegExp(r'\*\*|__|`'), '').replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!);
    final lines = [for (final l in markdown.split('\n')) if (l.trim().isNotEmpty) l.trimRight()];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final l in lines.take(40))
        if (l.startsWith('#'))
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(clean(l.replaceFirst(RegExp(r'^#+\s*'), '')),
                style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(clean(l.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ')),
                style: TextStyle(color: p.muted, height: 1.35)),
          ),
    ]);
  }
}

/// Settings card: the installed version and a manual check.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final u = UpdateScope.of(context);
    final r = u.available;
    final status = switch (u.status) {
      UpdateStatus.checking => 'Checking…',
      UpdateStatus.downloading => 'Downloading ${(u.progress * 100).round()}%…',
      UpdateStatus.installing => 'Installing…',
      _ => r != null ? 'Version ${r.version} is available.' : 'You have the latest version.',
    };
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(FluentIcons.download, color: p.muted, size: 18),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chess Coach $appVersion', style: TextStyle(color: p.text)),
            Text(u.error ?? status, style: TextStyle(color: u.error != null ? p.danger : p.muted, fontSize: 12)),
          ]),
        ),
        if (r != null)
          FilledButton(
            onPressed: () => showDialog<void>(context: context, builder: (_) => UpdateDialog(updater: u)),
            child: const Text('Update'),
          )
        else
          Button(
            onPressed: u.status == UpdateStatus.checking ? null : () => u.check(force: true),
            child: const Text('Check for updates'),
          ),
      ]),
    );
  }
}
