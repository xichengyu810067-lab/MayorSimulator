# Mayor Simulator 版本治理

## 獨立版本層級

| 層級 | 格式／來源 | 用途 |
| --- | --- | --- |
| Git | commit、branch、annotated tag | 可追溯的原始碼歷史 |
| SDK | SemVer，例如 `v1.1.0` | 開發、驗證與發布工具的相容性 |
| 遊戲發布 | `vYYYY.MM.DD` | 對外發布與 GitHub Actions 觸發 |
| Windows metadata | `YYYY.M.D.0` | EXE 檔案與產品版本 |
| 遊戲內容 | `CONTENT_VERSION` | 存檔內容相容性 |
| 儲存資料 | 各資料結構的整數 schema | 可讀取範圍與明確遷移 |

## 規則

1. 發布版變更不得自行改變內容版本或任何存檔 schema。
2. schema 變更必須提供明確 migration 或拒絕路徑，並測試最舊支援資料、每個升級邊界、現版 round-trip 與未知未來版本。
3. SDK 相容性由 `.mayor-sdk.json` 宣告；每次更新 SDK submodule，都要驗證 `sdk/manifest.json` 的版本落在允許範圍內。
4. 只有完成測試與發布證據後，才建立 annotated release tag。
5. 私有 SDK submodule 的 GitHub Actions 需要 repository secret `SDK_REPOSITORY_READ_TOKEN`，權限限於讀取 `MayorSimulator-SDK`。
