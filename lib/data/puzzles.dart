/// Starter puzzles. Milestone 3 replaces these with the Lichess puzzle set.
library;

enum PuzzleGoal { mate, check }

class Puzzle {
  const Puzzle(this.fen, this.solution, this.theme, this.rating, this.goal, this.hint);

  final String fen;

  /// First move of the solution in UCI notation, e.g. `a1a8`.
  final String solution;
  final String theme;
  final int rating;
  final PuzzleGoal goal;
  final String hint;
}

const starterPuzzles = [
  Puzzle('r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4', 'h5f7',
      'Mate in 1', 500, PuzzleGoal.mate,
      'f7 is only defended by the king. Which two pieces aim at it?'),
  Puzzle('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', 'a1a8', 'Back-rank mate', 600,
      PuzzleGoal.mate, 'Black\'s own pawns trap the king on the back rank.'),
  Puzzle('7k/8/6K1/8/8/8/8/R7 w - - 0 1', 'a1a8', 'King and rook mate', 550,
      PuzzleGoal.mate, 'Your king already covers g7 and h7.'),
  Puzzle('q3k3/8/8/1N6/8/8/8/4K3 w - - 0 1', 'b5c7', 'Knight fork', 700, PuzzleGoal.check,
      'Find a square where the knight attacks the king and the queen at once.'),
];
