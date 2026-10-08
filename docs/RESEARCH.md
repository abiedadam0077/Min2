# Research notes

Sources were checked on 2026-10-08. Items marked **unverified** could not be confirmed from the build sandbox and must be validated on a real account.

## 1. UX patterns for server, DevOps and Minecraft apps

| Finding | Source | How VoxelOps uses it |
| --- | --- | --- |
| Floating toolbars are for contextual actions on a page; a bottom navigation bar is for primary destinations. Google does not pair a toolbar and a nav bar on the same page. | 9to5Google, Material 3 Expressive coverage (May 2025 and Dec 2025) | The bottom bar only switches the five top-level tabs. Page actions use the app bar and one floating action per page. |
| Material 3 Expressive uses spring-based motion instead of fixed easing, and short 64 dp navigation bars with persistent labels. | Material Design 3 Expressive web showcase (materialwebunofficial) | Motion tokens use physical curves (`easeOutCubic`, `fastOutSlowIn`, `easeOutBack` for emphasis). Navigation labels persist. |
| Dashboards should lead with health and critical alerts, use progressive disclosure, and keep 7 to 10 high-level charts. | DevOps dashboard guidance (Level.io, May 2026; DevOps Training Institute, Dec 2025) | Dashboard order: status card, connection card, controls, metrics (four cards), workflow runs. Details sit behind taps. |
| Mobile incident response needs responsive layouts and clear online and offline status. | Level.io, May 2026 | Every list shows a status chip. Stale status (no update for two minutes) is flagged. Cached data remains visible when offline. |
| Logs should be centralized, structured and filterable. | Digia, server-driven UI logging (Jan 2026) | Console tab filters (all, warnings, errors), colour by severity, quick commands, and a full run log stored in Drive `logs/`. |

Synthesised principles: calm dark surfaces, one primary action per card, state always visible (colour plus text), destructive actions behind confirmation, and Arabic-first RTL that is verified in widget tests.

## 2. Platform and API facts

- **GitHub Actions terms.** Actions may be used to develop and test applications. Using hosted runners for unrelated activity is prohibited. Running a continuous Minecraft server on GitHub-hosted runners is likely outside the permitted use. VoxelOps runs servers only on GitHub-hosted runners (ubuntu-latest), shows the terms to the user, requires an acknowledgement in the wizard, and keeps every world and backup in Google Drive so that a suspended repository never removes player data. No self-hosted or VPS option exists.
- **GitHub secrets.** Secrets must be encrypted with the repository public key (libsodium sealed box). VoxelOps uses `pinenacl` 0.6.0 `SealedBox`. The test suite decrypts a PyNaCl-generated vector to confirm compatibility.
- **GitHub device flow** (RFC 8628) needs no client secret, so the APK can ship without secrets. Personal access tokens are accepted as a fallback.
- **Google Drive `drive.file` scope** limits access to files the app creates. Refresh tokens are stored in Android Keystore-backed storage. Google may expire refresh tokens for apps in "Testing" status after seven days (**unverified** for this client; publish the consent screen or re-consent when this happens).
- **AppAuth (`flutter_appauth` 12.1.0)** provides PKCE for Android. The redirect scheme is the reversed client ID and must be injected into the manifest at build time, which CI does.
- **Modrinth API v2.** Search uses `facets`. Version lookups accept `loaders` and `game_versions`. A descriptive User-Agent is required. Modrinth has no world project type.
- **CurseForge API v1.** Requires a user API key in `x-api-key`. Minecraft gameId 432. Class IDs: mods 6, Bukkit plugins 5, worlds 17. Mod loader types: Forge 1, Fabric 4, Quilt 5, NeoForge 6. Relation type 3 means required dependency. Hash algorithm 1 is SHA-1.
- **PaperMC Fill v3.** Use `https://fill.papermc.io/v3/projects/paper`, build lists per version, and the `server:default` download. A custom User-Agent is required. The legacy `api.papermc.io/v2` stopped serving builds on 31 Dec 2025.
- **Purpur**, **Fabric meta** (`meta.fabricmc.net/v2`), **Mojang manifest** (`piston-meta`), **Forge** and **NeoForge** Maven metadata, and the **Spigot** hub (BuildTools) are read live by the version catalogue. The NeoForge version-to-Minecraft mapping is **unverified** for future schemes; the test suite covers the current patterns.
- **Tailscale.** OAuth client credentials grant against `api.tailscale.com/api/v2/oauth/token`. The official `tailscale/github-action@v3` joins the tailnet with OAuth secrets and a tag. The OAuth client needs `auth_keys` and devices read scopes.
- **Flutter 3.47.6 stable** and Gradle 9.5.0 with AGP 9.3.1 and Kotlin 2.4.20 are taken from Flutter's own Android template and `flutter_tools` constants.
- **Riverpod 3.4.3**, **go_router 18.0.2**, **flutter_secure_storage 10.3.4**, **http 1.5.0**, **file_selector 1.1.0**, **image 4.10.1**, **image_picker 1.2.4**, **shared_preferences 2.5.6** were verified against their tags.

## 3. Decisions

1. Flutter native UI only. No WebView anywhere.
2. Google Drive holds all durable state. The runner is stateless beyond a single job; a new run can rebuild everything from Drive.
3. The runner is Python with only the standard library, so no install step is needed on the runner.
4. Commands from the app are one JSON file each in `control/commands/`. The runner consumes them in name order and trashes them after processing. This keeps the protocol auditable and tolerant of phone disconnects.
5. Console output is a Drive file (`control/live.log`), polled by the app. This avoids any public endpoint.
6. Player IP addresses are redacted from runner logs because public repositories expose Actions logs.

## 4. Risks that remain

- **Terms of service** for hosted runners (above).
- **Six-hour job limit.** The runner stops at 330 minutes, saves, then dispatches a new run when auto-continue is on. There can be a short gap.
- **Actions minutes and storage quotas** are plan-dependent and were not verified for this account.
- **Public repositories** expose logs. Repositories default to private in the wizard.
- **Forge and NeoForge installers** are slow the first time (several minutes). Subsequent starts reuse the generated launch arguments within the same job only.
