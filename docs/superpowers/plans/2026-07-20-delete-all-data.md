# Delete All Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user permanently erase all financial data (transactions, categories, credit cards, goals, health score history, forecast cache) from within Settings, with a destructive confirmation and — if a PIN is set — a PIN re-entry step before the wipe executes.

**Architecture:** A standalone `DataWipeService` enum performs the SwiftData batch delete against the shared `ModelContext` — no dependencies, fully unit-testable. A new lightweight `PINConfirmationView`/`PINConfirmationViewModel` pair (mirroring `PINEntryView`'s visual style but decoupled from `BiometricAuthService`) gates the wipe when a PIN exists. `ProfileView` wires a destructive button → alert → optional PIN sheet → wipe call → result alert.

**Tech Stack:** SwiftUI, SwiftData (`ModelContext.delete(model:)` batch API, iOS 26), Swift Testing (`@Test`, `#expect`).

## Global Constraints

- Wipes only the 6 SwiftData models: `TransactionModel`, `CategoryModel`, `CreditCardModel`, `GoalModel`, `HealthScoreSnapshot`, `DailyForecastCache`. PIN (Keychain), biometric setting, and profile prefs (`user_full_name`, currency, pay cycle, `member_since_timestamp`) are never touched.
- `PINConfirmationViewModel` must NOT call `BiometricAuthService` or touch `isUnlocked` — it only validates the PIN via `PINService.validatePIN(_:)`.
- Follow existing dark-only styling: `.appBackground()`, `.preferredColorScheme(.dark)`, `Color.textPrimary`/`.textDim`/`.negative`, per `Utilities/DesignTokens.swift`.
- Test target uses Swift Testing (`@Test`, `#expect`), not XCTest, per `PersonalFinanceTrakerTests/Utilities/PayCycleServiceTests.swift` convention.

---

### Task 1: `DataWipeService` with unit tests

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/DataWipeService.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/DataWipeServiceTests.swift`

**Interfaces:**
- Produces: `enum DataWipeService { static func wipeAllData(context: ModelContext) throws }` — later tasks (Task 3) call this exact signature.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct DataWipeServiceTests {

    private func makeSeededContext() -> ModelContext {
        let schema = Schema([
            TransactionModel.self,
            CategoryModel.self,
            CreditCardModel.self,
            GoalModel.self,
            HealthScoreSnapshot.self,
            DailyForecastCache.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        // Categories + transactions via the app's existing sample data
        SampleData.populateModelContext(context)

        // One instance of each of the remaining models
        context.insert(CreditCardModel(name: "Test Card", lastFour: "1234", balance: 100, limit: 1000))
        context.insert(GoalModel(name: "Test Goal", targetAmount: 500))
        context.insert(HealthScoreSnapshot(
            timestamp: .now, score: 80, savingsScore: 80,
            stabilityScore: 80, adherenceScore: 80, subscriptionScore: 80
        ))
        context.insert(DailyForecastCache(monthKey: "2026-07", computedUpToDay: 1, days: [1], amounts: [10]))
        try! context.save()

        return context
    }

    @Test("wipeAllData removes every model type")
    func wipesAllModels() throws {
        let context = makeSeededContext()

        // Sanity check: seeded data exists before wiping
        #expect(try context.fetchCount(FetchDescriptor<TransactionModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<CategoryModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<CreditCardModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<GoalModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthScoreSnapshot>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<DailyForecastCache>()) > 0)

        try DataWipeService.wipeAllData(context: context)

        #expect(try context.fetchCount(FetchDescriptor<TransactionModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CategoryModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CreditCardModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GoalModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthScoreSnapshot>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<DailyForecastCache>()) == 0)
    }

    @Test("wipeAllData is idempotent on an already-empty context")
    func wipingEmptyContextDoesNotThrow() throws {
        let context = makeSeededContext()
        try DataWipeService.wipeAllData(context: context)

        // Calling again on an already-empty store must not throw
        try DataWipeService.wipeAllData(context: context)

        #expect(try context.fetchCount(FetchDescriptor<TransactionModel>()) == 0)
    }
}
```

This new test file must be added to the `PersonalFinanceTrakerTests` target. If the project uses synchronized folder groups in Xcode, adding the file under the existing `Utilities/` test folder is picked up automatically — no manual pbxproj edit needed (matches how `PayCycleServiceTests.swift` is already organized).

- [ ] **Step 2: Run test to verify it fails**

Use `ToolSearch` with `query: "select:mcp__xcode__RunSomeTests,mcp__xcode__GetTestList"` to load the tools, then:
- `mcp__xcode__GetTestList(tabIdentifier: "windowtab1")` to find the identifier for `DataWipeServiceTests`.
- `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", tests: [{targetName: "PersonalFinanceTrakerTests", testIdentifier: "DataWipeServiceTests"}])`

Expected: build FAILS — `DataWipeService` does not exist yet (`Cannot find 'DataWipeService' in scope`).

- [ ] **Step 3: Write minimal implementation**

```swift
import SwiftData

enum DataWipeService {
    static func wipeAllData(context: ModelContext) throws {
        try context.delete(model: TransactionModel.self)
        try context.delete(model: CategoryModel.self)
        try context.delete(model: CreditCardModel.self)
        try context.delete(model: GoalModel.self)
        try context.delete(model: HealthScoreSnapshot.self)
        try context.delete(model: DailyForecastCache.self)
        try context.save()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", tests: [{targetName: "PersonalFinanceTrakerTests", testIdentifier: "DataWipeServiceTests"}])`
Expected: PASS (both tests green).

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/DataWipeService.swift \
        PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/DataWipeServiceTests.swift
git commit -m "feat: add DataWipeService to batch-delete all financial data"
```

---

### Task 2: `PINConfirmationView` + `PINConfirmationViewModel`

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/ViewModels/PINConfirmationViewModel.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/PINConfirmationView.swift`

**Interfaces:**
- Consumes: `PINService.validatePIN(_ pin: String) -> Bool` (`Utilities/PINService.swift:20`); `PINDotsView(filledCount: Int)`, `PINPadView(onDigit: (String) -> Void, onDelete: () -> Void)`, `MonkeyAnimationView(eyesOpen: Binding<Bool>, isShaking: Bool)` (all in `Features/Security/Components/`).
- Produces: `PINConfirmationView(viewModel: PINConfirmationViewModel)` and `PINConfirmationViewModel(pinService: PINService, onConfirmed: @escaping () -> Void)` — Task 3 constructs and presents this view as a sheet.

This view model is deliberately **not** wired to `BiometricAuthService` — it is a one-off confirmation gate for a destructive action, not part of the app-unlock flow (see plan's Global Constraints).

- [ ] **Step 1: Write the view model**

```swift
import SwiftUI

@Observable @MainActor
final class PINConfirmationViewModel {
    var pinInput: String = ""
    var isShaking: Bool = false
    var eyesOpen: Bool = true
    var errorMessage: String = ""

    private let pinService: PINService
    private let onConfirmed: () -> Void

    init(pinService: PINService, onConfirmed: @escaping () -> Void) {
        self.pinService = pinService
        self.onConfirmed = onConfirmed
    }

    func appendDigit(_ digit: String) {
        guard pinInput.count < 4 else { return }
        pinInput += digit
        eyesOpen = false
        if pinInput.count == 4 {
            Task { try? await Task.sleep(for: .seconds(0.15)); self.verifyPIN() }
        }
    }

    func deleteDigit() {
        if !pinInput.isEmpty { pinInput.removeLast() }
        eyesOpen = pinInput.isEmpty
    }

    private func verifyPIN() {
        if pinService.validatePIN(pinInput) {
            onConfirmed()
        } else {
            errorMessage = "Incorrect PIN. Try again."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        }
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }
}
```

- [ ] **Step 2: Write the view**

```swift
import SwiftUI

struct PINConfirmationView: View {
    @State var viewModel: PINConfirmationViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MonkeyAnimationView(
                eyesOpen: $viewModel.eyesOpen,
                isShaking: viewModel.isShaking
            )
            .padding(.bottom, 32)

            VStack(spacing: 8) {
                Text("Confirm your PIN")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.textPrimary)

                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.negative)
                        .transition(.opacity)
                        .animation(.easeInOut, value: viewModel.errorMessage)
                }
            }
            .padding(.bottom, 32)

            PINDotsView(filledCount: viewModel.pinInput.count)
                .padding(.bottom, 48)

            PINPadView(
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() }
            )

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .preferredColorScheme(.dark)
    }
}

#Preview {
    PINConfirmationView(viewModel: PINConfirmationViewModel(pinService: PINService(), onConfirmed: {}))
}
```

- [ ] **Step 3: Build to verify it compiles**

Use `ToolSearch` with `query: "select:mcp__xcode__BuildProject"` (if not already loaded), then `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds (no test yet — this is a pure UI component, verified visually in Task 3's manual pass).

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/ViewModels/PINConfirmationViewModel.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/Features/Security/PINConfirmationView.swift
git commit -m "feat: add PINConfirmationView for gating destructive actions"
```

---

### Task 3: Wire "Delete All Data" into `ProfileView`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift`

**Interfaces:**
- Consumes: `DataWipeService.wipeAllData(context: ModelContext) throws` (Task 1); `PINConfirmationView(viewModel:)` / `PINConfirmationViewModel(pinService:onConfirmed:)` (Task 2); `PINService().isPINSet() -> Bool` (`Utilities/PINService.swift:27`).
- The view needs a `ModelContext` to pass to `DataWipeService` — use `@Environment(\.modelContext)`, which SwiftUI provides automatically since `PersonalFinanceTrakerApp` applies `.modelContainer(sharedModelContainer)` to the whole `WindowGroup` (`App/PersonalFinanceTrakerApp.swift:63`).

- [ ] **Step 1: Add the new state and imports to `ProfileView`**

Modify the top of `ProfileView.swift` (currently lines 1-9):

```swift
import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @State private var showingFileImporter = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPINConfirmation = false
    @State private var showingDeleteSuccess = false
    @State private var deleteErrorMessage: String?
    private let pinService = PINService()
```

- [ ] **Step 2: Add the "Delete All Data" row to the DATA section**

The DATA section is currently (lines 31-52 of the existing file):

```swift
                    Section {
                        Button {
                            showingFileImporter = true
                        } label: {
                            if transactionViewModel.isLoadingCSV {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reading file…")
                                }
                            } else {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(transactionViewModel.isLoadingCSV)
                    } header: {
                        Text("DATA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textDim)
                            .padding(.horizontal, 4)
                    }
                    .appFormSectionBackground()
```

Add a second button inside the same `Section`, after the Import CSV button:

```swift
                    Section {
                        Button {
                            showingFileImporter = true
                        } label: {
                            if transactionViewModel.isLoadingCSV {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reading file…")
                                }
                            } else {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(transactionViewModel.isLoadingCSV)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete All Data", systemImage: "trash")
                        }
                    } header: {
                        Text("DATA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textDim)
                            .padding(.horizontal, 4)
                    }
                    .appFormSectionBackground()
```

- [ ] **Step 3: Add the alert, PIN sheet, and wipe logic**

Add these modifiers to the outer `NavigationStack` (alongside the existing `.fileImporter` at the end of the current `body`, currently lines 79-90):

```swift
            .alert("Delete All Data?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if pinService.isPINSet() {
                        showingPINConfirmation = true
                    } else {
                        performWipe()
                    }
                }
            } message: {
                Text("This will permanently erase every transaction, category, credit card, and goal. This cannot be undone.")
            }
            .sheet(isPresented: $showingPINConfirmation) {
                PINConfirmationView(
                    viewModel: PINConfirmationViewModel(pinService: pinService) {
                        showingPINConfirmation = false
                        performWipe()
                    }
                )
            }
            .alert("All Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK") { dismiss() }
            }
            .alert(
                "Delete Failed",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("OK") { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
```

Add the private helper at the bottom of the `ProfileView` struct, right before the closing brace (after the existing `.fileImporter` block, before line 92's closing brace):

```swift
    private func performWipe() {
        do {
            try DataWipeService.wipeAllData(context: modelContext)
            showingDeleteSuccess = true
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Build to verify it compiles**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`
Expected: build succeeds.

- [ ] **Step 5: Manual verification pass in the simulator**

Reinstall the app fresh (delete + reinstall, or clear `pin_setup_complete`/re-seed sample data — this app has no App Store migration constraints per project policy) and walk through:
1. **No PIN set:** Settings → Delete All Data → confirm alert → Delete → data wipes immediately → success alert → Dashboard/Activity/Insights show empty states.
2. **PIN set:** Settings → Delete All Data → confirm alert → Delete → PIN confirmation sheet appears → enter wrong PIN → shakes, clears, stays on sheet → enter correct PIN → sheet dismisses → wipe executes → success alert.
3. **Cancel at either step:** tapping "Cancel" on the alert, or swiping away the PIN sheet, leaves all data intact.

- [ ] **Step 6: Run the full test suite**

Use `ToolSearch` with `query: "select:mcp__xcode__RunAllTests"` if not already loaded, then `mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`.
Expected: all tests pass, including the new `DataWipeServiceTests`.

- [ ] **Step 7: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift
git commit -m "feat: wire Delete All Data action into Settings"
```
