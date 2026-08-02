# Runtime Asset Ledger

本台帳只列入 canonical registry 或明確 runtime reference 可證明正在使用的 88 項媒體；原始圖、預覽、封存檔、測試截圖與 .import 不列入。

- JSON SHA-256：`D2E2EE70FFAEC917C5CC8F47BF8DD6EA38AE503915FDCA97C2FCAD566DC6C06B`
- 驗證：存在、SHA-256、重複路徑 0、重複內容雜湊 0、registry coverage、預期數量與必填 metadata 均通過。
- 唯一未解來源權利資產：`res://assets/images/world/backgrounds/city-map-background.png`；作者與公開散布授權尚未建立。
- 專案自身 `LICENSE` 尚未選定；`THIRD_PARTY_NOTICES.md` 不是專案授權。
- 生成／處理 provenance 只能說明素材如何產生，不等於授予或選定專案散布 license。

| 類別 | 預期 | 實際 |
|---|---:|---:|
| `audio` | 6 | 6 |
| `npc_portrait` | 8 | 8 |
| `npc_walk_sheet` | 8 | 8 |
| `ui_icon` | 37 | 37 |
| `building_clean` | 27 | 27 |
| `tutorial` | 1 | 1 |
| `background` | 1 | 1 |
| **合計** | **88** | **88** |

重建：`pwsh -NoProfile -File tools/generate_runtime_asset_ledger.ps1`。產生器不啟動 Godot、不修改 runtime 行為或素材。
