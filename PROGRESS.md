# Progress

| # | Milestone | Status |
|---|---|---|
| 1 | Foundation | In progress: UI approved, Stockfish coach working; packaging + release left |
| 2 | Human-like coach | Not started |
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
- GitHub Actions: analyze, test, screenshots, Linux tarball, Android arm64 APK, Windows zip (all green).

## Next step

Finish milestone 1: app icon, Android release signing, Linux AppImage, Windows installer,
GitHub Release `v0.1.0` with all three builds. Then milestone 2 (post-game review, Maia opponent).

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
