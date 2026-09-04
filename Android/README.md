# Personal Finance Tracker · Android

Native Android implementation of Personal Finance Tracker.

- Language: Kotlin
- UI: Jetpack Compose + Material 3
- Persistence: Room for financial data, DataStore for preferences
- Minimum SDK: 26
- Compile and target SDK: 34

Open the `Android/` directory in Android Studio, then run `./gradlew :app:assembleDebug`.

The Room schema and repository boundary are documented in `../docs/android/room-entity-map.md`.
