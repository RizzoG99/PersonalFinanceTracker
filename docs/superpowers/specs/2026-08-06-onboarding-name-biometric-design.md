# Onboarding: name + biometric steps after PIN setup

## Problem

Onboarding today only asks for a PIN (`PINSetupView` / `PINSetupViewModel`, shown by
`AuthenticationWrapper` when `pin_setup_complete` is unset). The app already has a
`fullName` setting (`user_full_name`, read by `ProfileViewModel`, greeting/avatar
initials) and a biometric lock setting (`biometric_lock_enabled`, read by
`BiometricAuthService.isLockEnabled`), but neither is ever surfaced until the user
finds them manually in Profile. Most users never do, so the app greets them as
"Your Name" and never offers Face ID/Touch ID unlock.

## Scope

New installs only. Existing users who already completed PIN setup are unaffected —
they keep going straight into the app and can still set name/biometric manually via
Profile, exactly as today. No backfill, no new persisted "extras complete" flag.

## Flow

`PINSetupViewModel.SetupStep` gains two cases, appended after the existing `success`
checkmark, reachable only from the true first-run path.

**Gating note:** `isChangeMode == false` is not sufficient on its own — `PINEntryView`'s
"Forgot PIN?" reset flow also constructs `PINSetupViewModel(pinService:, isChangeMode:
false)`, and that's an existing user resetting their PIN, not a new install. A new
`showsOnboardingExtras: Bool = false` init parameter distinguishes the two. Only
`AuthenticationWrapper`'s initial (`!isPINSetup`) call site passes
`showsOnboardingExtras: true`; the other three call sites (Change PIN in `ProfileView`,
forgot-PIN reset in `PINEntryView`, the `PINSetupView` preview) leave it at the default
`false` and behave exactly as today — stopping at `success`.

```
verifyCurrentPin → enterPin → confirmPin → success → biometricPrompt → nameEntry
```

Both new steps reuse `PINSetupView`'s existing shell (mascot, dark background);
`PINDotsView` is hidden for them since they're not digit entry.

### `biometricPrompt`

- Shown only if `authService.isBiometricsAvailable` (device has Face ID/Touch ID
  enrolled). If not, auto-skip straight to `nameEntry` — no screen shown.
- Title/button wording follows the same Face ID vs. Touch ID pattern already used by
  `ProfileViewModel.biometricLabel`.
- Primary button ("Enable Face ID" / "Enable Touch ID") triggers a **live** biometric
  challenge.
  - Success: sets `isLockEnabled = true`, auto-advances to `nameEntry`.
  - Failure: shows an inline error (reusing the existing `errorMessage` /
    `triggerShake` pattern already used for wrong-PIN entry), e.g. "Couldn't verify —
    you can enable this later in Profile." Does not set `isLockEnabled`. Both the
    "Enable" button (retry) and "Skip" link stay available; either clears the error.
- "Skip" link: advances to `nameEntry` without changing `isLockEnabled`.

**Implementation note — existing bug this depends on:** `BiometricAuthService.authenticate()`
has a guard that short-circuits to `completion(true)` without showing any biometric UI
whenever `isLockEnabled == false` (see `BiometricAuthService.swift:39-43`). During
onboarding `isLockEnabled` is always false at this point, so calling `authenticate()`
as-is would silently "succeed" with no Face ID prompt ever shown — the opposite of
what this step needs. Add a new method, e.g. `authenticateToEnable(completion:)`, that
always runs the `LAContext` challenge regardless of `isLockEnabled` (the existing
`authenticate()` stays unchanged, since unlock-flow callers still need the guard).
Use `authenticateToEnable` here; `authenticate()` is not touched.

**DI note:** `PINSetupViewModel` currently takes only `pinService`. It needs a
`BiometricAuthService` too. `AuthenticationWrapper` already owns one instance
(`authService`) — pass it into `PINSetupViewModel.init` alongside `pinService`. No new
instance is created.

### `nameEntry`

- New `fullName: String = ""` property on `PINSetupViewModel` (onboarding always
  starts from empty — no need to preload from `UserDefaults`).
- Title: "What should we call you?"
- `TextField` bound to `fullName`.
- "Continue" button, always enabled (empty input behaves as skip).
- On continue: trims whitespace. Whitespace-only input is treated the same as empty
  (i.e. skip — don't write it). Non-empty trimmed input saves to `UserDefaults` key
  `user_full_name` — the same key `ProfileViewModel` already reads on init, so no new
  storage path.
- This step is also where the flow finalizes (see Completion below).

## Completion

`validateAndSave()` (called after PIN confirmation) currently finalizes onboarding
directly: after the success-checkmark bounce animation, it sets `pin_setup_complete`
and posts `.pinSetupComplete` for `!isChangeMode`. This must change: when
`showsOnboardingExtras == true`, that bounce animation transitions to
`.biometricPrompt` instead of finalizing, and finalization
(`UserDefaults.standard.set(true, forKey: "pin_setup_complete")` +
`NotificationCenter.default.post(name: .pinSetupComplete, ...)`) moves to the end of
`nameEntry`'s continue/skip handler. Both `isChangeMode == true` (Change PIN) and
`showsOnboardingExtras == false` with `isChangeMode == false` (forgot-PIN reset) are
untouched — they still finalize exactly as today (`isComplete = true` for change mode,
immediate finalization for forgot-PIN reset).

`AuthenticationWrapper` itself needs no changes — it already reacts to
`.pinSetupComplete` the same way regardless of which step triggers it.

## View changes

`PINSetupView` currently renders `PINDotsView` unconditionally and only branches on
`.success` for alternate content. It needs a real per-step content switch:
`PINDotsView` shown only for `.verifyCurrentPin` / `.enterPin` / `.confirmPin`;
`.success` keeps its checkmark; `.biometricPrompt` and `.nameEntry` get their own
content views (extract as separate `View`s/computed properties, following the existing
`successContent` pattern) reusing the shared mascot/dark-background shell.

## Error handling

Only the biometric failure case needs explicit handling (above). Name entry has no
validation since the value is optional free text — any string, including empty, is
acceptable.

## Testing

Extend `PINSetupViewModel` test coverage (new test file, following the existing
`PINConfirmationViewModelTests` pattern):

- Full flow (`isChangeMode == false, showsOnboardingExtras == true`) reaches
  `nameEntry` and completes normally.
- `biometricPrompt` auto-skips to `nameEntry` when `isBiometricsAvailable == false`.
- Biometric "Skip" link advances without setting `isLockEnabled`.
- Biometric success sets `isLockEnabled = true` before advancing.
- Name is trimmed before being saved to `user_full_name`; whitespace-only input is
  not saved.
- Change-PIN flow (`isChangeMode == true`) still stops at `success` and never reaches
  `biometricPrompt`/`nameEntry`.
- Forgot-PIN reset flow (`isChangeMode == false, showsOnboardingExtras == false`)
  still finalizes immediately at `success` and never reaches `biometricPrompt`/
  `nameEntry`.
- `authenticateToEnable` success sets `isLockEnabled = true` and does not affect the
  unlock-flow `authenticate()` method's existing guard behavior.
