#!/usr/bin/env bash
# #372: right after boot, android-emulator-runner sends `input keyevent 82` (MENU). On the API 34
# image the Pixel Launcher may not have a focused window yet, so input dispatch times out and the
# launcher ANRs. Its "isn't responding" dialog then keeps window focus for the whole run, and
# Espresso's pressBack() needs the app window to have it. Build first so any boot ANR has already
# fired, then close the dialog before the suite. Verified by freezing the launcher (SIGSTOP + MENU)
# to force the dialog on API 26 and 34: run 42817202420.
set -u
cd Android
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest --stacktrace || exit 1

# API 26 swaps a closed ANR dialog for an "Application Error" one, so match both.
anr_dialog() { adb shell dumpsys window | grep -qE "mCurrentFocus=.*Application (Not Responding|Error)"; }

for _ in $(seq 6); do
  if anr_dialog; then
    echo "Closing system ANR/error dialog:"
    adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"
    # ponytail: CLOSE_SYSTEM_DIALOGS makes the ANR dialog close the hung app; HOME brings the launcher back.
    adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null
    adb shell input keyevent KEYCODE_HOME
  fi
  sleep 5
done
adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"
if anr_dialog; then
  echo "A system ANR/error dialog still holds window focus; Espresso tests would fail" >&2
  exit 1
fi

./gradlew :app:connectedDebugAndroidTest --stacktrace
