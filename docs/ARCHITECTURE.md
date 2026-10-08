# Architecture

VoxelOps is a native Flutter app (Android, Dart 3.10+) with a separate Python runner that executes inside each server's GitHub Actions workflow. There is no WebView and no web content.

## Layers

```
lib/
  app/        Routing (go_router), shell (bottom tabs), root MaterialApp
  core/       Cross-cutting: config, errors, HTTP client, secure storage, i18n, theme, motion,
              layout tokens, shared widgets, formatting
  domain/     Pure models: server, server draft, GitHub/Drive/Tailscale/content DTOs
  data/       Services that talk to the outside world
    github/       REST API, device flow, libsodium sealed boxes for secrets
    google/       AppAuth sign-in, Drive v3 client (resumable uploads)
    tailscale/    OAuth client-credentials API
    minecraft/    Version catalogue, server.properties, workflow renderer, icon builder
    content/      Modrinth and CurseForge clients, compatibility checks
    provisioning/ Create/import/rebind servers, server actions, Drive layout
    local/        SharedPreferences wrapper (no secrets)
  state/      Riverpod providers: service graph, auth, servers, live polling, wizard draft
  features/   Screens grouped by feature (home, servers, dashboard, console, content, files,
              backups, settings, create, connect, accounts, import, notifications, more)
assets/runtime/voxelops_runner.py   Runner shipped into every server repository
```

Dependency direction: `features -> state -> data -> domain`. `core` is depended on by everything, and depends on nothing feature-specific. Screens never call HTTP directly.

## State management

- `sharedPreferencesProvider` is overridden in `main()` after loading, so every provider is synchronous where it can be.
- Auth state is a `Notifier` (GitHub accounts, multiple accounts with an active one) or `AsyncNotifier` (Google, Tailscale).
- The server list is a `Notifier` backed by SharedPreferences. Active server id is persisted separately.
- Live data uses `StreamProvider.autoDispose.family` pollers: status every 12 s, console every 6 s, workflow runs every 20 s. They stop when the last widget leaves the screen.
- Wizard draft and creation job are notifiers, so progress survives navigation.

## Secrets and storage

| Data | Where | Why |
| --- | --- | --- |
| GitHub tokens (one per account) | `FlutterSecureStorage` (Android Keystore) | Never in prefs or logs |
| Google refresh token | `FlutterSecureStorage` | Only `drive.file` scope |
| Tailscale client ID and secret | `FlutterSecureStorage` | Used to verify and to write GitHub secrets |
| CurseForge API key | `FlutterSecureStorage` | User-owned key |
| Server list, active server, language, account names | SharedPreferences | Not sensitive |
| Drive folder id, Drive refresh token, Tailscale secret for the runner | GitHub Actions secrets (encrypted client-side with the repo public key) | The runner needs them; nothing is committed to the repo |
| OAuth client IDs (GitHub, Google) | `--dart-define` from repository variables | Public identifiers, not secrets |

No client secret is compiled into the APK. Android backups are disabled (`allowBackup=false`) so tokens are not copied off the device.

## Google Drive as the source of truth

Each server lives at `Minecraft Servers/<Name>/` (the storage root is configurable; system files live in `_voxelops/`) (see `DriveLayout`). Recovery needs only the Drive folder and a GitHub repository:

1. `Import existing server` lists folders that contain `metadata.json`.
2. `attachToRepository` reads metadata, writes the workflow and runner, and re-creates the secrets in the chosen repository.
3. The next start pulls every mirrored folder before launching Minecraft.

## App to runner protocol

| Direction | Mechanism | Content |
| --- | --- | --- |
| App to runner (commands) | New file in `control/commands/` | JSON `{type, requestedAt, payload}`; types: `stop`, `restart`, `kill`, `backup`, `sync`, `console`, `restore`, `import` |
| Runner to app (status) | `control/status.json`, every 15 s | state, players, CPU, RAM, uptime, Tailscale IP, sync state, last error, last backup and sync times |
| Runner to app (console) | `control/live.log`, every 15 s | last 400 log lines (IP addresses redacted) |
| App to GitHub | REST: dispatch, runs list, cancel and force-cancel | Start, and last-resort kill when the runner does not answer |
| Runner to GitHub | REST dispatch with `GITHUB_TOKEN` | Continues the server after the six-hour limit |

Commands are processed in file-name order (timestamp prefix), trashed after processing, and never block the status loop for long.

## Runner lifecycle

1. Install the server software (Mojang, Fabric meta, Fill v3 Paper, Purpur, Forge/NeoForge installers, or BuildTools for Spigot with a Drive cache).
2. Pull `server.properties`, `eula.txt`, `server-icon.png`, `world*`, `mods/`, `plugins/`, `config/` from Drive (mirror, md5-compared).
3. Apply pending `imports/*.zip` (renamed to `applied-*`).
4. Start Minecraft with the memory limit from `control/runtime.json`.
5. Loop every 5 s: commands, status and console uploads, periodic sync (flush, upload changed files, trash removed files), periodic automatic backups, crash recovery (up to three restarts).
6. Before any stop, restart or restore: `save-all flush`, wait for "Saved the game", then `stop`, then final sync.
7. At 330 minutes: save, sync, and dispatch the next run when auto-continue is on.

## Error handling

- `ApiClient` retries idempotent requests on 429 and 5xx with `Retry-After`, and maps every failure to `AppException` with a typed `AppErrorKind`.
- The UI maps kinds to localized copy (`describeError`). Technical messages never contain tokens.
- `guardedAction` shows a snackbar and records failures in the notification centre.
- Offline: pollers keep the last good data; status shows "stale" after two minutes.

## Testing

- Unit: sealed box interop (PyNaCl vector), server.properties round trip, workflow rendering, hostname rules, NeoForge mapping, i18n key parity, model JSON, formatting, icon builder, runner protocol markers.
- Widget: RTL rendering, floating navigation callbacks, state chips.
- CI runs `flutter analyze`, `flutter test`, then builds and publishes the release APK.
