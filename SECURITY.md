# Security policy

## Reporting a problem

Please **don't open a public issue** for security problems. Report them privately instead:
open the repository's **Security** tab and click **Report a vulnerability**
(<https://github.com/saad-rafeque/chess-coach/security/advisories/new>).

Include what you found, how to reproduce it, and which version and platform you used. You'll get an answer
within a week, and a fixed release as soon as possible.

## Supported versions

Only the [latest release](https://github.com/saad-rafeque/chess-coach/releases/latest) gets security fixes.

## How releases are trusted

- Releases are built by GitHub Actions with SHA-pinned actions. Every file's SHA-256 is published in the
  release's `SHA256SUMS.txt`.
- `SHA256SUMS.txt` is signed at release time with an Ed25519 release key. The app pins the public half
  (`lib/app/release_key.dart`) and refuses to auto-install a release whose checksums do not carry that
  signature — a release published without the private key (for example after a takeover of the GitHub
  account) never installs itself automatically; the player is sent to the release page instead.
- To verify a download by hand: check the signature first
  (`dart run tool/sign_release.dart verify SHA256SUMS.txt <public key hex> SHA256SUMS.txt.sig` — the public
  key hex is in `lib/app/release_key.dart`), then compare your file's `sha256sum` with its line in
  `SHA256SUMS.txt`.
- Linux builds are reproducible: after every release, CI rebuilds the AppImage, deb and tar.gz from the
  same commit and fails loudly unless their hashes match the published `SHA256SUMS.txt`. Windows artifacts
  are built with fixed timestamps (`SOURCE_DATE_EPOCH`) so they stay comparable across builds; a rebuild
  verification job for them is planned.

## How the app protects you

- No server: data stays on your device, and optional sync goes straight to a hidden folder in your own
  Google Drive (`drive.appdata` permission only).
- Google sign-in uses the system browser with PKCE and a random `state`; the refresh token is kept in the
  platform keychain (Windows DPAPI, Linux libsecret, macOS Keychain, Android Keystore) and falls back to a
  file only your user account can read where no keychain exists. Android excludes the app from backups.
- Everything read from the sync file or the data folder is validated before use, with size limits.
- Downloads (language model, engine, packaging tools, llama.cpp runtime) are checked against pinned SHA-256
  digests, and update and model downloads never follow a link off the release host. The language model is
  re-hashed once per session right before it is loaded, so a file swapped in after its last check is refused.
- Releases are built by GitHub Actions with pinned actions and come with `SHA256SUMS.txt`, its signature,
  and a CycloneDX SBOM. Dependencies are scanned for known vulnerabilities on every push and pull request.

The Google OAuth client ID and secret are built into the app. That is how Google's sign-in works for installed
apps: Google does not treat that secret as confidential. It gives no access to anyone's data without their
own sign-in.

## Incident response

1. Reports arrive through the private channel above and are acknowledged within a week.
2. Confirmed problems get a fix and a new release; the release notes say what was fixed. No public detail
   until the fixed release is out.
3. If the release signing key or the GitHub account is compromised: rotate the key
   (`dart run tool/sign_release.dart gen`, update `lib/app/release_key.dart` and the `RELEASE_SIGNING_KEY`
   secret), enable MFA, revoke any unknown collaborators, and say so in the next release notes.

## Decision log (security advisory review)

| Suggestion | Decision | Reason |
|---|---|---|
| Sign SHA256SUMS.txt with a pinned key | Adopt | Closes the same-origin checksums gap: a takeover of the GitHub account alone cannot auto-install anything |
| Manual redirect validation (updater, model downloads) | Adopt | Requests never reach an unvalidated host |
| Keychain token storage (flutter_secure_storage) | Adopt | Encrypts the refresh token at rest; file with mode 600 remains as fallback |
| Model re-hash before load | Adopt | Closes the stamp TOCTOU without hashing on every explanation |
| SHA256SUMS.txt for every release | Already present | Extended with the signature |
| SBOM in CI (CycloneDX) | Adopt | Dependency inventory for vulnerability tracking |
| Dependency audit in CI | Adopt | osv-scanner on pubspec.lock, SARIF to Code Scanning |
| Dependabot (pub + actions) | Adopt | Every bump is gated by the CI check job |
| Pin GitHub Actions by SHA, least-privilege permissions, mandatory signing key on tags | Already present | Extended: the release signing key is now also mandatory |
| Secret scanning with push protection, MFA, branch protection | Adopt (GitHub settings) | Manual steps for the maintainer, listed below |
| CodeQL | Skip | CodeQL has no Dart support; `flutter analyze` + osv-scanner + the test suite cover it |
| Sigstore/cosign | Skip | The pinned Ed25519 release key covers the same need without new infrastructure |
| SLSA provenance | Defer | Revisit after the reproducible-build verification job has settled |
| Reproducible builds for desktop releases | Adopt | Linux: rebuild-and-compare job after every release. Windows: `SOURCE_DATE_EPOCH` normalization, verify job to follow |
| Electron hardening (contextIsolation, CSP, IPC checks, fuses, custom protocol) | Skip | Not an Electron app |
| Lichess puzzle download checksum in build_puzzles.py | Skip | Dev-time only; lichess publishes no official checksums to pin |
| Threat model document, pen test, fuzz testing | Defer | Revisit before 2.0 |

## Manual settings for the maintainer

These live in GitHub's settings, not in the repository:

- Require MFA for all collaborators, and keep collaborator access to a minimum.
- Protect `main`: require pull requests, at least one review, and a passing check job; no direct pushes.
- Enable secret scanning with push protection.
- Add the `RELEASE_SIGNING_KEY` secret (the seed hex from `tool/sign_release.dart gen`; releases fail
  without it).
