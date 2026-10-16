// Middlegame lessons: blunder check, tactics and plans. Puzzle positions come from
// the Lichess puzzle database (CC0); every "find" step is checked with Stockfish
// by tool/verify_lessons_test.dart.
import '../../data/curriculum.dart';
import '../lesson.dart';

const middlegameLessons = [
  Lesson('blunder-check', 'Blunder check', 'Before every move: checks, captures, threats.', 800, Area.tactics, [
    LessonStep.show(
        'Before every move, ask two questions. What does my opponent\'s last move threaten? And does my move '
        'leave anything undefended? Here White\'s 4.Ng5 threatens Nxf7, forking Black\'s queen and rook.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5',
        arrows: 'g5f7 c4f7',
        circles: 'd8 h8'),
    LessonStep.find(
        'You are Black. Stop the threat: strike in the centre with a pawn that also blocks the bishop\'s attack '
        'on f7.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5',
        solution: 'd5',
        hint: 'A central pawn move cuts the line from c4 to f7.',
        success: 'Now 5.exd5 is the main line, and f7 is safe for the moment.'),
    LessonStep.find(
        'Black just took your knight with 3...fxe5?. Before you take anything back, look at checks: one of them '
        'wins material.',
        line: 'e4 e5 Nf3 f6 Nxe5 fxe5',
        solution: 'Qh5+ g6 Qxe5+',
        hint: 'Black\'s f-pawn is gone, so the diagonal from h5 to e8 is open.',
        success: 'Fork! The queen checks the king and attacks the rook on h8 at the same time.'),
    LessonStep.find(
        'You are Black. White threatens Qxf7 checkmate and also Qxe5+. Defend both with your queen, keeping '
        'f6 free for your knight.',
        line: 'e4 e5 Bc4 Bc5 Qh5',
        solution: 'Qe7',
        hint: 'One queen move guards f7 and e5 at once.',
        success: '3...g6?? would have lost to 4.Qxe5+, forking king and rook. Always check what your move '
            'leaves undefended.'),
    LessonStep.find(
        'Black attacked your queen with ...Rg8. Don\'t just run away with it: first check what Black left '
        'undefended.',
        fen: '1k2r3/1p6/4p3/p3P2p/P7/5q2/1P1p2Q1/6RK b - - 3 45',
        line: 'e8g8',
        solution: 'g2f3 g8g1 h1g1',
        hint: 'Black\'s queen has no defender.',
        success: 'You won a whole queen. Your queen on f3 also stops the d-pawn from queening.'),
    LessonStep.find(
        'Black\'s last move ...Nf6 left two pawns weak: f7 and b7. Find the queen move that attacks both.',
        line: 'e4 e5 Nf3 d6 d4 Bg4 dxe5 Bxf3 Qxf3 dxe5 Bc4 Nf6',
        solution: 'Qb3',
        hint: 'Your queen and bishop can team up against f7.',
        success: 'Morphy played this in 1858. Black can\'t protect b7 and f7 at the same time.',
        arrows: 'b3b7 b3f7'),
    LessonStep.show(
        'Your blunder check, every single move: 1) What changed after my opponent\'s move? 2) Their checks, '
        'captures and threats. 3) My checks, captures and threats. 4) After my move, is anything left '
        'undefended? It takes ten seconds and saves most games under 1200.'),
  ]),
  Lesson('forks-pins-skewers', 'Forks, pins and skewers', 'The three tactics that win most games.', 900,
      Area.tactics, [
    LessonStep.show(
        'A fork attacks two things at once. Knights are the best forkers, because nothing can block them. '
        'Watch: Nc7+ checks the king and attacks the bishop on e8.',
        fen: '4b3/8/Pk3P2/3N4/1KpP3p/8/8/8 b - - 0 49',
        line: 'b6a6',
        demo: 'd5c7 a6b7 c7e8'),
    LessonStep.find('Black\'s bishop just went to e5. Find a knight check that also attacks it.',
        fen: '7k/6b1/3N4/2p3Pp/5p1P/8/4K3/8 b - - 1 64',
        line: 'g7e5',
        solution: 'd6f7 h8g7 f7e5',
        hint: 'Which knight jump checks the king on h8?',
        success: 'Check plus attack: the king must move and the bishop falls.'),
    LessonStep.find(
        'Pawns fork too. You are Black: you gave up a knight with 4...Nxe4 and White took it. Win the piece '
        'back with a pawn fork.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6 Nc3 Nxe4 Nxe4',
        solution: 'd5',
        hint: 'One pawn can attack the bishop on c4 and the knight on e4.',
        success: 'The "fork trick": you win back the piece and get a fine pawn centre.',
        arrows: 'd5c4 d5e4'),
    LessonStep.show(
        'A pin: a piece can\'t move without exposing something more valuable behind it. Here Black\'s knight on '
        'f6 is pinned to the queen. A pin against the king is absolute: the pinned piece may not move at all.',
        line: 'd4 d5 c4 e6 Nc3 Nf6 Bg5',
        arrows: 'g5d8',
        circles: 'f6'),
    LessonStep.find(
        'You are Black. White\'s queen pins your rook to your king, but the queen stands on the same diagonal as '
        'its own king. Pin it back with your bishop!',
        fen: '8/4b1k1/5r2/5Q2/6P1/6K1/5P2/8 w - - 3 44',
        line: 'f5e5',
        solution: 'e7d6 e5d6 f6d6',
        hint: 'Look at the diagonal from your bishop to White\'s king on g3.',
        success: 'The queen is pinned to its king, so White has to give it up for your bishop.'),
    LessonStep.find(
        'Black just took your queen on f8. Pin Black\'s queen to its king with your rook, then collect it.',
        fen: 'q4Qk1/7p/6p1/p7/1p6/1P2R2P/P1P2P2/4R1Kb b - - 0 30',
        line: 'a8f8',
        solution: 'e3e8 h1c6 e8f8',
        hint: 'The e-file leads straight to the eighth rank.',
        success: 'The pinned queen is lost, and your second rook backs up the first.'),
    LessonStep.find(
        'A skewer is a pin in reverse: the more valuable piece stands in front, and when it moves the piece behind '
        'it falls. Black just took your rook on b8. Take back with check and look along the back rank.',
        fen: 'rR2k2r/5ppp/4p3/2np4/8/2P5/P4PPP/1R4K1 b k - 1 24',
        line: 'a8b8',
        solution: 'b1b8 e8e7 b8h8',
        hint: 'Recapture on b8: it is check.',
        success: 'The king had to step aside and the rook on h8 fell.'),
  ]),
  Lesson('discovered-attacks', 'Discovered attacks', 'Move one piece, attack with another.', 1100, Area.tactics, [
    LessonStep.show(
        'A discovered attack: one piece moves away and uncovers an attack by the piece behind it. When the moving '
        'piece gives check, the opponent has no time to save the other piece. Here Bh7+ uncovers the rook on d1.',
        fen: '3r2k1/5pb1/p2Np2p/1p4p1/2p5/P1PB4/1P3P2/3RK3 b - - 0 31',
        line: 'd8d6',
        demo: 'd3h7 g8h7 d1d6'),
    LessonStep.find(
        'Black\'s king just took on f7. Your bishop stands between your rook and Black\'s rook on d2. Move it '
        'with check!',
        fen: '8/2p1kP2/1pP5/pP2p1p1/P4pP1/5P1b/3rBR1P/7K b - - 2 34',
        line: 'e7f7',
        solution: 'e2c4 f7f6 f2d2',
        hint: 'Which bishop move gives check to the king on f7?',
        success: 'The check forces the king to move, and your rook takes the rook on d2.'),
    LessonStep.find(
        'Black offered a queen trade with ...Qh5, but your rook on g4 stands between your queen and Black\'s. '
        'Move the rook with check, even if it can be taken.',
        fen: '1r2r1k1/pp3pp1/2p3qp/2Pp4/6R1/4P3/P3QPPP/5RK1 b - - 5 23',
        line: 'g6h5',
        solution: 'g4g7 g8g7 e2h5',
        hint: 'A capture on g7 is check.',
        success: 'You gave a rook and won a queen.'),
    LessonStep.find(
        'Your queen on b3 and Black\'s king on g8 are on one diagonal, with your d5 pawn in between. Push it: '
        'discovered check, and the pawn attacks the bishop on e7.',
        fen: '5rk1/pppqb1pp/5n2/3P4/8/1QP5/P4PPP/3R1RK1 b - - 0 17',
        line: 'b7b6',
        solution: 'd5d6 g8h8 d6e7',
        hint: 'The pawn moves one square.',
        success: 'The pawn on e7 even attacks the rook on f8 now.'),
    LessonStep.find(
        'Double check: two pieces give check at once, so the king must move: nothing can block or capture two '
        'checkers. Black just took your knight on e5. Find the double check that is mate.',
        fen: 'r2qkbnr/pp2pppp/2n5/1N2N3/Q7/8/PP1P1PPP/R1B1K2R b KQkq - 2 10',
        line: 'c6e5',
        solution: 'b5c7',
        hint: 'Your queen on a4 is aiming at e8. Move the piece in the way.',
        success: 'The knight and the queen both give check, and the king has no square: checkmate.'),
    LessonStep.find(
        'Even a king can uncover an attack. Black\'s king took your pawn on g5 and now stands on the same rank as '
        'your rook. Step your king aside with discovered check and win the rook on d7.',
        fen: '8/3r3p/6pP/1RK3P1/5k2/8/8/8 b - - 2 75',
        line: 'f4g5',
        solution: 'c5c6 g5h6 c6d7',
        hint: 'Your king can attack the rook on d7 in two moves.',
        success: 'The check gave you the time to take the rook.'),
  ]),
  Lesson('pawn-structure', 'Pawn structure basics', 'Isolated, doubled and passed pawns.', 1300, Area.middlegame, [
    LessonStep.show(
        'An isolated pawn has no friendly pawns on the files beside it, so only pieces can defend it. Black\'s '
        'd5 pawn gives active piece play, but it can become a target, and the square in front of it (d4) is a '
        'perfect home for a white knight.',
        line: 'd4 d5 c4 e6 Nc3 c5 cxd5 exd5 Nf3 Nc6 g3 Nf6 Bg2 Be7 O-O O-O dxc5 Bxc5',
        circles: 'd5 d4'),
    LessonStep.find('Put pressure on the isolated pawn: pin the knight that defends it.',
        line: 'd4 d5 c4 e6 Nc3 c5 cxd5 exd5 Nf3 Nc6 g3 Nf6 Bg2 Be7 O-O O-O dxc5 Bxc5',
        solution: 'Bg5',
        hint: 'Your dark-squared bishop can pin the f6 knight to the queen.',
        success: 'The knight on f6 is d5\'s best defender. Pinned, it defends badly, and Bxf6 may win the pawn.'),
    LessonStep.show(
        'Doubled pawns stand on the same file. After 4.Bxc6 dxc6 Black gets the bishop pair and open lines, but '
        'White has a healthy 4-against-3 pawn majority on the kingside. In a pawn ending White makes a passed '
        'pawn there, while Black\'s doubled queenside majority can\'t.',
        line: 'e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6',
        circles: 'c6 c7'),
    LessonStep.show(
        'A passed pawn has no enemy pawns in front of it or on the files beside it. Passed pawns must be pushed: '
        'the closer they get, the more the opponent must give up to stop them.',
        fen: '6k1/5ppp/8/1P6/8/8/5PPP/6K1 w - - 0 1',
        circles: 'b5',
        arrows: 'b5b8'),
    LessonStep.find(
        'Three pawns against three, but White to move can force a passed pawn: find the breakthrough!',
        fen: '7k/ppp5/8/PPP5/8/8/8/7K w - - 0 1',
        solution: 'b6 axb6 c6 bxc6 a6',
        hint: 'Sacrifice the middle pawn.',
        success: 'After b6 any capture lets another pawn through. Black\'s king is too far away to stop it.'),
    LessonStep.find(
        'You are Black in the French Defence. White\'s pawn chain d4–e5 points at your kingside. Attack its base '
        'with your c-pawn.',
        line: 'e4 e6 d4 d5 e5',
        solution: 'c5',
        hint: 'The base of the chain is d4.',
        success: 'Attack a pawn chain at its base: if d4 falls, e5 loses its support.',
        arrows: 'c5d4'),
  ]),
  Lesson('good-bad-pieces', 'Good and bad pieces', 'Improve your worst piece.', 1400, Area.middlegame, [
    LessonStep.show(
        'A bad bishop is hemmed in by its own pawns standing on its colour, like Black\'s c8 bishop behind e6 '
        'and d5. A good piece has open lines and safe squares. Ask every move: which is my worst piece, and how '
        'can I improve it?',
        line: 'd4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7',
        circles: 'c8'),
    LessonStep.show(
        'An outpost is a square that enemy pawns can never attack. Black has no pawn that can ever hit d5, so a '
        'knight there is a monster, much stronger than Black\'s bishop on e7, which is blocked by its own pawns '
        'on d6 and e5.',
        fen: 'r4rk1/1p2bppp/p2p4/3Np3/4P3/8/PPP2PPP/R4RK1 w - - 0 1',
        circles: 'd5'),
    LessonStep.find('Put your knight on the outpost.',
        fen: 'r4rk1/1p2bppp/p2p4/4p3/4P3/2N5/PPP2PPP/R4RK1 w - - 0 1',
        solution: 'Nd5',
        hint: 'The knight on c3 is one jump away.',
        success: 'Nothing can chase the knight away, and it eyes c7, e7, b6 and f6.'),
    LessonStep.show(
        'Rooks belong on open files, where no pawns block them, and on the seventh rank, where they attack pawns '
        'that can\'t be defended by other pawns. A rook on the seventh often wins the game by itself.',
        fen: '6k1/1R3ppp/p7/8/8/8/5PPP/6K1 w - - 0 1',
        arrows: 'b7f7'),
  ]),
  Lesson('king-attack', 'Attacking the castled king', 'Sacrifices and pawn storms.', 1600, Area.tactics, [
    LessonStep.show(
        'Attack the king only when you have more pieces near it than your opponent has defenders. Typical tools: '
        'a bishop aimed at h7, a knight jumping to g5, the queen arriving on h5, and sacrifices that rip open the '
        'pawn cover. With kings on opposite sides, push the pawns in front of the enemy king.',
        fen: 'rnb1k2r/ppq1nppp/4p3/2ppP3/3P4/P1PB1N2/2P2PPP/R1BQK2R b KQkq - 4 8',
        line: 'e8g8',
        arrows: 'd3h7 f3g5 d1h5'),
    LessonStep.find(
        'The Greek gift. Black just castled, and your bishop, knight and queen are ready. Sacrifice on h7!',
        fen: 'rnb1k2r/ppq1nppp/4p3/2ppP3/3P4/P1PB1N2/2P2PPP/R1BQK2R b KQkq - 4 8',
        line: 'e8g8',
        solution: 'd3h7 g8h7 f3g5 h7g8 d1h5',
        hint: 'Take with the bishop, check with the knight, then bring the queen.',
        success: 'Qh5 threatens Qh7 mate and Black has no good defence. The pawn on e5 keeps Black\'s pieces '
            'away from f6.'),
    LessonStep.find(
        'Black grabbed a pawn on b2. Your queen and bishop both aim at h7. Sacrifice your knight with check to '
        'open the king, then mate.',
        fen: 'r4rk1/p1p2ppp/1pb5/4q3/3bN2Q/3B1PP1/PPP4P/1K4NR b - - 2 22',
        line: 'd4b2',
        solution: 'e4f6 g7f6 h4h7',
        hint: 'The knight check on f6 forces the g-pawn away.',
        success: 'Mate on h7: the bishop on d3 protects the queen.'),
    LessonStep.find(
        'Black played ...Rd5, offering a trade. Ignore it: your doubled rooks on the h-file can smash open the '
        'king.',
        fen: '3r1r1k/pp2qpp1/2p1p2p/7R/3P1P1R/2PQ4/PP3P1P/6K1 b - - 0 29',
        line: 'd8d5',
        solution: 'h5h6 g7h6 h4h6 h8g7 d3h7',
        hint: 'Capture on h6 with check.',
        success: 'Two rook sacrifices and the queen finishes on h7.'),
    LessonStep.find(
        'Black\'s king is boxed in by its own pieces. Take on e8 with check, then let your knight deliver mate.',
        fen: 'r3Q1kr/p2n1ppp/1pq5/2pN4/5b2/6P1/PP3P1P/3RR1K1 b - - 3 25',
        line: 'a8e8',
        solution: 'e1e8 d7f8 d5e7',
        hint: 'After ...Nf8, which knight check can\'t be answered?',
        success: 'Mate: every square around the king is blocked by Black\'s own pieces.'),
  ]),
  Lesson('making-a-plan', 'Making a plan', 'Find targets and build a strategy.', 1800, Area.middlegame, [
    LessonStep.show(
        'Planning in three steps. 1) Find the weaknesses: loose pieces, weak pawns, holes, an exposed king. '
        '2) Pick one target. 3) Bring more pieces to it than your opponent can bring to defend it. And before '
        'every plan, ask what your opponent wants to do.'),
    LessonStep.show(
        'The minority attack: in the Exchange QGD, White pushes two queenside pawns (b4–b5) against Black\'s '
        'three. After b5xc6 Black is left with a weak pawn on c6 or d5, and White\'s pieces attack it.',
        line: 'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Be7 Bd3 O-O Qc2 Nbd7 Nf3 Re8 O-O Nf8',
        arrows: 'b2b4 b4b5'),
    LessonStep.find('The rook on b1 supports it: start the minority attack.',
        line: 'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Be7 Bd3 O-O Qc2 Nbd7 Nf3 Re8 O-O Nf8 Rab1 Ng6',
        solution: 'b4',
        hint: 'The b-pawn goes first.',
        success: 'Next comes b5. Black will have to accept a weak pawn on c6 or d5.'),
    LessonStep.find(
        'Black\'s king has few defenders. Bring one more piece into the attack: lift your rook to the h-file.',
        fen: 'rnbq1rk1/pp2n3/2pb2pQ/3p1p2/3P1P2/3B1R2/PPP3PP/RNB3K1 b - - 1 13',
        line: 'f8f7',
        solution: 'f3h3 f7h7 h6h7',
        hint: 'The rook on f3 can reach the h-file in one move.',
        success: 'Rook and queen on the h-file: Black\'s defence collapses. More attackers than defenders wins.'),
  ]),
];
