import 'package:fluent_ui/fluent_ui.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../coach/llm/coach_voice.dart';
import '../coach/llm/model_store.dart';
import 'common.dart';

/// Settings card for the optional on-device language model.
class VoiceSettings extends StatelessWidget {
  const VoiceSettings({super.key});

  static const sample = 'Now Black can take your bishop on c4. Better was Nf3.';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final voice = VoiceScope.of(context);
    final models = voice.models;
    return ListenableBuilder(
      listenable: models,
      builder: (context, _) {
        final chosen = voice.model;
        final status = models.status(chosen);
        return SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(FluentIcons.robot, color: p.accent, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Friendly explanations', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
                  Text(
                      'A small language model on this device rewords the coach\'s explanations in plain English. '
                      'The chess facts always come from Stockfish; the model only rephrases them, and anything it '
                      'adds is thrown away. Without it the coach uses its standard sentences.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            RadioGroup<String>(
              groupValue: chosen.id,
              onChanged: (id) {
                if (id == null || models.busy) return;
                s.voiceModel = id;
                voice.reset();
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final m in explainerModels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioButton<String>(
                      value: m.id,
                      enabled: !models.busy,
                      content: Text(
                          '${m.name} · ${m.sizeLabel} · ${m.detail}'
                          '${models.status(m) == ModelStatus.ready ? ' · downloaded' : ''}',
                          style: TextStyle(color: p.text)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            ...switch (status) {
              ModelStatus.absent || ModelStatus.failed => [
                  if (status == ModelStatus.failed) ...[
                    Text(models.error(chosen) ?? 'Download failed.', style: TextStyle(color: p.danger, fontSize: 12)),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: models.busy ? null : () => models.download(chosen),
                    child: Text('Download ${chosen.sizeLabel}'),
                  ),
                  const SizedBox(height: 6),
                  Text('Use Wi-Fi: the file is large. A stopped download continues where it left off.',
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ModelStatus.downloading => [
                  ProgressBar(value: models.progress(chosen) * 100),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Text('Downloading… ${(models.progress(chosen) * 100).toStringAsFixed(0)}%',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                    Button(onPressed: models.cancel, child: const Text('Stop')),
                  ]),
                ],
              ModelStatus.verifying => [
                  Row(children: [
                    const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text('Checking the file…', style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                ],
              ModelStatus.ready => [
                  Row(children: [
                    Expanded(child: Text('Use friendly explanations', style: TextStyle(color: p.text))),
                    ToggleSwitch(checked: s.friendlyVoice, onChanged: (v) => s.friendlyVoice = v),
                  ]),
                  if (voice.failed) ...[
                    const SizedBox(height: 6),
                    Text('The model could not start on this device, so the coach keeps its standard sentences.',
                        style: TextStyle(color: p.warning, fontSize: 12)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Button(
                      onPressed: s.friendlyVoice && !voice.failed ? () => _tryIt(context, voice) : null,
                      child: const Text('Try it'),
                    ),
                    Button(
                      onPressed: () async {
                        await voice.unload();
                        await models.delete(chosen);
                        voice.reset();
                      },
                      child: const Text('Delete model'),
                    ),
                  ]),
                ],
            },
          ]),
        );
      },
    );
  }

  Future<void> _tryIt(BuildContext context, CoachVoice voice) => showDialog<void>(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('Friendly explanations'),
          content: FutureBuilder<String?>(
            future: voice.polish(sample),
            builder: (context, snap) {
              final p = Palette.of(context);
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Standard', style: TextStyle(color: p.muted, fontSize: 12)),
                const Text(sample),
                const SizedBox(height: 12),
                Text('Friendly', style: TextStyle(color: p.muted, fontSize: 12)),
                if (snap.connectionState != ConnectionState.done)
                  const Row(children: [
                    SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Thinking… (the first time takes a few seconds)'),
                  ])
                else
                  Text(snap.data ?? 'No safe answer this time, so the standard sentence would be used.'),
              ]);
            },
          ),
          actions: [FilledButton(child: const Text('Close'), onPressed: () => Navigator.pop(context))],
        ),
      );
}
