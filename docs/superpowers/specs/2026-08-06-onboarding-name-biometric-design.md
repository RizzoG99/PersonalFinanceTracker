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
checkmark, reachable only when `isChangeMode == false` (i.e. never during the
Profile → Change PIN flow, which still stops at `success` exactly as today):

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
- Primary button ("Enable Face ID" / "Enable Touch ID") calls
  `authService.authenticate()` — a live biometric challenge, not just flipping the
  setting on trust.
  - Success: sets `isLockEnabled = true`, auto-advances to `nameEntry`.
  - Failure: shows an inline error ("Couldn't verify — you can enable this later in
    Profile"). Does not set `isLockEnabled`. A "Skip" link remains available.
- "Skip" link: advances to `nameEntry` without changing `isLockEnabled`.

### `nameEntry`

- Title: "What should we call you?"
- `TextField` bound to `fullName`.
- "Continue" button, always enabled (empty input behaves as skip).
- On continue: trims whitespace, saves to `UserDefaults` key `user_full_name` — the
  same key `ProfileViewModel` already reads on init, so no new storage path.

## Completion

Unchanged from today: after `nameEntry`, the flow sets
`UserDefaults.standard.set(true, forKey: "pin_setup_complete")` and posts
`.pinSetupComplete`, which `AuthenticationWrapper` already listens for to flip
`isPINSetup` and unlock. No changes to `AuthenticationWrapper` are needed.

## Error handling

Only the biometric failure case needs explicit handling (above). Name entry has no
validation since the value is optional free text — any string, including empty, is
acceptable.

## Testing

Extend `PINSetupViewModel` test coverage (new test file, following the existing
`PINConfirmationViewModelTests` pattern):

- Full flow (`isChangeMode == false`) reaches `nameEntry` and completes normally.
- `biometricPrompt` auto-skips to `nameEntry` when `isBiometricsAvailable == false`.
- Biometric "Skip" link advances without setting `isLockEnabled`.
- Biometric success sets `isLockEnabled = true` before advancing.
- Name is trimmed before being saved to `user_full_name`.
- Change-PIN flow (`isChangeMode == true`) still stops at `success` and never reaches
  `biometricPrompt`/`nameEntry`.
