# Working rules for this repo

The owner is a chess student, not a developer. You do all coding and testing and hand over finished builds.
The full spec is `PLAN.md`; current state is `PROGRESS.md`.

## How to work

- Work through the milestones in `PLAN.md` in order. Don't stop to ask questions: make a sensible choice,
  note it under "Decisions" in `PROGRESS.md`, and keep going.
- Commit and push after every working step (at least every hour of work), so nothing is lost if the
  session stops because credit runs out. Push to `main` if allowed; otherwise push your branch and write
  its name in `PROGRESS.md`.
- Keep `PROGRESS.md` current: milestone status, what's done, the exact next step, and how to resume.
- Each milestone is done only when its tests pass and the GitHub Actions workflow builds the Android APK,
  the Windows installer and the Linux AppImage. Attach the builds to a GitHub Release tagged `v0.<n>.0`.
- Write unit and widget tests for engine wrappers, coach detectors, the skill model and the sync merge.
- Keep token use low: read only the files you need and don't re-run checks that already passed.

## Style

- English everywhere (UI, docs, commit messages).
- No AI or tool attribution anywhere: no Co-Authored-By lines, no "Generated with" footers in commits,
  PRs, README, release notes or code comments.
