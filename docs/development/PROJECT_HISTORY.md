# 專案歷程與反思

## 時間軸

| 日期 | 事件 | 連結 |
| --- | --- | --- |
| 2026-07 | 在 Git 版控之外完成原型與多輪整理、稽核 | [7/26 全面稽核](../project-organization/MAYOR_SIMULATOR_FULL_AUDIT_2026-07-26.md) |
| 2026-08-01 | 建立 Git 版控：一次匯入既有專案（1,264 個檔案）作為基線 | tag `baseline-2026-08-01` |
| 2026-08-02 | MVP Alpha `0.1.0-alpha.1`：66 項自動化測試、強制終止存檔測試、Windows／Linux 封裝 | [PR #1](https://github.com/xichengyu810067-lab/MayorSimulator/pull/1)、[Release](https://github.com/xichengyu810067-lab/MayorSimulator/releases/tag/v0.1.0-alpha.1) |
| 2026-08-03 | 版本號改採 SemVer | [PR #2](https://github.com/xichengyu810067-lab/MayorSimulator/pull/2) |
| 2026-08-10 | `alpha.2`、`alpha.3` 候選版：存檔單一來源、人口容量量測、Linux CI（未合併；commit 保存在 [PR #6](https://github.com/xichengyu810067-lab/MayorSimulator/pull/6) 的歷史中） | 分支 `codex/linux-ci-alpha3-20260811` |
| 2026-08-05 ～ 09-10 | 主要在另一個重建工作區開發（原工作區的 Git 損壞），只有部分分支推回本儲存庫 | 見下一節 |
| 2026-09-12 | 把重建成果整合回本儲存庫：建築占地、交通工程、存檔保護、延後載入的市政介面 | [PR #7](https://github.com/xichengyu810067-lab/MayorSimulator/pull/7) |
| 2026-09-20 | 開場動畫、教學說明、封裝驗證；CI 全部通過 | [PR #9](https://github.com/xichengyu810067-lab/MayorSimulator/pull/9) |
| 2026-10-01 | 作品集整理：README、架構與測試文件、清理殘留檔案、財政介面重構 | [PR 列表](https://github.com/xichengyu810067-lab/MayorSimulator/pulls?q=is%3Apr) |

## 為什麼 Git 歷史有兩個起點？

`git rev-list --max-parents=0 HEAD` 會列出兩個 root commit：

1. `e0fdf85`（2026-08-01）：最初匯入的基線。
2. `08c29c5`（2026-09-11）：重建工作區的**完整快照**（1,510 個檔案）。它的 commit 訊息寫成 `feat(transport): classify completed corridor reuse`，這是錯的：它其實是「匯入整個專案快照」。

[PR #7](https://github.com/xichengyu810067-lab/MayorSimulator/pull/7) 把這條沒有共同祖先的歷史合併進 main，合併結果等於用快照取代原本的 main。因此：

- `git blame` 會把大部分舊程式碼算在 `08c29c5` 上，看不出原本是哪一次修改。
- 2026-08-12 到 09-10 的細部開發紀錄不在這個儲存庫裡。

**學到的事**：搬移歷史時，應該用 `git subtree`、`git filter-repo` 保留原始 commit；至少也要用清楚的訊息標示「匯入快照」，並在 PR 說明裡寫出來。

## 失誤與修正

| 失誤 | 影響 | 修正 |
| --- | --- | --- |
| [PR #7](https://github.com/xichengyu810067-lab/MayorSimulator/pull/7) 在 CI 失敗時合併（CI 在取得私有 SDK 時失敗，測試沒有執行） | main 的 CI 紅了 8 天，PR 說明只有本機測試結果 | 合併前必須等 CI 綠燈；建議開啟分支保護 |
| 文件很多但互相矛盾（公開 vs 僅限內部、版本號不一致、產品名稱不一致） | 讀者不知道該相信哪一份 | 2026-10 統一授權說明與產品名稱，過時的發佈流程移到[發佈流程](../release/RELEASE_PROCESS.md) |
| AI 傾向「加東西」不「刪東西」 | 臨時腳本、只會印字的假測試、本機路徑留在儲存庫裡；`main.gd` 長到 9,700 行 | 2026-10 刪除殘留檔案；結構問題列入[技術債清單](TECH_DEBT.md) |
| 用 AI 稽核分數（「90/100」）當目標 | 在證據流程上投入過多，可讀性與可維護性不足 | 目標改成「讓別人看得懂、改得動」 |

## 這個專案帶給我的改變

- **從「會寫功能」到「會定義完成」**：我學會先寫驗收標準與測試清單，再讓 AI 實作（[測試策略](../qa/TEST_STRATEGY.md)）。
- **完整走過一次產品發佈**：版本規則、封裝、已知問題分級、授權與素材權利（[發佈文件](../release/)）。
- **知道 AI 的邊界**：AI 會宣稱完成、會產生重複程式碼與過時文件；需要測試、CI 與人工審查一起把關（[開發方式](../how-it-was-built.md)）。
- **學會承認並記錄錯誤**：上面的失誤表本身就是 QA 與 PM 的日常工作。
