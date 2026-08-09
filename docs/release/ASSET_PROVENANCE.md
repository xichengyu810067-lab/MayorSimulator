# Asset Provenance Inventory — 0.1.0-alpha.2

Status: **Internal-only evidence inventory. It does not grant redistribution rights.**

Only local evidence is recorded. “Unknown” is intentional: no author, license,
model, prompt, or permission is inferred from a filename, timestamp, adjacent
asset, or prior package.

| Item | Exact file | SHA-256 | Local evidence / current scope | Disposition |
| --- | --- | --- | --- | --- |
| Project license | `LICENSE.txt` | `F35DC634749109AC585D7312339FFEA0C2D76C2A562195CE28B9E2952673EE37` | Says internal pre-release, all rights reserved by the CivicTale: Voice of Promise project team; not an owner-supplied COPYRIGHT/ownership record or public grant. Internal testing only. | P0: owner authority plus applicable LICENSE/COPYING required. |
| City-map background | `assets/images/world/backgrounds/city-map-background.png` | `B968762C5F8756B26874D1B3610D889D2472B251C7E6F3D052B9C0533612E119` | Migrated from `幻想遊戲地圖風景.png`; no author, license, purchase receipt, or redistribution permission is in the repo. Internal-only. | P0: authorization/license or documented replacement required. |
| Train-station raw | `assets/images/world/buildings/storybook_v1/train_station/raw.png` | `8EF3C6400895E51DD69FF07AEC5D620C2ED969EA6CA5299F76EB4C78BD363256` | No generation receipt, prompt, processing log, author attribution, or redistribution permission. | P0. |
| Train-station processed source | `assets/images/world/buildings/storybook_v1/train_station/clean-full.png` | `EBB90A8B6A1C33715D4EC140181FACBFD711A328379E290BA3DD8C5F68C846B5` | Same missing evidence chain as raw image. | P0. |
| Train-station runtime asset | `assets/images/world/buildings/storybook_v1/train_station/clean.png` | `02100EC526DEE75C042463AF0141218606251B693AE2F88158534618A20C6BB9` | Runtime mapping/checksum only; see `train_station_asset_provenance_blocker.md`. | P0: checksum-linked provenance and public permission required. |

## Closure material

1. Rights-holder identity and written authorization/license/purchase evidence for
   the background’s intended public distribution.
2. For all train-station hashes: provider/generation record (or explicit unknown
   attestation), retained inputs/prompt, processing record, attribution, and
   separate redistribution permission.
3. Project-owner authority and a selected project LICENSE/COPYING record.

Regenerate the runtime ledger and re-run exact-commit acceptance after closure.
This inventory alone cannot close a P0.
