《城諾之音》 / CivicTale: Voice of Promise 0.1.0-alpha.3

內部 Alpha 測試包說明
====================

本包僅限專案擁有者授權的內部測試，不得轉傳、公開上傳、販售或宣稱為正式發布。
它不是公開版本，也尚未完成公開散布所需的權利與驗收。

啟動方式
--------
完整解壓縮對應平台封裝，保留執行檔、`MayorSimulator.pck` 與所有隨附文件；不要只複製執行檔。

Windows：執行 `MayorSimulator.exe`。

Linux：在解壓目錄執行：

  chmod +x MayorSimulator.x86_64
  ./MayorSimulator.x86_64

存檔與備份
----------
遊戲在 Godot 使用者資料根的 `user://mayor_simulator/` 保存本機進度、設定與備份／暫存檔；
實際作業系統路徑依應用程式名稱與平台而異。請先完全結束遊戲，再複製整個
`mayor_simulator` 資料夾作備份。遊戲執行時請勿手動替換、同步或刪除存檔、`.bak`、`.tmp`
或復原暫存檔。

較舊且受支援的存檔可能在較新版本中遷移；未知或較新的資料會被拒絕。更新前仍應備份，
且新版本寫出的存檔不保證能由較舊版本讀取。

限制與隨附文件
--------------
目前執行檔與封裝未簽章。自動化檢查不能取代新局、繼續遊戲、NPC、片頭、多尺寸、
滑鼠操作與實際裝置的人工驗收。

請一併閱讀 `LICENSE.txt`、`TERMS_OF_USE.md`、`PRIVACY_NOTICE.md`、
`THIRD_PARTY_NOTICES.md` 與 `GODOT_COPYRIGHT.txt`。這些文件與執行檔、PCK 必須保留在
同一封裝目錄。遊戲內容與結果是模擬，不是現實政策、財務、法律或其他專業建議。
