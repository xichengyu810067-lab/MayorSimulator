# 專案整理遷移對照表

本文件記錄 2026-07-22 的目錄整理。原始狀態已備份於
`backups/mayor-simulator-pre-organization-20260722.zip`，可在搬移或路徑更新失敗時回復。

## 分類原則

| 類別 | 目標位置 | 說明 |
| --- | --- | --- |
| 資料庫 | `data/databases/<系統>/` | 僅放可被載入的 JSON 主資料 |
| 資料目錄與結構 | `data/catalogs/`、`data/schemas/` | 遊戲內容清單、平衡參數與資料結構 |
| UI | `ui/<系統>/` | 可見介面、視窗與面板程式 |
| UX | `ux/specifications/` | 介面行為、美術與體驗規格 |
| 圖片 | `assets/images/<用途>/` | 執行時背景、概念圖與參考圖 |
| 遊戲系統 | `scripts/systems/<系統>/`、`systems/<系統>/` | 共用系統程式與完整自治模組 |
| 測試 | `tests/<層級>/` | 單元、整合與 UI 擷取測試 |
| 產物 | `artifacts/` | 測試紀錄與畫面擷取，不作為遊戲來源 |
| 文件 | `docs/<主題>/` | 設計、開發、系統與專案管理文件 |

## 主要搬移對照

| 原位置 | 新位置 |
| --- | --- |
| `幻想遊戲地圖風景.png` | `assets/images/world/backgrounds/city-map-background.png` |
| 根目錄四張 `ChatGPT Image ...png` | `assets/images/world/concepts/city-layout-concept-01..04.png` |
| `MayorSimulator_BackgroundReference_Pack/.../images/` | `assets/images/reference/background-style/` |
| `screenshots/`、`tests/*.png` | `artifacts/screenshots/manual/`、`artifacts/screenshots/ui-tests/` |
| 根目錄 `*.log` | `artifacts/logs/parser|runtime|tests|ui/` |
| `data/buildings.gd`、`policies.gd`、`content_registry.gd` | `data/catalogs/` |
| `data/definitions/` | `data/schemas/` |
| `下議院資料/data/councilors.json` | `data/databases/governance/lower-council/councilors.json` |
| `司法系統資料/data/committee_members.json` | `data/databases/governance/justice-oversight/committee_members.json` |
| `下議院資料/scripts/` | `systems/governance/lower-council/` |
| `司法系統資料/scripts/` | `systems/governance/justice-oversight/` |
| `scripts/population/` | `scripts/systems/population/` |
| `scripts/systems/construction_system.gd`、`durability_system.gd` | `scripts/systems/city/` |
| `scripts/systems/governance_system.gd` | `scripts/systems/governance/` |
| `scripts/main.gd`、`vertical_slice_coordinator.gd` | `scripts/app/` |
| `scripts/city_*`、`npc_actor.gd` | `scripts/world/` |
| `scripts/ui/`、司法介面 | `ui/shell/`、`ui/governance/` |
| 原模組測試與根 `tests/*.gd` | `tests/unit/`、`tests/integration/`、`tests/ui/` |
| `markdown/`、散落的 Markdown | `docs/development/`、`docs/design/`、`ux/specifications/` |

## 不搬移項目

| 位置 | 理由 |
| --- | --- |
| `project.godot` | Godot 專案根設定必須留在根目錄 |
| `export_presets.cfg` | Godot 匯出設定慣例位於根目錄 |
| `scenes/Main.tscn` | 已正確歸入場景目錄 |
| `.godot/` | Godot 自動產生的匯入快取 |
| `.agents/`、`.codex/` | 工具與工作區中繼資料 |
| `backups/` | 無 Git 歷史時的本次整理安全回復點 |

## 驗證門檻

整理完成前必須同時符合：所有 `res://` 路徑存在、JSON 可解析、Godot 無解析錯誤、
司法／下議院／人口／系統／垂直切片／主畫面整合測試全部通過，且根目錄不再散落圖片與紀錄檔。

## 完成狀態

2026-07-22 已完成全部搬移與路徑更新。上述門檻全部通過，詳細數據見
[專案整理驗證報告](VALIDATION_REPORT.md)。
