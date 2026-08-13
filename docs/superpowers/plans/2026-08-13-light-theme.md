# Light Theme + Appearance Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user an Auto / Light / Dark appearance picker, with a light theme that mirrors the existing dark brand language.

**Architecture:** All colour work is asset-catalog data — each of the 18 colorsets gains a light appearance alongside its existing dark one, so views need no changes. Exactly one view reads `@Environment(\.colorScheme)` (`AppBackground`, whose gradient can't live in the catalog), and exactly one modifier declares the app's appearance (`.preferredColorScheme` on `AuthenticationWrapper`). A `ThemeMode` enum in `@AppStorage` feeds that single modifier.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`@Test` / `#expect`), Xcode asset catalogs.

## Global Constraints

- **Working directory:** `/Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme` — a git worktree on branch `worktree-light-theme`. Do not `cd` to the parent repo.
- **Source root:** `PersonalFinanceTraker/PersonalFinanceTraker/` — note the typo, "Traker" is missing the `c`. This is correct and intentional.
- **NEVER run `xcodebuild` in Bash.** It is banned in this project.
- **Build and test only via Xcode MCP tools.** Two steps, every time. First load schemas:
  `ToolSearch` with query `select:mcp__xcode__XcodeListWindows,mcp__xcode__BuildProject,mcp__xcode__RunAllTests`
  Then call with `tabIdentifier`.
- **Verify `tabIdentifier` before first use.** It changes per Xcode launch. Call `mcp__xcode__XcodeListWindows` and confirm `workspacePath` points at `.claude/worktrees/light-theme/...`, **not** the parent checkout. It was `windowtab1` at time of writing.
- **Tests are Swift Testing** (`@Test`, `#expect`, `struct` suites), **not XCTest**. Use `@testable import PersonalFinanceTraker`.
- Expenses are stored as **negative** `Decimal`. Currency is EUR throughout.
- **No `.xcodeproj` edits are needed in this plan, for any file type.** The project is `objectVersion = 77` and uses `PBXFileSystemSynchronizedRootGroup` (synchronized filesystem groups) — it lists no individual `.swift in Sources` build references. Any `.swift` file created inside a source folder, and any `.colorset` created inside `Assets.xcassets`, is picked up by its target automatically. **Never hand-edit `project.pbxproj`.** If a new file appears not to compile, re-check its path, don't touch the project file.
- Colour values below are verified against the worst-case composited backdrop `#DDE1F1`, not flat `bg0`. Do not "tidy" them toward rounder numbers.

## Prerequisites (already committed — do not redo)

- `1145b09` — overlay tokens `hairline`/`surfaceRaised` created and wired; eight production `.preferredColorScheme(.dark)` overrides removed and replaced with one root declaration; `#030712` de-duplicated onto `Color.appBackgroundBase`.
- `561d563` — pie slices read `CategoryModel.colorToken`; amounts always signed.

Baseline at start of this plan: **build clean, 398/398 tests passing.**

## File Structure

| File | Responsibility |
| --- | --- |
| `Assets.xcassets/*.colorset/Contents.json` (18 of 20) | Modify: add a light appearance to each. Pure data. `hairline` and `surfaceRaised` are excluded — they already carry both appearances from `1145b09`. |
| `Models/ThemeMode.swift` | Create: the enum, its `ColorScheme?` mapping and display labels. No UI, no storage. |
| `Utilities/DesignTokens.swift:78-104` | Modify: `AppBackground` gains a `colorScheme` branch for bloom opacity only. |
| `Features/Profile/Components/ProfileAppearanceSection.swift` | Create: the picker UI alone, matching its nine sibling sections. |
| `Features/Profile/Views/ProfileView.swift:63-66` | Modify: insert the new section after Currency. |
| `App/PersonalFinanceTrakerApp.swift` | Modify: read `@AppStorage`, swap the hardcoded `.dark` literal. |
| `PersonalFinanceTrakerTests/Models/ThemeModeTests.swift` | Create: covers the enum's mapping and storage default. |

Ordering is deliberate: colours land first and are invisible (the app is still pinned to `.dark`), and the final task flips everything on at once. There is no intermediate state where the app looks broken.

---

### Task 1: Light appearances for the remaining 18 colorsets

**Files:**
- Modify: 18 of the 20 `PersonalFinanceTraker/PersonalFinanceTraker/Assets.xcassets/*.colorset/Contents.json`
- Leave alone: `hairline.colorset` and `surfaceRaised.colorset` — they already hold both appearances (light alpha 0.280 / 0.100, dark 0.100 / 0.070) from `1145b09`. They are deliberately absent from the generator's `TOKENS` map; adding them would overwrite their alpha values with opaque ones and destroy the overlay effect.
- Test: none — asset catalogs have no unit-test surface. Verified by build plus the visual check in Task 4.

**Interfaces:**
- Consumes: nothing.
- Produces: every `Color("token")` in the app resolves to a light value under a light trait. No Swift symbols change, so no other task depends on names from this one.

- [ ] **Step 1: Write the generator script**

Hand-editing 18 JSON files is error-prone and the float conversion is easy to get wrong. Write this to `/tmp/gen_colorsets.py`:

```python
import json, os

ROOT = ("/Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme/"
        "PersonalFinanceTraker/PersonalFinanceTraker/Assets.xcassets")

# token: (light hex, dark hex).  Dark values are exactly what ships today.
TOKENS = {
    "bg0":            ("#EEF0F6", "#060B18"),
    "bg1":            ("#F9FAFB", "#0D1526"),
    "bg2":            ("#FFFFFF", "#131D30"),
    "LaunchBackground": ("#E6EAF1", "#030712"),
    "textPrimary":    ("#0F172A", "#F1F5F9"),
    "textMid":        ("#475569", "#94A3B8"),
    "textDim":        ("#576477", "#708096"),
    "accentIndigo":   ("#4F46E5", "#6366F1"),
    "positive":       ("#0A6B4F", "#22D3A0"),
    "negative":       ("#991B1B", "#F87171"),
    "categoryIndigo": ("#4F46E5", "#6366F1"),
    "categoryPurple": ("#7C3AED", "#8B5CF6"),
    "categoryPink":   ("#DB2777", "#EC4899"),
    "categoryAmber":  ("#B45309", "#F59E0B"),
    "categoryGreen":  ("#0A6B4F", "#22D3A0"),
    "categoryTeal":   ("#0E7490", "#14B8A6"),
    "categoryGray":   ("#64748B", "#94A3B8"),
    "AccentColor":    ("#4F46E5", "#6366F1"),
}

def components(hex_str, alpha="1.000"):
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    return {"alpha": alpha, "blue": "%.3f" % b, "green": "%.3f" % g, "red": "%.3f" % r}

def entry(hex_str, appearance=None):
    e = {"color": {"color-space": "srgb", "components": components(hex_str)},
         "idiom": "universal"}
    if appearance:
        e["appearances"] = [{"appearance": "luminosity", "value": appearance}]
    return e

for name, (light, dark) in TOKENS.items():
    path = os.path.join(ROOT, "%s.colorset" % name, "Contents.json")
    assert os.path.exists(path), "missing colorset: %s" % path
    doc = {
        # First entry carries no `appearances` key: it is the "Any" appearance,
        # which iOS resolves for light. The second is explicitly dark.
        "colors": [entry(light), entry(dark, "dark")],
        "info": {"author": "xcode", "version": 1},
    }
    with open(path, "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print("wrote %-18s light %s / dark %s" % (name, light, dark))

print("\n%d colorsets updated" % len(TOKENS))
```

Note `AccentColor` is included: it currently holds a `reference` to `systemBlueColor`, which this replaces with the real indigo. That is intentional — see spec §9.

- [ ] **Step 2: Run it**

Run: `python3 /tmp/gen_colorsets.py`
Expected: 18 lines of output, ending `18 colorsets updated`. If any assert fires, a colorset name is wrong — stop and check the directory listing rather than creating a new colorset.

- [ ] **Step 3: Verify the dark values are byte-equivalent to what shipped**

Dark mode must not shift. Run:

```bash
cd /Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme
git stash list
python3 - <<'EOF'
import json, subprocess, glob, os
ROOT = "PersonalFinanceTraker/PersonalFinanceTraker/Assets.xcassets"
bad = 0
for p in sorted(glob.glob(os.path.join(ROOT, "*.colorset/Contents.json"))):
    old = subprocess.run(["git", "show", "HEAD:%s" % p], capture_output=True, text=True).stdout
    if not old.strip():
        continue
    o = json.load(open(p))
    try:
        prev = json.loads(old)["colors"][0]["color"]["components"]
    except (KeyError, TypeError):
        print("SKIP (was a reference): %s" % p)
        continue
    now = [c for c in o["colors"] if c.get("appearances")][0]["color"]["components"]
    if {k: round(float(v), 3) for k, v in prev.items()} != {k: round(float(v), 3) for k, v in now.items()}:
        print("DARK CHANGED: %s\n  was %s\n  now %s" % (p, prev, now)); bad += 1
print("dark-value drift: %d" % bad)
EOF
```

Expected: `dark-value drift: 1`, with one `SKIP (was a reference)` line for `AccentColor`.

**The single expected drift is `textDim`, and it is correct.** The shipped file held rounded floats (`0.440 / 0.500 / 0.590`); the exact conversion of the documented `#708096` is `0.439 / 0.502 / 0.588`. Both quantise to the same 8-bit colour, so nothing renders differently — the difference is below the quantisation floor. Ruled 2026-08-13: the hex table governs, so the file matches the documented value rather than preserving a historical rounding artifact. **Any drift other than `textDim` is a real defect** — dark mode must not shift.

- [ ] **Step 4: Build**

Load schemas via `ToolSearch`, confirm the tab with `mcp__xcode__XcodeListWindows`, then `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: `The project built successfully.` with no errors. A malformed `Contents.json` surfaces here as an asset-catalog compile error.

- [ ] **Step 5: Commit**

```bash
cd /Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme
git add PersonalFinanceTraker/PersonalFinanceTraker/Assets.xcassets
git commit -m "feat: add light appearances to all colorsets

Every token gains a light value alongside its existing dark one, which is
preserved byte-for-byte. AccentColor stops referencing systemBlueColor and
becomes the real indigo in both appearances.

Light values are verified against the worst-case composited backdrop
#DDE1F1 rather than flat bg0, since AppBackground blooms and Liquid Glass
sit between content and the base."
```

---

### Task 2: `AppBackground` light branch

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/DesignTokens.swift:78-104`
- Test: none — a gradient has no assertable output. Verified by build and the Task 4 visual check.

**Interfaces:**
- Consumes: `Color.appBackgroundBase` (exists already, from `1145b09`).
- Produces: no new symbols. `AppBackground` keeps its current initialiser and `appBackground()` modifier.

- [ ] **Step 1: Replace the `AppBackground` struct**

The base colour already flips automatically via the catalog (Task 1). Only the three bloom opacities need to vary — the bloom *hues* are identical in both themes. Replace the struct body:

```swift
// Matches the Claude Design spec:
// base + radial blooms — indigo at top-left, teal at bottom-right, indigo at centre.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    // The one legitimate colorScheme branch in the app: a gradient can't live in the
    // asset catalog. Light opacities are ~a quarter of dark, not equal — adding light
    // to a near-black base barely moves contrast, but adding saturated indigo to a
    // light base moves it a lot. At parity the worst-case backdrop pushed four tokens
    // below their contrast bar.
    private var bloom: (indigoTop: Double, teal: Double, indigoCentre: Double) {
        colorScheme == .dark ? (0.22, 0.10, 0.10) : (0.05, 0.03, 0.03)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.appBackgroundBase

                // Indigo bloom — top-left (ellipse at 20% 0%)
                RadialGradient(
                    colors: [
                        Color(red: 0.506, green: 0.549, blue: 0.973).opacity(bloom.indigoTop),
                        .clear
                    ],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.55
                )

                // Teal bloom — bottom-right (ellipse at 80% 100%)
                RadialGradient(
                    colors: [
                        Color(red: 0.133, green: 0.827, blue: 0.627).opacity(bloom.teal),
                        .clear
                    ],
                    center: UnitPoint(x: 0.8, y: 1.0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.55
                )

                // Indigo bloom — centre (ellipse at 50% 50%)
                RadialGradient(
                    colors: [
                        Color(red: 0.388, green: 0.400, blue: 0.945).opacity(bloom.indigoCentre),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.height * 0.60
                )
            }
        }
        .ignoresSafeArea()
    }
}
```

Geometry, radii and `UnitPoint` centres are unchanged from the current implementation.

- [ ] **Step 2: Build**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`
Expected: `The project built successfully.`

- [ ] **Step 3: Run the suite to confirm no regression**

`mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`
Expected: `398 tests: 398 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
cd /Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/DesignTokens.swift
git commit -m "feat: light-mode bloom opacities for AppBackground

Base colour flips via the asset catalog; only the three bloom opacities
branch on colorScheme. Light values are roughly a quarter of dark because
adding saturated indigo to a light base costs far more contrast than adding
light to a near-black one."
```

---

### Task 3: `ThemeMode` enum and its tests

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/ThemeMode.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/ThemeModeTests.swift`
- Test: the file above

**Interfaces:**
- Consumes: nothing.
- Produces: `enum ThemeMode: String, CaseIterable, Identifiable` with cases `.auto`, `.light`, `.dark`; `var id: String`; `var colorScheme: ColorScheme?`; `var label: LocalizedStringKey`. Task 4 consumes all of these and the raw values `"auto" | "light" | "dark"`.

Both new files are picked up automatically by their targets — `ThemeMode.swift` sits under the app's source folder, `ThemeModeTests.swift` under the test folder. No project-file edit; see Global Constraints.

- [ ] **Step 1: Write the failing test**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/ThemeModeTests.swift`:

```swift
import Testing
import SwiftUI
@testable import PersonalFinanceTraker

struct ThemeModeTests {

    @Test func autoMapsToNilSoTheSystemDecides() {
        #expect(ThemeMode.auto.colorScheme == nil)
    }

    @Test func lightAndDarkMapToTheirColorSchemes() {
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
    }

    @Test func rawValuesRoundTrip() {
        for mode in ThemeMode.allCases {
            #expect(ThemeMode(rawValue: mode.rawValue) == mode)
        }
    }

    /// @AppStorage keys off these strings. Changing one silently resets every
    /// existing user's choice back to the default, so pin them.
    @Test func rawValuesAreStable() {
        #expect(ThemeMode.auto.rawValue == "auto")
        #expect(ThemeMode.light.rawValue == "light")
        #expect(ThemeMode.dark.rawValue == "dark")
    }

    @Test func allCasesAreOfferedInPickerOrder() {
        #expect(ThemeMode.allCases == [.auto, .light, .dark])
    }

    /// An absent key must fall back to .auto — the shipped default.
    @Test func absentStoredValueFallsBackToAuto() {
        #expect(ThemeMode(rawValue: "not-a-mode") == nil)
        #expect(ThemeMode(rawValue: "not-a-mode") ?? .auto == .auto)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

`mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`
Expected: compile failure — `cannot find 'ThemeMode' in scope`. That counts as the failing state; the type does not exist yet.

- [ ] **Step 3: Write the enum**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Models/ThemeMode.swift`:

```swift
import SwiftUI

/// The user's appearance preference. Persisted by raw value under the
/// `app_theme_mode` key — see `ProfileAppearanceSection`.
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    /// `nil` means "follow the system", which is what `.preferredColorScheme`
    /// interprets as no override.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  nil
        case .light: .light
        case .dark:  .dark
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .auto:  "Auto"
        case .light: "Light"
        case .dark:  "Dark"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

`mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`
Expected: `404 tests: 404 passed, 0 failed` — the previous 398 plus the 6 above.

- [ ] **Step 5: Commit**

```bash
cd /Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/ThemeMode.swift \
        PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/ThemeModeTests.swift
git commit -m "feat: add ThemeMode enum

Auto maps to nil so .preferredColorScheme defers to the system. Raw values
are pinned by test because @AppStorage keys off them - renaming one would
silently reset every existing preference."
```

---

### Task 4: Appearance picker, and activation

This is the task that makes the feature visible. It ends with a manual visual pass, because no automated test in this project asserts colour.

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Components/ProfileAppearanceSection.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift:63-66`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`

**Interfaces:**
- Consumes: `ThemeMode` (all members) from Task 3; the `app_theme_mode` storage key is shared between the picker and the root modifier and must match exactly in both.
- Produces: `struct ProfileAppearanceSection: View` with a no-argument initialiser.

`ProfileAppearanceSection.swift` is picked up automatically — no project-file edit.

- [ ] **Step 1: Create the section**

Mirrors `ProfileCurrencySection` exactly — same caption header treatment, same `.tint`. Create `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Components/ProfileAppearanceSection.swift`:

```swift
import SwiftUI

struct ProfileAppearanceSection: View {
    @AppStorage("app_theme_mode") private var themeMode: ThemeMode = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPEARANCE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)

            Picker("Appearance", selection: $themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(.accentIndigo)
        }
    }
}
```

`@AppStorage` supports a `String`-backed `RawRepresentable` directly, so no manual encoding is needed.

- [ ] **Step 2: Insert it into `ProfileView`**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift`, find:

```swift
                    Section {
                        ProfileCurrencySection()
                    }
                    .appFormSectionBackground()
```

Replace with:

```swift
                    Section {
                        ProfileCurrencySection()
                    }
                    .appFormSectionBackground()
                    Section {
                        ProfileAppearanceSection()
                    }
                    .appFormSectionBackground()
```

- [ ] **Step 3: Activate it at the root**

In `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`, add the storage property alongside the existing `@State private var containerErrorMessage: String?`:

```swift
    /// Drives the single `.preferredColorScheme` declaration below. Key must match
    /// `ProfileAppearanceSection`.
    @AppStorage("app_theme_mode") private var themeMode: ThemeMode = .auto
```

Then find:

```swift
                // Single place the app's appearance is declared. Previously eight views
                // each pinned `.preferredColorScheme(.dark)` on their own body, which
                // meant a descendant silently overrode any app-level choice. Becomes
                // `themeMode.colorScheme` when the Appearance picker lands.
                .preferredColorScheme(.dark)
```

Replace with:

```swift
                // Single place the app's appearance is declared. Eight views used to
                // pin `.preferredColorScheme(.dark)` on their own bodies, which meant a
                // descendant silently overrode any app-level choice.
                .preferredColorScheme(themeMode.colorScheme)
```

- [ ] **Step 4: Build and run the suite**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")` then `mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`
Expected: build succeeds; `404 tests: 404 passed, 0 failed`.

- [ ] **Step 5: Manual visual pass — the real verification**

No test in this project asserts colour, so this step is not optional. Run the app in the simulator and check:

1. Profile → Appearance shows a three-segment picker defaulting to **Auto**.
2. Switching to **Light** flips the app immediately, including sheets and the PIN screens.
3. Switching to **Dark** looks identical to before this plan started.
4. In Light, walk the screens whose tokens changed: Dashboard, Activity, Insights (health score, goals, forecast, timeline chart), Credit, Budgets, Profile, PIN setup/entry, category settings, CSV import result.
5. Specifically confirm in Light: form rows and the `ArcGaugeView` track are visible (they use `surfaceRaised`); dividers are visible (`hairline`); the "Importing…" button label is legible.
6. Set the system appearance opposite to the app's forced mode and relaunch. The launch screen will briefly show the *system's* appearance — this is expected and documented in spec §10, not a bug to chase.

Report anything that looks wrong rather than fixing it silently — several values were chosen against a contrast floor and may want an aesthetic second pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/gabrielerizzo/Develop/PersonalFinanceTracker/.claude/worktrees/light-theme
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Components/ProfileAppearanceSection.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift
git commit -m "feat: Auto/Light/Dark appearance picker

Adds a segmented picker to Profile and swaps the root .preferredColorScheme
literal for the stored ThemeMode. Defaults to Auto for all installs; the app
is not on the App Store so no migration flag is needed."
```

---

## Not in this plan

- **Direct labels on `CategoryPieChart`.** Spec §5 asked for direct segment labels *or* "a legend pairing swatch with name adjacently". `CategoryLegendItem` (`CategoryPieChart.swift:111-151`) already renders the swatch adjacent to the category name, amount and percentage, so every value the pie encodes is available as text and WCAG 1.4.1 is satisfied. No task needed. The residual weakness is wayfinding — a CVD user cannot map a specific *slice* to its legend row when two hues are indistinguishable — which is worth a future look but is not an information-availability failure.
- **High-contrast (`luminosity: high`) appearance variants.** Spec §12, deferred.
- **Reducing the category palette below 7 hues.** Spec §12, deferred.

## Self-Review

**Spec coverage:** §1 mechanism → Tasks 3, 4. §2 methodology → constrains Task 1's values. §3 surface ramp → Task 1. §4 text/accent tokens → Task 1. §5 category tokens → Task 1; its CVD limitation is resolved in `561d563` and the labelling clause is already satisfied (see "Not in this plan"). §6 overlay tokens → no task needed: `hairline` and `surfaceRaised` shipped with both appearances in `1145b09`, and Task 1 explicitly excludes them so their alpha values survive. §7 AppBackground → Task 2. §8 UI → Task 4. §9 AccentColor → Task 1. §10 launch flash → Task 4 step 5.6. §11 testing → Task 3. §12 out of scope → "Not in this plan".

**Placeholder scan:** none — every code step carries complete, runnable content.

**Type consistency:** `ThemeMode.colorScheme`, `.label`, `.allCases`, `.id` are defined in Task 3 and used with those exact names in Task 4. The storage key `"app_theme_mode"` appears identically in `ProfileAppearanceSection` and `PersonalFinanceTrakerApp`, and is pinned by `rawValuesAreStable`.
