Mayor Simulator MVP Alpha 0.1.0-alpha.2 - INTERNAL-ONLY 測試包說明

此 Windows x64 包僅限經授權的內部測試；不得轉傳、公開上傳、販售或宣稱為公開版本。
公開散布為 NO-GO：專案權利授權、city-map background 的散布權利、train-station 的來源與散布權利均未閉環。
使用前請閱讀同包的 RELEASE_NOTES、KNOWN_ISSUES、TESTER_README 與 THIRD_PARTY_NOTICES。
====================================

版本定位
--------
本包是 Internal Alpha（內部測試版），不是已完成公開發行驗收的正式版。
目前 Windows 執行檔與封裝檔均未簽章。

啟動方式
--------
Windows：解壓縮完整 ZIP 後，執行 MayorSimulator.exe。請勿只複製 EXE；
MayorSimulator.pck 與本文件、第三方聲明必須保留在同一資料夾。

Linux：解壓縮完整 tar.gz 後，在終端機進入該資料夾並執行：
  chmod +x MayorSimulator.x86_64
  ./MayorSimulator.x86_64

存檔與備份
----------
遊戲資料位於 Godot 的 user data 目錄下，專案資料夾名稱為「Mayor Simulator MVP」，
主要存檔位於其 mayor_simulator 子目錄。Windows 通常位於：
  %APPDATA%\Godot\app_userdata\Mayor Simulator MVP\mayor_simulator\
Linux 通常位於：
  ~/.local/share/godot/app_userdata/Mayor Simulator MVP/mayor_simulator/

原子存檔流程會保留 .bak 備份。遊戲執行時請勿手動修改、取代或同步存檔、.bak、
.tmp 或 .recovery.tmp；需要備份時，請先完全結束遊戲，再複製整個 mayor_simulator 資料夾。

授權與散布限制
--------------
Godot 與第三方元件聲明位於 THIRD_PARTY_NOTICES.md 與 GODOT_COPYRIGHT.txt。
目前背景素材的公開散布權利證明，以及專案自身 LICENSE，均尚未閉環。
因此本包目前不得公開散布、販售或宣稱為正式發行版；僅限授權的內部驗收使用。
