import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/train/skill_model.dart';
import 'package:fluent_ui/fluent_ui.dart' show Size, TextBox;
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, size) in [('desktop', const Size(1400, 900)), ('phone', const Size(390, 800))]) {
    testWidgets('first start asks for names and level, then opens the app ($name)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings.memory()..onboarded = false;
      final store = EventStore.memory();
      await tester.pumpWidget(ChessCoachApp(settings: settings, store: store));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Chess Coach'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextBox), '  Saad\n');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Name your coach'), findsOneWidget);
      await tester.tap(find.text('Nova'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hi Saad! I\'m Nova.'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('How well do you play?'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('How well do you play?'), findsOneWidget, reason: 'a level must be picked first');
      await tester.tap(find.text('Casual player'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Pick a look'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      // Sync is skipped: this build has no Google sign-in.
      expect(find.text('You\'re all set, Saad!'), findsOneWidget);
      await tester.tap(find.text('Start playing'));
      await tester.pumpAndSettle();

      expect(settings.onboarded, isTrue);
      expect(settings.playerName, 'Saad');
      expect(settings.coachName, 'Nova');
      expect(settings.coachElo, 900);
      expect(store.ofType(profileEventType).single.data, {'level': 1000});
      expect(find.textContaining(', Saad'), findsOneWidget, reason: 'the home page greets the player');
      expect(find.text('Tip from Nova'), findsOneWidget);
    });
  }

  test('the chosen level is where the skill model starts', () async {
    final store = EventStore.memory();
    final before = SkillModel.fromEvents(store.events).recommendedCoachElo;
    await store.add(profileEventType, {'level': 1800});
    final after = SkillModel.fromEvents(store.events).recommendedCoachElo;
    expect(after, greaterThan(before + 500));
  });

  test('names are cleaned and synced', () {
    final a = AppSettings.memory()
      ..playerName = ' Saad\n\tRafique  '
      ..coachName = 'x' * 40;
    expect(a.playerName, 'Saad Rafique');
    expect(a.coachName.length, 24);
    final b = AppSettings.memory()..applySync(a.toSyncJson(), DateTime.now().add(const Duration(minutes: 1)));
    expect(b.playerName, 'Saad Rafique');
    expect(b.coachName, a.coachName);
    expect(AppSettings.memory().coachName, 'Coach');
  });
}
