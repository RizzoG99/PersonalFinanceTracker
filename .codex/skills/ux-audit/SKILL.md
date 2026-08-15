---
name: ux-audit
description: Performs a professional UX/UI audit of Personal Finance Tracker mobile app screenshots. Use when the user shares screenshots and asks to review, critique, audit, roast, improve, or assess design, layout, usability, accessibility, visual hierarchy, or consistency.
---

# UX Audit

Audit Personal Finance Tracker screenshots as a senior mobile product designer and SwiftUI engineer. Be direct, evidence-based, and constructive.

## Context

- The app is a SwiftUI iOS personal finance app.
- EUR currency and money clarity matter.
- HIG conformance, Dynamic Type, VoiceOver, touch targets, and contrast are high priority.
- Cross-platform consistency is secondary to iOS-native quality.

## Method

Audit each screen individually, then the overall experience. Check:

1. Visual hierarchy.
2. Layout and spacing.
3. Typography.
4. Color and contrast.
5. Components and affordances.
6. Navigation.
7. Interaction feedback and states.
8. Accessibility.
9. Cross-screen consistency.
10. Overall UX.

Flag outdated patterns, missing states, confusing terminology, unnecessary complexity, information overload, and missed simplifications.

## Finding Format

Use this block for each issue:

```markdown
**[Severity: Critical | High | Medium | Low] - Short title**
- **Problem:** What is wrong.
- **Why it hurts UX:** Principle and user consequence.
- **Recommendation:** Concrete fix.
```

Group by `## Screen: <name>`, ordered by severity.

## Required Ending Sections

Always end with:

```markdown
## Executive Summary
- Top 10 UX problems
- Top 10 UI problems
- Biggest accessibility issues
- Biggest consistency issues

## Quick Wins

## High-Impact Improvements

## Long-Term Improvements

## UX Score
- Visual Design
- Usability
- Accessibility
- Information Architecture
- Navigation
- Consistency
- Learnability
- Overall Experience

## Redesign Suggestions
```
