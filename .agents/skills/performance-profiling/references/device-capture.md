# Manual device capture

Use this when requesting a recording, tailoring the actions and acceptance observation to
the complaint. Give the user one self-contained protocol, not a list of possible tools.

## Build and provenance

Use a physical device with an optimized build for responsiveness conclusions. Xcode's
Product → Profile normally uses the scheme's Release configuration; inspect the scheme
instead of assuming. A TestFlight build is suitable for daily-use observation. Debug and
simulator recordings remain useful for structural work counts and causal exploration;
label their limits. Keep the binary/symbols for the exact build being recorded.

Record device/OS, build configuration and commit plus dirty scope, ledger size, thermal
state, cold/warm process state, language, and exact launch arguments. Keep these equivalent
across before/after runs. For PFT, inspect PerformanceAuditDataSeeder and the scheme for
currently supported audit flags. Preserve an existing store; use seeding only when the
user requests a disposable fixture. Inspect DEBUG guards: skip-lock or seeding arguments
may have no effect in Release. Unlock manually when necessary and mark the measured action
after authentication.

## Recording

The user selects the connected device and app in Instruments and records Time Profiler
plus Points of Interest together. Hitches is unavailable in the established environment;
CPU samples and signposts are the supported evidence. Avoid collecting unrelated
instruments that change load or capture unnecessary personal data.

Give concrete steps, for example:

1. Launch into the specified screen and wait until launch work settles (record the wait).
2. Perform exactly the target action. Include both first and repeated occurrences when
   first-use initialization is the question; keep their boundaries distinguishable.
3. For search, first show the keyboard without typing, then type a fixed non-sensitive
   query, wait for results, extend it, and clear it. Leave enough time between steps to
   distinguish them. Record the query length or a fixture query, not real financial notes.
4. Record another five seconds, stop, and **save the trace**. State the path and run number;
   recording again in the same document adds a run rather than replacing the first.
5. Note what visibly froze and at which step. Return the full saved `.trace`; screenshots
   can supplement it but cannot replace sample/marker extraction.

For an existing recording with a user-described final ten-second search segment, analyze
that segment first. If markers cannot distinguish typing from keyboard animation or result
publication, state the missing latency evidence instead of asking for a new full capture
without first using the available data.

## Acceptance and stop

Use the product's existing latency budget when available. Otherwise agree on the visible
interaction that must improve and a bounded experiment. Several equivalent runs support a
distribution; one exploratory trace supports a finding about that run. A small difference
between two simulator CPU totals does not establish a user-visible win or regression.

Accept a bounded first-use cost if everyday device use is satisfactory and no actionable
app-owned cause remains. Keep a specific follow-up trigger, such as repeated typing stalls
on the device, rather than leaving an indefinite optimization task open.
