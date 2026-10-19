# Analysis: Contradictory Insights Charts (Build 93)

**Date:** 2026-09-22  
**Priority:** P2  
**Classification:** Computation Bugs (two separate mechanisms, same root cause pattern)

---

## Symptom

Two user submissions report contradictory or misleading financial data on the Insights tab:

1. **AAN0F2_tXh3eC3cm4VrPq60**: The yearly spending chart ("Anno") shows a sharp decline at the end, implying finances are worsening, when they should not. The last data point (shown as "ago"/August) drops almost to zero compared to prior months (1500–2500 range). The user reports "the chart appears to decline, implying the user's finances dropped, when it should not decline but stay higher."

2. **AFOVGksRslo7X1F_feTm1_A**: Two charts on screen contradict each other: the "Under last month's pace ↓ 22%" widget (shown with a downward green arrow, labeled "Spending 22% less") contradicts the Financial Health score of 90/100 ("Optimal financial habits"). User reports confusion: "the user cannot tell whether things are going well or badly."

Both reports are from build 93 on today's date (September 21, 2026 in the app).

---

## What Each Chart Computes

### 1. Spending Timeline Chart (Yearly View)

**File:** `/Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ChartDataService.swift:89–106`

**Method:** `generateYearlyData(from:referenceDate:)`

**Data Pipeline:**
1. Loop through i ∈ [0, 11] (last 12 periods)
2. For each i: `monthStart = calendar.date(byAdding: .month, value: -i, to: referenceDate)`
3. `monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)`
4. Filter transactions: `$0.timestamp >= monthStart && $0.timestamp < monthEnd`
5. Sum expenses (as positive `Decimal`) for that window
6. Label with `monthStart.formatted(.dateTime.month(.abbreviated))` — e.g., "Aug" for August
7. Reverse the array and return

**Critical Issue — Non-Calendar Aggregation:**

With `referenceDate = Date.now` (today, Sept 21, 2026):
- **i=0** (last data point, labeled "ago"/August): `monthStart = Sept 21`, `monthEnd = Oct 21` → **Captures only Sept 21 to Oct 20** (~1 day of Sept data, then future transactions; actual intent unclear but definitely not a full month)
- **i=1** (labeled "lug"/July): `monthStart = Aug 21`, `monthEnd = Sept 21` → **Captures Aug 21 to Sept 20** (~31 days, but misaligned with calendar month)
- **i=11** (labeled "ott"/October, last year): `monthStart = Oct 21, 2025`, `monthEnd = Nov 21, 2025` → **Oct 21–Nov 20, 2025** (~31 days)

**Result:** Data points represent day-21-to-day-20 windows (or "today-to-1-month-forward"), not calendar months or financial months. The **current window (Sept 21 to Oct 20) includes only today's data** (< 1 day in), so it will appear dramatically lower than all prior windows, which each span ~30 days.

**Sign handling:** `calculateExpenses()` (line 114–118) takes the absolute value of negative amounts, so expenses are stored and plotted as positive `Decimal`. No sign-flip bug here.

---

### 2. "Under Last Month's Pace" Hero Insight

**File:** `/Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SpendingInsightService.swift:12–56`

**Method:** `heroInsight(expenseTransactions:payCycleStartDay:)`

**Data Pipeline:**
1. Line 17: `startOfCurrentMonth = PayCycleService.financialMonthStart(for: now, startDay: payCycleStartDay)`
2. Line 18: `startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth)`
3. Line 20: `currentTotal = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfCurrentMonth })` — **includes all transactions from financial month start to `Date.now`**
4. Lines 21–22: `lastTotal = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfLastMonth && $0.timestamp < startOfCurrentMonth })` — **includes full previous financial month**
5. Line 33: `changeDecimal = (currentTotal - lastTotal) / lastTotal * 100`
6. Lines 37–42: If change < −5%, display "Spending NN% less" with `.down` direction (green downward arrow) and subtitle "You're under last month's pace"

**Critical Issue — Incomplete Current Month:**

With `startOfCurrentMonth = Sept 1, 2026` (assuming default startDay=1) and `Date.now = Sept 21, 2026 11:02 AM`:
- **currentTotal** sums expenses from Sept 1 00:00 to Sept 21 11:02 (~21 days)
- **lastTotal** sums expenses from Aug 1 00:00 to Sept 1 00:00 (~31 days)

If the user's daily spending is roughly uniform, `currentTotal` will automatically be **~32% lower** than `lastTotal` (21/31 ≈ 0.68), triggering the "22% less" message (which matches the report's "↓ 22%") even if the user is actually on exactly the same pace.

**Example:**
- Aug 1–Sept 1: €310 total (€10/day average) → `lastTotal = 310`
- Sept 1–21: €210 total (€10/day average) → `currentTotal = 210`
- Change: (210 − 310) / 310 × 100 = −32% ✓ Triggers "22% less" (after rounding)

---

## Root Cause — Bug vs Presentation

**Classification: COMPUTATION BUGS (both charts)**

Neither issue is a presentation-only problem (missing disclaimers, inverted y-axes, conflicting conventions between charts).

### Bug 1: Yearly Chart — Non-Calendar Aggregation

The bug is **structural**: `generateYearlyData()` computes month-to-date (or day-21-to-day-20) windows by arithmetic on the reference date, **not by extracting the calendar month from each transaction's date**. This makes the current partial window appear structurally lower than every complete prior window, regardless of actual spending pattern.

**Why it's not just presentation:**
- The data **values themselves are wrong** — the last point includes only ~1 day of the month, not 30 days.
- No label or note can fix this; the chart would need a visual marker like "incomplete month" or a different calculation entirely.
- Relabeling the x-axis or adding a legend does not change the fact that the calculation is wrong.

### Bug 2: Hero Insight — Incomplete Month Comparison

The bug is **algorithmic**: `heroInsight()` directly compares an incomplete current period (today to month start) against a full prior period, producing a guaranteed negative bias.

**Why it's not just presentation:**
- The **computation itself is flawed** — it is mathematically guaranteed to understate current-month spending for any user who has not yet completed the month.
- A disclaimer or color coding does not fix the underlying arithmetic.
- Swapping the comparison direction (current > last month?) does not help; the root issue is the mismatch in period lengths.

### Consistency Failure

The two bugs compound each other: the yearly chart's misleading final data point **aligns with the hero insight's always-negative bias** for incomplete months. Together, they create a **coherent false signal**: "Your finances are declining," when actually the month is simply not over yet.

---

## Edge Cases

### Chart Edge Cases (generateYearlyData)

1. **First month of data ever**: If the earliest transaction is Sept 10, 2026, and today is Sept 21, the chart will show only Sept 21–Oct 20 (~1 day) + earlier empty months. Displays as "sharp decline from nothing."

2. **Single transaction**: One €50 expense on Sept 15. Chart for i=0 (Sept 21–Oct 20) = €0; chart for i=1 (Aug 21–Sept 20) = €50. Last point (current) appears lower, even though it's the same transaction window.

3. **No transactions in current window**: If all transactions occurred before Sept 21, then i=0 shows €0, all others show historical averages. Displays as a dramatic cliff.

4. **Future-dated transactions** (in wallet, pending card): Included in current window (Sept 21 to Oct 20) if post-dated; skipped if before Sept 21. Adds noise to current month aggregation.

5. **Pay-cycle start day ≠ 1**: The chart uses calendar arithmetic (byAdding .month), **not PayCycleService**, so users with startDay=15 will see 21st-to-20th windows mislabeled with calendar month names that imply 1st-to-end-of-month. Worse misalignment than default.

### Hero Insight Edge Cases (heroInsight)

1. **First month of data**: `lastTotal > 0` guard fails if no prior-month data exists, displays "Building your picture" placeholder. Correct behavior.

2. **Zero spending in both months**: `lastTotal == 0` guard (line 25) prevents division by zero, displays placeholder. Correct.

3. **High spending in prior month, low this month**: Produces large negative percentage, triggers "Spending NN% less" even if pace is identical (due to partial month). **False negative.**

4. **Month with few days** (e.g., February with 28 days): If startDay is late in the month, the "current" financial month may span only a few days of the current calendar month plus many days of the next. Example: startDay=25, today=Sept 10 → financial month is Aug 25–Sept 25, so Sept 10 is only 16 days into a 31-day window. Amplifies the incomplete-month bias.

5. **Exact same expenses each month**: Should show 0% change, but will show ~20–30% negative change in early month due to partial aggregation. **False signal of decline.**

---

## Priority Assessment

**Confirm P2:**

- **User-facing impact:** High. Both charts directly contradict the financial health score (90/100), creating confusion about whether the user is doing well or badly. This is a **trust/confidence issue** with the core Insights feature.
  
- **Severity:** Medium. The app does not corrupt data; transactions are recorded correctly. But the visual output is systematically misleading for any user viewing the app before month-end.

- **Scope:** Limited to Insights tab; does not affect transaction recording, budgets, or exports.

- **Reproducibility:** 100%. Any user viewing the Insights chart on any date before month-end will see an artificially low final data point. The hero insight shows negative change for ~80% of days in any month.

**P2 is justified.** This is a clear computation bug with high user-facing impact, not a cosmetic issue. However, it is not P1 because workarounds exist (wait until month-end, use weekly view, check transaction list directly).

---

## Open Points

1. **Intended aggregation strategy for yearly chart:**
   - Should it show full calendar months (1st–end-of-month)?
   - Or financial months (payroll cycle start to end)?
   - Or calendar month aggregate regardless of referenceDate?
   - Current code does none of these; it does day-arithmetic windows that don't align with any standard month definition.

2. **Design intent for incomplete-month handling:**
   - Should the hero insight compare "current pace to date" vs. "last month's daily average" (pro-rata adjusted)?
   - Or should it skip the comparison if < N days have elapsed (e.g., before day 5)?
   - Or should it display a confidence band showing the range of possible end-of-month outcomes?

3. **Why PayCycleService is inconsistently used:**
   - `heroInsight()` correctly uses `PayCycleService.financialMonthStart()` (line 17).
   - But `generateYearlyData()` uses raw calendar arithmetic and ignores payCycleStartDay entirely in its month-to-date logic (only passed to `filterItems`, which is not used in the .year case).
   - This should be harmonized.

4. **Why tests did not catch this:**
   - No test in `ChartDataServiceTests` covers the yearly view with an incomplete current month.
   - No test in `SpendingInsightServiceTests` covers the hero insight on an incomplete month; the regression test at line 122 only checks pay-cycle awareness, not the incomplete-month math.
   - A test that compares "today (day 21 of month)" vs. "end of month (day 28+)" would have immediately surfaced the issue.

5. **Potential data visibility in production:**
   - Are there existing bug reports or analytics about "sudden spending drops" around month boundaries?
   - This bug would produce a **systematic false spike in "spending decline" reports** near month-end.

---

## Recommendation

**Fix priority:** High (within current sprint if possible).

**Root fixes needed:**
1. Redefine `generateYearlyData()` to aggregate by full calendar months or financial months, not day-arithmetic windows.
2. Redefine `heroInsight()` to either (a) pro-rata-adjust `currentTotal` by remaining days, (b) compare against an average daily rate, or (c) display a confidence range, not a point estimate.
3. Add regression tests for both cases with `referenceDate` set to various days in the month (especially early-month and late-month).

**Presentation improvements (after fix):**
- Add a subtle label to the chart: "Partial month" for the current window, if aggregation remains incomplete.
- Clarify in the hero insight subtitle: "pace is based on X days of data so far" if uncertainty is unavoidable.

---

**End of Analysis**
