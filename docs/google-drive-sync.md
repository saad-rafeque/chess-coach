# Setting up Google Drive sync (one time, about 10 minutes)

> **Status (16 Oct 2026):** done for this repo. Project `chess-coach-511811`, Desktop client "Chess Coach",
> app in **Testing** with saadrafiique@gmail.com as test user, scope `drive.appdata` only, no billing account.
> Both GitHub secrets are set. In Testing, Google expires the sign-in after about a week; the app then asks
> you to tap Connect again. To avoid that, the app would need a public home page and privacy policy so it can
> be published (step 5), which needs a public page (for example a public repo).

Sync keeps your phone, Windows PC and Ubuntu PC in step. Each device stores your games, puzzles and lessons
locally; the app merges them through **one small file in a hidden app folder of your Google Drive**. Only
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
3. Google shows **"Google hasn't verified this app"**. That's expected for a personal app: click
   **Advanced**, then **Go to Chess Coach (unsafe)**, then **Continue**.
4. The page says "Signed in". Go back to Chess Coach: it syncs right away.

Do this on each device with the same Google account. From then on the app syncs by itself when it opens and
when you close it or switch away, and it retries a few times if you are offline. **Sync now** forces a sync,
and **Disconnect** stops it on that device (the file in Drive stays).
