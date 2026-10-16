// Endgame lessons: basic mates, pawn endings, rook endings and converting an
// advantage. Puzzle positions come from the Lichess puzzle database (CC0); every
// "find" step is checked with Stockfish by tool/verify_lessons_test.dart.
import '../../data/curriculum.dart';
import '../lesson.dart';

const endgameLessons = [
  Lesson('basic-mates', 'Mate with queen and rook', 'The essential checkmates.', 800, Area.endgames, [
    LessonStep.show(
        'The ladder mate: one rook cuts off a rank, the other gives check on the next one. The rooks take turns '
        'until the king is pushed to the edge.',
        fen: '4k3/8/8/8/8/8/R7/1R4K1 w - - 0 1',
        demo: 'Ra7 Kd8 Rb8#'),
    LessonStep.find('Mate in one with the two rooks.',
        fen: '6k1/R7/8/8/8/8/8/1R4K1 w - - 0 1',
        solution: 'Rb8#',
        hint: 'The rook on a7 already guards the seventh rank.',
        success: 'Checkmate: one rook guards the seventh rank, the other checks on the eighth.'),
    LessonStep.show(
        'King and queen against king: use the queen to shrink the king\'s box (a knight\'s jump away from the '
        'king works well), then bring your own king closer. Mate happens on the edge, with your king guarding '
        'the escape squares. Never leave the lone king without a move unless it is in check: that is stalemate, '
        'a draw.',
        fen: '8/8/8/3k4/8/8/8/Q3K3 w - - 0 1',
        arrows: 'a1a5 e1e4'),
    LessonStep.find('Mate in one. Your king guards the squares next to Black\'s king.',
        fen: '7k/8/6K1/8/8/8/8/1Q6 w - - 0 1',
        solution: 'Qb8#',
        hint: 'Check along the back rank.',
        success: 'Checkmate. The queen covers the eighth rank and your king covers g7 and h7.'),
    LessonStep.find('Mate in one again. Careful: Qg6?? would be stalemate, a draw!',
        fen: '7k/8/5K2/8/8/8/8/6Q1 w - - 0 1',
        solution: 'Qg7#',
        hint: 'Put the queen right next to Black\'s king, protected by your king.',
        success: 'Checkmate. The king can\'t take the queen because your king protects it.'),
    LessonStep.find(
        'King and rook: the rook checks along the edge while your king takes away the escape squares. Mate in one.',
        fen: 'k7/8/1K6/8/8/8/8/7R w - - 0 1',
        solution: 'Rh8#',
        hint: 'Your king already covers a7 and b7.',
        success: 'Checkmate on the back rank.'),
  ]),
  Lesson('opposition', 'King and pawn: opposition', 'The key idea in pawn endings.', 1000, Area.endgames, [
    LessonStep.show(
        'Kings can never stand next to each other. When they face each other with one square between them, the '
        'side that does NOT have to move "has the opposition": the other king must give way. Here Black is to '
        'move and must let White\'s king forward.',
        fen: '8/8/4k3/8/4K3/4P3/8/8 b - - 0 1',
        circles: 'e4 e6'),
    LessonStep.show(
        'Key squares: with the pawn on e4, the squares d6, e6 and f6 are key. If your king reaches one of them, '
        'the pawn queens whatever the defender does.',
        fen: '4k3/8/8/8/4P3/8/8/4K3 w - - 0 1',
        circles: 'd6 e6 f6'),
    LessonStep.find('White to move. Take the opposition!',
        fen: '8/8/4k3/8/3K4/4P3/8/8 w - - 0 1',
        solution: 'Ke4',
        hint: 'Put your king directly opposite Black\'s, with one square between them.',
        success: 'Now Black must give way, and your king walks forward to a key square.'),
    LessonStep.find('Your king is in front of the pawn. Take the opposition again.',
        fen: '8/4k3/8/3K4/4P3/8/8/8 w - - 0 1',
        solution: 'Ke5',
        hint: 'Kings on e5 and e7, Black to move.',
        success: 'Black must step aside and your king reaches d6 or f6.'),
    LessonStep.find('Head straight for a key square in front of the pawn.',
        fen: '4k3/8/8/2K5/4P3/8/8/8 w - - 0 1',
        solution: 'Kd6',
        hint: 'd6, e6 and f6 are the key squares.',
        success: 'From d6 your king escorts the pawn: e5, e6, e7 and e8 can\'t be stopped.'),
    LessonStep.find('Now you defend with Black. Take the opposition and the game is a draw.',
        fen: '8/4k3/8/8/4K3/4P3/8/8 b - - 0 1',
        solution: 'Ke6',
        hint: 'Face White\'s king with one square between you.',
        success: 'Every other move loses. With the opposition you keep White\'s king away from the key squares.'),
  ]),
  Lesson('square-rule', 'The square of the pawn', 'Can the king catch it?', 1000, Area.endgames, [
    LessonStep.show(
        'The square of the pawn: draw a square from the pawn to its queening square, here a4–a8–e8–e4. If the '
        'defending king can step inside it, it catches the pawn. When the pawn moves, the square shrinks.',
        fen: '8/8/8/5k2/P7/8/8/7K w - - 0 1',
        circles: 'a4 a8 e8 e4'),
    LessonStep.find('White to move. Push the pawn and see whether Black\'s king can still get into the square.',
        fen: '8/8/8/5k2/P7/8/8/7K w - - 0 1',
        solution: 'a5',
        hint: 'Only the pawn can win the race.',
        success: 'After a5 the square is a5–a8–d8–d5. Black\'s king on f5 can\'t get in, so the pawn queens.'),
    LessonStep.find('Black to move. Step into the square of the a-pawn and you will catch it.',
        fen: '8/8/8/8/P7/5k2/8/7K b - - 0 1',
        solution: 'Ke4',
        hint: 'The square runs from a4 to e8. Which of its squares can your king reach?',
        success: 'e4 is a corner of the square. Next Kd5, Kc6, Kb7 and the pawn falls.'),
    LessonStep.show(
        'Careful: a pawn on its starting square can jump two squares at once, so draw its square from one rank '
        'further (here a3–a8–f8–f3). And if the king\'s path is blocked by its own pieces, the rule doesn\'t help.',
        fen: '8/8/8/4k3/8/8/P7/7K w - - 0 1',
        circles: 'a3 a8 f8 f3'),
    LessonStep.find(
        'Réti\'s famous study. Your king looks too far from Black\'s h-pawn, and your c-pawn is about to fall. '
        'Walk diagonally: chase the pawn and support your own at the same time!',
        fen: '7K/8/k1P5/7p/8/8/8/8 w - - 0 1',
        solution: 'Kg7 h4 Kf6',
        hint: 'A diagonal king walk is as fast as a straight one.',
        success: 'Now if 2...h3 3.Ke7 h2 4.c7 and both sides queen; if 2...Kb6 3.Ke5 Kxc6 4.Kf4 catches the pawn. '
            'A draw from nowhere!'),
  ]),
  Lesson('rook-endings', 'Rook endings: Lucena and Philidor', 'The two positions every player must know.', 1500,
      Area.endgames, [
    LessonStep.show(
        'The Philidor defence: when your king stands in front of the pawn, keep your rook on your third rank '
        '(here the sixth). White\'s king can\'t come forward without being checked from the side.',
        fen: '4k3/7R/1r6/3KP3/8/8/8/8 w - - 0 1',
        flip: true,
        arrows: 'b6g6'),
    LessonStep.find('You are Black. Hold the draw: put your rook on the sixth rank.',
        fen: '4k3/7R/8/3KP3/8/8/8/1r6 b - - 0 1',
        solution: 'Rb6',
        hint: 'Your rook keeps White\'s king off the sixth rank.',
        success: 'White\'s king can\'t advance. If White pushes e6, your rook drops back to check from behind.'),
    LessonStep.find(
        'White pushed the pawn to e6, so White\'s king has no shelter from checks any more. Drop your rook all the '
        'way back to your first rank.',
        fen: '4k3/7R/1r2P3/3K4/8/8/8/8 b - - 0 1',
        solution: 'Rb1',
        hint: 'From far away the rook can check forever.',
        success: 'From b1 the rook checks White\'s king from behind again and again. A draw.'),
    LessonStep.show(
        'The Lucena position: your pawn on the seventh, your king in front of it, Black\'s king cut off. Win by '
        'building a bridge: Rd1+, then Rd4, then walk your king out. The rook on the fourth rank blocks the checks.',
        fen: '1K6/1P1k4/8/8/8/8/r7/2R5 w - - 0 1',
        demo: 'Rd1+ Ke7 Rd4 Ra1 Kc7 Rc1+ Kb6 Rb1+ Kc6 Rc1+ Kb5 Rb1+ Rb4'),
    LessonStep.find(
        'Your turn: first push Black\'s king one more file away with a check, then put your rook on the fourth '
        'rank.',
        fen: '1K6/1P1k4/8/8/8/8/r7/2R5 w - - 0 1',
        solution: 'Rd1+ Ke7 Rd4',
        hint: 'Check on the d-file.',
        success: 'The bridge is ready. Your king steps out and the rook blocks the checks on b4.'),
    LessonStep.show(
        'Rook endings in one sentence: rooks belong behind passed pawns, yours or your opponent\'s, and an active '
        'rook is often worth a pawn.',
        fen: '8/5pk1/6p1/P7/8/6P1/5PK1/R7 w - - 0 1',
        arrows: 'a1a4'),
  ]),
  Lesson('bishop-vs-knight', 'Bishop versus knight', 'Which minor piece wins, and when.', 1700, Area.endgames, [
    LessonStep.show(
        'A bad bishop: Black\'s pawns on c5, d6 and e5 stand on the bishop\'s colour and block it, while White\'s '
        'knight attacks them from d3. With pawns fixed on one colour, the knight is often better. Bishops shine '
        'in open positions with pawns on both wings, because they cross the board in one move.',
        fen: '4k3/8/3p1b2/2pPp3/2P1P3/3NK3/8/8 w - - 0 1',
        arrows: 'd3c5 d3e5'),
    LessonStep.find(
        'You are Black. White\'s bishop runs on light squares, but your c-pawn would queen on c1, a dark square. '
        'Break through with your pawns!',
        fen: '4B3/8/1k4Kp/p5p1/1pp5/P7/1P5P/8 w - - 0 39',
        line: 'a3a4',
        solution: 'c4c3 b2c3 b4c3 e8d7 c3c2',
        hint: 'Push the c-pawn first.',
        success: 'The bishop can never control c1. Bishops are helpless against a pawn that queens on the other '
            'colour.'),
    LessonStep.find(
        'You are Black. Knights can fork, bishops can\'t jump. White\'s bishop just took on e5: find the fork.',
        fen: '2k5/1p3p2/1K3n2/7p/1P3B1P/P4P2/8/8 w - - 1 47',
        line: 'f4e5',
        solution: 'f6d7 b6b5 d7e5',
        hint: 'A knight check that also hits e5.',
        success: 'The knight checks the king and attacks the bishop, which falls next.'),
    LessonStep.find(
        'Push your passed pawn! If the bishop takes it, your knight takes the bishop and you have a knight '
        'against pawns.',
        fen: '8/7p/2bP1Np1/5p2/pk3P2/6P1/2K5/8 b - - 1 48',
        line: 'b4c4',
        solution: 'd6d7 c6d7 f6d7',
        hint: 'The pawn on d6 is one step from d7.',
        success: 'Black had to give up the bishop for the pawn.'),
    LessonStep.find(
        'Black\'s bishop just grabbed your d5 pawn. Take it with the knight, then march your king to win the f4 '
        'pawn: the pawn ending is yours.',
        fen: '8/p1N2b2/1p6/1P1Pk3/P4p2/5P1K/8/8 b - - 1 48',
        line: 'f7d5',
        solution: 'c7d5 e5d5 h3g4',
        hint: 'Capture on d5 first.',
        success: 'Your king takes f4 next and the f-pawn runs. Trading into a won pawn ending is the simplest way '
            'to win.'),
  ]),
  Lesson('converting', 'Converting an advantage', 'Win "won" positions without stress.', 1900, Area.endgames, [
    LessonStep.show(
        'When you are ahead: 1) trade pieces, not pawns; 2) keep your king safe, then make it active; 3) create a '
        'passed pawn and push it; 4) take away your opponent\'s counterplay first. Don\'t rush, but don\'t drift.',
        fen: '8/4b2k/3p2p1/1P1Pp2p/K1N1Pp2/5P2/5P2/8 w - - 0 1',
        arrows: 'b5b8'),
    LessonStep.find(
        'Trade the last pieces: Nf5+ forks king and knight, and the pawn ending is easily won.',
        fen: '8/3k4/2P4n/6p1/3NKp2/8/6P1/8 b - - 0 47',
        line: 'd7d6',
        solution: 'd4f5 h6f5 e4f5',
        hint: 'Your knight can check from f5.',
        success: 'Black\'s king must watch your c-pawn while your king eats the kingside pawns.'),
    LessonStep.find(
        'Black\'s knight came to e6. Trade your bishop for it and walk into the d4 pawn.',
        fen: '2B2n2/8/6p1/1p1k2P1/p2p1K2/P2P4/1P6/8 b - - 3 41',
        line: 'f8e6',
        solution: 'c8e6 d5e6 f4e4 e6d6 e4d4',
        hint: 'Capture on e6 with check.',
        success: 'Your king is in front of everything and the pawn ending is winning.'),
    LessonStep.find(
        'Black\'s c-pawn is one step from queening. Stop it with your king first; then your own g-pawn runs.',
        fen: '8/pp6/8/6P1/1k6/2p1K3/8/8 b - - 0 47',
        line: 'c3c2',
        solution: 'e3d2 c2c1q d2c1 b4c5 g5g6',
        hint: 'Your king must reach c1 in time.',
        success: 'Black\'s king is too far from your g-pawn. Counterplay first, then your own plan.'),
    LessonStep.find('Push your passed pawn all the way: it queens first.',
        fen: '8/4b2k/3p2p1/1P1Pp2p/K1N1Pp2/5P2/5P2/8 b - - 0 52',
        line: 'h5h4',
        solution: 'b5b6 h4h3 b6b7 h3h2 b7b8q',
        hint: 'One step at a time: b6, b7, b8.',
        success: 'Your passed pawn was faster. Count the moves in races like this.'),
    LessonStep.find('Trade rooks: the pawn ending after Kxd4 is winning for you.',
        fen: '8/3r4/pR2k1p1/P4p1p/3p1P1P/3K2P1/8/8 b - - 2 41',
        line: 'd7d6',
        solution: 'b6d6 e6d6 d3d4',
        hint: 'Capture on d6 with check.',
        success: 'Your king wins the d4 pawn and soon the a6 pawn too. A rook trade turned an edge into a win.'),
  ]),
];
