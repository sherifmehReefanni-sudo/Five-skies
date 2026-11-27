# Getting Five Skies onto TestFlight

This guide covers the one-time setup that only the account owner can do. After it, every new
TestFlight build is one click in GitHub. No Mac is needed: GitHub builds and uploads the app.

You need: a Windows PC, your iPhone, your paid Apple Developer (organization) account, and
admin access to this GitHub repository.

Names used below (copy them exactly):

| What | Value |
| --- | --- |
| App bundle ID | `app.fiveskies.ios` |
| Widget bundle ID | `app.fiveskies.ios.widgets` |
| App Group | `group.app.fiveskies.ios` |

---

## Step 1. Register the identifiers and create the app record

Do this in a browser at https://developer.apple.com/account, signed in with the account that
owns the developer team.

**Do these by hand.** The GitHub build may be able to create some of them by itself, but it is
not reliable for App Groups, and App Store Connect needs the app's bundle ID to exist before you
can create the app record. Doing all three by hand avoids a failed first run.

1. Go to **Certificates, Identifiers & Profiles**, then **Identifiers**.
2. Create the App Group first:
   1. Click the **+** button, choose **App Groups**, click **Continue**.
   2. Description: `Five Skies Group`. Identifier: `group.app.fiveskies.ios`.
   3. Click **Continue**, then **Register**.
3. Create the app's identifier:
   1. Click **+**, choose **App IDs**, then **App**, click **Continue**.
   2. Description: `Five Skies`. Bundle ID: choose **Explicit** and type `app.fiveskies.ios`.
   3. In the capabilities list, tick **App Groups**. Click **Continue**, then **Register**.
   4. Open the new `app.fiveskies.ios` entry again, click **Configure** (or **Edit**) next to
      App Groups, tick `group.app.fiveskies.ios`, click **Continue**, then **Save**.
4. Create the widget's identifier the same way:
   1. Description: `Five Skies Widgets`. Bundle ID (Explicit): `app.fiveskies.ios.widgets`.
   2. Tick **App Groups**, register, then configure it with `group.app.fiveskies.ios` and save.
5. (May be needed) Register your iPhone as a device. Apple's signing tools sometimes refuse to
   work for a team that has no devices at all, even for App Store builds. To be safe:
   1. On the PC, open the **Apple Devices** app (free in the Microsoft Store) or iTunes, and
      connect the iPhone with a cable.
   2. On the device summary, click the **Serial Number** text until it changes to **UDID**.
      Right-click or select it to copy it.
   3. In **Certificates, Identifiers & Profiles**, go to **Devices**, click **+**, platform iOS,
      give it a name (for example `My iPhone`), paste the UDID, then **Continue** and **Register**.

What the GitHub build creates by itself (you do not need to make these):

- Signing certificates (development, and the cloud-managed distribution certificate).
- Provisioning profiles for both the app and the widget.

Now create the app record in App Store Connect:

6. Go to https://appstoreconnect.apple.com, then **Apps**, click the **+** button, then
   **New App**.
7. Fill in:
   - Platforms: **iOS**
   - Name: `Five Skies` (if the name is taken, add a word, for example `Five Skies: Prayer Times`;
     this is the store name only and can change later)
   - Primary language: English (U.S.)
   - Bundle ID: pick `Five Skies - app.fiveskies.ios` from the list
   - SKU: `fiveskies-ios` (any text you like; nobody sees it)
   - User Access: **Full Access**
8. Click **Create**.

## Step 2. Create an App Store Connect API key

This key lets GitHub sign and upload builds for you.

1. In App Store Connect, go to **Users and Access**, then the **Integrations** tab, then
   **App Store Connect API** (choose **Team Keys** if asked).
2. If this is the first key, click **Request Access** and accept. Then click **Generate API Key**
   (or the **+** button).
3. Name: `GitHub TestFlight`. Access: **Admin**.
   App Manager is enough to upload, but Apple's cloud signing (which the build uses because
   there is no Mac) has been reported to refuse keys below Admin. Use Admin.
4. Click **Generate**.
5. Write down two values shown on the page:
   - **Key ID** (a short code next to your key's name, for example `2X9R4HXF34`)
   - **Issuer ID** (a long code with dashes, shown above the list of keys)
6. Click **Download API Key**. You get a file named like `AuthKey_2X9R4HXF34.p8` in your
   Downloads folder. **Apple lets you download it only once.** Keep it somewhere safe and private.
   Never email it or put it in the repository.

Also find your **Team ID**: on https://developer.apple.com/account, open **Membership details**.
It is 10 characters of capital letters and digits.

## Step 3. Add the four secrets to GitHub

1. First turn the `.p8` file into one line of text (base64). On the PC, open **PowerShell**
   (Start menu, type PowerShell) and run this single line, changing the file name to match yours:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_2X9R4HXF34.p8")) | Set-Clipboard
   ```

   Nothing is printed; the text is now on your clipboard. (If you prefer, ask for a
   double-click helper file that asks you to pick the `.p8` file and copies the text for you.)
2. On GitHub, open this repository, then **Settings**, then **Secrets and variables**, then
   **Actions**, then **New repository secret**. Add these four, one at a time. The names must
   match exactly:

   | Name | Value |
   | --- | --- |
   | `ASC_KEY_P8_BASE64` | Paste from the clipboard (the long text from step 1) |
   | `ASC_KEY_ID` | The Key ID from Step 2 |
   | `ASC_ISSUER_ID` | The Issuer ID from Step 2 |
   | `APPLE_TEAM_ID` | Your 10 character Team ID |

3. Paste only the value, with no spaces or quotes around it.

## Step 4. Run the TestFlight build

1. On GitHub, open the repository's **Actions** tab.
2. In the left list, click **TestFlight**.
3. Click **Run workflow** (on the right). Leave **Build number** empty; it uses a number that goes
   up by itself each run. Click the green **Run workflow** button.
4. Wait about 15 to 30 minutes. A green tick means the build was uploaded. A red cross means it
   failed; open the run and look at the red step, and download **testflight-logs** at the bottom
   of the run page if you need help.
5. After a green run, Apple processes the build. In App Store Connect, open the app, then the
   **TestFlight** tab. The build shows as "Processing" and then becomes available, usually within
   5 to 30 minutes. Apple also emails you when it is done.

## Step 5. Install it on your iPhone

1. In App Store Connect, app page, **TestFlight** tab, under **Internal Testing** click **+** to
   create a group (for example `Me`), then add yourself as a tester (your Apple account email must
   be a user in App Store Connect, which it is if you own the account). Add the new build to the
   group if it is not added already.
2. On the iPhone, install **TestFlight** from the App Store.
3. Open the invitation email on the iPhone and tap **View in TestFlight** (or open TestFlight
   and sign in with the same Apple Account). Tap **Accept**, then **Install**.
4. New builds you upload later show up in TestFlight automatically.

---

## What can go wrong the first time

Most likely first:

1. **"Cloud signing permission error" or "You haven't been given access to cloud-managed
   distribution certificates"** during the export step. The API key is not Admin. Make a new key
   with Admin access (Step 2) and update `ASC_KEY_ID` and `ASC_KEY_P8_BASE64`.
2. **"Your team has no devices from which to generate a provisioning profile"** during the archive
   step. Do Step 1, item 5 (register your iPhone), then run the workflow again.
3. **A message about agreements** ("PLA update", "unsigned agreement"). Sign in to
   developer.apple.com and App Store Connect (Business section) and accept any pending agreement,
   then run again.
4. **"Provisioning profile doesn't support the App Groups capability" or doesn't include
   `group.app.fiveskies.ios`.** One of the identifiers is missing App Groups or the group is not
   ticked. Recheck Step 1, items 3 and 4.
5. **"No suitable application records were found"** during upload. The app record from Step 1,
   item 6 is missing or uses a different bundle ID.
6. **"ASC_KEY_P8_BASE64 did not decode to a .p8 private key"** or **"secrets are missing"**. A
   secret name is misspelled or the value was pasted with extra text. Redo Step 3.
7. **"The bundle version must be higher than the previously uploaded version"**. Run the workflow
   again and type a bigger number in **Build number**.
8. **Too many certificates.** Each run may create a fresh Apple Development certificate. If a run
   fails saying the maximum number of certificates was reached, delete old ones on
   developer.apple.com under **Certificates** (the ones marked as created by the API are safe to
   revoke), then run again.
9. **A compile error that the normal test build does not show.** The TestFlight build uses
   Xcode 26 (Apple requires it for uploads) while the everyday test build uses Xcode 16. Send the
   log to whoever maintains the code.
