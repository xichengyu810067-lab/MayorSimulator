# 專案檔案分類結果（依既有子資料夾）

這份分類報告用現有資料夾主題整理目前檔案，不新增新目錄、不改變既有用途。

## 根目錄（保留在根目錄）

- `project.godot`
- `export_presets.cfg`

## artifacts（639 檔）

- `logs/`：327（parser/runtime/tests/ui/full-regression/settings-toggle/localization-blocker 等）
- `screenshots/`：308（ui-tests / gui-playtest / ui-visualization / manual）
- `playtests/`：7（playtest 流程輸出資料）
- `visual-qa/`：2（視覺校正參考圖）

## assets（96 檔）

- `archives/`：4（封存壓縮包）
- `images/`：92（world / reference / ui 圖片與 `.import`）

## backups（1 檔）

- `mayor-simulator-pre-organization-20260722.zip`（整理前全量備份）

## data（27 檔）

- `catalogs/`：6（`buildings.gd`、`policies.gd`、`content_registry.gd`）
- `schemas/`：12（各種資料欄位定義）
- `databases/`：2（下議院/司法監察主資料 JSON）
- `localization/`：7（多語系資料）

## docs（21 檔）

- `design/`：3（美術/設計/大更動紀錄）
- `development/`：3（開發參考與 notes）
- `project-organization/`：11（整理、測試、報告）
- `systems/`：3（治理制度說明）
- `README.md`：1（專案入口）

## scenes（1 檔）

- `Main.tscn`：1（主場景）

## scripts（46 檔）

- `app/`：6（主流程與跨模組協調）
- `core/`：18（城市核心/存檔/模擬）
- `systems/`：14（城建、治理、人口共用系統）
- `world/`：6（世界畫面與 NPC 繪製）
- `rendering/`：2（著色器）

## systems（6 檔）

- `governance/`：6（自治模組：下議院、司法與監察）

## tests（49 檔）

- `unit/`：8（單元測試）
- `integration/`：18（整合測試）
- `ui/`：23（UI 擷取、回歸、互動測試）

## tools（6 檔）

- `localization/`：1（本地化產生工具）
- `tools 根目錄`：5（JSON 清理、截圖 script）

## ui（20 檔）

- `shell/`：16（主流程與通用面板）
- `governance/`：2（司法監察互動面板）
- `effects/`：2（天氣視覺層）

## ux（3 檔）

- `specifications/`：3（版面、視覺、視覺化規格）

## 結論

在不改變既有子資料夾架構的前提下，檔案已經符合主題化歸類；目前沒有找到需要搬移到其他既有目錄的正式來源檔案。  
若你要，我可以再做「第二階段」：把 `artifacts/` 裡依功能再做一次子分類命名（例如 `artifacts/screenshots/` 與 `artifacts/logs/` 已內建子分類後再加上時間切片資料夾彙總），但這是純結構補強，不會影響遊戲執行。
