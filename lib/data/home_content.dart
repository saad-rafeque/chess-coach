/// Fixed text and choices shown on Home.
library;

import 'curriculum.dart';

class SessionOption {
  const SessionOption(this.label, this.minutes);

  final String label;
  final int minutes;
}

const sessionOptions = [
  SessionOption('2 min', 2),
  SessionOption('15 min', 15),
  SessionOption('1 hour', 60),
  SessionOption('2 h+', 120),
];

/// Coach tips by skill area; Home shows one for your weakest area.
const tipsByArea = {
  Area.tactics: [
    'Look for checks, captures and threats first, for both sides.',
    'Two pieces on the same line? Look for a pin or a skewer.',
    'A loose piece is a target: forks love undefended pieces.',
  ],
  Area.openings: [
    'Knights before bishops: develop the knights first in most openings.',
    'Castle early. A king in the centre is a target.',
    'Don\'t move the same piece twice in the opening without a good reason.',
  ],
  Area.middlegame: [
    'Find your worst piece and improve it.',
    'Rooks belong on open files.',
    'Before you attack, count attackers and defenders.',
  ],
  Area.endgames: [
    'In the endgame your king is a fighting piece. Bring it to the centre.',
    'Passed pawns must be pushed.',
    'When you are ahead, trade pieces, not pawns.',
  ],
  Area.blunders: [
    'Before every move, ask: what is my opponent threatening?',
    'After choosing a move, check that it leaves nothing undefended.',
    'Count attackers and defenders before you capture.',
  ],
};
