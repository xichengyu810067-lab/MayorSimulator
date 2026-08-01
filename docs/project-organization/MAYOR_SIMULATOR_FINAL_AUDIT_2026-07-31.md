# Mayor Simulator 2026 年 7 月最終程式碼稽核

> 歷史基線：本檔記錄閉環修正前的 86 分暫定結論。最終權威結論請改讀 `MAYOR_SIMULATOR_FINAL_AUDIT_2026-07-31_CLOSURE_2026-08-01.md`（90/100）。

- 稽核凍結版本：`2026.07.31`
- 稽核證據完成時間：2026-08-01 03:09:57（Asia/Taipei；工作跨越午夜，但仍屬 7 月最終稽核）
- 稽核方式：來源唯讀量測、45 項完整斷言矩陣、長期模擬、多解析度 UI 驗收、匯出成品 smoke、雙平台封裝、可見 GUI 操作與獨立複評
- 最終客觀分數：**86 / 100**
- 成熟度判定：**成熟的 Internal Alpha／release staging**
- 發行判定：**尚不是可對外發布的 95 分 Release Candidate**

## 一、結論

本輪沒有新增遊戲功能，工作限於修復既有缺陷、降低單一責任耦合、加強回歸測試及建立可驗證的發行證據鏈。核心模擬、治理、NPC、存檔、本地化、主要 UI 與 Windows 匯出成品均已達到可信的內部 Alpha 水準。

目前不能把分數灌到 95。剩餘扣分主要不是再多寫幾個單元測試就能消除，而是：

1. 城市背景圖的作者／授權仍無法由專案證明，且專案本身沒有 LICENSE。
2. 目前不是有效 Git repository，沒有可追溯 commit，也沒有遠端 GitHub Actions 與真實 Linux runtime 成功紀錄。
3. Windows 成品未簽章，也未取得 SmartScreen／乾淨電腦安裝證據。
4. 控制器、按鍵重綁、UI scale、色覺、公開 Reduced Motion 與輔助科技支援尚未閉環。
5. 尚無外部玩家可用性及長局平衡證據。

其中第 4 類含新功能性質；在「95 分以前禁止新增功能」的限制下，不應偷偷實作。第 1～3、5 類還需要專案擁有者決策、外部帳號／憑證、不同作業系統或真人參與，不能用本機假證據替代。

## 二、固定權重評分

| 指標 | 權重 | 得分 | 客觀判定 |
|---|---:|---:|---|
| 功能性與模擬深度 | 20 | **19** | 核心玩法、治理、NPC、建築、月結與 3,600 日模擬通過；缺外部長局平衡證據 |
| 資料、存檔與本地化 | 15 | **14** | 300 NPC、111 項存檔復原及五語 1,471 筆通過；缺真實程序中斷／斷電式驗證 |
| 架構與可維護性 | 15 | **13** | CityState 單一資料寫入邊界及服務拆分成立；`main.gd` 仍過大 |
| 美術、音訊與授權 | 15 | **12** | 視覺與六個 WAV 有來源紀錄，Godot 法務檔已封裝；背景圖權利及專案 LICENSE 未閉環 |
| UI 細緻度與響應式 | 10 | **9** | 四解析度、九個市政頁、10,660 項幾何檢查及可見 GUI 通過；缺 1280×720 與 Windows DPI／UI scale 實測 |
| UX、輸入與無障礙 | 10 | **7** | 教學、焦點、ESC、明暗、語言、音訊與安全退出具備；控制器、重綁、色覺、Reduced Motion、輔助科技不足 |
| 測試、版本控制與發行 | 10 | **8** | 45/45、雙平台匯出、Windows smoke、交易式封裝與 v2 證據鏈完整；無 Git、遠端 CI、Linux 實跑及簽章 |
| 內容量、平衡與文件 | 5 | **4** | 26 棟建築、300 NPC、治理資料與操作文件成熟；缺真人測試及量化平衡報告 |
| **總分** | **100** | **86** | **未達 95，不得宣稱正式發行候選** |

獨立複評採相同固定權重，結論同為 86/100。純本地、且維持禁止新增功能時，可信上限約 88～90；95 分需要外部發行條件與無障礙能力，不是增加測試數量即可達成。

## 三、最終證據鎖

### 3.1 完整斷言矩陣

- 路徑：`.tmp/final-acceptance-20260731/matrix45-chart-redraw-fixed/summary.json`
- SHA-256：`2E5646C04A6EFA30A4A66BFC853603A1F5055F3F7C735DE01CD35EF105EF21CC`
- manifest：45 項；ID 重複 0；遺失腳本 0
- 結果：45/45 `PASS_WITH_ENVIRONMENT_WARNING`
- product-clean：45/45
- failed：0
- 總時間：360.861 秒
- 唯一共同環境警告：Godot 無法讀取這台 Windows 的根憑證庫；原始紀錄保留，未被當成產品錯誤刪除

重要子證據：

- 3,600 日 soak：1,757 checks，2,871.613 ms
- 多解析度 UI：1366×768、1920×1080、2560×1440、2880×1800；9 個市政頁、192 個表面、10,660 checks
- 存檔復原：111 checks
- 本地化：`zh_TW`、`zh_CN`、`en`、`ja`、`ko`，來源鍵 1,471
- 城市資料儀表板：3 個頁籤，圖表集合 9／4／1，快照不可變，首月／前月基準通過

### 3.2 可見 GUI 驗收

自動截圖 traversal 產生 33 張本輪聲明的 PNG；33 張皆存在且皆為 2880×1800。涵蓋起始畫面、載入、教學、主地圖、天氣、設定、建築、治理、司法、監督、藍圖、財政、公共事務、城市數據、報告、深色模式及退出確認。`artifacts/screenshots/ui-tests` 是累積型產物目錄，目前共 51 張，不能把累積數誤報為本輪數量。

另外以匯出的 Windows EXE 在 1440×900 可見視窗實際操作兩次：

1. 第一次發現「居民滿意」隱藏頁籤在顯示後沒有重畫彩色軌跡。
2. 新增先失敗的 redraw contract regression，修正 `BenchmarkDeltaChart` 對 `visibility_changed` 與 `plot_area.resized` 的 redraw invalidation。
3. 針對測試及完整 45 項矩陣均通過。
4. 第二次以相同路徑重測，紅／綠軌跡、基準線、節點均正常顯示。
5. 兩次皆由遊戲內退出確認正常離開；`process.stderr.log` 皆為 0 bytes，最終殘留 Godot／MayorSimulator 程序為 0。

### 3.3 匯出、smoke 與交易式封裝

目前雙平台 staging 各恰為四個檔案：執行檔、PCK、`THIRD_PARTY_NOTICES.md`、`GODOT_COPYRIGHT.txt`。Windows 與 Linux PCK 完全相同：

- PCK SHA-256：`89E8C0980CAC11921446A2A5C6950DF35688DB4F28D961E4CF8CDD525BF98ED2`
- Windows EXE：`F5DCC7DCBFF9BA71E8F71DBB4609814E67099FD576FE6F1C8B22F1A5A6CBA3E6`
- Linux ELF：`3154BB4465F616E24B811DD576E9230022872CD80F8D5AB854EFED2716B926D4`
- Windows ZIP：`C0E30EC594F62403778A64FF54C5BF2B1761EC28329151DDB2781703397B7DDD`
- Linux TAR.GZ：`7327FCB6AE5791752F9891B4C2F50B279E025CA292EA957F72B2698C4EC162FB`
- Linux archive 權限：執行檔 `0755`；PCK／法務檔 `0644`
- 交易式封裝：所有成品於同層 `.partial` 目錄完成驗證後，才以單次目錄 rename 發布；最終無殘留 partial 目錄

Windows 匯出 EXE 直接執行 120 幀 release smoke：exit code 0；`QA_RELEASE_SMOKE_ARMED frames=120` 與 `QA_RELEASE_SMOKE_COMPLETED` 各出現一次；產品診斷 0。

### 3.4 最終 v2 發行證據

- 路徑：`.tmp/final-release-20260731/release-evidence-chart-redraw-fixed-v2.json`
- SHA-256：`4A8FB49FCDDE8176250E778118E47350001A12797D395AE2DFE2D5FC4DE77CA7`
- 來源檔：139
- 來源指紋：`28855E9E74E874DB1A3B6FD0344D7758D8CB0799F1AF58E069E30CB09B2DBF16`
- 產生後受指紋涵蓋的來源變更：0
- 矩陣、Windows export、Linux export、Windows smoke、package exit code：全為 0
- smoke stdout 與 stderr 均納入雜湊
- 根憑證環境警告：1
- 產品診斷：0
- Linux runtime：`not_run_locally`
- Git commit：不可用

較早的 `release-evidence-chart-redraw-fixed.json` 只讀 stdout，因而把 stderr 的根憑證警告誤記為 false，已明確作廢；最終稽核只引用 v2。

## 四、已閉環功能與品質問題

### 4.1 核心與資料

- `CityState` 成為產品程式的城市 metrics 寫入邊界；直接 `metrics[...] =` 的產品寫入集中在 `scripts/core/city_state.gd`。
- `CitySimulationService` 承接模擬更新；市政經濟不再依賴靜默 fallback。
- NPC schema v2 的薪資、債務、人格、外觀、職業容量、稅務與交易 ledger 已驗證。
- 300 NPC 持久化、collision-free ID、穩定外觀、地圖 ownership 及 proxy rebind 均有回歸測試。
- 存檔 envelope、語意驗證、migration、`.bak` 復原與失敗退出防護已閉環。

### 4.2 治理與互動

- 下議院資料仍留在既定隔離模組，未被擅自整合到其他模型。
- 表決 terminal latch、終局 freeze、彈劾映射、多案件選擇與 fail-closed 行為均已驗證。
- modal click-through、焦點、ESC、教學 Enter 單次前進、NPC 點擊、建築放置及退出確認均有回歸測試。
- 自動儲存失敗時提供重試／捨棄決策，不再無條件退出。

### 4.3 UI、音訊與視覺

- `CityDataDashboard` 已從 `main.gd` 拆出，承接三頁城市數據 composition 與圖表更新。
- 隱藏 TabContainer 頁籤的圖表 redraw 缺陷已由真實 GUI 找出並修復。
- 多解析度幾何驗收、明暗主題、五語、城市數據警告、天氣、退出確認與設定頁均通過。
- 音訊正常 shutdown，無 WAV resource leak。

### 4.4 QA 與發行工具

- 45 項 manifest 是單一來源，ID 唯一且腳本零缺漏。
- release metadata 由 tag 或 workflow input 驗證；Windows metadata 與 version 一致。
- GitHub Actions 使用完整 SHA 固定 `actions/checkout` v7.0.1 與 `actions/upload-artifact` v7.0.1；兩者皆為 Node 24 action。
- 封裝工具拒絕未知檔案、reparse point、錯誤 magic、錯誤法務雜湊與既有輸出路徑。
- 證據工具現在同時驗證 smoke stdout／stderr，避免環境警告被漏記。

## 五、未閉環項目

### 5.1 對外發布阻斷

1. `assets/images/world/backgrounds/city-map-background.png`
   - 2,405,319 bytes
   - SHA-256：`B968762C5F8756B26874D1B3610D889D2472B251C7E6F3D052B9C0533612E119`
   - 專案只能證明它由既有檔案遷移，不能證明作者或再散布權。
   - 在取得權利證明或由擁有者核准替換前，**公開散布仍應封鎖**。
2. 專案沒有自身 LICENSE；`GODOT_COPYRIGHT.txt` 只處理引擎與第三方聲明，不能代替遊戲專案授權。
3. Windows 未簽章，沒有簽章憑證與 SmartScreen／乾淨機器證據。

### 5.2 版本控制與跨平台證據

- `git rev-parse --verify HEAD` 與 `git status` 均回傳 128：目前不是 Git repository。
- workflow 已建立，但沒有遠端成功 run；因此不能宣稱 CI 已通過。
- Linux 成品已匯出且 ELF／權限／封裝通過，但沒有在真實 Linux runner 執行。

### 5.3 架構債務

| 檔案 | 行數 | 函式 | 頂層變數 | 判定 |
|---|---:|---:|---:|---|
| `scripts/app/main.gd` | 5,215 | 316 | 143 | 仍是主要維護風險 |
| `scripts/app/vertical_slice_coordinator.gd` | 1,186 | 72 | 21 | 可再按流程邊界拆分 |
| `scripts/app/npc_map_controller.gd` | 957 | 51 | 9 | ownership 已正確，但體積仍大 |
| `ui/shell/city_data_dashboard.gd` | 776 | 42 | 10 | 已自 Main 拆出，責任較集中 |
| `ui/components/benchmark_delta_chart.gd` | 290 | 22 | 19 | redraw contract 已補齊 |

此項是維護性扣分，不代表現有功能失效。後續重構必須保持行為不變並逐步進行，不能以大規模改寫換取表面行數下降。

### 5.4 UX、無障礙與真實使用

- 尚未驗證 1280×720、Windows 125%／150%／200% DPI 與公開 UI scale。
- 尚無完整控制器操作與按鍵重綁。
- 尚無色覺模式／非顏色單一提示、公開 Reduced Motion 設定與輔助科技驗收。
- 尚無外部玩家完成教學、建造、治理、存檔／載入、退出的可用性紀錄。

### 5.5 韌性與平衡

- 存檔 recovery 測試涵蓋損毀與備份，但未以 OS 層級強制終止程序模擬正在寫檔時的斷電。
- 3,600 日 soak 證明確定性及不崩潰，不等於經濟與治理平衡已由真人證實。

## 六、未來規劃建議

### P0：不新增功能即可處理的發布阻斷

1. 由專案擁有者提供背景圖權利證明，或明確授權以已知權利素材替換。
2. 決定專案自身 LICENSE 與散布方式；完成法務檢查。
3. 建立有效 Git 歷史與遠端 repository，以當前來源指紋作可追溯基準。
4. 在 GitHub Actions 真實跑完 Windows 與 Linux jobs，保存 run URL、commit SHA、artifact SHA 與 logs。
5. 取得 Windows code-signing certificate，簽章後在乾淨 Windows VM／實機驗證。

驗收門檻：權利、LICENSE、commit、CI/Linux runtime、簽章五項都有可追溯證據，才解除公開散布封鎖。

### P1：既有功能的韌性與相容性閉環

1. 在 1280×720 與 Windows 125%／150%／200% DPI 逐頁跑現有功能；只修正 clipping、overlap 與不可點擊問題。
2. 新增 OS 層級強制終止的存檔測試，確認 temp／backup／主檔恢復順序。
3. 以固定種子之外的多組長局模擬產生分布報告，設定可解釋的平衡警戒線。
4. 逐段拆分 `main.gd` 的既有責任；每段重構都需先有 contract test，再跑 45 項矩陣與可見 GUI。

此階段仍不新增玩法。

### P2：需先解除「禁止新增功能」的能力缺口

1. 控制器完整導航與按鍵重綁。
2. 公開 UI scale。
3. 色覺安全提示及對比驗收。
4. Reduced Motion 設定。
5. 輔助科技／螢幕閱讀器可辨識結構。

這些能力對 95 分是必要的，但屬於新功能或明顯擴充；必須由擁有者明確解除禁令後才可實作。

### P3：外部驗證

1. 至少一輪非開發者可用性測試，預先定義成功率、時間、誤點、放棄點與嚴重度。
2. 以外部長局存檔核對經濟、人口、治理與勝敗節奏，不接受只挑成功樣本。
3. 對 P0～P3 的新證據重新跑固定權重稽核；未通過的項目不得用主觀描述補分。

## 七、95 分門檻判定

分數提升不是機械加分，仍需完整重評；但至少必須同時滿足：

- 公開散布權利與專案 LICENSE 閉環。
- 可追溯 Git commit、遠端 CI、Windows 與 Linux runtime 成功證據。
- Windows 簽章及乾淨環境驗證。
- DPI／UI scale、控制器、重綁、色覺、Reduced Motion 與輔助科技達成可操作標準。
- OS 強制終止存檔驗證與外部玩家／平衡證據。
- 架構債務持續下降且不造成回歸。

在這些條件缺一的情況下，宣稱 95 分以上不符合本稽核的證據標準。

## 八、產品檔與產物界線

- 產品／來源：`scripts/`、`systems/`、`ui/`、`scenes/`、`data/`、`tests/`、`tools/`、`project.godot`、`export_presets.cfg`、README、workflow 與法務聲明。
- 產物：`builds/`、`.tmp/`、`artifacts/screenshots/` 及本機 Godot user data。
- 稽核報告不把產物數量當作功能數量，也不把第三方素材重置成本當成使用者已支付現金。

## 九、官方依據

- [Godot 4.7 stable archive 與 export templates](https://godotengine.org/download/archive/4.7-stable/)
- [Godot 4.7 專案匯出說明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html)
- [Godot 授權遵循說明](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html)
- [actions/checkout 官方 repository](https://github.com/actions/checkout)
- [actions/upload-artifact 官方 releases](https://github.com/actions/upload-artifact/releases)
