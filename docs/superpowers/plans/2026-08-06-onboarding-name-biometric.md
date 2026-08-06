# Onboarding Name + Biometric Steps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After PIN setup on a brand-new install, offer two skippable steps — enable biometric unlock, then enter a display name — before entering the app.

**Architecture:** Extend `PINSetupViewModel`'s existing step-based state machine (`SetupStep`) with two new cases reachable only on the true first-run path, gated by a new `showsOnboardingExtras` flag so Change-PIN and Forgot-PIN-reset flows are unaffected. A new `BiometricAuthenticating` protocol lets tests substitute a fake for `BiometricAuthService` (which wraps real `LocalAuthentication` hardware).

**Tech Stack:** SwiftUI, `@Observable` view models, Swift Testing (`@Test`/`#expect`), `LocalAuthentication`, `UserDefaults`.

## Global Constraints

- Build and test ONLY via Xcode MCP tools (`mcp__xcode__BuildProject`, `mcp__xcode__RunAllTests`, `mcp__xcode__RunSomeTests`), loaded first via `ToolSearch` with `query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"`, called with `tabIdentifier: "windowtab1"`. Never run `xcodebuild` in Bash.
- Tests use Swift Testing (`@Test`, `#expect`), NOT XCTest. Test files start with `@testable import PersonalFinanceTraker`.
- Scope is new installs only — no backfill for existing users, no new persisted "extras complete" flag.
- `BiometricAuthService.authenticate()` (the unlock-flow method) must not change behavior — a separate `authenticateToEnable()` is added instead.
- `isChangeMode == true` (Profile → Change PIN) must keep stopping at `.success` exactly as today.
- The Forgot-PIN reset flow (`PINEntryView`) must keep finalizing immediately at `.success` exactly as today — it must NOT reach the new steps. This is why `showsOnboardingExtras` is a separate flag from `isChangeMode`, defaulting to `false`.
- Directory typo is intentional: `PersonalFinanceTraker` (no missing files to "fix").

---

### Task 1: `BiometricAuthService` — testable seam + live enable challenge

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BiometricAuthService.swift`

**Interfaces:**
- Produces: `protocol BiometricAuthenticating: AnyObject` with `isBiometricsAvailable: Bool { get }`, `biometricLabel: String { get }`, `isLockEnabled: Bool { get set }`, `func authenticateToEnable(completion: @escaping (Bool) -> Void)`. `BiometricAuthService` conforms to it. `authenticate()` is untouched.

This task has no dedicated unit test — like the existing `authenticate()` method, `authenticateToEnable()` drives real `LAContext`/`LocalAuthentication` hardware, which isn't unit-testable in this codebase's test target (no existing `BiometricAuthService` tests to follow a pattern from). Correctness of the *calling* code is covered by Task 2's tests via a fake conforming to `BiometricAuthenticating`. This task is verified by a successful build plus manual smoke-test in Task 5.

- [ ] **Step 1: Rewrite `BiometricAuthService.swift`**

Replace the full file contents with:

```swift
//
//  BiometricAuthService.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import Foundation
import LocalAuthentication

/// Seam for testing biometric-dependent view models without real LocalAuthentication
/// hardware — see `FakeBiometricAuthService` in PINSetupViewModelTests.
public protocol BiometricAuthenticating: AnyObject {
    var isBiometricsAvailable: Bool { get }
    var biometricLabel: String { get }
    var isLockEnabled: Bool { get set }
    func authenticateToEnable(completion: @escaping (Bool) -> Void)
}

/// Service for handling biometric authentication (FaceID / TouchID)
public class BiometricAuthService: ObservableObject, BiometricAuthenticating {

    @Published public var isUnlocked = false
    @Published public var isBiometricsAvailable = false
    @Published public private(set) var biometricLabel = "Biometrics"

    public var isBiometricFeatureEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "biometric_lock_enabled")
    }

    private let kBiometricLockEnabled = "biometric_lock_enabled"

    public init() {
        checkBiometrics()
    }

    /// Checks if biometric authentication is available on the device
    public func checkBiometrics() {
        let ctx = LAContext()
        var error: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isBiometricsAvailable = ctx.biometryType != .none
        switch ctx.biometryType {
        case .faceID:  biometricLabel = "Face ID"
        case .touchID: biometricLabel = "Touch ID"
        default:       biometricLabel = "Biometrics"
        }
    }

    /// Attempts to authenticate the user using biometrics
    public func authenticate(completion: @escaping (Bool) -> Void) {
        let reason = "Unlock your financial data"

        guard isLockEnabled else {
            isUnlocked = true
            completion(true)
            return
        }

        // Create a fresh context for each evaluation (LAContext is single-use).
        let authContext = LAContext()
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics are no longer available (enrollment removed or denied in Settings).
            // Disable the lock to avoid leaving the app permanently inaccessible.
            isLockEnabled = false
            isUnlocked = true
            completion(true)
            return
        }

        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                self.isUnlocked = success
                completion(success)
            }
        }
    }

    /// Runs a live biometric challenge to confirm biometrics actually work before
    /// enabling the setting (used during onboarding). Unlike `authenticate()`, this
    /// always challenges — it never short-circuits based on `isLockEnabled`, and it
    /// never mutates `isUnlocked` or `isLockEnabled` itself (the caller decides what
    /// to do with the result).
    public func authenticateToEnable(completion: @escaping (Bool) -> Void) {
        let authContext = LAContext()
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable biometric unlock") { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// User setting to enable/disable the lock
    public var isLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kBiometricLockEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: kBiometricLockEnabled) }
    }

    /// Unlock the app (called after successful PIN entry)
    public func unlock() {
        isUnlocked = true
    }

    /// Lock the app (e.g., when going to background)
    public func lock() {
        isUnlocked = false
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Load the MCP schema first:
```
ToolSearch query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"
```
Then:
```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: build succeeds. (`PINEntryViewModel` and `AuthenticationWrapper` still reference `BiometricAuthService` as a concrete type — that's unaffected since conforming to a protocol doesn't change the concrete type's public surface.)

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BiometricAuthService.swift
git commit -m "feat: add BiometricAuthenticating protocol and authenticateToEnable"
```

---

### Task 2: `PINSetupViewModel` — new steps, DI, and tests

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/ViewModels/PINSetupViewModel.swift`
- Create: `PersonalFinanceTrakerTests/Features/Security/PINSetupViewModelTests.swift`

**Interfaces:**
- Consumes: `BiometricAuthenticating` (Task 1) — `isBiometricsAvailable: Bool`, `biometricLabel: String`, `isLockEnabled: Bool { get set }`, `authenticateToEnable(completion:)`.
- Produces:
  - `PINSetupViewModel.SetupStep` gains `.biometricPrompt`, `.nameEntry`.
  - `PINSetupViewModel.init(pinService: PINService, authService: BiometricAuthenticating, isChangeMode: Bool = false, showsOnboardingExtras: Bool = false)` — **breaking change** to the existing init signature (Task 4 fixes all call sites).
  - `var fullName: String` (new, bindable in the view).
  - `var biometricLabel: String { get }` (passthrough for the view's step title).
  - `func enableBiometric()`, `func skipBiometric()`, `func finishNameEntry()` (new, called by the view in Task 3).

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTrakerTests/Features/Security/PINSetupViewModelTests.swift`:

```swift
import Testing
import Foundation

@testable import PersonalFinanceTraker

private final class FakeBiometricAuthService: BiometricAuthenticating {
    var isBiometricsAvailable: Bool
    var biometricLabel: String = "Face ID"
    var isLockEnabled: Bool = false
    var authenticateResult: Bool = true

    init(isBiometricsAvailable: Bool = true) {
        self.isBiometricsAvailable = isBiometricsAvailable
    }

    func authenticateToEnable(completion: @escaping (Bool) -> Void) {
        completion(authenticateResult)
    }
}

@MainActor
struct PINSetupViewModelTests {
    private let pinService = PINService()

    /// Drives digit entry for a full enter+confirm PIN cycle. Callers still need to
    /// wait out validateAndSave's own bounce-animation delay afterward.
    private func enterAndConfirmPIN(_ pin: String, on viewModel: PINSetupViewModel) async throws {
        for digit in pin { viewModel.appendDigit(String(digit)) }
        try await Task.sleep(for: .seconds(0.25))
        for digit in pin { viewModel.appendDigit(String(digit)) }
    }

    @Test("Full onboarding flow reaches nameEntry and finalizes")
    func fullFlowReachesNameEntryAndFinalizes() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
            UserDefaults.standard.removeObject(forKey: "user_full_name")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )

        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.0))

        #expect(viewModel.currentStep == .biometricPrompt)

        viewModel.skipBiometric()
        #expect(viewModel.currentStep == .nameEntry)
        #expect(!authService.isLockEnabled)

        viewModel.fullName = "Ada"
        viewModel.finishNameEntry()

        #expect(UserDefaults.standard.string(forKey: "user_full_name") == "Ada")
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }

    @Test("biometricPrompt auto-skips to nameEntry when biometrics unavailable")
    func biometricPromptAutoSkipsWhenUnavailable() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }

        let authService = FakeBiometricAuthService(isBiometricsAvailable: false)
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )

        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.0))

        #expect(viewModel.currentStep == .nameEntry)
    }

    @Test("Skip link on biometricPrompt advances without enabling the lock")
    func biometricSkipDoesNotEnableLock() {
        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .biometricPrompt

        viewModel.skipBiometric()

        #expect(viewModel.currentStep == .nameEntry)
        #expect(!authService.isLockEnabled)
    }

    @Test("Successful biometric enable sets isLockEnabled and advances")
    func biometricEnableSuccessSetsLockEnabled() {
        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        authService.authenticateResult = true
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .biometricPrompt

        viewModel.enableBiometric()

        #expect(authService.isLockEnabled)
        #expect(viewModel.currentStep == .nameEntry)
        #expect(viewModel.errorMessage.isEmpty)
    }

    @Test("Failed biometric enable shows an error and stays on biometricPrompt")
    func biometricEnableFailureShowsError() {
        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        authService.authenticateResult = false
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .biometricPrompt

        viewModel.enableBiometric()

        #expect(!authService.isLockEnabled)
        #expect(viewModel.currentStep == .biometricPrompt)
        #expect(!viewModel.errorMessage.isEmpty)
    }

    @Test("Name is trimmed before saving")
    func nameIsTrimmedBeforeSaving() {
        defer { UserDefaults.standard.removeObject(forKey: "user_full_name") }
        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .nameEntry
        viewModel.fullName = "  Ada Lovelace  "

        viewModel.finishNameEntry()

        #expect(UserDefaults.standard.string(forKey: "user_full_name") == "Ada Lovelace")
    }

    @Test("Whitespace-only name is not saved")
    func whitespaceOnlyNameIsNotSaved() {
        UserDefaults.standard.removeObject(forKey: "user_full_name")
        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .nameEntry
        viewModel.fullName = "   "

        viewModel.finishNameEntry()

        #expect(UserDefaults.standard.string(forKey: "user_full_name") == nil)
    }

    @Test("Change-PIN flow stops at success and never reaches the new steps")
    func changePINFlowStopsAtSuccess() async throws {
        defer { try? pinService.clearPIN() }
        try pinService.setPIN("0000")

        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            isChangeMode: true
        )

        for digit in "0000" { viewModel.appendDigit(String(digit)) }
        try await Task.sleep(for: .seconds(0.25))
        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.0))

        #expect(viewModel.currentStep == .success)
        #expect(viewModel.isComplete)
    }

    @Test("Forgot-PIN reset flow finalizes immediately and never reaches the new steps")
    func forgotPINResetFinalizesImmediately() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            isChangeMode: false,
            showsOnboardingExtras: false
        )

        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.0))

        #expect(viewModel.currentStep == .success)
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

```
ToolSearch query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")
```
Expected: build/compile failure — `PINSetupViewModel` has no `.biometricPrompt`/`.nameEntry` cases, no `authService`/`showsOnboardingExtras` init params, no `fullName`/`enableBiometric`/`skipBiometric`/`finishNameEntry`.

- [ ] **Step 3: Rewrite `PINSetupViewModel.swift`**

Replace the full file contents with:

```swift
import SwiftUI

@Observable @MainActor
final class PINSetupViewModel {
    enum SetupStep { case verifyCurrentPin, enterPin, confirmPin, success, biometricPrompt, nameEntry }

    var currentStep: SetupStep = .enterPin
    var pinInput: String = ""
    var confirmInput: String = ""
    var fullName: String = ""
    var errorMessage: String = ""
    var isShaking: Bool = false
    var isBouncing: Bool = false
    var eyesOpen: Bool = true
    var isComplete: Bool = false

    let isChangeMode: Bool
    let showsOnboardingExtras: Bool
    private let pinService: PINService
    private let authService: BiometricAuthenticating
    private var firstPin: String = ""

    var biometricLabel: String { authService.biometricLabel }

    init(
        pinService: PINService,
        authService: BiometricAuthenticating,
        isChangeMode: Bool = false,
        showsOnboardingExtras: Bool = false
    ) {
        self.pinService = pinService
        self.authService = authService
        self.isChangeMode = isChangeMode
        self.showsOnboardingExtras = showsOnboardingExtras
        currentStep = isChangeMode ? .verifyCurrentPin : .enterPin
    }

    func appendDigit(_ digit: String) {
        switch currentStep {
        case .verifyCurrentPin:
            guard pinInput.count < 4 else { return }
            pinInput += digit
            eyesOpen = false
            if pinInput.count == 4 {
                Task { try? await Task.sleep(for: .seconds(0.15)); self.verifyCurrentPIN() }
            }
        case .enterPin:
            guard pinInput.count < 4 else { return }
            pinInput += digit
            eyesOpen = false
            if pinInput.count == 4 {
                Task { try? await Task.sleep(for: .seconds(0.15)); self.advanceToConfirm() }
            }
        case .confirmPin:
            guard confirmInput.count < 4 else { return }
            confirmInput += digit
            eyesOpen = false
            if confirmInput.count == 4 {
                Task { try? await Task.sleep(for: .seconds(0.15)); self.validateAndSave() }
            }
        case .success, .biometricPrompt, .nameEntry:
            break
        }
    }

    func deleteDigit() {
        switch currentStep {
        case .verifyCurrentPin, .enterPin:
            if !pinInput.isEmpty { pinInput.removeLast() }
            eyesOpen = pinInput.isEmpty
        case .confirmPin:
            if !confirmInput.isEmpty { confirmInput.removeLast() }
            eyesOpen = confirmInput.isEmpty
        case .success, .biometricPrompt, .nameEntry:
            break
        }
    }

    func goBackToEnterPin() {
        currentStep = .enterPin
        pinInput = ""
        confirmInput = ""
        firstPin = ""
        errorMessage = ""
        eyesOpen = true
    }

    private func verifyCurrentPIN() {
        if pinService.validatePIN(pinInput) {
            pinInput = ""
            eyesOpen = true
            errorMessage = ""
            withAnimation { currentStep = .enterPin }
        } else {
            errorMessage = "Incorrect PIN. Try again."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        }
    }

    private func advanceToConfirm() {
        if isChangeMode && pinService.validatePIN(pinInput) {
            errorMessage = "New PIN must be different from the current one."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
            return
        }
        firstPin = pinInput
        pinInput = ""
        errorMessage = ""
        eyesOpen = true
        withAnimation { currentStep = .confirmPin }
    }

    private func validateAndSave() {
        guard confirmInput == firstPin else {
            errorMessage = "PINs don't match. Try again."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.confirmInput = ""; self.eyesOpen = true }
            return
        }

        do {
            try pinService.clearPIN()
            try pinService.setPIN(firstPin)
        } catch {
            errorMessage = "Failed to save PIN. Try again."
            triggerShake()
            confirmInput = ""
            eyesOpen = true
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = .success
        }
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) {
                self.isBouncing = true
            }
            try? await Task.sleep(for: .seconds(1.3))
            if self.isChangeMode {
                self.isComplete = true
            } else if self.showsOnboardingExtras {
                self.advanceToBiometricPrompt()
            } else {
                self.finishOnboarding()
            }
        }
    }

    private func advanceToBiometricPrompt() {
        guard authService.isBiometricsAvailable else {
            currentStep = .nameEntry
            return
        }
        withAnimation { currentStep = .biometricPrompt }
    }

    func enableBiometric() {
        errorMessage = ""
        authService.authenticateToEnable { success in
            if success {
                self.authService.isLockEnabled = true
                withAnimation { self.currentStep = .nameEntry }
            } else {
                self.errorMessage = "Couldn't verify — you can enable this later in Profile."
            }
        }
    }

    func skipBiometric() {
        errorMessage = ""
        withAnimation { currentStep = .nameEntry }
    }

    func finishNameEntry() {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: "user_full_name")
        }
        finishOnboarding()
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "pin_setup_complete")
        NotificationCenter.default.post(name: .pinSetupComplete, object: nil)
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")
```
Expected: all 8 tests in `PINSetupViewModelTests` PASS. (This will fail to build until Task 3's view is also fixed to use the new init signature at its `#Preview` and Task 4's call sites are updated — if the build fails only on non-test call sites, that's expected at this point; proceed to Task 3 and Task 4 before re-running, then come back and confirm green here too.)

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/ViewModels/PINSetupViewModel.swift PersonalFinanceTrakerTests/Features/Security/PINSetupViewModelTests.swift
git commit -m "feat: add biometric and name-entry steps to PINSetupViewModel"
```

---

### Task 3: `PINSetupView` — UI for the two new steps

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/PINSetupView.swift`

**Interfaces:**
- Consumes: `PINSetupViewModel.currentStep` (`.biometricPrompt`, `.nameEntry` from Task 2), `viewModel.fullName`, `viewModel.biometricLabel`, `viewModel.enableBiometric()`, `viewModel.skipBiometric()`, `viewModel.finishNameEntry()`.

- [ ] **Step 1: Rewrite `PINSetupView.swift`**

Replace the full file contents with:

```swift
import SwiftUI

struct PINSetupView: View {
    @State var viewModel: PINSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MonkeyAnimationView(
                eyesOpen: $viewModel.eyesOpen,
                isShaking: viewModel.isShaking,
                isBouncing: viewModel.isBouncing
            )
            .padding(.bottom, 32)

            VStack(spacing: 8) {
                Text(stepTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)

                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.negative)
                        .transition(.opacity)
                        .animation(.easeInOut, value: viewModel.errorMessage)
                }
            }
            .padding(.bottom, 32)

            if showsPINDots {
                PINDotsView(filledCount: currentFilledCount)
                    .padding(.bottom, 48)
            }

            stepContent

            Spacer()

            if viewModel.currentStep == .confirmPin {
                Button("Go back") { viewModel.goBackToEnterPin() }
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
                    .padding(.bottom, 32)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .preferredColorScheme(.dark)
        .navigationTitle(viewModel.isChangeMode ? "Change PIN" : "")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!viewModel.isChangeMode)
        .onChange(of: viewModel.isComplete) { _, done in
            if done { dismiss() }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .success:
            successContent
        case .biometricPrompt:
            biometricPromptContent
        case .nameEntry:
            nameEntryContent
        case .verifyCurrentPin, .enterPin, .confirmPin:
            PINPadView(
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() }
            )
            .transition(.opacity)
        }
    }

    private var showsPINDots: Bool {
        switch viewModel.currentStep {
        case .verifyCurrentPin, .enterPin, .confirmPin, .success: return true
        case .biometricPrompt, .nameEntry: return false
        }
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case .verifyCurrentPin: return "Enter current PIN"
        case .enterPin:         return "Enter new PIN"
        case .confirmPin:       return "Confirm new PIN"
        case .success:          return "PIN successfully set"
        case .biometricPrompt:  return "Unlock with \(viewModel.biometricLabel)"
        case .nameEntry:        return "What should we call you?"
        }
    }

    private var currentFilledCount: Int {
        switch viewModel.currentStep {
        case .verifyCurrentPin, .enterPin: return viewModel.pinInput.count
        case .confirmPin:                  return viewModel.confirmInput.count
        case .success, .biometricPrompt, .nameEntry: return 4
        }
    }

    private var successContent: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(.accentIndigo)
            .transition(.scale.combined(with: .opacity))
    }

    private var biometricPromptContent: some View {
        VStack(spacing: 16) {
            Button {
                viewModel.enableBiometric()
            } label: {
                Text("Enable \(viewModel.biometricLabel)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentIndigo, in: RoundedRectangle(cornerRadius: 14))
            }

            Button("Skip") { viewModel.skipBiometric() }
                .font(.subheadline)
                .foregroundStyle(.textDim)
        }
        .transition(.opacity)
    }

    private var nameEntryContent: some View {
        VStack(spacing: 16) {
            TextField("Your name", text: $viewModel.fullName)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit { viewModel.finishNameEntry() }

            Button {
                viewModel.finishNameEntry()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentIndigo, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    PINSetupView(viewModel: PINSetupViewModel(pinService: PINService(), authService: BiometricAuthService()))
}
```

- [ ] **Step 2: Render the preview to confirm it builds and looks right**

```
ToolSearch query: "select:mcp__xcode__RenderPreview"
mcp__xcode__RenderPreview(tabIdentifier: "windowtab1")
```
Expected: preview renders the `.enterPin` step (default `currentStep`) without errors. This confirms the file compiles standalone; the new `.biometricPrompt`/`.nameEntry` branches are exercised by Task 5's manual walkthrough since the preview's default step is `.enterPin`.

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/PINSetupView.swift
git commit -m "feat: add biometric and name-entry screens to PINSetupView"
```

---

### Task 4: Wire up all call sites to the new init signature

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/AuthenticationWrapper.swift:29-33`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/PINEntryView.swift:70-74`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift:27-28,181-184`

**Interfaces:**
- Consumes: `PINSetupViewModel.init(pinService:authService:isChangeMode:showsOnboardingExtras:)` (Task 2).

- [ ] **Step 1: Update `AuthenticationWrapper.swift` — the real onboarding entry point**

In `AuthenticationWrapper.swift`, find:

```swift
            if !isPINSetup {
                PINSetupView(
                    viewModel: PINSetupViewModel(pinService: pinService)
                )
                .transition(.opacity)
```

Replace with:

```swift
            if !isPINSetup {
                PINSetupView(
                    viewModel: PINSetupViewModel(
                        pinService: pinService,
                        authService: authService,
                        showsOnboardingExtras: true
                    )
                )
                .transition(.opacity)
```

(`authService` is the `@StateObject private var authService = BiometricAuthService()` already declared at the top of `AuthenticationWrapper`.)

- [ ] **Step 2: Update `PINEntryView.swift` — forgot-PIN reset stays extras-free**

In `PINEntryView.swift`, find:

```swift
        .onChange(of: viewModel.showForgotPINSheet) { _, isPresented in
            if isPresented {
                setupViewModel = PINSetupViewModel(pinService: PINService(), isChangeMode: false)
            }
        }
```

Replace with:

```swift
        .onChange(of: viewModel.showForgotPINSheet) { _, isPresented in
            if isPresented {
                setupViewModel = PINSetupViewModel(
                    pinService: PINService(),
                    authService: viewModel.authService,
                    isChangeMode: false
                )
            }
        }
```

(`showsOnboardingExtras` stays at its `false` default — reusing `viewModel.authService`, the `let authService: BiometricAuthService` already on `PINEntryViewModel`, instead of constructing a throwaway instance.)

- [ ] **Step 3: Update `ProfileView.swift` — Change PIN stays extras-free**

In `ProfileView.swift`, find:

```swift
    private let pinService = PINService()
    private let backupService = BackupService()
```

Replace with:

```swift
    private let pinService = PINService()
    private let authService = BiometricAuthService()
    private let backupService = BackupService()
```

Then find:

```swift
                    case .changePIN:
                        PINSetupView(
                            viewModel: PINSetupViewModel(pinService: pinService, isChangeMode: true)
                        )
```

Replace with:

```swift
                    case .changePIN:
                        PINSetupView(
                            viewModel: PINSetupViewModel(pinService: pinService, authService: authService, isChangeMode: true)
                        )
```

- [ ] **Step 4: Build to confirm every call site compiles**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: build succeeds with no remaining references to the old two-argument `PINSetupViewModel.init`.

- [ ] **Step 5: Run the full test suite**

```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```
Expected: all tests pass, including the 8 new `PINSetupViewModelTests` from Task 2 and the pre-existing `PINConfirmationViewModelTests` (unaffected — different class).

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/App/AuthenticationWrapper.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/PINEntryView.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift
git commit -m "feat: wire biometric/name onboarding steps into the real PIN flows"
```

---

### Task 5: Manual verification

**Files:** none (no code changes — this task is a manual walkthrough).

- [ ] **Step 1: Fresh-install walkthrough**

Run the app in the Simulator (delete the app first, or reset `UserDefaults` for the bundle, so `pin_setup_complete` is unset). Set a PIN, confirm it. Verify:
- The biometric step appears (if the Simulator has an enrolled biometric — Simulator menu → Features → Face ID/Touch ID → Enrolled) with correct Face ID/Touch ID wording, and tapping "Enable" triggers the Simulator's Face ID prompt (Simulator menu → Features → Face ID → Matching/Non-matching Face).
- Tapping "Skip" on the biometric step advances to the name step without enabling biometrics (check Profile afterward — the toggle should be off).
- The name step accepts input, "Continue" advances into the app, and the name now appears in Profile / the Dashboard greeting.
- Leaving the name field empty and tapping "Continue" also advances into the app (Profile shows "Your Name" placeholder).

- [ ] **Step 2: Regression walkthrough — Change PIN**

From Profile → Change PIN, verify the flow still stops at the checkmark and dismisses — it must never show the biometric or name steps.

- [ ] **Step 3: Regression walkthrough — Forgot PIN**

Lock the app, enter the wrong PIN, tap "Forgot PIN?", authenticate biometrically, and reset the PIN. Verify it returns straight to the app after the checkmark — it must never show the biometric or name steps.

- [ ] **Step 4: Update the knowledge graph**

```bash
graphify update .
```
