# 測試策略

**原則：先找出「出錯最貴」的地方，再決定怎麼測。** 自動化測試負責擋住回歸，人工驗收負責判斷體驗；兩者都過才發佈。

## 1. 風險與對應測試

| 風險 | 為什麼貴 | 怎麼測 | 代表測試 |
| --- | --- | --- | --- |
| 存檔損毀或遺失 | 玩家進度消失、無法挽回 | 先寫暫存檔、驗證雜湊、再輪替備份；在 5 個寫檔階段強制終止程序後檢查能否復原；限制不可信存檔的大小與深度 | [save_recovery_self](../../tests/unit/core/save_recovery_self_test.gd)、[save_input_limits](../../tests/unit/core/save_input_limits_test.gd)、[OS-kill 測試](../../tools/run_save_os_kill_qa.ps1) |
| 交易不一致（重複扣款、做一半） | 遊戲規則失真、存檔帶著錯誤狀態 | 失敗必須完全回滾；被拒絕的操作不得改動任何狀態 | [transport_route_package_atomicity](../../tests/integration/transport_route_package_atomicity_test.gd)、[transport_network_system](../../tests/unit/systems/transport_network_system_test.gd) |
| 地形、建築與居民路徑互相矛盾 | 畫面和規則對不上，玩家不信任遊戲 | 建築占地、導航與地形共用同一份資料，做交叉檢查 | [building_footprint_authority](../../tests/integration/building_footprint_authority_test.gd)、[terrain_navigation_blocker](../../tests/ui/terrain_navigation_blocker_test.gd) |
| 介面無法操作（遮擋、超出畫面、點不到） | 玩家卡關 | 多解析度幾何檢查、44px 點擊目標、彈窗點擊穿透回歸 | [multi_resolution_ui_acceptance](../../tests/ui/multi_resolution_ui_acceptance_test.gd)、[modal_click_through](../../tests/ui/modal_click_through_regression_test.gd) |
| 翻譯錯誤 | 文字缺漏、格式字元錯位 | 五語系掃描、切換語言後狀態保留 | [localization](../../tests/integration/localization_test.gd)、[locale_switch_state_preservation](../../tests/integration/locale_switch_state_preservation_test.gd) |
| 長時間遊玩崩潰或洩漏 | 測試者流失 | 多種子長時間模擬；每項測試都檢查記憶體洩漏 | [multiseed_long_soak](../../tests/integration/multiseed_long_soak_test.gd)、[測試執行器](../../tools/run_assertion_matrix.ps1) |
| 交付錯誤的封裝 | 測試者拿到缺檔或混入內部檔案的版本 | 封裝清單檢查、SHA-256、Windows／Linux 成品啟動測試 | [CI release-exports](../../.github/workflows/godot-ci.yml)、[PCK 清單檢查](../../tools/inspect_pck_inventory.ps1) |

## 2. 測試層級

| 層級 | 數量（在測試清單內） | 位置 |
| --- | --- | --- |
| 單元 | 17 | [`tests/unit`](../../tests/unit) |
| 整合 | 41 | [`tests/integration`](../../tests/integration) |
| UI 與視覺契約 | 39 | [`tests/ui`](../../tests/ui) |
| 專項 QA（強制終止、程序退出） | 由專用執行器執行 | [`tests/qa`](../../tests/qa) |
| 人工驗收腳本（產生截圖供人工判讀；部分已失效，見[技術債 TD-06](../development/TECH_DEBT.md)） | 14 | [`tests/manual`](../../tests/manual) |

唯一的測試清單是 [`tests/assertion_matrix.json`](../../tests/assertion_matrix.json)（97 項）。每一項在獨立的使用者資料夾執行，並同時檢查：結束碼、成功標記、執行期錯誤、記憶體洩漏。

## 3. 不測什麼，以及為什麼

| 項目 | 原因 | 替代做法 |
| --- | --- | --- |
| 美術好不好看 | 主觀，無法自動判定 | 自動產生 33 個畫面的截圖，由人工判讀 |
| 20 萬人口極限 | 已量測但未達標，不列為發佈門檻 | 記錄為 P3 已知問題 |
| macOS | 沒有匯出目標 | 不宣稱支援 |
| 五語系人工點擊驗收 | 尚未完成 | 記錄為 P1 已知問題，未驗證語系標示為實驗性 |

## 4. 進入與退出標準

- **合併到 main**：測試清單全部通過、強制終止存檔測試 5/5、CI 綠燈。
- **發佈測試封裝**：再加上 Windows／Linux 匯出成品啟動測試、封裝清單與 SHA-256 檢查、[已知問題](../release/KNOWN_ISSUES_0.1.0-alpha.3.md)更新。

## 5. 最近一次結果

| 日期 | 環境 | 結果 |
| --- | --- | --- |
| 2026-10-01 | Linux、Godot 4.7、本機 | 97/97 通過，0 個執行期錯誤，0 個洩漏；33 畫面 UI 截圖驗收通過 |
| 2026-09-20 | GitHub Actions（Windows + Ubuntu） | [全部工作通過](https://github.com/xichengyu810067-lab/MayorSimulator/actions/runs/35489395672) |

執行方式見 [README](../../README.md#執行自動化測試)。
