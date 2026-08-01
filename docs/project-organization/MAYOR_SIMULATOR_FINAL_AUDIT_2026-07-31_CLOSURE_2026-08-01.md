# Mayor Simulator 2026 年 7 月最終程式碼稽核：閉環複驗版

- 稽核凍結版本：`2026.07.31`
- 閉環證據完成時間：2026-08-01（Asia/Taipei；工作跨越午夜，仍屬 7 月最後一輪稽核）
- 稽核邊界：只修正既有缺陷、重構既有責任、補強測試／證據／文件；**沒有新增玩法或產品功能**
- 本報告地位：取代 `MAYOR_SIMULATOR_FINAL_AUDIT_2026-07-31.md` 的 86 分暫定結論；舊報告保留為歷史基線
- 最終客觀分數：**90 / 100**
- 成熟度：**高完成度 Internal Alpha／可重現 release staging**
- 對外發行判定：**不通過**；不得宣稱 95 分 Release Candidate

## 一、結論

這一輪把前次稽核中仍可由本機、且不新增功能就能處理的主要缺口推到目前合理上限：

1. 47/47 完整斷言矩陣在單一 fail-closed 發行流程中通過，產品錯誤 0。
2. 存檔以 5 個原子寫入階段做真實 OS 強制終止；5/5 都能復原，173 個語意檢查通過，程序全部結束。
3. UI 嚴格驗收到 1280×720，涵蓋 5 個解析度、9 個市政頁、240 個表面、85 個互動元件、50 個捲動容器、99 次實際捲動與 14,147 個檢查。
4. 匯出成品完成 Windows／Linux 雙平台封裝，Windows 成品 smoke 與可見 GUI 實玩通過；實玩後來源指紋完全未變。
5. 執行期素材建立 87 項 deterministic ledger；檔案、雜湊、registry coverage 與必填 metadata 均完整。
6. `main.gd` 的城市報告歷史責任已拆出，從 5,218 行／316 函式降到 5,047 行／311 函式，相關 6 項回歸測試全過。

因此分數由歷史基線 86 提升至 **90**。沒有再往上灌分，因為剩餘缺口包含權利／授權、Git 與遠端 CI、Linux 真機 runtime、Windows 簽章、外部玩家與正式平衡驗證，以及目前禁止新增的無障礙／輸入能力。這些不能用更多本機測試假裝閉環。

## 二、固定權重重評

| 指標 | 權重 | 得分 | 客觀判定 |
|---|---:|---:|---|
| 功能性與模擬深度 | 20 | **19** | 核心玩法、治理、NPC、建築、月結及 7 seed × 2 replay × 3,600 日穩定；仍缺正式平衡門檻與外部長局 |
| 資料、存檔與本地化 | 15 | **15** | 300 NPC、存檔 envelope／備份／migration、五語及 5 階段 OS 強制終止復原皆有證據 |
| 架構與可維護性 | 15 | **14** | 單一資料寫入邊界及多項服務拆分成立；`main.gd` 仍為 5,047 行主要風險 |
| 美術、音訊與授權 | 15 | **12** | 87 項 runtime asset ledger 完整；城市背景權利與專案自身 LICENSE 仍未閉環 |
| UI 細緻度與響應式 | 10 | **10** | 1280×720 至 2880×1800 嚴格幾何、44×44 互動面、捲動可達性及可見成品 traversal 通過 |
| UX、輸入與無障礙 | 10 | **7** | 教學、鍵盤焦點、ESC、明暗、語言、音訊與安全退出具備；DPI、控制器、重綁、色覺、Reduced Motion、輔助科技不足 |
| 測試、版本控制與發行 | 10 | **9** | 單一 fail-closed 流程完成矩陣、OS-kill、雙平台匯出、Windows smoke、封裝及雜湊；仍無 Git／遠端 CI／Linux runtime／簽章 |
| 內容量、平衡與文件 | 5 | **4** | 26 棟建築、300 NPC、治理資料、素材 ledger 與文件完整；多 seed 只證明穩定與確定性，不等於正式平衡 |
| **總分** | **100** | **90** | **未達 95；維持禁止新增功能與對外散布封鎖** |

### 2.1 相對 86 分基線的四個可稽核加分

| 類別 | 變化 | 依據 |
|---|---:|---|
| 資料、存檔與本地化 | +1 | OS 層級 5 階段強制終止復原 5/5、173 checks |
| 架構與可維護性 | +1 | `CityReportHistoryService` 拆分且 6/6 回歸通過 |
| UI 細緻度與響應式 | +1 | 補齊 1280×720、嚴格邊界、44×44、scroll truth／reach／move |
| 測試、版本控制與發行 | +1 | 單一來源指紋鎖定的 fail-closed release orchestrator 完整通過 |

素材 ledger、多 seed soak、財政契約及 33 張 append-only 截圖加強了可信度，但沒有被重複計分。舊的 v1～v3 發行嘗試均因各自失敗條件被拒絕，只有 v4 可以作為最終證據。

## 三、最終證據鎖

### 3.1 單一發行驗收 v4

- 證據：`.tmp/final-release-20260731/orchestrated-20260801-v4/release-evidence.json`
- SHA-256：`F6E72C369EDFD5A2C388C88C6443EB470BF4D05FC76344F9883C59F504E0A287`
- schema：3；status：`PASS`
- 來源：1,175 檔、389,027,969 bytes
- 來源指紋：`4a0cf0aba4df9adb0e4362c744f07da392575e0fc27c1281130ab050475500c6`
- 起始／結束／封裝前來源 manifest 完全相同
- 斷言矩陣：47 selected、47 product-clean、0 failed
- OS-kill：5 passed、0 failed、5 forced termination、173 semantic checks、程序全停
- import、Windows export、Linux export、Windows smoke：產品診斷 0、leak signature 0
- Windows／Linux PCK：15,435,180 bytes，位元完全相同
- PCK SHA-256：`5ed66ab5f4762efec42976748c95f5612ff96a79a884598a7be7b629fcf93e16`
- Windows ZIP SHA-256：`479d300f5f5128044c1e26e3e533bd369c9e302c4c327787fa375462ad63e9a6`
- Linux TAR.GZ SHA-256：`aab09605d3178113820c7f15e6c44a59e4d9f80afc51210ed579bc0d04ef846b`

Godot 官方文件說明匯出需要對應的 export templates；本輪以 Godot 4.7 stable 官方 template archive 的固定 SHA-256 安裝到隔離目錄，並驗證 archive-to-installed stream hash 與執行後 tree 未變。[Godot 4.7 stable archive](https://godotengine.org/download/archive/4.7-stable/)；[Godot 4.7 匯出說明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html)

### 3.2 嚴格 UI 與可見實玩

- 嚴格 UI summary：`.tmp/assertion-matrix/ui-scroll-operability-strict-20260801-v3-final-candidate/summary.json`
- SHA-256：`E057AC482E6EC431CC69089A4369998C1ED52E7329824B9A2BBC324116A014AE`
- 解析度：1280×720、1366×768、1920×1080、2560×1440、2880×1800
- 結果：5 resolutions、9 municipal pages、240 surfaces、85 interactives、50 scroll containers、99 scroll moves、14,147 checks、缺口 0
- 所有可見且啟用的 `BaseButton` 均需至少 44×44 logical pixels；此為專案採用的保守內部門檻，參考 WCAG 2.2 Target Size (Enhanced) 的 44×44 CSS pixel 概念，但不等同宣稱完整 WCAG conformance。[W3C WCAG 2.2 Target Size (Enhanced)](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced)

乾淨 append-only 視覺證據：

- summary：`.tmp/final-acceptance-20260731/ui-capture-append-only-20260801-v1/summary.json`
- SHA-256：`E56AF3421B74289662B1847464C6268A525A7F7FACCB4B78441B4CC2DAC3C80F`
- 33/33 PNG、每張 2880×1800、exit 0、diagnostics 0、來源前後未變
- 涵蓋起始、教學、主地圖、天氣、設定、明暗、建築、治理、司法、監察、藍圖、財政、城市資料、報告及退出確認
- 人工抽查財政、居民、深色藍圖、退出確認，未見產品重疊或裁切

匯出 Windows EXE 的可見 traversal：

- summary：`.tmp/final-visible-gui-20260801/v1/summary.json`
- SHA-256：`53080974AA38A0F003566B375A7400FABB25DEF39259B88FD094DA896DCD333E`
- 實際走過：開始 → 新遊戲 → 教學 → 主地圖 → 市政 → 建設與發展 → 財政三類分頁 → 居民與資訊 → 城市資料 → 實際捲動 → 居民滿意 → 退出確認 → 確認離開
- 9 張 1440×900 desktop capture；日誌診斷 0；殘留產品程序 0
- CLI 曾要求 1280×720 windowed，但產品依 project-level 設定保持全螢幕 1440×900；因此本證據只證明可見成品 traversal，1280×720 必須引用前述嚴格自動驗收
- 畫面右側有 Codex 桌面寵物／通知外部覆蓋；不把它誤判為產品 UI，乾淨視覺判定引用 33 張產品截圖
- 實玩後重算來源指紋仍為 `4a0cf0...00c6`，與 v4 發行證據完全一致

### 3.3 多 seed、財政及重構

- 多 seed summary：`.tmp/assertion-matrix/multiseed-long-soak-20260801-v2-final/summary.json`
- SHA-256：`61E196B43064E3E9A5D142599F72CEEB98409AD2B78C0C7BA2080DB89DB70619`
- 7 seeds × 2 deterministic replays × 3,600 days = 50,400 simulated days
- 12,903 checks；failure 0；non-finite 0；replay determinism 全部成立；7 組初始 profile 皆不同
- 限制：測試明確採 `reported_only_no_ratio_gate`，所以不把它寫成正式經濟平衡證明

- 財政 GUI stdout SHA-256：`05ACAA027C4161E2CBFE9D54A6DB764A1CA572435800AFAFE8B7EC74624AD9E3`
- 3 個根分類、6 個葉分類、14 個 slider；正常／低／高狀態語意通過
- 1280×800 時內容可完整容納，因此 maximum scroll = 0 且不顯示假捲軸；狀態與頁籤均復原

- 報告歷史重構 summary：`.tmp/assertion-matrix/city-report-history-refactor-final-v3/summary.json`
- SHA-256：`E655847BD5C506E355CFB1D0854DE72C5F24B94798506C744D24EC86DAD3AD2D`
- localization、localized runtime view model、main integration、start screen、service unit、city dashboard：6/6 product-clean

### 3.4 執行期素材與法務界線

- JSON ledger：`docs/project-organization/RUNTIME_ASSET_LEDGER.json`
- SHA-256：`FF17D94772C260C3F4AEF9742ACB4B6C56959318AB815F57DEC88945050B01E8`
- 87 項：audio 6、NPC portraits 8、NPC walk sheets 8、UI icons 37、buildings 26、tutorial 1、background 1
- 遺失 0、重複路徑 0、重複內容 hash 0、必填 metadata 空白 0、registry coverage 完整
- 唯一 source-rights unresolved：`city-map-background.png`
- project distribution license：`unselected_no_root_license_file`

Godot 的授權遵循文件要求散布時提供引擎授權／著作權資訊；本輪封裝已包含 `GODOT_COPYRIGHT.txt` 與 `THIRD_PARTY_NOTICES.md`，但它們不能代替遊戲專案自身的 LICENSE，也不能補出背景圖權利。[Godot 授權遵循說明](https://docs.godotengine.org/en/4.7/about/complying_with_licenses.html)

## 四、已閉環範圍

### 4.1 核心玩法與資料一致性

- 城市日／月模擬、建築目錄、建造與藍圖、財政、公用事業、民意、月報及城市資料頁均在矩陣內。
- `CityState` 維持城市 metrics 的產品寫入邊界；模擬與 UI 透過服務／view model 互動。
- 300 NPC schema、穩定 ID、外觀、職業、家庭／交易／稅務、地圖 ownership 與持久化均有測試。
- 下議院模組維持既定隔離，沒有趁重構擅自整合或改變模型範圍。
- 治理表決終局 latch、司法／監察、多案件選擇、fail-closed 狀態及存檔銜接通過。

### 4.2 存檔、本地化與失敗處理

- 存檔 envelope、schema／semantic validation、migration、temporary file、`.bak` recovery 與失敗退出決策閉環。
- OS-kill 覆蓋 temp partial write、temp verified、backup removed、primary rotated、primary installed 五個原子階段。
- 五語 runtime catalog 與動態 view model 回歸通過；沒有用格式化後字串替換冒充本地化。
- 自動儲存失敗時不會無條件離開，使用者有重試／捨棄的明確選擇。

### 4.3 UI、互動與可見產品流程

- 1280×720 下頁面邊界、互動面尺寸、捲動需求、可達底部、滾動後內容確實移動均由測試量測。
- 教學、鍵盤焦點、ESC、modal click-through、防重複觸發、明暗主題、城市資料 redraw 與退出確認皆有回歸。
- 匯出成品已真正點擊進入財政、城市資料與居民頁，並從遊戲內完成退出，而非只看靜態場景。
- 33 張產品截圖採 append-only 新目錄；既有目錄會被拒絕，避免舊圖混入本輪證據。

### 4.4 QA、匯出與封裝

- 47 項 manifest 為矩陣單一來源；重複 ID 0、缺腳本 0。
- 發行流程鎖定來源、Godot executable、PowerShell、官方 templates、所有命令輸出、雙平台 PCK、smoke marker、程序清理與套件雜湊。
- 流程遇到 stderr marker、diagnostic、leak、timeout、來源漂移、template 漂移或未知 staging 檔案會直接失敗。
- staging 每平台恰為 5 個 regular files：執行檔、PCK、release readme、third-party notices、Godot copyright。

## 五、仍未閉環與扣分理由

### 5.1 公開散布權利（阻斷）

1. `assets/images/world/backgrounds/city-map-background.png`
   - 2,405,319 bytes
   - SHA-256：`B968762C5F8756B26874D1B3610D889D2472B251C7E6F3D052B9C0533612E119`
   - 專案只證明既有素材遷移，無法證明作者與再散布權。
2. 專案根目錄沒有自身 LICENSE，且授權方案尚未選定。

在兩者閉環前，公開散布必須維持封鎖。這不是程式 bug，也不能由我替擁有者做法律決策。

### 5.2 發行工程與外部環境（阻斷）

- 目前不是有效 Git repository；沒有可信 commit SHA 或 clean-tree 證明。
- workflow 雖存在，但沒有遠端 GitHub Actions 成功 run URL／artifact 證據。
- Linux 已匯出及封裝，尚未在真實 Linux runner 執行。
- Windows 執行檔與封裝未簽章，沒有憑證鏈、timestamp、SmartScreen 或乾淨 VM 驗證。
- 目前可見 GUI 是本機 Intel Iris Xe／Compatibility renderer 的單機證據，不代表不同 GPU／驅動相容性。

### 5.3 UX、輸入與無障礙（部分屬新功能）

- 尚未逐頁驗證 Windows 125%／150%／200% DPI。
- 完整控制器導航與按鍵重綁尚未建立。
- 尚無非顏色單一提示的完整色覺驗收。
- 尚無公開 Reduced Motion 設定。
- 尚無螢幕閱讀器／輔助科技可辨識結構的正式驗收。

其中控制器、重綁、UI scale、Reduced Motion 與輔助科技結構會改變產品能力，屬於目前明令禁止的新增功能；本輪沒有偷做。

### 5.4 外部可用性與正式平衡

- 沒有非開發者完成教學、建造、治理、存檔／載入、退出的任務紀錄。
- 多 seed soak 證明「不崩潰、數值有限、同 seed 可重播、不同 seed 有不同人口 profile」，沒有事先核准的經濟／治理接受區間。
- 沒有外部長局存檔、流失點、挫折點、任務成功率或平衡評審。

### 5.5 架構債務

| 檔案 | 行數 | 函式 | 判定 |
|---|---:|---:|---|
| `scripts/app/main.gd` | 5,047 | 311 | 仍是最大單檔維護風險 |
| `scripts/app/vertical_slice_coordinator.gd` | 1,186 | 72 | 可按既有流程責任繼續拆分 |
| `scripts/app/npc_map_controller.gd` | 957 | 51 | ownership 正確但體積仍大 |
| `ui/shell/city_data_dashboard.gd` | 776 | 42 | 責任已集中，仍需控制增長 |
| `scripts/app/city_report_history_service.gd` | 334 | 24 | 新拆分服務；已有 unit／integration 保護 |

這是維護性扣分，不代表現有功能失效。後續只准小步、先契約測試、再重構，禁止大改寫換取表面行數下降。

## 六、未來規劃建議

### P0：維持功能凍結，先取得擁有者／外部證據

1. 背景圖二選一：提供可稽核的作者與再散布權證明，或由擁有者明確核准替換為權利明確素材。
2. 由擁有者與法務選定專案 LICENSE／EULA／散布政策；不要拿 Godot 授權代替專案授權。
3. 決定如何處理目前無效的 `.git` 狀態，再建立可信 repository、commit、tag 與 clean-tree 基準。
4. 將現有 fail-closed orchestrator 放到真實 Windows／Linux CI；保存 commit SHA、run URL、logs 與 artifact hashes。
5. 提供 Windows code-signing certificate，在乾淨 VM 驗證簽章、timestamp、啟動、儲存與解除安裝／移除流程。
6. 安排 125%／150%／200% DPI 的既有頁面 traversal；本階段只修 clipping、overlap、不可點擊，不新增 UI 功能。

### P1：仍不新增功能的品質工作

1. 由產品擁有者先訂平衡接受區間，例如破產率、收入／支出覆蓋率、人口與民怨範圍；再讓多 seed 測試套用，避免事後挑門檻。
2. 招募非開發者按固定腳本測試現有流程，記錄成功率、時間、誤點、放棄點及嚴重度。
3. 逐段拆 `main.gd` 的既有責任；每段必須先有 contract test，之後跑 47 項矩陣、OS-kill、嚴格 UI、33 張截圖與可見成品 traversal。
4. 定期重建 87 項 runtime asset ledger；任何新增／替換素材都必須同時有 runtime reference、provenance 與 distribution-rights 狀態。

### P2：只有解除「禁止新增功能」後才能排程

1. 控制器完整導航與按鍵重綁。
2. 公開 UI scale。
3. 色覺安全的非顏色單一提示。
4. Reduced Motion。
5. 輔助科技／螢幕閱讀器結構。

這些不是本輪可偷偷修補的小缺陷；若仍要求 95 分且同時禁止新增功能，兩個條件在目前證據標準下互相衝突。

## 七、95 分門檻

90 到 95 不是再補五個單元測試。重新評分前至少要同時具備：

- 背景圖散布權與專案 LICENSE。
- 有效 Git commit／tag、遠端 CI、Windows 與 Linux runtime 成功證據。
- Windows 簽章與乾淨環境驗證。
- DPI matrix、外部可用性與事前定義的平衡門檻。
- 經擁有者解除禁令後，補足控制器／重綁／色覺／Reduced Motion／輔助科技能力。
- 架構債務持續下降且完整回歸無退步。

所有項目完成後仍須重跑固定權重稽核；不能預先保證一定加到 95。現況的可信本地上限是 **90**。

## 八、產品檔與產物界線

- 產品／來源：`assets/`、`data/`、`scenes/`、`scripts/`、`systems/`、`tests/`、`tools/`、`ui/`、workflow、project／export／README／release／法務檔。
- 稽核／產物：`docs/project-organization/` 的報告、`.tmp/`、`builds/`、截圖及隔離 app data。
- 本報告不把測試數量當成功能數量、不把模擬穩定當正式平衡、不把 provenance 當散布授權，也不把匯出成功當跨平台 runtime 成功。

