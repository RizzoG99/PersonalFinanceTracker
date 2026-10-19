# Step 1 outcome + ID-keyed cluster table

Generated from open24.json. `feedbackIdentifier` is authoritative; `[n]` is not stable.


## Issues to file (14 + 1 parked)

| # | Title | Priority | feedbackIdentifier(s) | build | screenshot |
|---|---|---|---|---|---|
| 1 | Bulk category update after "select all" rewrites every outgoing transaction | P0 | `AH1o8htLNPtGWxn-p-ze-dA` | 93 | b93-AH1o8htL.jpg |
| 2 | CSV-created category missing from transaction detail and Settings → Categories | P1 | `ADdR89AM80RkY0p3FiCAmO0` | 93 | b93-ADdR89AM.jpg |
| 3 | Category search matches the stored English key, not the localised name | P1 | `AG-sJ061VEaIThBZMisMkLU` | 82 | b82-AG-sJ061.jpg |
| 4 | Hide amounts does not cover Financial Pulse or the daily-habit card | P1 | `APtS9TPPQlGAuqAVz6ow3f8<br>AEM4c1zXiIRUE0fRhjKOTJY` | 93, 51 | b93-APtS9TPP.jpg <br>b51-AEM4c1zX.jpg |
| 5 | Recurring rules with no occurrence yet are untappable and drawn as disabled | P1 | `ACqzwHMpItdBJ2DSoVofBBc<br>ANuvxqHFv_2rjCtmWjX2bh8` | 76, 76 | b76-ACqzwHMp.jpg <br>b76-ANuvxqHF.jpg |
| 6 | Category icons fall back to a generic glyph (trends + list filter) | P2 | `ADhQB8gpytFPxbJmMYVgsQY<br>ACYpq1C16H-stcS1mVlDxpw` | 93, 93 | b93-ADhQB8gp.jpg <br>b93-ACYpq1C1.jpg |
| 7 | Two insight charts read as contradictory; line falsely declines | P2 | `AAN0F2_tXh3eC3cm4VrPq60<br>AFOVGksRslo7X1F_feTm1_A` | 93, 93 | b93-AAN0F2_t.jpg <br>b93-AFOVGksR.jpg |
| 8 | Selection mode: no way to create a trip when none exists | P2 | `AAjn2hItNdN6J_DUKMvYkno` | 93 | b93-AAjn2hIt.jpg |
| 9 | Long-press on a trip opens detail and enters selection mode | P2 | `ADfDYFFOEo4mH6wzXxkTrIc` | 93 | b93-ADfDYFFO.jpg |
| 10 | Selection mode: cannot tell a transaction is already in a trip | P2 | `AOzAYR1pCzloGgDptXqmZag` | 93 | b93-AOzAYR1p.jpg |
| 11 | Theme change does not update the nav-bar close button until reopened | P2 | `AGHPTTAq1EKytlXLt_aPQUc` | 54 | b54-AGHPTTAq.jpg |
| 12 | iPad: filter-chips band does not match the app background | P3 | `AEwZqtBfav0G9w40_67sjOw` | 61 | b61-AEwZqtBf.jpg |
| 13 | Trip transaction rows do not match Dashboard/list row layout | P3 | `AIxFxfyDLbi4TEmK-XS8OZs` | 93 | b93-AIxFxfyD.jpg |
| 14 | Budgets screen: expense-only, "No limit" wording, jumpy focus, dead space | P3 | `ACCOAyuX6T-lvGTBmOymMUc` | 76 | b76-ACCOAyuX.jpg |

## Parked as `enhancement`

- Dashboard suggestions surface recurring transactions instead of habitual daily spends — `AIj6ORDlJ3cpPBd3Y4cAb7Y` (build 93, b93-AIj6ORDl.jpg)

## Evidence onto existing issues

- #56 / #101 ← `ADvhdCBzDtNpLf8SMQX2Lv8` (b54-ADvhdCBz.jpg)
- #72 ← `AJq_EB1kl6q1KadcIoqewIE`, `ABUv5v19l-R7ro4Gv8Ue-dk`, `AAuRcsd_7ec8JCqUCzenfd4` (b61-AJq_EB1k.jpg, b61-ABUv5v19.jpg, b61-AAuRcsd_.jpg)

## Dropped by Step 1

- `ANhcVN6rhZ1o8qpwmBZyuPQ` (build 61, b61-ANhcVN6r.jpg) — fixed by 6cb2cb1 (2026-08-27); current-build iPad ledger screenshot shows table reflowed beside the sidebar
