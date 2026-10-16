// Opening lessons: principles, the Italian Game for White, 1...e5 and the
// Queen's Gambit Declined for Black. Every "find" step is checked with
// Stockfish by tool/verify_lessons_test.dart.
import '../../data/curriculum.dart';
import '../lesson.dart';

const openingLessons = [
  Lesson('opening-principles', 'Opening principles', 'Control the centre, develop pieces, castle early.', 800,
      Area.openings, [
    LessonStep.show(
        'The opening has three jobs: take the centre, bring out your knights and bishops, and castle your king '
        'to safety. The four centre squares d4, e4, d5 and e5 matter most: pieces placed there reach the whole board.',
        circles: 'd4 e4 d5 e5'),
    LessonStep.find('White to move. Take a share of the centre: push your king\'s pawn two squares.',
        solution: 'e4',
        hint: 'The king\'s pawn stands on e2.',
        success: 'Good. The pawn claims the centre and opens lines for your queen and your light-squared bishop.',
        arrows: 'f1c4 d1h5'),
    LessonStep.show(
        'Knights come out first, towards the centre. After 1.e4 e5 2.Nf3 the knight attacks the e5 pawn '
        'and watches the d4 square.',
        line: 'e4 e5',
        demo: 'Nf3',
        arrows: 'f3e5 f3d4'),
    LessonStep.find(
        'Black defended e5 with 2...Nc6. Develop your bishop to an active square where it aims at f7, '
        'the weakest point near Black\'s king.',
        line: 'e4 e5 Nf3 Nc6',
        solution: 'Bc4',
        hint: 'The bishop on f1 wants the long diagonal that ends at g8.',
        success: 'The bishop on c4 eyes f7, which only Black\'s king defends.',
        arrows: 'c4f7'),
    LessonStep.find(
        'Black copied you with 3...Bc5. Now put your king to safety and bring a rook towards the centre, '
        'all in one move.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5',
        solution: 'O-O',
        hint: 'Castle short: move your king two squares towards the rook on h1.',
        success: 'Castled! Your king hides behind its pawns and the rook joins the game.'),
    LessonStep.show(
        'Don\'t bring the queen out early and don\'t move the same piece twice. Here White\'s queen comes out '
        'on move two and Black develops a piece with every move while chasing it.',
        demo: 'e4 e5 Qh5 Nc6 Bc4 g6 Qf3 Nf6'),
    LessonStep.find(
        'You are Black. White\'s queen came out early and attacks your e5 pawn. Defend it by developing a knight.',
        line: 'e4 e5 Qh5',
        solution: 'Nc6',
        hint: 'Which knight can reach a square that protects e5?',
        success: 'A developing move that defends. If White now threatens mate with 3.Bc4, you kick the queen '
            'with 3...g6. You will practise that in "Opening traps to avoid".'),
  ]),
  Lesson('italian-basics', 'Italian Game basics', 'Your first White opening: 1.e4 e5 2.Nf3 Nc6 3.Bc4.', 900,
      Area.openings, [
    LessonStep.show(
        'The Italian Game: 1.e4 e5 2.Nf3 Nc6 3.Bc4. White develops quickly, attacks e5 and aims the bishop at f7.',
        demo: 'e4 e5 Nf3 Nc6 Bc4',
        arrows: 'c4f7 f3e5'),
    LessonStep.find(
        'Now you play it. Play the first three moves of the Italian Game as White; your coach answers for Black.',
        solution: 'e4 e5 Nf3 Nc6 Bc4',
        hint: 'King\'s pawn two squares, then the king\'s knight, then the bishop to c4.',
        success: 'That\'s the Italian Game. Black\'s most common answers are 3...Bc5 and 3...Nf6.'),
    LessonStep.show(
        'The main reply is 3...Bc5, the Giuoco Piano ("quiet game"). White wants a big pawn centre with c3 and d4.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5',
        arrows: 'c2c3 d2d4'),
    LessonStep.find('Prepare d4: play the quiet pawn move that will support it.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5',
        solution: 'c3',
        hint: 'A pawn on c3 protects the d4 square.',
        success: 'Now d4 is coming, and if Black takes on d4 you recapture with the c-pawn.'),
    LessonStep.find(
        'Black played 4...Nf6, attacking e4. Strike in the centre, and when Black captures, take back with a pawn.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6',
        solution: 'd4 exd4 cxd4',
        hint: 'Push the d-pawn two squares.',
        success: 'Two pawns on e4 and d4: a classical centre. After 6...Bb4+ block the check with Bd2.'),
    LessonStep.find(
        'Black chose 3...Nf6, the Two Knights Defence, and attacks e4. Protect it with a pawn that also frees '
        'your dark-squared bishop.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6',
        solution: 'd3',
        hint: 'One small step for the d-pawn.',
        success: 'Calm and solid. The sharp 4.Ng5 also exists, but the quiet move is easier to play well.'),
    LessonStep.show(
        'The plan in the quiet Italian: castle, play c3 and Re1, then send the queen\'s knight on a trip, '
        'd2–f1–g3, towards Black\'s king. Development first, action later.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 O-O d6 c3 O-O Re1',
        arrows: 'b1d2 d2f1 f1g3'),
  ]),
  Lesson('opening-traps', 'Opening traps to avoid', 'Scholar\'s mate, the Fried Liver and other early knockouts.',
      1000, Area.openings, [
    LessonStep.show(
        'Scholar\'s Mate: the queen and bishop team up against f7. If Black doesn\'t notice the threat, '
        '4.Qxf7 is checkmate on move four.',
        demo: 'e4 e5 Bc4 Nc6 Qh5 Nf6 Qxf7#'),
    LessonStep.find(
        'You are Black. White threatens Qxf7 checkmate. Defend f7 by kicking the queen with a pawn, and when the '
        'queen comes back with the same threat, block it with a piece.',
        line: 'e4 e5 Bc4 Nc6 Qh5',
        solution: 'g6 Qf3 Nf6',
        hint: 'The g-pawn attacks h5. Later, a knight can stand between f3 and f7.',
        success: 'Both threats are parried and you are developing. White\'s early queen achieved nothing.'),
    LessonStep.show(
        'In the Two Knights, 4.Ng5 attacks f7 again. After 4...d5 5.exd5 Nxd5?! White can sacrifice with '
        '6.Nxf7! Kxf7 7.Qf3+: the Fried Liver Attack. Black\'s king is dragged into the open.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6',
        demo: 'Ng5 d5 exd5 Nxd5 Nxf7 Kxf7 Qf3+'),
    LessonStep.find(
        'You are Black after 4.Ng5 d5 5.exd5. Don\'t take back with the knight. Attack the bishop on c4 instead.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5',
        solution: 'Na5',
        hint: 'The knight on c6 has a square on the edge that hits c4.',
        success: 'The main line. You are a pawn down, but you will gain time chasing White\'s pieces.'),
    LessonStep.find(
        'You are White. Black pinned your knight with ...Bg4 and then played the careless ...g6. Break the pin '
        'by taking on e5, even though it lets Black take your queen!',
        line: 'e4 e5 Nf3 d6 Bc4 Bg4 Nc3 g6',
        solution: 'Nxe5 Bxd1 Bxf7+ Ke7 Nd5#',
        hint: 'After the queen falls, check on f7, then a knight jump finishes the job.',
        success: 'Légal\'s Mate: three minor pieces beat the queen. If Black declines with 5...dxe5, then 6.Qxg4 '
            'simply wins a pawn.'),
    LessonStep.show(
        'A trap for the greedy: after 3...Nd4 don\'t grab the e5 pawn. 4.Nxe5? Qg5! and White collapses: '
        '5.Nxf7? Qxg2 6.Rf1 Qxe4+ 7.Be2 Nf3 is mate.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nd4',
        demo: 'Nxe5 Qg5 Nxf7 Qxg2 Rf1 Qxe4+ Be2 Nf3#'),
    LessonStep.find('Black played 3...Nd4 again. Don\'t fall for it: simply take the knight.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Nd4',
        solution: 'Nxd4',
        hint: 'Your knight on f3 attacks d4.',
        success: 'After 4...exd4 you castle and play c3: Black has just wasted time.'),
  ]),
  Lesson('black-e5', 'Meeting 1.e4 with 1…e5', 'Solid, classical answers as Black.', 1000, Area.openings,
      asBlack: true, [
    LessonStep.show(
        'Against 1.e4, answer 1...e5. You take your share of the centre and open lines for your queen and '
        'your dark-squared bishop.',
        line: 'e4',
        demo: 'e5'),
    LessonStep.find('White attacks e5 with 2.Nf3. Defend the pawn and develop a piece at the same time.',
        line: 'e4 e5 Nf3',
        solution: 'Nc6',
        hint: 'A knight move protects e5.',
        success: 'The most natural move. The knight defends e5 and controls d4.'),
    LessonStep.find(
        'White plays the Italian Game, 3.Bc4. Mirror it: put your bishop on its most active square.',
        line: 'e4 e5 Nf3 Nc6 Bc4',
        solution: 'Bc5',
        hint: 'Your bishop on f8 can aim at f2.',
        success: 'The Giuoco Piano. Your bishop eyes f2, just as White\'s eyes f7.',
        arrows: 'c5f2'),
    LessonStep.find('White prepares d4 with 4.c3. Develop your king\'s knight with an attack on e4.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3',
        solution: 'Nf6',
        hint: 'Which knight move hits the e4 pawn?',
        success: 'Now 5.d4 exd4 6.cxd4 Bb4+ is the main line.'),
    LessonStep.find('White pushed 5.d4. Take the pawn, and when White recaptures, check with your bishop.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4',
        solution: 'exd4 cxd4 Bb4+',
        hint: 'Capture on d4 with the e-pawn first.',
        success: 'After 7.Bd2 Bxd2+ 8.Nbxd2 strike back in the centre with 8...d5!'),
    LessonStep.show(
        'Against the Spanish Game (3.Bb5) play 3...a6 4.Ba4 Nf6 5.O-O Be7, then ...b5, ...d6 and castle. '
        'The bishop on b5 doesn\'t really threaten e5 yet: if it takes on c6 and then on e5, your queen wins '
        'the pawn back.',
        line: 'e4 e5 Nf3 Nc6',
        demo: 'Bb5 a6 Ba4 Nf6 O-O Be7'),
    LessonStep.find(
        'White gave up the bishop with 4.Bxc6 dxc6 and grabbed a pawn with 5.Nxe5. Win it back: your queen can '
        'attack the knight and the e4 pawn from one square.',
        line: 'e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6 Nxe5',
        solution: 'Qd4',
        hint: 'The queen goes to the centre.',
        success: 'Double attack! After 6.Nf3 Qxe4+ material is level and your two bishops are strong.',
        arrows: 'd4e5 d4e4'),
    LessonStep.find(
        'The Scotch Game: White opens the centre with 3.d4. Take the pawn, and after 4.Nxd4 develop your '
        'knight with an attack on e4.',
        line: 'e4 e5 Nf3 Nc6 d4',
        solution: 'exd4 Nxd4 Nf6',
        hint: 'Capture with the e-pawn first.',
        success: 'Natural development with a threat. 5.Nxc6 bxc6 6.e5 Qe7 is a typical continuation.'),
  ]),
  Lesson('qgd', 'Queen\'s Gambit Declined', 'A rock-solid defence against 1.d4.', 1100, Area.openings,
      asBlack: true, [
    LessonStep.show(
        'Against 1.d4, answer 1...d5. If White offers the c-pawn with 2.c4 (the Queen\'s Gambit), keep your '
        'centre with 2...e6: the Queen\'s Gambit Declined, one of the most solid defences in chess.',
        demo: 'd4 d5 c4 e6'),
    LessonStep.find('White opened with 1.d4. Answer with a pawn in the centre.',
        line: 'd4',
        solution: 'd5',
        hint: 'Stop White from playing e4 easily.',
        success: 'Now the centre is balanced.'),
    LessonStep.find(
        'With 2.c4 White attacks d5. Support it with the pawn move that also frees your dark-squared bishop.',
        line: 'd4 d5 c4',
        solution: 'e6',
        hint: 'A pawn on e6 protects d5 and opens the f8–a3 diagonal.',
        success: 'The Queen\'s Gambit Declined. If White takes on d5, you take back with the e-pawn.'),
    LessonStep.find('3.Nc3 adds pressure on d5. Develop your king\'s knight to defend it.',
        line: 'd4 d5 c4 e6 Nc3',
        solution: 'Nf6',
        hint: 'The knight on g8 can protect d5.',
        success: 'Solid. Now d5 is defended three times.'),
    LessonStep.find('4.Bg5 pins your knight to the queen. Break the pin by developing your bishop.',
        line: 'd4 d5 c4 e6 Nc3 Nf6 Bg5',
        solution: 'Be7',
        hint: 'Put a piece between the knight and your queen.',
        success: 'The pin is gone and you are ready to castle.'),
    LessonStep.show(
        'Typical QGD setup: ...Be7, ...O-O, ...Nbd7 and ...c6. Your problem piece is the bishop on c8, locked in '
        'by e6. Free it later with ...dxc4 and ...c5 (or ...e5), or with ...b6 and ...Bb7.',
        line: 'd4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7',
        arrows: 'c7c5 e6e5',
        circles: 'c8'),
    LessonStep.find(
        'The Elephant Trap. White just took on d5 with the knight, thinking your knight on f6 is pinned. It isn\'t '
        'really: take the knight! If White grabs your queen, a bishop check wins it back.',
        line: 'd4 d5 c4 e6 Nc3 Nf6 Bg5 Nbd7 cxd5 exd5 Nxd5',
        solution: 'Nxd5 Bxd8 Bb4+ Qd2 Bxd2+ Kxd2 Kxd8',
        hint: 'Start by capturing on d5 with the f6 knight.',
        success: 'You end up a whole piece ahead. Pins are only real if the piece behind is really in danger.'),
  ]),
  Lesson('italian-plans', 'Italian middlegame plans', 'c3, d3, Re1 and the slow Giuoco Pianissimo.', 1400,
      Area.openings, [
    LessonStep.show(
        'In the slow Italian (Giuoco Pianissimo) White plays c3, d3, castles, Re1, Bb3 and h3. Then the queen\'s '
        'knight travels d2–f1–g3 towards Black\'s king. h3 stops ...Bg4 and ...Ng4; Bb3 keeps the bishop safe '
        'from ...b5 while it still aims at f7.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O Re1 a6 Bb3 Ba7 h3 h6',
        arrows: 'b1d2 d2f1 f1g3'),
    LessonStep.find('Start the manoeuvre: bring the queen\'s knight to d2.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O Re1 a6 Bb3 Ba7 h3 h6',
        solution: 'Nbd2',
        hint: 'The knight on b1 has only one good square.',
        success: 'The knight is on its way. It doesn\'t block the c1 bishop for long.'),
    LessonStep.find('Black played ...Re8. Continue the trip: knight to f1, and then on to g3.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O Re1 a6 Bb3 Ba7 h3 h6 Nbd2 Re8',
        solution: 'Nf1 Be6 Ng3',
        hint: 'The rook left f1, so the knight can use that square.',
        success: 'From g3 the knight eyes f5 and h5, close to Black\'s king.'),
    LessonStep.show(
        'With all pieces out, White prepares the central break d3–d4. Play it when your pieces support d4 and '
        'Black can\'t win the e4 pawn. Until then, keep improving: Bc2, Be3, Qd2 or a4 to gain space.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O Re1 a6 Bb3 Ba7 h3 h6 Nbd2 Re8 Nf1 Be6 Ng3',
        arrows: 'd3d4'),
    LessonStep.find(
        'Black traded on b3 with ...Bxb3. Take back so that your a-pawn is ready to gain space on the queenside.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O Re1 a6 Bb3 Ba7 h3 h6 Nbd2 Re8 Nf1 Be6 Ng3 Bxb3',
        solution: 'axb3',
        hint: 'Capture with a pawn.',
        success: 'Taking with the a-pawn opens the a-file for your rook and keeps the queen in the centre.'),
  ]),
  Lesson('deeper-lines', 'Deeper repertoire lines', 'Sidelines and move orders at club level.', 1700, Area.openings, [
    LessonStep.find(
        'As White: Black answered 2.Nf3 with 2...d6, the Philidor Defence. Grab the centre with your d-pawn.',
        line: 'e4 e5 Nf3 d6',
        solution: 'd4',
        hint: 'Two pawns side by side in the centre.',
        success: 'Black\'s position is passive. Develop with Nc3 and Bc4 next.'),
    LessonStep.find(
        'As White: Black played 2...Nf6, the Petrov Defence. Take on e5. If Black copies you with 3...Nxe4?, '
        'a queen move on the e-file wins material.',
        line: 'e4 e5 Nf3 Nf6',
        solution: 'Nxe5 Nxe4 Qe2 Nf6 Nc6+',
        hint: 'After 3...Nxe4, put your queen on the e-file behind your knight.',
        success: 'Discovered check! Your queen checks the king and the knight attacks Black\'s queen. Correct for '
            'Black was 3...d6 4.Nf3 Nxe4.'),
    LessonStep.find(
        'As White: Black played 3...Be7, the Hungarian Defence. It is solid but passive: take space in the centre.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Be7',
        solution: 'd4',
        hint: 'Challenge e5 with a pawn.',
        success: 'White gets the freer game. Against passive setups, the d4 push is often right.'),
    LessonStep.find(
        'As Black: White chose the Evans Gambit, 4.b4. Take the pawn, and after 5.c3 retreat the bishop to a5, '
        'where it pins c3.',
        line: 'e4 e5 Nf3 Nc6 Bc4 Bc5 b4',
        solution: 'Bxb4 c3 Ba5',
        hint: 'Capture on b4 with the bishop.',
        success: 'You are a pawn up. White has quick development, so castle soon and give back the pawn if needed.'),
    LessonStep.find(
        'As Black: White played the King\'s Gambit, 2.f4. Take the pawn, and after 3.Nf3 play the quiet ...d6: it '
        'takes e5 away from White\'s knight and prepares ...g5 to keep the extra pawn.',
        line: 'e4 e5 f4',
        solution: 'exf4 Nf3 d6',
        hint: 'Capture on f4 with the e-pawn.',
        success: 'Fischer\'s Defence. Next ...g5 protects the f4 pawn, and White has to prove the gambit was worth it.'),
    LessonStep.find(
        'As Black: White chose the London System (2.Bf4 and 3.e3) instead of the Queen\'s Gambit. Hit the '
        'centre with your c-pawn.',
        line: 'd4 d5 Bf4 Nf6 e3',
        solution: 'c5',
        hint: 'Attack d4 from the side.',
        success: 'The c5 push gives Black active play against White\'s d4 pawn and the b2 pawn.'),
    LessonStep.show(
        'The Exchange QGD (4.cxd5 exd5): your c8 bishop is suddenly free. Play ...c6, ...Be7, ...O-O and '
        '...Nbd7, and later ...Bf5 or ...Bg4. White often plans a minority attack with b4–b5.',
        line: 'd4 d5 c4 e6 Nc3 Nf6',
        demo: 'cxd5 exd5 Bg5 c6',
        flip: true,
        arrows: 'c8f5'),
  ]),
];
