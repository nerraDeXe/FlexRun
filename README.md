# FlexRun

A new Flutter project.

## Map / compile-time configuration

Copy `dart_defines.example.json` to `dart_defines.json`, set `MAPTILER_KEY` (and optional map URLs).

In **Cursor/VS Code**, Run or Debug Flutter uses `.vscode/settings.json` so you can start the app without typing the flag (it still passes `--dart-define-from-file=dart_defines.json` for you).

From a **terminal**, Flutter has no project default; use:

```sh
flutter run --dart-define-from-file=dart_defines.json
```

The same flag applies to `flutter build` when you build from the CLI.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
