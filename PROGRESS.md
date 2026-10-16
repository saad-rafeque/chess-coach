# Progress

| # | Milestone | Status |
|---|---|---|
| 1 | Foundation | Done (v0.2.0) |
| 2 | Human-like coach | Done (v0.2.0) |
| 3 | Puzzles | Done (v0.5.0) |
| 4 | Lessons | Done (v0.5.0) |
| 5 | Personal learning | Done (v0.5.0) |
| 6 | Local LLM explainer | Not started |
| 7 | Google Drive sync | Not started |
| 8 | Polish | Not started |

## Done

- UI: Home, Play, Puzzles, Lessons, Settings; side navigation on desktop, bottom bar on phones; pages keep
  their state when switching tabs; Light / Dark / Wooden themes.
- Stockfish 19 everywhere: desktop binary bundled next to the app (`tool/fetch_engines.sh` + CMake install),
  Android via the `multistockfish` plugin. Falls back to simple rules if the engine can't start.
- Coach plays like a human of a chosen strength (400–3200): Maia 1100–1900 nets in pure Dart (`lib/maia/`),
  Stockfish MultiPV sampling above that; below 1100 the 1100 net is sampled with a higher temperature.
- Training mode grades every move with engine-based explanations, hints, evaluation bar; Real game mode.
- Finished games are stored in an append-only event log (`events.jsonl`, sync-ready); Review screen with
  accuracy, key moments, better-move arrows.
- Puzzles: 30,000 Lichess puzzles (CC0, 400–2400, `tool/build_puzzles.py`), Glicko-2 puzzle rating, themes,
  your-mistake puzzles; drill mode (`openPuzzleDrill`) used by training sessions.
- Lessons (milestone 4): 20 lessons in `lib/lessons/content/` (openings, middlegame, endgames), each with
  "show" steps (text + board + animated demo moves + arrows) and "find" steps checked like puzzles
  (`PuzzleSession`). Moves are written in SAN or UCI (`lib/lessons/lesson.dart`). Progress is stored as
  `lesson` events (`lib/lessons/progress.dart`) and shown on the Lessons and Home screens. Lesson player:
  `lib/screens/lesson_page.dart`.
- Personal learning (milestone 5), all derived from the event log:
  - Skill model (`lib/train/skill_model.dart`): Glicko-2 per area (tactics, openings, middlegame, endgames,
    blunder check) and per puzzle theme, from puzzles, lesson exercises and games (result vs coach, phase
    errors from reviews or live grades). Estimated rating, training streak, recommended coach strength.
  - FSRS v4.5 spaced repetition (`lib/train/fsrs.dart`, `lib/train/cards.dart`): repertoire exercises,
    missed lesson exercises, game mistakes and failed puzzles; `card` events; Review screen
    (`lib/screens/cards_page.dart`) grades automatically (wrong/answer = again, hint = hard, fast = easy).
  - Planner (`lib/train/planner.dart`): LinUCB contextual bandit over activity kinds with priors; rewards
    stored as `activity` events. "I have X minutes" opens a session (`lib/screens/session_page.dart`).
  - Coach strength auto-tuned to a ~45% expected score (New game dialog toggle, on by default).
- Packaging: app icon, signed APK (key in `~/Documents/chess-coach-keys`, also in GitHub secrets),
  AppImage, Inno Setup installer with the VC++ runtime; pushing a `v*` tag publishes a GitHub Release.
- GitHub Actions: analyze, test, screenshots, Linux tarball + AppImage, Android arm64 APK, Windows installer.

## Next step

Milestone 6: local LLM explainer. Optional ~1B model via llama.cpp, downloaded on demand, that rephrases the
facts from `lib/coach/explain.dart` into friendly English; the current templates stay as the fallback.

## Decisions

- Flutter 3.47.7 with `fluent_ui` (Fluent design), `chessground` (Lichess board widget) and `dartchess` (rules).
- Board per theme: Light = blue + cburnett pieces, Dark = blue2 + cburnett, Wooden = wood4 + staunty.
- Flutter SDK lives in `~/development/flutter`. Platform folders (android, linux, windows) are committed.
- No web build: `dartchess` uses 64-bit integers that can't compile to JavaScript.
- A pre-push hook (`tool/hooks/pre-push`, enabled with `git config core.hooksPath tool/hooks`) runs
  `flutter analyze` and `flutter test` and blocks the push if either fails, so CI stays green.
- CI renders screenshots of every screen (`screenshots/screenshots_test.dart`) for visual review.
- Lesson content is Dart code (const data), not a JSON asset: the compiler and `test/lessons_test.dart`
  catch typos and illegal moves. Tactics and some endgame exercises reuse Lichess puzzle positions (CC0).
  `tool/verify_lessons_test.dart` checks every exercise with Stockfish (run locally; prints a report).
- Lesson ids are stable keys in stored events: never rename them.
- A lesson step counts as done when the player presses Next; a "find" step records whether the first try
  was right (feeds the skill model and the review cards).
- Releases are tagged after milestones 5 and 8 (v0.5.0, v0.8.0); milestones 3–5 shipped together in v0.5.0.
- Skill areas start at 900 ±350 and count as "rated" once the deviation is below 300.
- Game phases: opening = first 10 moves, endgame = 6 or fewer pieces besides kings and pawns.
- The planner's context is [bias, skill gap, pending work, time fit, days since last done]; the reward is the
  rating gain in the block's area (0.5 = no change), the recall rate for reviews, or the first-try rate for
  lessons. Training sessions live in memory only (not synced).
- New review cards are limited to 10 per day.

## How to resume

Pull the repo, read `PLAN.md`, then continue from "Next step" above. Flutter is in `~/development/flutter/bin`
(not on PATH). Run `bash tool/fetch_engines.sh linux` once for the desktop engine.
