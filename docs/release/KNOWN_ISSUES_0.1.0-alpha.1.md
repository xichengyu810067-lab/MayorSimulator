# Known Issues — 0.1.0-alpha.1 RC

| 優先級 | 狀態 | 項目與處置 |
| --- | --- | --- |
| P0（公開發行） | 未解 | 專案根 LICENSE/COPYING、背景素材公開散布權利、train-station provenance 未閉環。公開發行 NO-GO；不阻擋授權內部 Alpha 測試。 |
| P1 | 已記錄、未重現 | 第一輪完整 release acceptance 的 Windows smoke 在結束時報告 2 個 ObjectDB leaks；同一 RC 的新鮮 smoke 診斷與第二輪完整 acceptance 均 product-clean。保留失敗 logs，不以白名單忽略。後續每次 RC 必須重跑 smoke。 |
| P1 | 未閉環 | 五語 assertion 已通過，但本輪 canonical native GUI captures 未逐語系保留人工點擊截圖；不可將它宣稱為完整手動五語視覺驗收。 |
| P2 | 未解 | Linux x64 已 export/package，未由真實 Linux runner 執行。 |
| P2 | 未解 | Windows 可執行檔與封裝未簽章。 |
| P3 | 歷史排程 | 先前 10:00 GO/NO-GO 時間閘門依中控指示已失效且記為 missed；本文件僅依實際完成的證據判定。 |

首次失敗證據：`.tmp/alpha-release-20260810/release-acceptance/logs/commands/windows_smoke.stderr.log`。

通過證據：`.tmp/alpha-release-20260810/release-acceptance-retry/release-evidence.json`。
