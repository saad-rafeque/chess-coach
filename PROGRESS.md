# Progress

| # | Milestone | Status |
|---|---|---|
| 1 | Foundation | In progress: UI preview built, waiting for owner's approval |
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
- Rule-based quick tips and a one-ply practice bot stand in for the real coach until milestone 2.
- GitHub Actions: analyze, test, screenshots, Linux tarball, Android arm64 APK, Windows zip (all green).

## Next step

Get the owner's feedback on the UI. Then finish milestone 1: Stockfish on all platforms
(engine wrapper + tests), AppImage and Windows installer packaging, Release `v0.1.0`.

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
