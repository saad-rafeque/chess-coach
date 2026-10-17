# Security policy

## Reporting a problem

Please **don't open a public issue** for security problems. Report them privately instead:
open the repository's **Security** tab and click **Report a vulnerability**
(<https://github.com/saad-rafeque/chess-coach/security/advisories/new>).

Include what you found, how to reproduce it, and which version and platform you used. You'll get an answer
within a week, and a fixed release as soon as possible.

## Supported versions

Only the [latest release](https://github.com/saad-rafeque/chess-coach/releases/latest) gets security fixes.

## How the app protects you

- No server: data stays on your device, and optional sync goes straight to a hidden folder in your own
  Google Drive (`drive.appdata` permission only).
- Google sign-in uses the system browser with PKCE and a random `state`; the sign-in token is stored in a file
  only your user account can read, and Android excludes the app from backups.
- Everything read from the sync file or the data folder is validated before use, with size limits.
- Downloads (language model, engine, packaging tools, llama.cpp runtime) are checked against pinned SHA-256
  digests. Releases are built by GitHub Actions with pinned actions and come with `SHA256SUMS.txt`.

The Google OAuth client ID and secret are built into the app. That is how Google's sign-in works for installed
apps: Google does not treat that secret as confidential. It gives no access to anyone's data without their
own sign-in.
