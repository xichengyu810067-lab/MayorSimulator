# Mayor Simulator 版本治理

## 獨立版本層級

| 層級 | 格式／來源 | 用途 |
| --- | --- | --- |
| Git | commit、branch、annotated tag | 可追溯的原始碼歷史 |
| SDK | SemVer，例如 `v1.1.0` | 開發、驗證與發布工具的相容性 |
| 遊戲發布 | SemVer；例如 `0.1.0-alpha.1`，權威來源為 `VERSION` | MVP Alpha、Beta、Pre-release 與 Release 的產品版本 |
| Git tag | `v<SEMVER>`；例如 `v0.1.0-alpha.1` | GitHub Actions release 觸發與可追溯發布點 |
| Windows metadata | `MAJOR.MINOR.PATCH.0`；例如 `0.1.0.0` | EXE 四段式檔案與產品版本相容欄位 |
| 遊戲內容 | `CONTENT_VERSION` | 存檔內容相容性 |
| 儲存資料 | 各資料結構的整數 schema | 可讀取範圍與明確遷移 |

## 規則

1. 發布版變更不得自行改變內容版本或任何存檔 schema。
2. schema 變更必須提供明確 migration 或拒絕路徑，並測試最舊支援資料、每個升級邊界、現版 round-trip 與未知未來版本。
3. SDK 相容性由 `.mayor-sdk.json` 宣告；每次更新 SDK submodule，都要驗證 `sdk/manifest.json` 的版本落在允許範圍內。
4. 只有完成測試與發布證據後，才建立 annotated release tag。
5. 私有 SDK submodule 的 GitHub Actions 需要 repository secret `SDK_REPOSITORY_READ_TOKEN`，權限限於讀取 `MayorSimulator-SDK`。
6. `data/version_updates.json` 的日期是內容更新紀錄，不是產品版本；不得再由日期推導 tag。
7. Alpha、Beta 與 release candidate 使用 SemVer prerelease，例如 `0.1.0-alpha.1`、`0.1.0-beta.1`、`0.1.0-rc.1`；正式版移除 prerelease 後綴。
