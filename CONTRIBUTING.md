# Contributing to Veil Player

Thank you for your interest in contributing to Veil Player! We welcome community contributions, bug reports, and feedback to help make Veil Player the best offline media player on Android.

---

## Code of Conduct

Please treat everyone with respect and kindness. We aim to foster an open, welcoming, and productive environment for all contributors.

---

## Current Status: Version 1.0 Stable

Veil Player has reached its **Version 1.0 Stable Release**. 

- **Bug Fixes & Stability**: High priority. We actively review and welcome PRs addressing crashes, playback failures, memory leaks, or platform incompatibilities.
- **New Feature Proposals**: Please open an issue to discuss new features or substantial UI/architectural changes before starting work on a pull request.

---

## Reporting Issues & Bugs

Before opening a new issue:
1. Search existing [Issues](https://github.com/rohitmorerocks/Veil_Player/issues) to verify the problem has not already been reported.
2. Ensure you are testing against the latest official release.

When creating an issue, please include:
- **Device Details**: Device manufacturer and model (e.g. Google Pixel 7, Samsung Galaxy S23).
- **Android Version**: Android OS version and API level (e.g. Android 14 / API 34).
- **Steps to Reproduce**: A numbered, step-by-step description of how to trigger the issue.
- **Expected vs Actual Behavior**: What should happen versus what actually occurred.
- **Media Information (if playback-related)**: Container format (e.g. MKV, MP4), video codec, audio codec, resolution, and whether hardware or software decoding was active.
- **Stack Traces / Logs**: Sanitized error traces from the in-app Diagnostic Report viewer or `adb logcat`.

---

## Development Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.10.0)
- [Dart SDK](https://dart.dev/get-dart) (>= 3.0.0)
- [Android Studio](https://developer.android.com/studio) or VS Code with Flutter extension
- Android SDK Platform 34 and Build Tools
- Java Development Kit (JDK 17)

### Local Build Steps
```bash
# 1. Clone the repository
git clone https://github.com/rohitmorerocks/Veil_Player.git
cd Veil_Player

# 2. Install dependencies
flutter pub get

# 3. Verify static analysis
flutter analyze

# 4. Run automated unit and widget tests
flutter test

# 5. Launch on a connected Android device or emulator
flutter run
```

---

## Pull Request Guidelines

1. **Branching**: Create a feature or fix branch from `main` with a descriptive name (e.g., `fix/pip-aspect-ratio` or `fix/audio-focus-resume`).
2. **Coding Standards**:
   - Follow standard Dart conventions and effective Dart guidelines.
   - Maintain the AMOLED Pure Black (`#000000`) visual identity.
   - Adhere to the strict **offline-first** architecture: do **not** add network calls, analytics SDKs, or cloud dependencies.
3. **Verification**:
   - Ensure `flutter analyze` passes with **0 issues**.
   - Ensure all automated tests pass with `flutter test`.
   - Add new tests in `test/` for new functionality or regression coverage where appropriate.
4. **Submitting**:
   - Submit your pull request against the `main` branch.
   - Describe what the PR accomplishes and reference relevant issue numbers (e.g., `Fixes #12`).

---

## License

By contributing to Veil Player, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
