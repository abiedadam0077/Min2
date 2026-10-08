# Setup

VoxelOps is a Minecraft Server Manager powered by **GitHub Actions + Google Drive + Tailscale**.
Servers run only on **GitHub-hosted runners** (`ubuntu-latest`). You do not need a VPS, a home server,
or a self-hosted runner, and the app has no setting for them.

You need a GitHub account and a Google account. Tailscale is optional. Nothing below needs a credit card.

## 1. Google Drive (required)

VoxelOps uses Google's standard sign-in (OAuth 2.0 with PKCE, through the system browser). You never
paste a token into the app. Google's consent screen asks for three basic profile scopes and the
`drive.file` scope. `drive.file` only lets VoxelOps see the files and folders it creates.

1. Google Cloud Console → create or select a project.
2. **APIs & Services → Library → Google Drive API → Enable**.
3. **APIs & Services → OAuth consent screen**: user type *External*, app name `VoxelOps`, your email as
   support and developer contact. Add the scopes `openid`, `.../auth/userinfo.email`,
   `.../auth/userinfo.profile` and `https://www.googleapis.com/auth/drive.file`.
   Under **Test users** add your Google account. Then press **Publish app**. `drive.file` is a
   non-sensitive scope, so publishing does not need Google's app verification. Apps left in "Testing"
   have their refresh tokens expire after seven days.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Android**
   - Package name: `com.voxelops.app`
   - SHA-1 certificate fingerprint: the SHA-1 of the key that signs the APK (section 3). For local
     debug builds, use the SHA-1 of `~/.android/debug.keystore`.
5. Copy the client ID (it ends with `.apps.googleusercontent.com`) and save it as the repository
   **variable** `GOOGLE_OAUTH_CLIENT_ID` (**Settings → Secrets and variables → Actions → Variables**).

The app derives the redirect URI from that client ID (`com.googleusercontent.apps.<id>:/oauth2redirect`)
in both Gradle and Dart, so there is nothing else to configure. The build warns when the variable is
missing or malformed.

After connecting, VoxelOps asks where to keep your servers: **Create folder** (default name
`Minecraft Servers`, editable) or **Choose existing folder** (only folders VoxelOps created are listed,
because `drive.file` cannot see other folders).

## 2. GitHub (required)

1. GitHub → Settings → Developer settings → **OAuth Apps → New OAuth App**.
2. Enable **Device flow**. The callback URL can be any URL you own.
3. Save the client ID as the repository variable `GITHUB_OAUTH_CLIENT_ID`.

VoxelOps requests the `repo`, `workflow` and `read:user` scopes. It creates the server repository,
writes the workflow and runner, and starts runs. Without the client ID, GitHub sign-in falls back to a
personal access token for developers; normal users should set the client ID.

## 3. Release signing (recommended)

Without a stable key, each CI build is signed with a different debug key, so updates may not install over
earlier builds and the Android OAuth client needs a new SHA-1. Create the key once:

```bash
keytool -genkeypair -v -keystore voxelops-release.p12 -storetype PKCS12 -alias voxelops \
  -keyalg RSA -keysize 4096 -validity 36500
keytool -list -v -keystore voxelops-release.p12 -alias voxelops | grep SHA1
```

Put the **SHA1** line into the Android OAuth client (step 1.4). Then add these repository **secrets**:

- `ANDROID_KEYSTORE_BASE64`: `base64 -w0 voxelops-release.p12`
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`voxelops`), `ANDROID_KEY_PASSWORD`

Keep the keystore and its passwords safe. Losing them means installed copies cannot be updated.

## 4. Tailscale (optional)

1. Tailscale admin console → **Settings → OAuth clients → Generate**.
2. Scopes: **Devices (read)** and **Auth keys (write)**. Tag: `tag:minecraft`, defined in your ACL
   (`tagOwners`).
3. In VoxelOps: **Connect Services → Tailscale**, then paste the client ID and secret.

Servers created before connecting Tailscale: open the server settings and refresh the workflow and secrets.
Tailscale gives players a private address. Without it, players cannot reach the server from outside.

## 5. CurseForge (optional)

Create an API key in the CurseForge developer console, then **Accounts → CurseForge**. Modrinth needs no key.

## 6. Your first server

1. Install the APK from the latest release.
2. Connect GitHub and Google Drive, then choose the Server Storage folder.
3. Create a server. Keep the repository private unless you accept public logs.
4. Press **Start**. The first start downloads the server, so it can take a few minutes. Spigot and Forge take longer.
5. The dashboard shows Ready, Running or Stopping, plus links to the workflow and its logs.

## Limits you must know

- **GitHub's terms.** GitHub Actions is meant for development and testing. GitHub's terms restrict its
  use for unrelated activity, and running a game server on hosted runners may conflict with them.
  VoxelOps shows this before a server is created and asks you to acknowledge it. Your world stays in Google
  Drive, so a suspended repository does not remove your data. You are responsible for checking that your
  use fits GitHub's terms.
- **Six-hour job limit.** GitHub stops every job after six hours. The runner saves and starts a new run
  before the limit when auto-continue is enabled. Expect a short gap between runs.
- **Public repositories expose logs.** The runner hides IP addresses in logs, but keep the repository
  private where possible.
- **Minutes and storage** depend on your GitHub plan.
- **Google visibility.** `drive.file` shows only what VoxelOps created. Create server folders through the app.
