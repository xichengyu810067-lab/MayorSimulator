# 文件導覽

## 先看這些

| 想知道 | 文件 |
| --- | --- |
| 這個專案在做什麼、為什麼做 | [產品需求 PRD](product/PRD.md) |
| 怎麼做出來的、AI 與我怎麼分工 | [開發方式](how-it-was-built.md) |
| 系統怎麼組成、資料怎麼存 | [系統架構](architecture.md) |
| 怎麼測試、為什麼這樣測 | [測試策略](qa/TEST_STRATEGY.md) |
| 做錯了什麼、學到什麼 | [專案歷程與反思](development/PROJECT_HISTORY.md) |
| 程式碼還有哪些問題 | [技術債清單](development/TECH_DEBT.md) |

## 發佈與品質

- [開發、測試與發佈流程（進階）](release/RELEASE_PROCESS.md)
- [已知問題 0.1.0-alpha.3](release/KNOWN_ISSUES_0.1.0-alpha.3.md)、[發佈說明](release/RELEASE_NOTES_0.1.0-alpha.3.md)、[測試者說明](release/TESTER_README_0.1.0-alpha.3.md)
- [公開發佈阻塞](release/PUBLIC_RELEASE_BLOCKERS.md)、[素材來源紀錄](release/ASSET_PROVENANCE.md)
- [Bug 回報範本](release/BUG_REPORT_TEMPLATE.md)
- [版本規則](../VERSIONING.md)

## 設計與系統

- [原創城市模擬設計契約](design/city_simulation_originality_contract.md)（模組職責與原創性邊界）
- [美術風格指南](design/art_direction_style_guide.md)、[背景重製指引](design/background_reference_guide.md)
- [下議院](systems/governance/lower_council.md)、[司法與監察](systems/governance/justice_oversight.md)
- [延期待辦](development/deferred_todos.md)、[Godot 開發筆記](development/godot_mvp_notes.md)

## 歷史紀錄

`acceptance/`、`project-organization/`、`marketing/` 保存各階段的驗收、稽核與行銷草稿。它們記錄的是**當時**的狀態，數字可能已經過時；目前狀態以上面的文件為準。

## 目錄邊界

- `scripts/systems/` 是主遊戲共用的領域系統；`systems/` 是有自己資料與測試的獨立模組（下議院、司法與監察）。
- `ui/` 放玩家看得到的畫面程式；`ux/` 放體驗與美術規格，不放程式。
- `assets/` 放遊戲素材；`artifacts/`、`.tmp/`、`builds/` 是本機產生的輸出，不納入版控。
- `.uid` 與 `.import` 是 Godot 的配套檔，搬移來源檔時必須一起搬。
