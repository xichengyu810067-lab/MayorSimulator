# Internal Alpha Tester Guide — 0.1.0-alpha.1

## 安裝與完整性

1. 僅從授權內部管道取得 Windows ZIP。
2. 比對 ZIP SHA-256：`ac39d9d82fdc297f8083e7dbfb90e6ecccf4b113e7e1e1bfc0d1ec2abb1cb139`。
3. 解壓縮完整 ZIP，保留 `MayorSimulator.exe`、`MayorSimulator.pck` 與三份隨附文件於同一資料夾。
4. 執行 `MayorSimulator.exe`；此為未簽章內部測試檔，請勿對外轉傳。

## 最低測試流程

1. 在開始畫面建立新城市，確認可進入主地圖。
2. 開啟設定、切換語言，確認文字更新且仍可返回主畫面。
3. 開啟市政頁面、建築與資料頁，測試滑動、按鈕與關閉流程。
4. 放置或檢視一項建築、檢查地形整平與 NPC 可視移動／點擊互動。
5. 進行一項市政決策，觀察狀態／報表更新。
6. 結束遊戲後重新啟動並選 Continue，確認存檔可讀。

## 回報格式

回報請附上：Windows 版本、螢幕解析度與 DPI、語言、重現步驟、預期／實際結果、截圖或 log。不要附上私人存檔內容。

## 存檔安全

完全結束遊戲後才備份 `%APPDATA%\Godot\app_userdata\Mayor Simulator MVP\mayor_simulator\`。不要在遊戲運行時修改 `autosave.json`、`.bak`、`.tmp` 或 `.recovery.tmp`。
