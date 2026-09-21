# Android Compose architecture

## State and data

- Compose screens collect immutable `StateFlow` UI state from a ViewModel. Keep Room DAOs and
  repository implementation details outside composables.
- Repositories expose `Flow` for observed data. Combine transactions, categories, and preferences
  in ViewModels or domain services, not in view layout code.
- Room holds financial records; DataStore holds preferences such as the pay-cycle start day and
  currency. Do not use destructive migration fallbacks.
- Keep money exact with `BigDecimal`; expenses are negative and income is positive in the domain.

## Composition and navigation

- Keep features under `features/<feature>/` and reusable UI under `ui/`. Extract a component only
  when it has a stable, reusable responsibility.
- Inject repositories through application composition and ViewModel factories. Do not construct a
  database or repository in a composable.
- Keep the main destinations in `PersonalFinanceNavHost`; use stable routes, preserve selected tab
  state, and follow Android Back expectations.

## Verification

- Add focused unit tests for domain rules and ViewModel transformations. UI behavior that depends
  on Compose semantics deserves Compose/UI coverage when the project has the appropriate test
  harness.
- Build and unit-test with Gradle. Device checks complement, but do not replace, behavioral tests.
