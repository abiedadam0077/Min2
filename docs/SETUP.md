# Setup

VoxelOps needs three accounts that only you can create: GitHub, Google and (optionally) Tailscale. Nothing below needs a credit card.

## 1. Build-time OAuth client IDs (repository variables)

Set these in **Settings → Secrets and variables → Actions → Variables**. Client IDs are public identifiers, not secrets.

| Variable | How to get it |
| --- | --- |
| `GITHUB_OAUTH_CLIENT_ID` | GitHub → Settings → Developer settings → OAuth Apps → New. Enable **Device flow**. Callback URL can be any URL on your domain. |
| `GOOGLE_OAUTH_CLIENT_ID` | Google Cloud Console → APIs & Services → Credentials → OAuth client ID → **Android**, package `com.voxelops.app`, and the SHA-1 of the signing key (see below). Enable the **Google Drive API**. |

If you skip GitHub OAuth, the app still works with a personal access token (scopes `repo`, `workflow`, `read:user`). Google sign-in needs the Android client.

## 2. Release signing (recommended)

Without a stable key CI signs with the debug key, so each build may not install over the previous one. Create a keystore once:

```bash
keytool -genkeypair -v -keystore voxelops-release.p12 -storetype PKCS12 -alias voxelops \
  -keyalg RSA -keysize 4096 -validity 36500
keytool -list -v -keystore voxelops-release.p12 -alias voxelops | grep SHA1
```

Add the **SHA-1** line to the Android OAuth client above. Then add these **secrets**:

- `ANDROID_KEYSTORE_BASE64`: `base64 -w0 voxelops-release.p12`
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`voxelops`), `ANDROID_KEY_PASSWORD`

Keep the keystore and its passwords safe. Losing them means existing installs cannot be updated.

## 3. Tailscale (optional)

1. Tailscale admin console → **Settings → OAuth clients → Generate**.
2. Scopes: **Devices (read)** and **Auth keys (write)**.
3. Tags: `tag:minecraft`. Define the tag in your ACL (`tagOwners`) for the OAuth client.
4. In VoxelOps: More → Accounts → Tailscale. Paste the client ID and secret. Use `-` for the default tailnet.

Servers created before connecting Tailscale: open Settings → Repository → **Refresh workflow and secrets**.

## 4. CurseForge (optional)

Create a key at the CurseForge developer console, then More → Accounts → CurseForge. Modrinth works without a key.

## 5. Your first server

1. Install the APK from the latest release.
2. Sign in to GitHub, connect Google Drive, optionally connect Tailscale.
3. Create a server. Keep the repository private unless you accept public logs.
4. Press **Start**. The first start downloads the server and may take a few minutes (Spigot and Forge take longer).
5. Join with the Tailscale address shown on the dashboard. Without Tailscale the server runs on a GitHub runner that has no public inbound address, so players cannot connect directly.

## Limits you must know

- **GitHub-hosted runners and game servers.** GitHub's terms restrict use of Actions to development and testing, and running game servers on hosted runners can violate them. Use your own runner for long-running servers: set the runner label in the wizard (for example `self-hosted`) and register the runner on a machine you control.
- **Six-hour job limit.** The runner saves and hands over to a new run before the limit when auto-continue is enabled. Expect a short gap.
- **Public repositories expose logs.** The runner redacts IP addresses, but keep repositories private where possible.
- **Minutes and storage.** Hosted runner minutes and Actions storage depend on your GitHub plan.
- **Google testing mode.** Apps in "Testing" can have refresh tokens expire after seven days. Publish the consent screen for long-term use.
