# Writing scenario tests

The mechanics are in `PersonalFinanceTraker/PersonalFinanceTrakerUITests/ScenarioTestCase.swift`:
- `launchApp`: a clean install, straight on Home with sample data, via `-skipOnboarding`;
- `shoot`;
- `auditAccessibility`;
- `knownAccessibilityIssues`.

`CategorySheetKeyboardScenarioTests.swift` (#259) is a worked example. This file holds what the code doesn't say.

## Shape

- One class per task, `<Topic>ScenarioTests: ScenarioTestCase`. One test per scenario, named `testS<k>_<what>`, marked `@MainActor` and `throws`.
- Each test launches the app itself. A test never depends on the state another test left behind.
- `shoot(app, "S<k>")` goes at the moment the scenario's *then* holds. The file is named `S<k>-<Topic>-<device>-<variant>.png`, so scenarios from different tasks don't collide. `try auditAccessibility(app, "S<k>", screens: …)` follows, on every screen the change touches.
- Assert the precondition too (for example "keyboard visible before tapping More"). That way a broken setup fails loudly instead of letting the scenario pass vacuously.
- Use waits (`waitForExistence`, `waitForNonExistence`, or `XCTNSPredicateExpectation` for a value), never sleeps or immediate reads. Scenario runs share the Mac with other work, and a read right after `typeText` or a foreground return has come back stale. "Stays hidden" means `XCTAssertFalse(x.waitForExistence(timeout: 2))`.

## Gotchas found so far

- **Every launch starts from default settings and first-run flags**, because `-skipOnboarding` clears them. First-run behaviour therefore applies in every test. For example, the first iPhone open of Add Transaction does not auto-focus Amount (`TransactionFormView.isFirstEverOpen`), so the test taps the field. Data is different: goals, recurring rules and trips persist until the pass's next reinstall (see the `launchApp` doc).
- **iPad layout differs.**
  - Add/Edit Transaction is an inspector beside Home, not a sheet.
  - Navigation is the sidebar (`app.collectionViews["Sidebar"]`), not the tab bar. iPadOS sometimes launches with the sidebar collapsed; `launchApp` reopens it.
  - On iPad, pass every visible screen to `auditAccessibility` (for example `screens: "AddTransaction", "Home"`).
- **The audit covers the whole app**, not one view. Known-issue labels must be exact. A trailing `*` is allowed only for labels holding dates or amounts. Never use a bare wildcard: it hides new findings.
- **Elements with no stable label**: add a test-only `.accessibilityIdentifier` on the containing view (precedent: `categoryStrip`, `categoryPickerGrid`). Query by identifier, not by text that also appears elsewhere on screen.
- **Selection or state that only shows as colour** is invisible to both the test and VoiceOver. Assert something structural instead, and file the missing accessibility state as its own issue (#270).
- **Orientation is pinned to portrait** in `setUpWithError`, because the simulator keeps whatever orientation it was last left in. A landscape scenario sets `XCUIDevice.shared.orientation` itself.
- **A text or search field found by its placeholder** may stop matching once it holds text (seen at AX-XXXL). Read its value through a query that doesn't depend on the label.
- **The keyboard is a separate window.** `shoot` captures the whole screen, so it shows. Check it with `app.keyboards.firstMatch`.
- **Background and foreground**: `XCUIDevice.shared.press(.home)`, then `app.activate()`. Coming back within 30 s (`BiometricAuthService.defaultGraceInterval`) shows no PIN overlay.
- **The simulator may not reproduce device timing.** If the scenario matching the report stays green on today's code, say so in the Decision log, and make sure another scenario goes red on the root cause.
- Verify launch-state behaviour through a scenario test. `simctl launch` renders a blank screen once a PIN is set.

## Reading results

- `scripts/xcb scenarios <Class>` prints a JSON summary. A run is good only when `result` is `Passed` and every pass has `passed == total`.
- Failure screenshots appear in `.build/scenarios/shots/` as `<pass>-<test>-failure-….png`.
- Full logs are in `.build/scenarios/<pass>.log`.
- A run takes several minutes: run it in the background.
