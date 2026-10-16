/// Placeholder profile shown until the personal-learning model (milestone 5) exists.
library;

class Skill {
  const Skill(this.name, this.value);

  final String name;

  /// 0..1 on the path to the 2000 target.
  final double value;
}

class SessionOption {
  const SessionOption(this.label, this.minutes, this.plan);

  final String label;
  final int minutes;
  final String plan;
}

const sampleRating = 750;
const samplePuzzleStreak = 4;

const sampleSkills = [
  Skill('Tactics', 0.32),
  Skill('Openings', 0.24),
  Skill('Middlegame', 0.18),
  Skill('Endgames', 0.28),
  Skill('Blunder check', 0.40),
];

const sessionOptions = [
  SessionOption('2 min', 2, '3 quick puzzles'),
  SessionOption('15 min', 15, 'Puzzles, 1 old mistake, short lesson'),
  SessionOption('1 hour', 60, 'Training game, review, targeted puzzles'),
  SessionOption('2 h+', 120, 'Lesson, 2 games, deep review, endgame drill'),
];

const tipsOfTheDay = [
  'Before every move, ask: what is my opponent threatening?',
  'Knights before bishops: develop the knights first in most openings.',
  'In the endgame your king is a fighting piece. Bring it to the centre.',
  'Count attackers and defenders before you capture.',
];
