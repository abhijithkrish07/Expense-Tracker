# Expense Tracker

Local-first Flutter expense tracker with category management, analytics, budgets, dark mode support, and Excel import.

## Features

- Add, edit, and delete expenses
- Category management with icon/color customization
- Budget setup and monthly spend tracking
- Analytics dashboard
- Light/Dark mode toggle (dark is default)
- Excel import for expenses with import preview and validation
- Android release build support

## Tech Stack

- Flutter 3.41.x
- Dart 3.11.x
- Riverpod (state management)
- SharedPreferences + secure storage
- fl_chart (analytics charts)

## Project Structure

```text
lib/
	app.dart
	main.dart
	models/
	providers/
	screens/
		analytics/
		budget/
		categories/
		expense/
		home/
	services/
	utils/
	widgets/
```

## Prerequisites

- Flutter SDK installed and on PATH
- Android Studio / Android SDK (for Android builds)
- Java 17 configured for Android Gradle builds

## Setup

```bash
flutter pub get
```

## Run the App

```bash
flutter devices
flutter run
```

Run on Chrome specifically:

```bash
flutter run -d chrome
```

## Build APK (Android)

```bash
flutter build apk --release
```

Output:

`build/app/outputs/flutter-apk/app-release.apk`

## Excel Import Format

Import is available from the app drawer: `Import from Excel`.

Expected input file:

- Two columns only:
1. `Category`
2. `Expense`

Example rows:

```text
Food            | 250
Transport       | 80
Shopping        | 1200
Total Expenses  | 1530
```

Rules:

- Import stops before the row where Category equals `Total Expenses`
- That `Total Expenses` row is not imported
- Invalid rows are skipped
- Missing categories are auto-created
- A preview dialog is shown before final import

## Versioning

Current app version is defined in `pubspec.yaml`:

`version: 1.0.1+2`

Format:

- `major.minor.patch+build`

## Security Notes

- Local financial data storage uses secure storage on native platforms
- Android backup is disabled in manifest
- Release builds use minification and resource shrinking

## Troubleshooting

### Android build issues (Java/Gradle)

If you see Java class version errors, configure Flutter to use JDK 17:

```bash
flutter config --jdk-dir /Library/Java/JavaVirtualMachines/sapmachine-17.jdk/Contents/Home
```

Then run:

```bash
flutter clean
flutter pub get
flutter build apk --release
```

### Android SDK licenses

```bash
flutter doctor --android-licenses
```

## License

Private/internal project.
