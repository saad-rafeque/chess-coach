import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show TextCapitalization;

import '../app/settings.dart';
import '../app/theme.dart';
import '../data/event_store.dart';
import '../sync/sync_service.dart';
import '../train/skill_model.dart';
import '../widgets/board_layout.dart';
import '../widgets/board_picker.dart';
import '../widgets/common.dart';
import '../widgets/sync_settings.dart';

/// A starting level the player picks on first run: the coach's first guess at their strength.
typedef LevelChoice = ({String title, String detail, int rating});

const levelChoices = <LevelChoice>[
  (title: 'Brand new', detail: 'I\'m learning how the pieces move.', rating: 400),
  (title: 'Beginner', detail: 'I know the rules but often lose pieces.', rating: 700),
  (title: 'Casual player', detail: 'I know some tactics and openings.', rating: 1000),
  (title: 'Club player', detail: 'I play often and think a few moves ahead.', rating: 1400),
  (title: 'Strong player', detail: 'Tournaments, or 1800+ online.', rating: 1800),
];

const coachNameIdeas = ['Coach', 'Max', 'Nova', 'Sage', 'Leo', 'Mira'];

enum _Step { welcome, name, coach, level, look, sync, done }

/// First run: the player's name, the coach's name, their level, the look and (optionally) sync.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  var _step = _Step.welcome;
  var _forward = true;
  late final _name = TextEditingController(text: SettingsScope.read(context).playerName);
  late final _coach = TextEditingController(text: SettingsScope.read(context).coachName);
  int? _level;

  @override
  void dispose() {
    _name.dispose();
    _coach.dispose();
    super.dispose();
  }

  /// The steps for this build: sync only when Google sign-in is set up.
  List<_Step> get _steps => [
        for (final s in _Step.values)
          if (s != _Step.sync || SyncScope.of(context).status != SyncStatus.notSetUp) s,
      ];

  void _go(int delta) {
    final steps = _steps;
    final i = (steps.indexOf(_step) + delta).clamp(0, steps.length - 1);
    setState(() {
      _forward = delta > 0;
      _step = steps[i];
    });
  }

  Future<void> _finish() async {
    final settings = SettingsScope.read(context);
    final store = StoreScope.read(context);
    final level = _level ?? levelChoices[1].rating;
    settings
      ..playerName = _name.text
      ..coachName = _coach.text
      ..coachElo = clampCoachElo(level - 100);
    await store.add(profileEventType, {'level': level});
    settings.onboarded = true;
  }

  String get _playerName => cleanName(_name.text);
  String get _coachName => cleanName(_coach.text).isEmpty ? 'Coach' : cleanName(_coach.text);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final steps = _steps;
    final index = steps.indexOf(_step);
    final (Widget body, String action, VoidCallback? onAction) = switch (_step) {
      _Step.welcome => (_welcome(p), 'Get started', () => _go(1)),
      _Step.name => (_nameStep(p), 'Continue', () => _go(1)),
      _Step.coach => (_coachStep(p), 'Continue', () => _go(1)),
      _Step.level => (_levelStep(p), 'Continue', _level == null ? null : () => _go(1)),
      _Step.look => (_lookStep(p), 'Continue', () => _go(1)),
      _Step.sync => (_syncStep(p), 'Continue', () => _go(1)),
      _Step.done => (_doneStep(p), 'Start playing', _finish),
    };
    final mobile = isMobile(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.background, p.backgroundEnd],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 20 : 32, 12, mobile ? 20 : 32, mobile ? 16 : 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  height: 40,
                  child: Row(children: [
                    if (index > 0 && _step != _Step.done) PageBackButton(onPressed: () => _go(-1)),
                    const Spacer(),
                    _Dots(count: steps.length, index: index),
                    const Spacer(),
                    if (index > 0 && _step != _Step.done) const SizedBox(width: 40),
                  ]),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: motion(context, const Duration(milliseconds: 320)),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final incoming = child.key == ValueKey(_step);
                      final dx = (incoming == _forward ? 0.08 : -0.08);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: body,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(Palette p, String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p.text, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 15, color: p.muted, height: 1.4)),
          const SizedBox(height: 24),
        ],
      );

  Widget _welcome(Palette p) => Column(children: [
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: motion(context, const Duration(milliseconds: 700)),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: v, child: child),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: -12,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const AppLogo(size: 128),
          ),
        ),
        const SizedBox(height: 28),
        Text('Welcome to Chess Coach',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.text, letterSpacing: -0.5)),
        const SizedBox(height: 10),
        Text(
          'A coach that plays at your level, explains your mistakes and plans what to practise next.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: p.muted, height: 1.45),
        ),
        const SizedBox(height: 28),
        for (final (icon, text) in const [
          (FluentIcons.game, 'Play and get advice on every move'),
          (FluentIcons.puzzle, 'Puzzles picked for your weak spots'),
          (FluentIcons.education, 'Short lessons, from the rules up'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(icon, color: p.accent, size: 18),
                const SizedBox(width: 14),
                Expanded(child: Text(text, style: TextStyle(color: p.text))),
              ]),
            ),
          ),
      ]);

  Widget _nameStep(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(p, 'What should we call you?', 'Your coach uses it to greet you. It stays on your devices.'),
        TextBox(
          controller: _name,
          autofocus: true,
          placeholder: 'Your name',
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          style: const TextStyle(fontSize: 17),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _go(1),
        ),
      ]);

  Widget _coachStep(Palette p) {
    final hello = _playerName.isEmpty ? 'Hi!' : 'Hi $_playerName!';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(p, 'Name your coach', 'Pick any name you like. You can change it later in Settings.'),
      TextBox(
        controller: _coach,
        placeholder: 'Coach',
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        style: const TextStyle(fontSize: 17),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _go(1),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final idea in coachNameIdeas)
          ToggleButton(
            checked: _coachName == idea,
            onChanged: (_) => setState(() => _coach.text = idea),
            child: Text(idea),
          ),
      ]),
      const SizedBox(height: 24),
      CoachBubble(text: '$hello I\'m $_coachName. Let\'s play some chess and get you better at it.'),
    ]);
  }

  Widget _levelStep(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(p, 'How well do you play?',
            '$_coachName starts near your level, then adjusts after every game and puzzle.'),
        for (final c in levelChoices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              selected: _level == c.rating,
              button: true,
              child: SurfaceCard(
                highlight: _level == c.rating,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                onTap: () => setState(() => _level = c.rating),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(c.detail, style: TextStyle(color: p.muted, fontSize: 13)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Pill('~${c.rating}', color: _level == c.rating ? p.accent : p.muted),
                ]),
              ),
            ),
          ),
      ]);

  Widget _lookStep(Palette p) {
    final s = SettingsScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(p, 'Pick a look', 'Choose a theme, pieces and board. Settings has them all too.'),
      Segmented<AppTheme>(
        options: const {AppTheme.dark: 'Dark', AppTheme.light: 'Light', AppTheme.wooden: 'Wooden'},
        value: s.theme,
        onChanged: (t) => s.theme = t,
      ),
      const SizedBox(height: 16),
      const BoardPicker(),
    ]);
  }

  Widget _syncStep(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(p, 'Keep your progress safe',
            'Optional: sign in with Google to keep your phone and computer in step. You can do it later.'),
        const SyncSettings(),
      ]);

  Widget _doneStep(Palette p) => Column(children: [
        const SizedBox(height: 32),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: motion(context, const Duration(milliseconds: 600)),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: p.success.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(FluentIcons.check_mark, color: p.success, size: 44),
          ),
        ),
        const SizedBox(height: 28),
        Text(_playerName.isEmpty ? 'You\'re all set!' : 'You\'re all set, $_playerName!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p.text, letterSpacing: -0.5)),
        const SizedBox(height: 12),
        Text(
          '$_coachName is ready. Play a game first: afterwards you can go through your mistakes '
          'together and see what to do next time.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: p.muted, height: 1.45),
        ),
      ]);
}

/// Which step of the setup this is.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: motion(context, const Duration(milliseconds: 220)),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i <= index ? p.accent : p.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ]),
    );
  }
}
