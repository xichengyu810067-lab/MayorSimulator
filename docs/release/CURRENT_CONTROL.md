# Mayor Simulator 現行中控指標

這份紀錄是目前專案控制權的唯一 repo 內指標；它不自行宣告遠端 CI、GitHub Pre-release 或公開發行完成。

- 現行中控 task：`019fc87e-d138-7010-a95c-29ca1fb678bf`（《城諾之音》Alpha 發布接管）
- 捕獲時狀態：`active`（本機 Internal Alpha RC 已驗證；未執行遠端 CI、GitHub Pre-release 或公開發行）
- 目前產品階段：MVP Alpha
- 目前版本：`0.1.0-alpha.1`
- 後續通道：Alpha → Beta → Pre-release → Release
- 權威工作區：`C:\Users\USER\遊戲\MayorSimulator-Rebuild-20260805\30_core`
- Release candidate branch：`main`
- Base commit：`4818b9e2bf23a97b33b98432858f7228bee14334`
- SDK gitlink：`956f0414b6cd42dc8b7a648e3ce942d7e061430a`（SDK 1.2.0 SemVer release contract）
- 產品版本唯一權威來源：根目錄 `VERSION`；目前為 `0.1.0-alpha.1`。
- Tag 契約：`v<SEMVER>`；本次目標為 `v0.1.0-alpha.1`。
- Windows 四段式 metadata：`MAJOR.MINOR.PATCH.0`；本次為 `0.1.0.0`，不再用日期當產品版本。

`專案移交_2026-08-02/GOAL_CURRENT.*` 與 `PACKAGE_CONTENT_MANIFEST.json` 是 2026-08-02 凌晨的歷史移交快照，仍指向舊 task、舊路徑與 `paused` 狀態，不是 live control evidence，也不得用來覆蓋現在的 UI 驗收要求。

本次 2026-08-10 本機 RC 已通過：

- fresh runtime assertion matrix 67/67，67/67 product-clean、失敗 0、環境警告測項 0。
- OS-kill save QA 5/5，173 個 semantic checks、5 次強制終止，全部程序停止。
- canonical UI 驗收通過：native root 4/4、offscreen evidence 33/33、產品 diagnostics 0、來源指紋執行前後一致。
- Native 是真正 Windows root viewport：視窗／capture `2880×1800`、logical `1280×800`、root backing `6480×4050`、DPI 192。
- release acceptance 已完成 Godot 匯入、Windows/Linux export、Windows smoke、封裝及 source fingerprint 一致；權威 evidence 為 `.tmp/alpha-release-20260810/release-acceptance-retry/release-evidence.json`。

公開 release 仍被 LICENSE/COPYING、88 項分發權利、city-map background source rights 與 train-station provenance 阻擋；這些是公開散布治理阻擋，不是已知 runtime 缺陷。根目錄 canonical `RELEASE_README.txt` 已存在，Windows／Linux CI staging 會將它連同第三方聲明納入封裝。

本次沒有建立 GitHub Pre-release、tag、push 或公開上傳。若日後另獲授權，遠端 CI、Linux 實機 smoke 與私有 Pre-release 資產仍須各自取得新鮮證據；本機 RC 不替代這些閘門。

2026-08-03 的 66/66、舊 task 與其完成聲明為歷史快照，不得覆蓋本次 current evidence。
