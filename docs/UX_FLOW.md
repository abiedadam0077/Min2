# UX flow

## Information architecture

Bottom tabs: **Home**, **Servers**, **Mods**, **Console**, **More**.
Pushed screens: Welcome, Connect, Accounts, Repository picker, Create wizard, Creation progress, Import, Notifications, Server dashboard, Files, File editor, Backups, Server settings.

## First run

1. **Splash** (1.4 s) loads the saved state.
2. **Welcome** introduces the three services and the language switch (Arabic or English). "Get started" stores onboarding as done.
3. **Connect** lists GitHub (required), Google Drive (required) and Tailscale (optional).
   - GitHub: device flow (code plus "Open GitHub"), or a personal access token when no client ID is configured.
   - Google: system browser sign-in (AppAuth). Only `drive.file` is requested.
   - Tailscale: OAuth client ID, secret and tailnet. Verified by listing devices before saving.
4. **Continue** unlocks Home once GitHub and Drive are connected. Redirect guards send users back to Connect otherwise.

## Create a server (wizard)

1. **Software**: Vanilla, Fabric, Forge, NeoForge, Paper, Purpur or Spigot, each with a one-line description.
2. **Version**: live list from the official source; Release or Snapshot filter; search. Choosing a version does not resolve the build yet.
3. **Details**: name (3 to 40 characters), description, optional icon (converted to 64 by 64 PNG).
4. **Settings**: MOTD, max players, game mode, difficulty, online mode (with warning), PvP, whitelist, Nether, seed; runner memory, backup interval, retention and auto-continue.
5. **Repository and consent**: choose an existing repository (with push access) or create a new one (private by default). GitHub-hosted runner (fixed: ubuntu-latest). EULA acceptance (required). GitHub Actions terms acknowledgement (required). Optional "start after creation".
6. **Review**: shows the resolved loader build and Java major version. "Create server" starts the job.
7. **Progress**: six steps with live status (resolve, Drive folders, repository, workflow and runner, encrypted secrets, first dispatch). Failure shows the exact reason with Retry or Edit settings. Success opens the dashboard.

## Dashboard

- Status card: state chip, players, uptime, version, last sync, stale and error notes.
- Connection card: Tailscale address (from the runner, or from the Tailscale API as a fallback), hostname, copy action.
- Controls: Start when offline. When running: Restart, Stop (confirmed; saves first), and Force kill (confirmed, escalates to cancelling the GitHub run if the runner does not respond).
- Quick actions: console, backups, mods, open the Drive folder.
- Metrics: players, CPU, memory, last backup.
- GitHub Actions: recent runs, each opening the run page.
- Danger zone: forget the server on this device only.

## Console

Filters (all, warnings, errors), colour by severity, auto-scroll, quick commands (`list`, `save-all flush`, `whitelist list`, `time query daytime`), and a text field. Commands are queued to the runner, so the response appears within about 10 to 20 seconds.

## Mods and plugins

- Tabs: Browse and Installed.
- Kinds follow the server: mods for Fabric, Forge and NeoForge; plugins for Paper, Purpur and Spigot; worlds from CurseForge for every server.
- Sources: all, Modrinth, CurseForge (needs a user API key). Sort: relevance, downloads, recently updated, newest.
- Each project opens a sheet of files filtered to the server's Minecraft version and loader. Each file shows a compatibility badge and a note. Unverified files can be installed after review.
- Install downloads the file, verifies its SHA-1 when published, and stores it in `mods/` or `plugins/` in Drive. Required dependencies are flagged, not auto-installed.
- Installed: list with remove (moves to Drive trash). World upload for `.zip` archives.

## Files

Browse the server folder in Drive. Folders open in place. Files support rename, delete (to trash), and save to the phone. Small text files (`server.properties`, JSON, YAML, TOML, logs) open in the editor with a save action and a warning when the server is running.

## Backups

Lists automatic, manual, pre-restore and imported archives with size and time. Actions: back up now, restore (confirmed; the runner first creates a pre-restore backup), delete (to trash), import a world archive.

## Settings

Server properties with the same controls as the wizard (applied at next start). Runner settings (memory, sync interval, backup interval, retention, auto-continue) applied at the next runner check. Repository: refresh workflow and secrets (needed after connecting Tailscale), attach to another repository, forget locally.

## More

Accounts and connections (switch GitHub accounts, add or remove, Google, Tailscale, CurseForge key), notifications, language (System, Arabic, English), Drive storage used, licences.

## Failure states

| Situation | What the user sees |
| --- | --- |
| No network | Cached data stays visible. Snackbar and error card explain the offline state. |
| Token rejected | "This account is not authorized. Reconnect it in Accounts." |
| Rate limited | "Too many requests. Wait a moment and try again." with automatic backoff. |
| Runner silent for more than two minutes | "Stale" note on the dashboard; kill escalates to GitHub cancellation. |
| Workflow missing (Actions disabled) | Clear message on Start, with the reason. |
| Drive folder missing | Import lists only folders that contain `metadata.json`. |
