# Progress

| # | Milestone | Status |
|---|---|---|
| 1 | Foundation | Done (v0.2.0) |
| 2 | Human-like coach | Done (v0.2.0) |
| 3 | Puzzles | Not started |
| 4 | Lessons | Not started |
| 5 | Personal learning | Not started |
| 6 | Local LLM explainer | Not started |
| 7 | Google Drive sync | Not started |
| 8 | Polish | Not started |

## Done

- UI preview: Home ("I have X minutes", skills, continue lesson, coach tip), Play (board, coach chat,
  Training / Real game, undo, hint, flip, resign), Puzzles (4 verified starter puzzles), Lessons
  (opening / middlegame / endgame outline), Settings (Light / Dark / Wooden themes, coordinates, hints).
- Side navigation on desktop, bottom bar on phones; pages keep their state when switching tabs.
- Stockfish 19 everywhere: desktop binary bundled next to the app (`tool/fetch_engines.sh` + CMake install),
  Android via the `multistockfish` plugin. Falls back to simple rules if the engine can't start.
- Coach plays like a human of a chosen strength (400–3200): MultiPV candidates sampled by centipawn loss.
- Training mode grades every move (best/good/inaccuracy/mistake/blunder, Lichess win% thresholds),
  explains errors from engine facts, shows the better move, two-step hints, evaluation bar.
- New game dialog (colour, strength), undo, resign, unfinished game restored on restart.
- Maia 1100–1900 nets run in pure Dart (`lib/maia/`, verified against a numpy reference) for a human-like
  opponent up to 1900; below 1100 the 1100 net is sampled with a higher temperature; Stockfish above 1900.
- Finished games are stored in an append-only event log (`events.jsonl`, sync-ready); Review screen with
  accuracy, key moments, better-move arrows, move navigation; recent games on Home.
- Packaging: app icon, signed APK (key in `~/Documents/chess-coach-keys`, also in GitHub secrets),
  AppImage, Inno Setup installer with the VC++ runtime; pushing a `v*` tag publishes a GitHub Release.
- GitHub Actions: analyze, test, screenshots, Linux tarball, Android arm64 APK, Windows zip (all green).

## Next step

Milestone 3: puzzles. Bundle a rated, themed subset of the Lichess puzzle database (CC0), puzzle rating
(Glicko-2), and turn mistakes from reviewed games into personal puzzles.

## Decisions

- Flutter 3.47.7 with `fluent_ui` (Fluent design), `chessground` (Lichess board widget) and `dartchess` (rules).
- Board per theme: Light = blue + cburnett pieces, Dark = blue2 + cburnett, Wooden = wood4 + staunty.
- Flutter SDK lives in `~/development/flutter`. Platform folders (android, linux, windows) are committed.
- No web build: `dartchess` uses 64-bit integers that can't compile to JavaScript.
- A pre-push hook (`tool/hooks/pre-push`, enabled with `git config core.hooksPath tool/hooks`) runs
  `flutter analyze` and `flutter test` and blocks the push if either fails, so CI stays green.
- CI renders screenshots of every screen (`screenshots/screenshots_test.dart`) for visual review.

## How to resume

Pull the repo, read `PLAN.md`, then continue from "Next step" above.
