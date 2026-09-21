# iOS and Android Parity Matrix

This is the working inventory for Android v1. `Planned` means the feature is required for full current iOS parity, not that its design is complete.

| Area | Current iOS capability | Android v1 status | Notes |
| --- | --- | --- | --- |
| Foundation | Local finance data, profile, pay cycle, app appearance | Planned | Android-native implementation |
| Transactions | Income/expense tracking, add/edit/delete, grouped history, undo | Planned | Preserve calculation and destructive-action rules |
| Activity | Search and type/date/amount filters | Planned | Match filter semantics |
| Categories | Custom categories, icons, colors, mappings | Planned | Preserve mapping behaviour |
| Dashboard | Balance, pay-cycle summary, recent transactions | Planned | Match financial rules |
| Insights | Health score, forecasts, habits, trends, charts, goals | Planned | Match calculation inputs and results |
| Budgets | Budget and spending-progress workflows | Planned | Include current iOS scope |
| Credit | Credit cards and utilization | Planned | Include current iOS scope |
| Imports | CSV/XLSX import with column and category mapping | Planned | Available after onboarding |
| Exports | CSV/XLSX transaction export | Planned | Available at any time |
| Migration | Full iOS-to-Android data transfer | Deferred | Separate enhancement; not Android v1 scope |
| Backup | Encrypted iCloud Drive backup and restore | Planned | Android equivalent is encrypted Google Drive backup and restore |
| Security | Biometric/PIN protection and protected data deletion | Planned | Use Android-native security APIs |
| Receipts | Receipt capture and category assistance | Planned | Match current iOS behaviour |
| Discovery | In-app feature discovery and What's New | Planned | Include current iOS scope |

## Rules

- Android v1 is complete only when every row is `Matched` or has a documented, user-approved exception.
- A behaviour change affecting financial calculations, imports, exports, archives, or backups requires an update here and in its shared contract.
- Platform implementation may differ, but the user-visible result and data safety must remain equivalent unless explicitly approved otherwise.
