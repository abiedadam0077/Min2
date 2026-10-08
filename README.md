# VoxelOps

Native Flutter Android app to create and run Minecraft servers from your phone.

- **Runs on your accounts.** GitHub Actions runs the server, Google Drive stores the world, configs, mods, backups and recovery metadata, and Tailscale gives you a private address.
- **Recoverable.** Every server is a Drive folder (`MinecraftServers/<Name>/`). Import it on any phone and reattach it to a repository.
- **Native UI.** Flutter widgets only. Arabic and English with full right-to-left layout.
- **Secure by design.** Tokens live in Android Keystore-backed storage. No client secret is compiled into the APK. Repository secrets are encrypted with the repository public key.

## Download

Latest build: https://github.com/abiedadam0077/Min2/releases/latest/download/VoxelOps.apk

Release notes and checksums: https://github.com/abiedadam0077/Min2/releases/latest

## Documentation

- [Setup](docs/SETUP.md): OAuth clients, signing, Tailscale, CurseForge, first server, limits.
- [Architecture](docs/ARCHITECTURE.md): layers, state, storage, Drive layout, app-to-runner protocol.
- [Design system](docs/DESIGN_SYSTEM.md): colour, type, motion, components, RTL and accessibility.
- [UX flow](docs/UX_FLOW.md): screens, wizard, dashboard, failure states.
- [Research](docs/RESEARCH.md): UX references, API facts, decisions and remaining risks.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

CI (`.github/workflows/android-release.yml`) runs analysis and tests, builds the release APK, and publishes it as a GitHub release on pushes to the working branches.

`tool/generate_icons.py` regenerates the launcher icons from the same geometry as the in-app logo.
