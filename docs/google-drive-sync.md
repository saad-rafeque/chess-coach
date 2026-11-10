# Setting up Google Drive sync (one time, about 10 minutes)

> **Status (17 Oct 2026):** done for this repo. Project `chess-coach-511811`, Desktop client "Chess Coach",
> scope `drive.appdata` only (non-sensitive, so Google needs no verification), no billing account. The app is
> **In production**: anyone can connect their own Google account and the sign-in no longer expires weekly.
> Home page and privacy policy: <https://saad-rafeque.github.io/chess-coach/> (GitHub Pages from `docs/`),
> authorised domain `saad-rafeque.github.io`. Both GitHub secrets are set; forks don't receive them.

Sync keeps your phone, Windows PC and Ubuntu PC in step. Each device stores your games, puzzles and lessons
locally; the app merges them through **private snapshots in a hidden app folder of your Google Drive**. Only
Chess Coach can see that folder, and it can't see any of your other files.

Google needs a "client" for the app's sign-in. Because this is your personal app, you create it in your own
Google account. You do this once; after that every new build has sync built in.

## 1. Create a project

1. Open <https://console.cloud.google.com/> and sign in with the Google account you want to sync with.
2. At the top left, click the project picker (it may say **Select a project**), then **New project**.
3. Project name: `Chess Coach`. Click **Create**, wait a few seconds, then select the new project in the
   project picker.

## 2. Turn on the Google Drive API

1. Open <https://console.cloud.google.com/apis/library/drive.googleapis.com> (make sure the project picker shows
   **Chess Coach**).
2. Click **Enable**.

## 3. Describe the app (the consent screen)

1. Open <https://console.cloud.google.com/auth/overview> and click **Get started**.
2. **App information**: App name `Chess Coach`, User support email: your email. Click **Next**.
3. **Audience**: choose **External**. Click **Next**.
4. **Contact information**: your email. Click **Next**.
5. Tick **I agree to the Google API Services: User Data Policy**, click **Continue**, then **Create**.

## 4. Allow only the hidden app folder

1. In the left menu click **Data access**, then **Add or remove scopes**.
2. In the filter box type `drive.appdata` and tick the row
   `.../auth/drive.appdata` ("See, create, and delete its own configuration data in your Google Drive").
3. Click **Update**, then **Save** at the bottom of the page.

## 5. Publish the app (so you don't have to sign in again every week)

1. In the left menu click **Audience**.
2. Under **Publishing status**, click **Publish app**, then **Confirm**.
   (You don't need Google's verification for your own use. If the button isn't there, add your email under
   **Test users** instead; then the app asks you to sign in again about once a week.)

## 6. Create the sign-in client

1. In the left menu click **Clients**, then **Create client**.
2. Application type: **Desktop app**. Name: `Chess Coach`. Click **Create**.
3. A window shows the **Client ID** (ends with `.apps.googleusercontent.com`) and the **Client secret**
   (starts with `GOCSPX-`). Keep this window open, or click **Download JSON**.

The same Desktop client works on the phone too: the app signs in through your browser on every device.

## 7. Give the client to the GitHub builds

1. Open your repository's **Settings → Secrets and variables → Actions** (for this repo:
   <https://github.com/saad-rafeque/chess-coach/settings/secrets/actions>).
2. Click **New repository secret**. Name: `GOOGLE_OAUTH_CLIENT_ID`. Secret: paste the Client ID. Click
   **Add secret**.
3. Click **New repository secret** again. Name: `GOOGLE_OAUTH_CLIENT_SECRET`. Secret: paste the Client secret.
   Click **Add secret**.
4. Push a new version tag (for example `v1.0.1`); that release includes sync. Forks never see these secrets:
   a fork builds without sync until its owner adds their own client.

## 8. Connect each device

1. Install the new build, open **Settings → Google Drive sync → Connect**.
2. Your browser opens Google sign-in. Choose your account.
3. Google asks you to allow Chess Coach to use its own folder in your Drive. Click **Continue** / **Allow**.
   (If you set up your own client and left it in Testing, Google first shows "Google hasn't verified this app":
   click **Advanced**, then **Go to Chess Coach**.)
4. The page says "Signed in". Go back to Chess Coach: it syncs right away.

Do this on each device with the same Google account. From then on the app syncs by itself when it opens and
when you close it or switch away, and it retries a few times if you are offline. **Sync now** forces a sync,
and **Disconnect** stops it on that device (the file in Drive stays).

## Concurrent devices and migration (November 2026)

Each current installation writes only its own `chess-coach-snapshot.json.gz` file, identified by a random
local writer ID. Every sync lists and reads all current snapshots plus every legacy
`chess-coach-sync.json.gz` file, merges events by ID, and applies the newest valid settings timestamp.
It never writes another installation's snapshot and never deletes legacy or duplicate files. This
avoids two devices overwriting each other's events while uploading at the same time. Reconnecting
the same installation reuses its snapshot; reinstalling may leave an additional read-only snapshot.

**Update every device to this version for two-way sync.** Old versions can continue writing their
legacy file, and the new version imports those changes, but old versions cannot read the new snapshot
files. This deliberate compatibility boundary protects new snapshots from old shared-file writers.

Sync is eventually consistent: an offline device keeps its progress locally, and a concurrent upload
that arrives after another device's read is picked up on the next successful sync. “Synced” records
the last successful exchange; it cannot mean that currently offline devices have received it.
Settings-only changes are uploaded on backgrounding, and changes made during an upload trigger a
follow-up pass. Account disconnect/cancel invalidates pending results before they can modify local
account metadata or merge newly downloaded data. A network request already sent cannot be recalled.

Discovery follows all `nextPageToken` results as specified by Google's
[files.list API](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list),
using only the [private appDataFolder](https://developers.google.com/workspace/drive/api/guides/appdata).
It does not rely on undocumented compare-and-swap behavior for media uploads.
