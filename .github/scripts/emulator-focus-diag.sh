#!/usr/bin/env bash
# Diagnostic for #372: what holds window focus on the API 34 emulator. Temporary.
set -u
out=Android/app/build/evidence/focus-diag
mkdir -p "$out"

focus() { echo "== $(date +%T) $1"; adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"; }

{
  echo "image: $(grep Pkg.Revision "$ANDROID_SDK_ROOT"/system-images/android-*/google_apis/x86_64/source.properties)"
  echo "fingerprint: $(adb shell getprop ro.build.fingerprint)"
  echo "patch: $(adb shell getprop ro.build.version.security_patch)"
} > "$out/image.txt"
cat "$out/image.txt"

focus boot | tee "$out/focus-boot.txt"
adb exec-out screencap -p > "$out/boot.png"

( i=0; while true; do focus sample >> "$out/focus-samples.txt" 2>&1
    i=$((i+1)); [ $((i % 20)) -eq 0 ] && adb exec-out screencap -p > "$out/during-$i.png"
    sleep 3; done ) &
sampler=$!

rc=0
(cd Android && ./gradlew :app:connectedDebugAndroidTest --stacktrace \
  -Pandroid.testInstrumentationRunnerArguments.class=com.rizzog99.personalfinancetracker.navigation.NavShellEvidenceTest,com.rizzog99.personalfinancetracker.navigation.NavShellGraphTest) \
  > "$out/isolated.log" 2>&1 && echo "ISOLATED: pass" || echo "ISOLATED: fail"
cp -r Android/app/build/outputs/androidTest-results/connected "$out/isolated-results" 2>/dev/null
focus after-isolated | tee -a "$out/focus-boot.txt"

(cd Android && ./gradlew :app:connectedDebugAndroidTest --stacktrace) || rc=$?

kill $sampler
focus after | tee -a "$out/focus-boot.txt"
adb exec-out screencap -p > "$out/after.png"
adb logcat -d -b events | grep -E "input_focus|am_anr|am_crash|wm_focus" > "$out/events.txt"
adb logcat -d | grep -iE "isn't responding|ANR in|not responding|FocusEvent|Focus (request|entering|leaving)" > "$out/logcat-focus.txt"
adb logcat -d > "$out/logcat-full.txt"
tail -40 "$out/events.txt"
exit $rc
