# Writing parity tests

Every `AC-xx` maps to at least one test, named in the issue. Worked examples on `codex/android-native`, under `Android/app/src/androidTest/java/com/rizzog99/personalfinancetracker/`:

- `ui/CaptureHarness.kt`: the one capture path (PNG plus semantics dump per cell). Read its doc comments; they record harness bugs that once faked a defect.
- `ui/UiStateCaptureTest.kt` (#111): a capture matrix over production composables.
- `ui/UiStateReachabilityTest.kt`: the same states driven end to end on `MainActivity`.
- `l10n/FoundationLocaleRecreationTest.kt` (#112): EN→IT→EN recreation through `LocaleManager`.

## Which kind of test

- **JVM** (`app/src/test`): calculations, filters, date boundaries, repositories with fakes. Money and dates use explicit fixtures and expected values, never "today".
- **Instrumented** (`app/src/androidTest`): anything the user sees, persistence across process death, Room migrations, locale recreation, the PIN gate.
- **Capture matrix**: one `CaptureHarness.Cell` per variant the AC cares about: locale (EN, IT), theme (light, dark), width (411 dp compact, a wide value), font scale (1, large). Host the production composable with its real locals; a bare `Box` sets no `LocalContentColor` and renders dark cells black-on-black.
  - A `ModalBottomSheet` or dialog is its own window whose `ComposeView` re-provides `LocalContext`, `LocalConfiguration`, and `LocalDensity`, so the harness's locale and font-scale override stops at its edge. Check every sheet or dialog cell shows the cell's locale and font scale before trusting it.
  - A wide cell (900 dp) on the phone AVD squeezes content the real tablet would not; treat clipping seen only there as a harness artifact, not a defect.

## Shape

- One class per topic, one test per AC, named `ac01_<what>`. Each test sets up its own state; a test never depends on another's leftovers. Reset the database with `app.database.clearAllTables()` followed by `app.categoryRepository.seedDefaultsIfEmpty()`.
- Assert the precondition too, so a broken setup fails loudly instead of passing vacuously.
- Query by semantics (text, content description, role, `testTag`). An element with no stable label gets a test-only `Modifier.testTag`; a state shown only as colour is invisible to TalkBack, so assert something structural and file the missing semantics as its own issue.
  - An unlabelled `Switch` sits beside its label: find it with `isToggleable() and hasAnySibling(hasText(label))`, and prove it is on through the content that appears when it is.
- Use `waitUntil` / `waitForIdle`, never `Thread.sleep`.
- Transient UI (a snackbar's 4 s lifetime) can pass entirely inside one idle sync while `mainClock.autoAdvance` is on. Set `composeRule.mainClock.autoAdvance = false` right after the triggering tap, then loop on `advanceTimeByFrame()` until the snackbar shows, and assert it.
- A tap that seems lost: compare the `boundsInWindow` of the target and its neighbours for overlap before blaming production code.
- Prefer driving `MainActivity` when the state is reachable for real. When it is not (a mid-session Room failure), capture the production composable in that state and record the choice as a `D-xx`, rather than adding a production hook to photograph it.

## Running

Run from the worktree root, one command per call, in the background. Boot the AVD first (`emulator -list-avds`; the Mac has `Pixel_7a`) and check `adb devices`. One device run at a time on this Mac: never start the emulator while an `xcb test` or `xcb scenarios` run holds the simulator.

- JVM, one class: `Android/gradlew -p Android :app:testDebugUnitTest --tests '<fqcn>'`.
- Instrumented, one class: `Android/gradlew -p Android :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=<fqcn>`; one method: `class=<fqcn>#<method>`.
- Results: `Android/app/build/test-results/testDebugUnitTest/*.xml` and `Android/app/build/outputs/androidTest-results/connected/**/*.xml`. Read `tests`, `failures`, `errors`, `skipped` from the XML; a Gradle exit code of 0 with zero tests is not a pass.

## Pulling captures

`connectedDebugAndroidTest` uninstalls the app when it finishes, and the app's files go with it. For captures, install and run the class directly, then pull. Take the runner and package from `adb shell pm list instrumentation` (`instrumentation:<runner> (target=<package>)`):

```bash
Android/gradlew -p Android :app:installDebug :app:installDebugAndroidTest
adb shell am instrument -w -e class <fqcn> <runner>
mkdir -p .build/android-captures
adb pull /sdcard/Android/data/<package>/files/<matrix-dir> .build/android-captures/
```

If the AVD has no emulated storage, `CaptureHarness.outputDir` falls back to the internal files dir; reach it with `adb shell run-as <package>`. An empty pull means nothing was photographed, never that the cells passed.
