# Mayor Simulator MVP Alpha 0.1.0-alpha.1 — 本機 RC

本次為授權內部測試使用的 Windows x64 Release Candidate；未建立 GitHub Release、未 push、未公開上傳。

## 本次已驗證

- 單次 canonical release acceptance：67/67 assertion product-clean、OS-kill save 5/5（173 semantic checks）、Godot 匯入、Windows/Linux export、Windows 匯出檔 smoke、封裝與來源指紋一致。
- Windows 原生 GUI：2880×1800、DPI 192、4 張 native captures；另有 33 張高解析 UI evidence，產品 diagnostics 為 0。
- RC 證據：`.tmp/alpha-release-20260810/release-acceptance-retry/release-evidence.json`。

## 產物

- Windows x64 ZIP：`MayorSimulator-Windows-x86_64-0.1.0-alpha.1.zip`，59,745,101 bytes，SHA-256 `ac39d9d82fdc297f8083e7dbfb90e6ecccf4b113e7e1e1bfc0d1ec2abb1cb139`。
- Linux x64 tar.gz 已輸出與封裝；未在 Windows 主機上執行 Linux smoke。
- 完整雜湊請見封裝內或 evidence 同目錄的 `SHA256SUMS`。

## 版本契約

- 產品版本：`0.1.0-alpha.1`（`VERSION`）。
- 現有回滾點：`v0.1.0-alpha.1` / `4818b9e2bf23a97b33b98432858f7228bee14334`。
- Windows metadata：`0.1.0.0`。

## 散布限制

本 RC 為 Internal Alpha。缺少專案根 LICENSE/COPYING、背景素材公開散布權利與 train-station provenance；因此公開散布、販售與正式 Release 均為 NO-GO。
