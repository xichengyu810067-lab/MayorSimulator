# 開發、測試與發佈流程（進階）

這份文件是原本 README 的完整版，給需要自己匯出、封裝或產生發佈證據的人。一般的安裝、執行與測試請看 [README](../../README.md)。

專案以 Godot 4.7 與 GDScript 開發，主場景是 `res://scenes/Main.tscn`，預設使用 Mobile renderer 與 Vulkan driver；遇到 Vulkan 或驅動問題時，可改用 Compatibility／OpenGL 3。目前是內部 Alpha，不是公開正式版；測試通過不代表素材授權或平台簽章已完成（見[公開發佈阻塞](PUBLIC_RELEASE_BLOCKERS.md)）。

## 環境需求

- Godot `4.7.stable` Standard；本機最後驗證版本為 `4.7.stable.official.5b4e0cb0f`。
- 從原始碼匯出時，需另安裝同版本的 Godot 4.7 Export Templates。
- 執行 release 封裝腳本需 PowerShell 7.4 以上。
- 專案沒有 C#、GDExtension、原生 DLL、Node.js、外部資料庫或後端服務等 runtime 依賴。

## Mayor Simulator SDK（私有，選用）

`sdk/` 是私有 Git 子模組，只有專案擁有者與 CI 能取得；玩遊戲與跑測試都不需要它。

`sdk/manifest.json` 是技術棧、建置入口與品質契約的機器可讀單一來源；`sdk/mayor_sdk.py` 只負責
檢查與調度，實際測試、截圖、OS-kill 與 release 判定仍由既有 PowerShell runner 負責。先執行：

```powershell
& .\sdk\mayor-sdk.ps1 doctor
& .\sdk\mayor-sdk.ps1 stack
& .\sdk\mayor-sdk.ps1 tests
& .\sdk\mayor-sdk.ps1 install-skill
```

執行完整斷言矩陣時可省略本機已知的 Godot 路徑，或明確傳入：

```powershell
& .\sdk\mayor-sdk.ps1 verify `
    --godot 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
```

`ui-qa`、`save-qa` 與 `build` 都沿用不可覆寫、隔離 app-data 與單次證據規則。完整 API、常用範例及
錯誤排解的 canonical source 位於 `skills/mayor-simulator-sdk`；`.codex/skills` 只作為本機安裝副本。
CI 會先驗證 SDK manifest、skill 參考與測試清單沒有漂移。

## 從原始碼啟動

在專案根目錄設定 Godot 執行檔路徑後，以預設 Mobile／Vulkan 啟動遊戲：

```powershell
$GodotExe = 'C:\path\to\Godot_v4.7-stable_win64.exe'
& $GodotExe --path . --rendering-method mobile --rendering-driver vulkan
```

若要開啟 Godot 編輯器並明確沿用相同 renderer：

```powershell
& $GodotExe --editor --path . --rendering-method mobile --rendering-driver vulkan
& .\builds\windows\MayorSimulator.exe --rendering-method mobile --rendering-driver vulkan
```

只有在 Mobile／Vulkan 無法於該機器正常啟動時，才改用下列 Compatibility／OpenGL 3 命令；參數必須成對使用：

```powershell
# Godot 編輯器
& $GodotExe --editor --path . --rendering-method gl_compatibility --rendering-driver opengl3

# 由 Godot 執行專案
& $GodotExe --path . --rendering-method gl_compatibility --rendering-driver opengl3

# 已匯出的 Windows 成品
& .\builds\windows\MayorSimulator.exe --rendering-method gl_compatibility --rendering-driver opengl3
```

需要隔離 `APPDATA`、`LOCALAPPDATA` 與 Godot `user://` 的人工遊玩時，使用固定模式 runner。每個 `ProfileName`
只能建立一次，runner 不接受額外 Godot 參數，也不會重用既有輸出：

```powershell
& .\tools\run_isolated_playtest.ps1 -RendererMode Mobile -ProfileName 'mobile-manual-01'
& .\tools\run_isolated_playtest.ps1 -RendererMode Compatibility -ProfileName 'compatibility-manual-01'
```

提交乾淨後，可用 intro CG 可見驗收確認 renderer 啟動與完整播放標記。輸出必須是
`.tmp\renderer-smoke` 下全新的目錄；失敗證據會保留，不能把 Compatibility 的 driver crash 當成通過：

```powershell
$GodotConsole = 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
& .\tools\run_renderer_smoke.ps1 -GodotExe $GodotConsole -RendererMode Mobile -OutputRoot '.\.tmp\renderer-smoke\mobile-01'
& .\tools\run_renderer_smoke.ps1 -GodotExe $GodotConsole -RendererMode Compatibility -OutputRoot '.\.tmp\renderer-smoke\compatibility-01'
```

在本機匯出後，成品會位於（`builds/` 不納入版控）：

- Windows：`builds/windows/MayorSimulator.exe`
- Linux：`builds/linux/MayorSimulator.x86_64`

這些檔案仍屬候選 staging，不等同已簽章或已跨平台驗收的公開發行包。Linux 解壓後若執行權限被外部工具移除，需先執行：

```bash
chmod +x MayorSimulator.x86_64
./MayorSimulator.x86_64
```

## 執行測試

斷言矩陣由 `tests/assertion_matrix.json` 作為唯一清單；測試數量以該 manifest 與當次 `summary.json` 為準，
不在 README 寫死容易漂移的數字。PowerShell runner 會為每一項測試隔離
`APPDATA`／`LOCALAPPDATA`，檢查 exit code、成功標記、script/runtime diagnostics、ObjectDB leak
與 resource leak：

```powershell
$GodotConsole = 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
& .\tools\run_assertion_matrix.ps1 `
    -GodotExe $GodotConsole `
    -OutputRoot '.\.tmp\assertion-matrix\manual'
```

本月 freeze 的精確通過數、執行時間與證據路徑記錄在最終審核報告與當次 `summary.json`，
不應取代未來版本的重新執行。
目前 Windows 環境仍會由 Godot 回報 `Failed to read the root certificate store`，runner 會保留原始訊息並獨立標記，
不會把它隱藏或誤列為產品錯誤。

原子存檔另有 Windows 程序猝死驗收；runner 會在五個實際寫檔階段以 `Stop-Process -Force` 終止
Godot writer，重啟後檢查 primary／backup 恢復、語意雜湊及後續存檔。輸出目錄必須尚不存在：

```powershell
& .\tools\run_save_os_kill_qa.ps1 `
    -GodotExe $GodotConsole `
    -OutputRoot '.\.tmp\save-os-kill-qa\manual'
```

這項測試證明 Windows `TerminateProcess` 等級的程序猝死恢復，不等同拔電、磁碟寫入快取遺失、
檔案系統損毀或實體磁碟故障；Linux 仍須以 `SIGKILL` 在真實 Linux runner 另行驗收。

33 個既有 UI 狀態的可見截圖驗收使用獨立、不可覆寫的輸出目錄。Runner 會逐張核對狀態與檔名、PNG magic、
2880×1800 實體尺寸、bytes、SHA-256、產品 diagnostics，以及執行前後完整來源指紋；只有 33 張全部通過才會
原子發布 `summary.json`：

```powershell
& .\tools\run_ui_capture_acceptance.ps1 `
    -GodotExe $GodotConsole `
    -OutputRoot '.\.tmp\ui-capture-acceptance\manual-run1'
```

這個流程會開啟 2880×1800 的 Godot 視窗；它是自動化視覺 traversal，不取代成品 EXE 的人工點擊與不同 Windows
DPI 比例驗收。失敗目錄保留原始 log 供診斷，但不得改名成成功證據或重用。

## Runtime 素材台帳

`docs/project-organization/RUNTIME_ASSET_LEDGER.json` 由 `tools/generate_runtime_asset_ledger.ps1` 從 canonical registries
與明確 runtime references 重建，逐項記錄實際使用素材的路徑、bytes、SHA-256、用途、provenance 證據與權利狀態。
產生器會拒絕缺檔、registry 漏項、重複路徑／內容、分類數漂移及空白必要欄位。台帳明確保留城市背景權利未解與
專案自身 `LICENSE` 尚未選定的事實；生成 provenance 不等於散布授權。

## 匯出 Windows 與 Linux staging

確認 Godot 4.7 Export Templates 已安裝後，可依 `export_presets.cfg` 匯出：

```powershell
$GodotConsole = 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
& $GodotConsole --headless --path . --import
& $GodotConsole --headless --path . --export-release 'Windows Desktop' 'builds/windows/MayorSimulator.exe'
& $GodotConsole --headless --path . --export-release 'Linux' 'builds/linux/MayorSimulator.x86_64'
Copy-Item .\RELEASE_README.txt, .\THIRD_PARTY_NOTICES.md, .\GODOT_COPYRIGHT.txt -Destination .\builds\windows\
Copy-Item .\RELEASE_README.txt, .\THIRD_PARTY_NOTICES.md, .\GODOT_COPYRIGHT.txt -Destination .\builds\linux\
```

封裝前，每個 staging 目錄都必須只有以下五個檔案：

| 平台 | 必要檔案 |
| --- | --- |
| Windows | `MayorSimulator.exe`、`MayorSimulator.pck`、`RELEASE_README.txt`、`THIRD_PARTY_NOTICES.md`、`GODOT_COPYRIGHT.txt` |
| Linux | `MayorSimulator.x86_64`、`MayorSimulator.pck`、`RELEASE_README.txt`、`THIRD_PARTY_NOTICES.md`、`GODOT_COPYRIGHT.txt` |

三份發行文件必須與專案根目錄的 canonical 版本逐位元一致。`RELEASE_README.txt` 會向收包者說明 Internal Alpha
限制、Windows／Linux 啟動方式、未簽章狀態、存檔與 `.bak` 備份，以及目前不得公開散布的原因。封裝腳本不會替
staging 補檔，也不會修改、刪除或覆寫 staging。

## 建立 release archives

先使用 dry-run；它只驗證來源、檔案 magic、法律文件 hash、輸出路徑與預定產物，不會建立目錄或檔案：

```powershell
& .\tools\package_release.ps1 `
    -Version '0.1.0-alpha.1' `
    -OutputDirectory '.\.tmp\release-output\0.1.0-alpha.1' `
    -DryRun
```

確認後移除 `-DryRun`。為避免覆寫，`OutputDirectory` 必須是尚不存在的新目錄：

```powershell
& .\tools\package_release.ps1 `
    -Version '0.1.0-alpha.1' `
    -OutputDirectory '.\.tmp\release-output\0.1.0-alpha.1'
```

預設會讀取 `builds/windows` 與 `builds/linux`。若要封裝其他已驗證 staging，可另外傳入
`-WindowsStagingDirectory` 與 `-LinuxStagingDirectory`；兩個目錄必須存在、互不包含，且不能是 reparse point。

成功後只會在指定輸出目錄建立：

- `MayorSimulator-Windows-x86_64-<Version>.zip`
- `MayorSimulator-Linux-x86_64-<Version>.tar.gz`
- `SHA256SUMS`

Linux archive 會明確把 `MayorSimulator.x86_64` 設為 `0755`，其他檔案設為 `0644`；封裝後仍會重新驗證 archive
內容、權限、SHA-256，以及 staging 前後 hash 是否一致。實際建置先在同層的執行專屬 `.partial` 目錄完成；三個產物
全部驗證通過後才把整個目錄改成正式名稱，因此不會留下看似完成、實際只含部分檔案的 release 目錄。

## 執行單次 release acceptance 並產生 evidence

`write_release_evidence.ps1` 是完整流程的唯一發行驗收入口，不接受舊摘要、舊 staging、外部 log 或呼叫者填寫的
exit code。它會在同一次執行中完成目前 manifest 的全部斷言、五階段 Windows OS-kill、乾淨 import、Windows／Linux
重新匯出、Windows 成品 smoke 與封裝，並為每個外部命令保留獨立 stdout、stderr 與真實 exit code。

`OutputRoot` 必須是專案內尚不存在的新目錄；`ExportAppDataRoot` 必須是專案外、尚不存在且與前者不相交的新目錄。
後者用來從官方 archive 逐檔串流驗證並乾淨安裝 Godot 4.7 templates，也隔離 import、export 與成品 smoke 的
`APPDATA`／`LOCALAPPDATA`：

```powershell
& .\tools\write_release_evidence.ps1 `
    -Version '0.1.0-alpha.1' `
    -GodotExe 'C:\path\to\Godot_v4.7-stable_win64_console.exe' `
    -TemplatesArchive 'C:\path\to\Godot_v4.7-stable_export_templates.tpz' `
    -ExportAppDataRoot 'C:\tmp\mayor-release-appdata-20260731-run1' `
    -OutputRoot '.\.tmp\release-acceptance\0.1.0-alpha.1-run1'
```

來源 gate 會逐位元涵蓋 `assets`、`data`、`scenes`、`scripts`、`systems`、`tests`、`tools`、`ui`、
`.github/workflows` 的所有檔案型別，以及 project/export/README/法務/發行文件；另保守納入根目錄既有角色素材與
`.gitignore`，即使 export preset 排除其中部分檔案，仍不允許它們在驗收途中漂移。Windows 與 Linux 的 PCK 必須
逐位元相同，smoke marker 必須各精確出現一次且順序正確，產品 diagnostics 必須為零。

只有全部 gate 通過時才會原子建立 `release-evidence.json`；失敗時會保留該次 log 供診斷，但不會留下成功名稱的
evidence。失敗的兩個 root 都不得重用，應以全新路徑重新執行。完整流程可能耗時較久並占用大量磁碟空間。

上方手動 import/export/package 指令只適合準備或診斷 staging，不能取代這個單次驗收，也不能據此宣稱 release
evidence 成功。本機只實際 smoke Windows 成品；Linux 在本流程僅完成乾淨匯出與封裝，仍須由真實 Linux CI
執行成品 smoke。未簽章、素材散布權利與專案 LICENSE 仍是公開發佈阻塞。

## 公開發佈阻塞

在下列項目閉環前，不應把目前 package 宣稱為可公開正式發行：

1. **背景素材授權未確認**：`assets/images/world/backgrounds/city-map-background.png` 是既有遷移素材；目前資料只能確認檔案來源路徑與 SHA-256，不能證明作者或公開散布授權。專案擁有者需取得權利證明或換成授權清楚的素材。
2. **平台簽章未完成**：`export_presets.cfg` 的 Windows `codesign/enable=false`；目前 EXE 與 archives 都未簽章。公開 Windows 發行前需決定憑證、簽章與信譽建立流程。
3. **Linux 尚未人工驗收**：Linux 匯出與 headless 啟動測試已在 CI 通過（[2026-09-20 執行紀錄](https://github.com/xichengyu810067-lab/MayorSimulator/actions/runs/35489395672)），但還沒有在真實 Linux 桌面做人工遊玩驗收。

另外，專案自身原始碼、資料、文字與媒體保留所有權利（見 `LICENSE.txt`），尚未選定開放授權。Godot 與 runtime notices 請見
`THIRD_PARTY_NOTICES.md` 及 `GODOT_COPYRIGHT.txt`；不得把 Godot 的 MIT 授權誤當成整個專案內容的授權。

## 文件入口

- [文件導覽](../README.md)
- [檔案用途索引](../project-organization/FILE_INDEX.md)
- [舊路徑與新路徑對照](../project-organization/MIGRATION_MAP.md)
- [2026-07-31 程式碼稽核](../project-organization/MAYOR_SIMULATOR_FINAL_AUDIT_2026-07-31.md)
- [Runtime 素材台帳](../project-organization/RUNTIME_ASSET_LEDGER.md)
- [第三方元件聲明](../../THIRD_PARTY_NOTICES.md)
- [Godot 版權聲明](../../GODOT_COPYRIGHT.txt)
