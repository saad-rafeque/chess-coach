# Chess Coach — Project Plan

A personal, fully offline chess coach for **Android, Windows and Ubuntu**. It plays you at your level,
explains every mistake, and drives a personalised training plan from beginner (<800) to strong club
level (1800–2000). Open source, distributed via GitHub Releases (no app stores).

## Decisions (from the Q&A, 2026-10-15)

| Topic | Decision |
|---|---|
| Starting level → target | Beginner (<800) → Strong club (1800–2000) |
| Platforms (v1) | Android (APK sideload), Windows (.exe installer), Ubuntu (AppImage + .deb) |
| Coach talks | Both: live hints in *Training* mode, silent in *Real game* mode, full review after |
| Language | English, text only (no voice) |
| Internet | Fully offline; internet used only for sync |
| Explanations | Local small LLM, fed by engine facts (template fallback on weak devices) |
| Opponent | Human-like at your level (Maia nets), grows with you |
| Openings | Coach picks a beginner-friendly repertoire |
| Personalisation | Fully adaptive (skill model + RL bandit + spaced repetition) |
| v1 features | Play vs coach + live tips, post-game review, tactics puzzles, lessons (opening/middle/end) |
| Game import | No |
| Sync | One file in your Google Drive hidden app folder, synced only when online, battery-friendly |
| Design | Modern Fluent UI; Light / Dark / Wooden themes, switchable anytime |
| Who builds | Claude codes and tests everything on your PC (Pro plan, no cloud); you test final builds |

## Architecture

```
Flutter app (one codebase → Android / Windows / Linux), Fluent UI, 3 themes
│
├── Chess core ............ rules, PGN/FEN, board UI (dartchess-style logic)
├── Engines (on-device, native via FFI/process)
│   ├── Stockfish ......... the "grandmaster": analysis, best moves, eval (~3500 Elo)
│   └── Lc0 + Maia nets ... the "sparring partner": plays like a human of rating X
│                            (Maia 1100–1900; below 1100 = Maia policy sampled with
│                            higher temperature → realistic beginner mistakes)
├── Coach brain
│   ├── Detectors ......... hanging pieces, forks, pins, skewers, mate threats,
│   │                        king safety, pawn structure, opening principles, endgame technique
│   ├── Explainer ......... local ~1B LLM (llama.cpp, ~700 MB optional download) turns
│   │                        detector + engine FACTS into plain English.
│   │                        The LLM never chooses moves (LLMs hallucinate chess).
│   └── Templates ......... same facts, fixed sentences — fallback if no LLM / slow device
├── Personal learning (ML / RL) — learns YOU; the coach itself is pre-trained
│   ├── Skill model ....... Glicko-2 rating per area: tactics (per motif), openings,
│   │                        middlegame plans, endgames, blunder rate, conversion
│   ├── Planner (RL) ...... contextual bandit picks the next activity that gives the
│   │                        biggest expected improvement for the time you have
│   ├── Spaced repetition . FSRS for opening lines and positions you got wrong
│   └── Difficulty ........ opponent rating auto-tuned so games stay challenging (~40–50% score)
├── Content (bundled, offline)
│   ├── Puzzles ........... filtered subset of the Lichess puzzle DB (CC0), tagged by theme/rating
│   ├── Your-mistake puzzles  generated from your own games
│   ├── Repertoire ........ e.g. White: Italian Game; Black: 1…e5 and Queen's Gambit Declined
│   └── Lessons ........... beginner → 2000 curriculum: opening principles, tactics,
│                            middlegame plans, essential endgames (K+P, rook endings, …)
└── Storage & sync
    ├── Local ............. SQLite; history stored as an append-only event log
    │                        (games, puzzle attempts, lessons), each event has a UUID
    └── Google Drive ...... one small file in the app's hidden appDataFolder.
                            Merge = union of events (no overwrites); settings = last-write-wins.
                            Sync only on app open, app close/background, and when internet
                            returns — no polling, no battery drain.
```

## "I have X minutes" button

| Time you have | Coach gives you |
|---|---|
| 2 min | 3 quick puzzles or 1 opening flashcard |
| 10–15 min | warm-up puzzles + review one old mistake + short lesson |
| 30–60 min | 1 training game with live tips + review + targeted puzzles |
| 2 h+ | full session: lesson, 2 games, deep review, endgame drill, repertoire practice |

The planner decides *what* to fill the slot with, based on your weakest areas.

## Milestones

| # | Milestone | Done when | Est. time |
|---|---|---|---|
| 1 | Foundation | Board, legal moves, play vs Stockfish, 3 themes; CI builds APK + .exe + AppImage | 3–4 days |
| 2 | Human-like coach | Maia opponent at your level, live tips, post-game review with key moments | 5–7 days |
| 3 | Puzzles | Lichess puzzle set + puzzles from your own mistakes, puzzle rating | 2–3 days |
| 4 | Lessons | Repertoire trainer + middlegame and endgame lessons, beginner → 2000 | 4–6 days |
| 5 | Personal learning | Skill model, RL planner, spaced repetition, "I have X minutes" | 3–5 days |
| 6 | Local LLM explainer | Offline natural-language explanations, template fallback | 4–6 days |
| 7 | Google Drive sync | Merge-safe, battery-friendly sync across all three devices | 2–3 days |
| 8 | Polish | Animations, Fluent UI details, performance on phone | 2–3 days |
|   | **Total** | | **≈ 4–6 weeks** |

All work runs on your PC under the Pro plan, so there's no extra cost. The pace is set by the plan's
5-hour usage windows and weekly cap. Times can move with debugging, especially cross-compiling Lc0 and
llama.cpp for Android.

## Testing (done by Claude)

- Unit tests: move generation, engine wrappers, detectors, skill model, sync merge
- Widget tests for UI; the Linux build is run and checked on your PC, Android on an emulator or your phone over USB
- GitHub Actions builds all three platforms on every change (Ubuntu can't build the Windows .exe itself)
- **You** do the final check: install the APK on your phone, run the .exe and AppImage

## What you need to do

1. Run a few `sudo apt install` commands Claude gives you (build tools for Flutter on Linux)
2. For sync (milestone 7): create a free Google Cloud project and OAuth client — Claude will give
   click-by-click steps. Because it's a personal app, Google shows an "unverified app" warning once;
   you accept it for your own account.
3. Test each milestone build on your devices and say what feels wrong

## Honest expectations

Going from <800 to 1800–2000 usually takes 1–3 years of steady practice, even with a great coach.
The app makes every minute count (right puzzle, right lesson, right opponent), but it can't skip the practice.

## Licences

Stockfish and Lc0 are GPL-3, Maia nets are GPL-3, Lichess puzzle DB is CC0 → the app is GPL-3 open source.
