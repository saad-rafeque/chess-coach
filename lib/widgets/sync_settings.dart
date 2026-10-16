import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import '../sync/sync_service.dart';
import 'common.dart';

/// "just now", "5 min ago"...
String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

/// Settings card for Google Drive sync.
class SyncSettings extends StatelessWidget {
  const SyncSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = SyncScope.of(context);
    final status = sync.status;
    final last = sync.lastSync;
    final (detail, color) = switch (status) {
      SyncStatus.notSetUp => (
          'Keeps your phone, Windows and Ubuntu in step. This build has no Google sign-in set up yet '
              '(see docs/google-drive-sync.md).',
          p.muted
        ),
      SyncStatus.signedOut => (
          'Keeps your phone, Windows and Ubuntu in step through one small file in a hidden app folder of your '
              'Google Drive. It syncs only when the app opens or closes, so it doesn\'t drain the battery.',
          p.muted
        ),
      SyncStatus.signingIn => ('Sign in with Google in your browser, then come back here.', p.accent),
      SyncStatus.syncing => ('Syncing…', p.accent),
      SyncStatus.offline => ('No connection. Your data is safe on this device and syncs when you\'re back online.', p.warning),
      SyncStatus.error => (sync.error ?? 'Sync failed.', p.danger),
      SyncStatus.idle => (last == null ? 'Connected.' : 'Connected · last synced ${_ago(last.toLocal())}', p.success),
    };
    return SurfaceCard(
      child: Row(children: [
        Icon(FluentIcons.cloud, color: p.accent, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Google Drive sync', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
            Text(detail, style: TextStyle(color: color, fontSize: 12, height: 1.4)),
            if (status == SyncStatus.error && !sync.connected && sync.error != null) const SizedBox(height: 2),
          ]),
        ),
        const SizedBox(width: 12),
        Wrap(spacing: 8, runSpacing: 8, children: switch (status) {
          SyncStatus.notSetUp => [const Button(onPressed: null, child: Text('Connect'))],
          SyncStatus.signedOut => [FilledButton(onPressed: sync.connect, child: const Text('Connect'))],
          SyncStatus.signingIn => [Button(onPressed: sync.cancelSignIn, child: const Text('Cancel'))],
          SyncStatus.syncing => [const SizedBox(width: 18, height: 18, child: ProgressRing(strokeWidth: 2))],
          _ => [
              if (sync.connected) Button(onPressed: sync.sync, child: const Text('Sync now')),
              if (sync.connected)
                Button(onPressed: sync.disconnect, child: const Text('Disconnect'))
              else
                FilledButton(onPressed: sync.connect, child: const Text('Connect')),
            ],
        }),
      ]),
    );
  }
}

/// Small "Sync now" button for page headers; shows the sync state and syncs on tap.
/// Hidden while sync isn't set up or connected.
class SyncChip extends StatelessWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sync = SyncScope.of(context);
    final status = sync.status;
    if (status == SyncStatus.notSetUp || status == SyncStatus.signedOut || status == SyncStatus.signingIn) {
      return const SizedBox.shrink();
    }
    final last = sync.lastSync;
    final (icon, label, color) = switch (status) {
      SyncStatus.syncing => (FluentIcons.sync, 'Syncing…', p.accent),
      SyncStatus.offline => (FluentIcons.cloud_not_synced, 'Offline', p.warning),
      SyncStatus.error => (FluentIcons.cloud_not_synced, 'Sync problem', p.danger),
      _ => (
          FluentIcons.cloud,
          last == null ? 'Sync now' : 'Synced ${_ago(last.toLocal())}',
          p.success
        ),
    };
    final compact = isMobile(context);
    return Tooltip(
      message: status == SyncStatus.error ? (sync.error ?? 'Sync now') : 'Sync now',
      child: Button(
        onPressed: status == SyncStatus.syncing ? null : sync.sync,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (status == SyncStatus.syncing)
            const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
          else
            Icon(icon, size: 14, color: color, semanticLabel: label),
          if (!compact) ...[const SizedBox(width: 8), Text(label)],
        ]),
      ),
    );
  }
}
