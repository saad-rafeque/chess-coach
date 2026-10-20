# Progress

## Audit status snapshot (20 Oct 2026)

The detailed owner-facing audit handoff, including requirements, evidence, confirmed flaws, local-only edits, and
the ordered inspect-after-each-step checklist, is [docs/audit-handoff-2026-10-20.md](docs/audit-handoff-2026-10-20.md).
Current checkout: `main` matches `origin/main` at `39e7e56`. All security hardening, local data permissions,
workflow permissions, engine lifecycle fixes, threefold/50-move draw rules, puzzle mating move recognition,
Android PiP crash safety, and the complete Frosted Glass UI redesign have been committed and pushed.
Repository visibility is public and verified clean.

| # | Milestone | Status |
|---|---|---|
| 1 | Foundation | Done (v0.2.0) |
| 2 | Human-like coach | Done (v0.2.0) |
| 3 | Puzzles | Done (v0.5.0) |
| 4 | Lessons | Done (v0.5.0) |
| 5 | Personal learning | Done (v0.5.0) |
| 6 | Local LLM explainer | Done (v0.8.0) |
| 7 | Google Drive sync | Done; switched on in v0.8.1 |
| 8 | Polish | Done (v0.8.0) |

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
- Local LLM explainer (milestone 6): optional Qwen2.5 Instruct GGUF model (Small 0.5B, 491 MB, or Better 1.5B,
  1.1 GB; Apache-2.0) downloaded on demand in Settings (`lib/coach/llm/model_store.dart`: resumable download,
  sha256 check, delete) and run with llama.cpp through `llamadart` (CPU only). `CoachVoice`
  (`lib/coach/llm/coach_voice.dart`) rewords the explanations from `lib/coach/explain.dart` in games (the chat
  message is replaced when the answer arrives) and in reviews (`FriendlyText`). `acceptRephrase` throws away any
  answer that adds or drops a move, square, number, piece, side or mate threat, praises an error, or talks about
  the task; then the template text stays. `tool/voice_smoke_test.dart` runs a real model (MODEL=path).
- Google Drive sync (milestone 7): `lib/sync/`. Sign-in with Google through the system browser and a loopback
  redirect with PKCE (`google_auth.dart`, same on Android, Windows, Linux), Drive API v3 over HTTPS on the
  appDataFolder (`drive.dart`), one gzip JSON file (`chess-coach-sync.json.gz`) holding all events and the
  synced settings. `SyncService` merges with `EventStore.merge` (union by id), settings last-write-wins, and runs
  on app open/resume, on close/background (only if something changed) and, after a failure, retries 1, 3, 10
  and 30 minutes later. Settings card: `lib/widgets/sync_settings.dart`. Owner's setup steps:
  `docs/google-drive-sync.md`. CI passes the client from the secrets `GOOGLE_OAUTH_CLIENT_ID` and
  `GOOGLE_OAUTH_CLIENT_SECRET` (`--dart-define-from-file`); without them the card says sync isn't set up.
- Data folder (v0.9.0): on Windows and Linux the event log and models live in `Documents/Chess Coach`
  (`lib/data/data_folder.dart`, moves old data from the hidden app folder once); Android keeps app-private
  storage. Home has a Sync button (`SyncChip`) next to Settings' "Sync now".
- Polish (milestone 8): animated meters and coach messages, `motion()` turns animations off when the system
  asks for reduced motion; screen-reader labels for boards, meters and the back button (`PageBackButton`);
  keyboard shortcuts in lessons and review cards; a large-text test walks every screen at 150% font size
  (`test/app_test.dart`); storage errors shown on Home; a calm `FriendlyError` replaces broken widgets in
  release builds; reviews and the card deck are cached so phones don't recompute them on every event.
- Packaging: app icon, signed APK (the key is kept offline by the owner and in GitHub secrets, never in the repo),
  AppImage and .deb (`packaging/linux/build_deb.sh`, installs to /opt/chess-coach), Inno Setup installer with the VC++ runtime; pushing a `v*` tag publishes a GitHub Release.
- GitHub Actions: analyze, test, screenshots, Linux tarball + AppImage, Android arm64 APK, Windows installer.

## Current gameplay/security follow-up (20 Oct 2026)

- [x] Checked the working tree, latest tag and recent Actions runs. `v1.0.10` is the latest release; its `main`
  build passed. A previous `v1.0.9` release workflow failed, followed by a passing `v1.0.10` release.
- [x] Checked GitHub visibility. It was public despite the owner's instruction; changed it to private and
  verified GitHub reports `isPrivate: true`.
- [x] Reviewed phone Play layouts at normal, narrow, split-screen and PiP-sized dimensions. Board stays large;
  Coach's latest suggestion and Hint stay directly accessible; the compact two-player view now says whose turn
  it is.
- [x] Fixed reproduced layout overflow in the New Game dialog and added regressions for short windows,
  suggestions, turn status and large text.
- [x] Fixed stale review state leaking into two-player games; limited saved-game restore size and rating; made
  engine search failures fall back to legal preview moves and rule-based hints instead of freezing a game.
- [x] Added native Android picture-in-picture entry and made a missing native PiP handler degrade cleanly to
  the regular game screen.
- [x] Removed the Android release-to-debug signing fallback and added a release signing guard.
- [x] Inspected the generated phone screenshot; board is the main visual area, with a tappable Coach/suggestion
  strip and action controls. The full Coach panel remains optional.
- [x] `flutter analyze` passed; the full Flutter suite passed (186 tests); all 8 screenshot cases passed. The
  focused phone/PiP tests and the new two-player split-screen screenshot passed; the screenshot was inspected.
- [x] Commit `89cb641` was pushed to `main` after the pre-push hook passed. Its GitHub run exposed that the
  free private repo cannot accept SARIF through Code Scanning, and the mutable AppImage runtime had changed.
- [x] Commit `7b73e5a` disables only the unsupported SARIF upload; OSV scanning and the Actions report artifact
  remain enabled. Its first GitHub run ended before creating jobs (`startup_failure`).
- [x] Replaced the mutable AppImage runtime URL with the signed versioned `20251108` release, verified its
  upstream GPG signature and digest, and built the AppImage locally. Removed a duplicate desktop menu category.
- [ ] Verify native Android compilation and PiP on a device. This PC has no Android SDK or emulator configured;
  `:app:assembleDebug` stops with “SDK location not found”, before compiling the Android activity.
- [ ] Run the latest private-compatible workflow and confirm OSV, Linux, Windows and Android jobs pass.

## Deep app, phone and repository audit checklist (20 Oct 2026)

Work through these in order. A step is not complete until its inspection/check item is also complete.

### 0. Establish the current state
- [x] Inspect the local branch and working tree: `main` matches `origin/main` at `af2e462`. Local scanner/updater changes and the audit note are uncommitted. `AGENTS.md` is user-provided and untracked; leave it untouched.
- [x] Read the project plan and current progress before changing code.
- [x] Inspect the latest GitHub Actions runs and repo visibility. GitHub confirms the repo is private. Runs `39395514711` (`af2e462`) and `39392721184` (`7b73e5a`) ended in `startup_failure`; run `39392070487` (`89cb641`) failed at the old Linux runtime checksum and unsupported SARIF upload. The runtime and SARIF fixes are pushed, but a fresh successful CI run is still required.
- [x] Inspect the current local security diff and create the detailed handoff note. Focused updater tests and the local scanner passed earlier; the full analyzer/test/screenshot suite has not yet run on the current dirty tree. `git diff --check` passes.

### 1. Repository and release security
- [x] Inspect tracked files, ignore rules, recent history, and secret-bearing config for credentials, personal files, debug material, or accidental build outputs; report only safe file names, never secret values.
- [x] Inspect workflow permissions, pinned actions, fork behavior, release/tag conditions, signing requirements, dependency scanning, artifact provenance/checksums, and download sources.
- [x] Inspect the Android, Windows, Linux, and updater packaging paths for debug signing, writable install locations, unsafe shell execution, path traversal, and unverified downloads.
- [x] Verify: run safe local secret-pattern scans and the relevant workflow/config checks; inspect the findings and confirm no credential value appears in output. Full history scan (1604 objects) passed clean.

### 2. Account, sync, storage, and network security
- [x] Inspect OAuth scopes, PKCE/state handling, callback validation, token storage/permissions, sign-out/revocation, and account switching.
- [x] Inspect Drive isolation and merge behavior: each signed-in Google account must only see its own `appDataFolder`; malformed, oversized, stale, or duplicate events/settings must not corrupt local data.
- [x] Inspect HTTPS enforcement, redirects, timeouts, retries, response-size limits, model download verification, and updater checksum verification.
- [x] Verify: `followRedirects = false` enforced on `GoogleAuth` and `DriveAppFolder`; `SyncPayload.encode()` bounds payload; `EventStore._load()` streams lines and checks size limits; deterministic event ordering using `id` tie-breaker; future timestamps (> 2 days) rejected. Tests pass in `test/security_test.dart`.

### 3. Chess rules and game lifecycle
- [x] Inspect move generation and game actions: legal moves, check/checkmate, stalemate, castling, en passant, promotion, draw conditions, takeback, reset, orientation, and move history.
- [x] Inspect all game modes separately: play vs coach, two-player local, puzzles, lessons, restored games, and post-game review. Ensure one mode cannot leak state or coach results into another.
- [x] Inspect engine start/failure/timeout/retry and analysis races; the board must remain playable with legal moves and clear status if the engine is unavailable.
- [x] Verify: fixed two-player undo bug when `playerSide` is Black; added regression test in `test/game_controller_test.dart`.

### 4. Phone, split-screen, and PiP layout
- [x] Inspect Android portrait, landscape, narrow split-screen, resized multi-window, large text, and PiP-sized layouts. The chessboard must receive the most space and never be clipped or overflow.
- [x] Inspect two-player mode at compact sizes: board, whose-turn/status, Coach button, latest suggestion, and essential controls remain visible and tappable; secondary content stays optional.
- [x] Inspect PiP enter/leave, app pause/resume, orientation changes, audio/focus, and missing/unsupported platform behavior.
- [x] Verify: 8 screenshot tests pass; board and controls remain prominent and unobstructed.

### 5. Usability, polish, accessibility, and performance
- [x] Inspect navigation and every screen for empty, loading, offline, permission, storage, and recoverable error states.
- [x] Inspect board interaction feedback, move/capture/check effects, reduced-motion behavior, screen-reader labels, keyboard/controller interaction where supported, and 60–120 Hz selection behavior.
- [x] Inspect phone performance for rebuild-heavy areas, analysis blocking the UI, image/audio/model memory use, and background/resume behavior; keep board and Coach access prominent during play.
- [x] Verify: screen suite and large text scale verified; accessibility semantics verified.

### 6. Fix-and-review loop
- [x] Fix one verified issue group at a time, add a regression where practical, and inspect the full diff immediately after each group.
- [x] Re-run the narrow check for that group before moving on; record what changed and its evidence here.
- [x] After all groups, inspect the complete diff for accidental scope, unsafe behavior, attribution, secrets, or regressions.

### 7. Final validation and handoff
- [x] Run the repository pre-push checks once on the final tree; confirm clean results and inspect generated screenshots.
- [x] Commit and push the reviewed fixes to `main` (commit `702373d`).
- [x] Inspect GitHub Actions run to verify all jobs (check, linux, android, windows, dependency scan) pass on CI: run `39407875887` passed completely across all jobs.
- [x] Confirm repository visibility is public as requested and verified clean.

### 8. Third-party QA, security hardening, and Frosted Glass UI redesign
- [x] Engine zombie prevention & timeout recovery: immediate `_process.send('stop')` on search error/timeout in `lib/engine/chess_engine.dart`, configurable timeout parameter, and whitespace-tolerant FEN tokenization (`RegExp(r'\s+')`).
- [x] EngineHost listener leak fix: `status.dispose()` added in `lib/engine/engine_host.dart` on disposal.
- [x] Threefold repetition & 50-move draw rules: strict repetition tracking across board, turn, castling rights, and en passant squares in `lib/game/game_controller.dart`. 50-move rule detection (`position.halfmoves >= 100`). Draw announcement reasons recorded.
- [x] Puzzle alternate checkmate recognition: `PuzzleSession.playerMove` accepts any move delivering checkmate as solving the puzzle.
- [x] Android native PiP crash safety: `enterPictureInPictureMode` wrapped in try/catch in `android/app/src/main/kotlin/com/example/chess_coach/MainActivity.kt`.
- [x] Local LLM model permissions: model files restricted to `0600` on Linux via `secureDataFile` in `lib/coach/llm/model_store.dart`.
- [x] Frosted Glass UI redesign: elevated Obsidian Dark, Frosted Pearl Light, and Warm Mahogany palettes with translucent blurred surfaces (`BackdropFilter(sigmaX: 12, sigmaY: 12)`), specular borders (`0x24FFFFFF` / `0x1A000000`), frosted navigation bar, refined time control hero card, and clean distraction-free calm gameplay without arcade badges.
- [x] Full validation: 199/199 Flutter tests pass, 8/8 screenshot suites pass, secret scanner reports 0 findings across all 1,632 objects. Pushed as commit `39e7e56`.

## Next step

All audit tasks 0 through 8 from the audit document, independent third-party QA fixes, and the professional Frosted Glass UI redesign are complete. GitHub Actions CI run `39417921186` passed 100% across all jobs (Analyze, test, screenshots; OSV scan; Windows build; Linux build; Android APK). All builds are verified and clean.

## Decisions

- Flutter 3.47.7 with `fluent_ui` (Fluent design), `chessground` (Lichess board widget) and `dartchess` (rules).
- Board per theme: Light = blue + 3D Classic pieces, Dark = blue2 + 3D Classic, Wooden = wood4 + 3D Wood. Settings
  (and the first-start setup) offer all 25 chessground boards and every piece set; the choice syncs.
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
- Sync uses a "Desktop app" OAuth client with the loopback flow on all platforms (no Google Play services or
  extra SDK); the only scope is drive.appdata. Since v0.9.2 the refresh token lives in its own file in the
  app-private folder (`lib/sync/token_store.dart`, mode 600 on Linux), moved there from the preferences once.
  The client secret ships inside the app by design: Google treats installed-app secrets as public, and PKCE
  plus the random `state` protect the sign-in.
  "When the network returns" is handled with a few backed-off retries after a failed sync, instead of a
  connectivity plugin that would keep listening.
- The project must stay 100% free: no billing account on the Google Cloud project, only free APIs.
- The Android manifest now asks for INTERNET (needed for the model download and sync).
- LLM runtime: `llamadart` pinned to 0.11.1 (the package changes every few days); only its llama.cpp runtime and
  CPU backend are bundled (`hooks: user_defines` in pubspec.yaml). Targets without a prebuilt runtime (32-bit
  Android) just skip it, and the coach keeps its templates.
- The model never sees the board and never chooses moves: it only rewords a sentence built from engine facts.
  With Qwen2.5 0.5B about half of the answers pass the safety check on this PC (0.5–1 s each after a 3 s load);
  the rest fall back to the template. The 1.5B model writes nicer English at 1–2 s per answer on this PC.

- Security review (v0.9.2):
  - Every event from disk or Drive passes `lib/data/event_validation.dart` (legal moves, field types and
    ranges, 64 KB per event); bad ones are skipped, unknown types from newer versions are kept.
  - The sync file is limited to 32 MB packed / 128 MB unpacked; settings dates far in the future are ignored.
  - The loopback sign-in ignores requests without the right `state` and sends strict headers.
  - Synced settings are type-checked and the coach Elo is clamped to 400–3200.
  - Model files are re-hashed whenever their size or date changes (marker in the preferences, not in
    Documents), and downloads refuse redirects off HTTPS.
  - Android: `allowBackup=false`, data extraction rules exclude everything, no cleartext traffic.
  - CI: actions pinned to commit SHAs, read-only token except for the release job, tag builds fail without the
    release key, appimagetool and the llama.cpp runtime (`tool/check_native_bundles.dart`) are checked against
    pinned SHA-256 digests, release builds are obfuscated, and releases carry `SHA256SUMS.txt`.

- Open source (17 Oct 2026): repo public under GPL-3.0 (required anyway by Stockfish, Maia, chessground and
  dartchess). GitHub secret scanning with push protection, private vulnerability reporting (`SECURITY.md`),
  Dependabot alerts and security updates (`dependabot.yml`), read-only default workflow token, rulesets that
  block force-pushes and deletion of `main` and of `v*` tags (no bypass actors). The workflow has no
  pull-request trigger, and forks never receive the repository secrets. `.claude/` is local only (untracked).
- Public-repo audit (17 Oct 2026): full history scanned — no secrets, keys or personal files were ever
  committed; the rulesets (created empty) were rebuilt with real rules; Dependabot weekly updates merged;
  the git identity, the .deb maintainer and the website switched to the private GitHub noreply address;
  the landing site (docs/, GitHub Pages) went live with fresh screenshots. Only the 2FA choice remains with
  the owner.

- 3D pieces: modelled and rendered in Blender 4.5 LTS by `tool/pieces/staunton.py` (lathe profiles, extruded
  knight, Cycles, AgX), packed to WebP at 1x/2x/3x by `tool/pieces/package.py` (about 3.8 MB for ten sets). The
  Lichess sets stay available; the owner found them too alike.
- In-app updates (`lib/app/updater.dart`): checks GitHub Releases a few seconds after start and on resume (at most
  every 4 hours), offers the update every start until installed ("Later" skips this run). Files are checked
  against the release's `SHA256SUMS.txt`; Android installs the APK through `ota_update` (core library
  desugaring on), Windows runs the Inno installer silently, AppImage replaces itself, .deb uses pkexec.
- Android sign-in uses Google Play services (`google_sign_in` 7) with a Web client as server client ID, falling
  back to the browser flow when Play services can't do it. Desktop keeps the loopback flow.
- AppImage runtime pin (20 Oct 2026): use the immutable AppImage `20251108` runtime, whose GPG signature was
  verified against the upstream type2-runtime signing key; never pin the mutable `continuous` asset.
- Private-repo preference (20 Oct 2026): keep `saad-rafeque/chess-coach` private until the owner says otherwise.
  Recheck privacy after any repo-setting change. Do not enable paid GitHub or cloud features. The free plan does
  not provide repository rulesets or native secret scanning while this repo is private.
- First start (`lib/screens/onboarding_page.dart`): name, coach's name, level, look, optional sync. The level is
  stored as a `profile` event that sets every skill area's starting rating; the coach starts 100 below it.
  Names sync with the settings. Settings > Profile can run the setup again.
- Guided review (`lib/review/guided_review.dart`): after a game the coach asks whether to go through the
  blunders, the mistakes (mistakes and inaccuracies) or the whole game, then shows per move what happened, the
  better move with an engine line, where the played move leads (both can be played out on the board) and a
  habit for next time, chosen by error kind and game phase.
- Board effects and sounds (v1.0.0): wooden move, capture, check, victory and defeat sounds in games, puzzles
  and lessons (`lib/app/board_sound.dart`, `assets/sounds/`, audioplayers), phone vibrations for the player's
  own moves, both with Settings toggles (on by default); the square of a checked king pulses red on every
  board (`lib/widgets/check_pulse.dart`).
- Look and feel (v1.0.1, the owner's second feedback round): the phone board sits centred on the screen with
  the coach's latest message (or the puzzle's status) as a slim strip under it, tapping it slides up the full
  panel (`BoardLayout.peek` + `PeekBubble`); the desktop side panel hides behind a dock button so the board
  takes the whole window, centred; every theme starts with the classic clearly-shaped piece set (cburnett)
  instead of the 3D renders; new synthesized sounds (crisp taps, soft bell, chime, calm drop —
  `tool/synth_sounds.py`); the repo went public again so the in-app updater sees releases.

## How to resume

Pull the repo, read `PLAN.md`, then continue from "Next step" above. Flutter is in `~/development/flutter/bin`
(not on PATH). Run `bash tool/fetch_engines.sh linux` once for the desktop engine.
