#!/usr/bin/env bash
# #372: on API 34 the Pixel Launcher ANRs shortly after boot ("Input dispatching timed out
# (Application does not have a focused window)"). Its "isn't responding" dialog then keeps
# window focus for the whole run, and Espresso's pressBack() needs the app window to have it.
# The dialog can appear ~15 s after boot completes, so watch for a while and close any that shows.
set -u

anr_dialog() { adb shell dumpsys window | grep -q "mCurrentFocus=.*Application Not Responding"; }

for _ in $(seq 12); do
  if anr_dialog; then
    echo "Closing system ANR dialog:"
    adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"
    # ponytail: CLOSE_SYSTEM_DIALOGS makes the ANR dialog force-close the hung app; HOME brings the launcher back.
    adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null
    adb shell input keyevent KEYCODE_HOME
  fi
  sleep 5
done
adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"
if anr_dialog; then
  echo "An ANR dialog still holds window focus; Espresso tests would fail" >&2
  exit 1
fi

cd Android && ./gradlew :app:connectedDebugAndroidTest --stacktrace
