# Mayor Simulator 現行中控指標

這份紀錄是目前專案控制權的唯一 repo 內指標；它不自行宣告 goal 完成。

- 現行中控 task：`019fa248-259e-7040-a887-cc73da543621`（Mayor Simulator｜專案中控中心）
- 捕獲時狀態：`complete`（`update_goal` 於 2026-08-03 00:34:13 +08:00 成功）
- 目前產品階段：MVP Alpha
- 目前版本：`0.1.0-alpha.1`
- 後續通道：Alpha → Beta → Pre-release → Release
- 權威工作區：`C:\Users\XCJ\遊戲\MayorSimulator_Authoritative_2026-08-02`
- Branch：`recovery/validated-handoff-20260802`
- Base commit：`ecec3e4f9cb592ee43f198f51bf9d1c2696d0ac3`
- SDK gitlink：`619a50a6af4573f4f51d90d0c270e34890c25b39`
- Dirty worktree：目前具權威性的未提交 WIP；不能只用 base commit 代表現況。

`專案移交_2026-08-02/GOAL_CURRENT.*` 與 `PACKAGE_CONTENT_MANIFEST.json` 是 2026-08-02 凌晨的歷史移交快照，仍指向舊 task、舊路徑與 `paused` 狀態，不是 live control evidence，也不得用來覆蓋現在的 UI 驗收要求。

目前已通過：

- 凍結後 fresh runtime assertion matrix 66/66，66/66 product-clean、失敗 0、環境警告測項 0。
- 凍結後 OS-kill save QA 5/5，173 個 semantic checks、5 次強制終止，全部程序停止。
- 兩次獨立 canonical UI 驗收皆通過：native root 4/4、offscreen evidence 33/33、產品 diagnostics 0、來源指紋執行前後一致。
- Native 是真正 Windows root viewport：視窗／capture `1656×843`、logical `1414×720`、root backing `1939×987`。
- Offscreen 高解析證據是 `2880×1800`、logical `1280×800`；它只作證據，不冒充 native-window 解析度。
- T3 產品凍結後 fresh 可視終驗 PASS：10×10／縮放、六車種、道路／軌道／跑道、NPC 避障、整地前置、多幀動畫、民情 lifecycle、healthcare、音效持久化、Save／Continue 與 Godot 零殘留均通過。
- SDK、ledger、marker 與 read-only release guard 終審。

技術驗收已封口：

- 本中控 task 已由 `update_goal` 正式標記為 `complete`。
- T0 最終 SDK／移交守門與 T2 Goal #8 可追溯性複核均已完成；Goal #8 runtime／visible acceptance gap 為 0。

公開 release 仍被 LICENSE/COPYING、88 項分發權利、city-map background source rights、train-station provenance，以及 Windows／Linux staging 各缺 `RELEASE_README.txt`（4/5 檔）阻擋；這些是發行治理阻擋，不是已知 runtime 缺陷。

因此本次只封存並提交 MVP Alpha `0.1.0-alpha.1` 的 Draft PR；在上述治理門檻解除前，不建立 GitHub Release，也不把版本提升為 Beta、Pre-release 或 Release。

真正完成狀態只由本中控 task 的 `update_goal` 成功結果決定。
