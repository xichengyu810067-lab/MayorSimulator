# 《Mayor Simulator》全專案審計與資金評估

**評估日期：** 2026-07-26（Asia/Taipei）  
**專案版本基線：** Godot 4.7，Windows 工作站  
**評估性質：** 唯讀技術、產品與資金評估  
**預設發行目標：** 免費 itch.io 公開下載版  
**估值幣別：** 新臺幣（NT$）

> 本報告沒有修改遊戲程式、資料、公開 API 或存檔格式。檔案數基線不包含本報告本身；測試所產生的 `.godot`、`.tmp`、日誌、存檔與擷取圖不納入產品規模或重製價值。

## 一、結論先行

《Mayor Simulator》目前是**小至中型的單機城市治理 vertical slice／Internal Alpha**，不是僅有畫面的概念原型，但也尚未達到可無條件公開發行的 Beta。

| 結論 | 本輪判定 |
|---|---|
| 綜合分數 | **57 / 100** |
| 成熟度 | **Internal Alpha** |
| 距離免費 itch.io 公開版的功能完成度 | **55%–65%** |
| 當下發行就緒度 | **45%–55%** |
| 本輪有效自動測試 | **15 / 17 通過；2 失敗** |
| 產品規模 | **277 檔、95.914 MB、69 份 GDScript、18,944 行** |
| 主要內容 | **26 種建築、300 名持久化 NPC、5 個語系** |
| 市場重製價值 | **NT$420 萬–876 萬；中位建議 NT$620 萬** |
| 單人開發建議現金預算 | **NT$45,000–100,000；建議先保留 NT$80,000** |
| 單人開發建議無薪工時 | **450–750 小時**（Windows＋Linux 可靠公開版） |

判斷核心很直接：本專案已具備可運作的城市資金、建築、時間、人口、治理、司法監察、存檔與 UI 骨架；核心資料模型也有明顯工程投入。然而，**本輪兩個測試回歸、人口狀態的雙重來源風險、五語系缺口、發行授權文件缺失，以及尚未真正匯出與跨平台啟動**，使它仍停留在 Internal Alpha。

市場重製價值與使用者真正需要支付的現金是兩回事。NT$620 萬是第三方團隊從零重建目前成果的估算，不是使用者應立即支出的金額。若自己的工時不計薪資，建議先以 **NT$80,000 現金＋450–750 小時**完成 Windows／Linux 免費公開版；暫時不購買 VPS、雲端資料庫或 Mac 硬體。

## 二、證據標籤與判定規則

| 標籤 | 定義 |
|---|---|
| **本輪實測** | 2026-07-26 由 Godot 4.7 實際執行、解析 JSON 或檢視新擷取畫面。 |
| **靜態檢查** | 直接讀取本輪檔案、資料結構、程式分支或設定，但未以互動流程觸發。 |
| **文件宣稱但已漂移** | 文件曾記載一個結果，但目前程式、內容或測試已改變。 |
| **尚未驗證** | 本輪沒有對應硬體、解析度、輸入裝置、語系或正式發行包證據。 |

評分只承認前兩類證據。文件宣稱不會自動轉為完成度；尚未驗證也不會被推定為通過。

## 三、範圍、完整檔案盤點與分類

### 3.1 盤點方式

產品範圍逐檔走訪 `assets/`、`data/`、`docs/`、`scenes/`、`scripts/`、`systems/`、`tests/`、`tools/`、`ui/`、`ux/`，另加根目錄 `project.godot` 與 `export_presets.cfg`。沒有用抽樣檔案數推估整體。

初始工作區共 1,538 檔、約 506.1 MB；其中 `.godot` 匯入快取、歷史 artifacts、暫存、備份與上傳暫存佔很大比例。這些項目另列，不灌入產品規模。

### 3.2 產品範圍 100% 盤點

| 區域 | 檔案數 | 位元組 | 主要用途 |
|---|---:|---:|---|
| `assets/` | 96 | 94,605,415 | 背景、建築、NPC、UI 圖像及匯入 sidecar |
| `data/` | 27 | 416,304 | 建築、治理、人口、本地化與 JSON 資料庫 |
| `docs/` | 21 | 107,976 | 設計、開發、驗收與專案組織文件 |
| `scenes/` | 1 | 320 | 主場景 |
| `scripts/` | 46 | 399,417 | 核心、應用、系統與 UI 程式 |
| `systems/` | 6 | 50,710 | 獨立系統資料／模組 |
| `tests/` | 49 | 186,094 | unit、integration、UI 與擷取測試 |
| `tools/` | 6 | 13,589 | catalog 產生、搜尋與臨時修補工具 |
| `ui/` | 20 | 118,298 | UI 報告、資源與模組 |
| `ux/` | 3 | 11,344 | UX 設定／說明 |
| 根設定 | 2 | 4,545 | Godot 專案與匯出 preset |
| **合計** | **277** | **95,914,012** | **95.914 MB（十進位）／91.471 MiB** |

副檔名分布：70 個 `.uid`、69 個 `.gd`、45 個 `.import`、44 個 `.png`、26 個 `.md`、9 個 `.json`、4 個 `.zip`、3 個 `.py`、2 個 `.tscn`，以及各 1 個 `.cfg`、`.gdshader`、`.godot`、`.ps1`、`.svg`。

### 3.3 明確排除的非產品規模

| 排除區域 | 初始快照 | 判定 |
|---|---:|---|
| `.godot/` | 523 檔、約 209.0 MB | Godot 匯入與編輯器快取 |
| `artifacts/` | 639 檔、約 119 MB | 歷史測試、畫面與日誌證據 |
| `.tmp/` | 45 檔（測試後增加） | 暫存與本輪診斷輸出 |
| `.tmp.driveupload/` | 50 檔、約 24.4 MB | 上傳暫存 |
| `backups/` | 1 檔、約 57.6 MB | 備份封裝 |
| `_appdata/` | 3 檔（測試後增加） | 隔離的 Godot 使用者資料／測試存檔 |

`.git/` 目錄存在但沒有可用的 `HEAD` 或追蹤資料，根目錄也沒有 `.github/`。因此，本輪不能把版本歷史、CI 或可回復的 Git 基線計為已具備。

## 四、已驗證的產品內容

### 4.1 程式與模擬

- **[靜態檢查]** 69 份 GDScript，共 18,944 行。`scripts/app/main.gd` 單檔 4,052 行、約 227 個函式；`scripts/app/vertical_slice_coordinator.gd` 約 1,036 行、69 個函式。
- **[本輪實測]** 城市系統 unit 測試、300 人 population subsystem、30 人下議院獨立模型、司法監察模型均通過。
- **[靜態檢查]** 核心包含 CityState、Ledger、DomainEvent、SimCommand、SimulationKernel、GameSession、deterministic RNG/hash 與 atomic SaveService，顯示專案已超過單純 UI prototype。
- **[靜態檢查]** 經濟與治理涵蓋稅率、規費、維護費、政策、法案、滿意度、遷移、建築施工／拆除、司法與監察頁面。
- **[尚未驗證]** 沒有 12–24 個遊戲月的長時間平衡跑測、玩家留存、難度曲線或破產復原情境證據。

### 4.2 建築與治理內容

**[靜態檢查]** `data/catalogs/buildings.gd` 與 `data/catalogs/content_registry.gd` 共定義 26 種建築、10 個分類：

| 分類 | 數量 | 建築 |
|---|---:|---|
| 交通 | 5 | 停車場、公車站、捷運站、機場、加油站 |
| 休閒 | 3 | 公園、體育館、游泳池 |
| 安全 | 2 | 警局、消防局 |
| 行政 | 3 | 法院、監察所、市政府 |
| 住宅 | 2 | 住宅、社會住宅 |
| 商業 | 2 | 商店、大型商場 |
| 基礎建設 | 5 | 發電廠、瓦斯場、自來水廠、垃圾處理場、核能發電廠 |
| 教育文化 | 2 | 學校、圖書館 |
| 產業 | 1 | 工廠 |
| 醫療 | 1 | 醫院 |

另有 4 個政策、8 個法案定義。30 名下議院成員、5 個黨團、16 票門檻及 240 筆種子投票資料存在於獨立資料／測試範圍；司法與監察資料庫則有 15 名司法委員與 10 名監察委員。

**隔離界線：** 主遊戲 `scripts/systems/governance/governance_system.gd:530-538` 仍使用 7 個抽象投票 profile。因此 30 人下議院模型只算「可通過自測的獨立模組」，不算「已整合主遊戲」功能。

### 4.3 NPC、存檔與資料

- **[本輪實測]** `scripts/systems/population/population_system.gd:12-14` 預設建立 300 名持久化 NPC、上限 500、最多 80 個可見代理；主地圖在 `scripts/app/main.gd:1561` 取 24 個代理繪製。
- **[本輪實測]** 新遊戲、繼續遊戲與 autosave flow 測試通過。
- **[靜態檢查]** `scripts/core/save_service.gd:27-60` 以 `.tmp` 寫入後 rename，保留一代 `.bak`；`63-74` 在主檔失敗時讀取備份。這比直接覆寫 JSON 安全。
- **[本輪實測]** 產品範圍 9 個 JSON 加上 2 個 playtest JSON，共 **11/11 可解析**；測試另外產生的 4 個存檔也 **4/4 可解析**。
- **[尚未驗證]** 沒有 checksum、schema migration 壓力測試、多代備份、磁碟空間不足、斷電點注入或故意破壞主檔＋備份的完整復原矩陣。

### 4.4 本地化

- **[靜態檢查]** 五個 catalog：`zh_TW`、`zh_CN`、`en`、`ja`、`ko`，每份 1,241 keys；manifest 的來源字串數是 1,280，產生時間 2026-07-24。
- **[靜態檢查]** manual overrides 數量為 zh_TW 88、zh_CN 142、en/ja/ko 各 140。
- **[本輪實測]** localized runtime view-model test 通過 139 項。
- **[本輪實測]** 完整 localization UI test 失敗 40 項，直接看見「游泳池」、「加油站」、「核能發電廠」在英文與韓文頁面殘留漢字，並出現「核能power plant」等混合結果。
- **[靜態檢查]** 五份 catalog 與 overrides 都沒有三個新增建築的完整名稱／描述映射。測試對日文、簡中漢字的容忍規則也不能證明語意已正確翻譯。

結論：專案有五語基礎設施，但「系統內所有文字均顯示該語言」目前**不成立**。

### 4.5 美術與音訊

- **[靜態檢查]** 44 個 raster 圖像、45 個 `.import` sidecar、4 個來源 zip；未發現重複圖像 hash 或孤兒 `.import`。
- **[靜態檢查]** 主背景為 1672×941，多數 UI／建築圖標為 256×256。背景與插圖具可辨識的童話城市方向。
- **[本輪實測]** 新畫面中 UI 卡片、圖示、背景與建築選單整體清楚，但地圖 NPC 周圍仍可見脫離角色的黑色短線碎片，且若干 NPC 站在水面、樹叢或純裝飾地形上；背景不是可供代理理解的地形導航資料。
- **[靜態檢查]** 沒有 `.wav`、`.ogg`、`.mp3`、`.flac` 或 `.m4a`，即目前沒有可交付的音效或配樂資產。
- **[靜態檢查]** 根目錄沒有 `LICENSE`、`NOTICE`、`COPYING` 或 `CREDITS`。四個來源 zip 與生成／引用圖像仍需逐一建立授權及來源台帳。

## 五、本輪測試與視覺驗收

### 5.1 自動測試：15 / 17 通過

執行引擎為 `Godot 4.7.stable.official.5b4e0cb0f`。為避免 `user://` 權限污染，`APPDATA` 與 `LOCALAPPDATA` 指向專案內隔離目錄。

| # | 測試 | 結果 | 關鍵證據 |
|---:|---|---|---|
| 1 | `tests/unit/systems/systems_self_test.gd` | 通過 | systems self-test passed |
| 2 | `tests/unit/population/population_self_test.gd` | 通過 | NPCs=300，deterministic hash |
| 3 | `tests/unit/governance/lower_council_self_test.gd` | 通過 | Members=30，Votes=300 |
| 4 | `tests/unit/governance/justice_oversight_self_test.gd` | 通過 | Members=25，司法／監察案件各 1 |
| 5 | `tests/integration/vertical_slice_test.gd` | **失敗** | 測試仍要求建築數等於 23 |
| 6 | `tests/integration/start_screen_flow_test.gd` | 通過 | 新遊戲／繼續／loading flow |
| 7 | `tests/integration/main_integration_test.gd` | 通過 | main integration passed |
| 8 | `tests/integration/localization_test.gd` | **失敗** | 40 個 UI 語系錯誤 |
| 9 | `tests/integration/localized_runtime_view_model_test.gd` | 通過 | 139 checks |
| 10 | `tests/integration/context_requests_time_test.gd` | 通過 | 建築 context、NPC 請求、自動時間 |
| 11 | `tests/integration/redundancy_audit_test.gd` | 通過 | Residents=300、Councilors=30、Committee=25 |
| 12 | `tests/ui/vertical_slice_panel_state_test.gd` | 通過 | panel state |
| 13 | `tests/ui/governance_status_tabs_test.gd` | 通過 | Policies=4、Bills=8、Tabs=3 |
| 14 | `tests/ui/npc_actor_visual_test.gd` | 通過 | actor visual-state |
| 15 | `tests/ui/placement_interaction_regression_test.gd` | 通過 | placement interaction |
| 16 | `tests/ui/fiscal_slider_pointer_test.gd` | 通過 | pointer value=160 |
| 17 | `tests/ui/settings_overlay_style_test.gd` | 通過 | settings light/dark state |

第一批 runner 有 8 個過時檔名，造成「找不到檔案」；本輪先用實際檔案清單找回正確路徑並全部重跑。這 8 個 runner 錯誤不算產品失敗，也不拿來稀釋分母。有效矩陣固定為上表 17 組。

### 5.2 兩個明確回歸

1. **建築數回歸：** `tests/integration/vertical_slice_test.gd:51` 寫死 `buildings.size() == 23`，但 registry 已是 26 種。這是測試維護失敗，不是 26 種建築內容不存在。
2. **五語本地化回歸：** 新增核能發電廠、加油站、游泳池後，catalog 與 override 未同步；UI 實測 40 個錯誤。這是玩家可見的產品回歸。

過去文件中的「1007／1012 項垂直切片檢查通過」已漂移，不能代表 2026-07-26 現況。可見 `docs/project-organization/VALIDATION_REPORT.md:39`、`PICTURE_FIRST_UI_REPORT.md:34`、`UI_VISUALIZATION_REPORT.md:59`、`REDUNDANCY_AUDIT.md:75`。

### 5.3 目標解析度視覺驗收

**[本輪實測]** 在隔離的完整產品副本重新匯入資源後，執行 `tests/ui/capture_ui_readability.gd`；實體畫面為 **2880×1800**、測試邏輯畫面 **1280×800**。23 個畫面狀態的結構與文字可讀性檢查通過：

- 起始頁、loading、主地圖、陰天、雨天；
- 設定（明亮／英文深色）；
- 建築 context 與建造流程；
- 市政首頁及九個市政頁：建築、治理、司法、監察、藍圖審核、財政、公共事務、城市資料、施政報告；
- 治理待審／已實施、藍圖待審／深色；
- 離開確認。

這個結果只能證明**一個**目標配置。`project.godot:23-24` 的預設 viewport 實際是 1280×720，與測試邏輯 1280×800 不同。下列項目仍屬證據缺口：

- 1366×768、1920×1080、4K、縮放 125%／150%／200%；
- 超寬、視窗化縮放、低階 GPU；
- 手把、純鍵盤、觸控、螢幕閱讀器；
- 色弱、減少動態、字幕／音量設定；
- 五語長字串在每一頁、每一狀態的截圖驗收。

## 六、架構與資料完整性判讀

### 6.1 優點

1. 核心 command/event/state/ledger 分離，並有 deterministic 自測，適合持續做模擬回歸。
2. SaveService 採 temp＋rename＋一代 backup，不是直接破壞式覆寫。
3. 300 名 NPC 為持久化 record，畫面只取代理，方向正確。
4. 建築 catalog、ID registry、視覺映射與測試已形成可追蹤鏈。
5. UI 頁面雖多，但目標解析度的實際可讀性已經有新證據，不只靠靜態 scene 判斷。

### 6.2 關鍵架構風險

#### A. 人口有兩個權威來源

**[靜態檢查；發布前必須以測試確認]**：

- `scripts/app/main.gd:2661-2668` 在建築套用時直接增加 main 的 `population`；
- `scripts/app/main.gd:2670-2676` 拆除時扣回其他指標，卻沒有扣回人口；
- `scripts/app/main.gd:2772-2780` 同步時又用 persistent population record 數覆寫 main 的 `population`。

因此建築或法案的人口效果可能被同步抹掉，或在拆除後不能對稱復原。這不是本輪已觸發的 runtime bug 證明，但它是明確的狀態權威衝突，應列 P0，先寫最小重現測試，再決定 population record 或城市 metric 誰是唯一真實來源。

#### B. 應用層過度集中

`scripts/app/main.gd` 4,052 行，同時承擔 UI 建立、輸入、經濟、治理、建築、存檔協調與本地化格式化。這會讓任何小改動同時觸發 UI、資料與存檔風險。核心 classes 雖然比 UI 層乾淨，但主應用仍是維護瓶頸。

#### C. 本地化採最終字串替換

目前 exact／regex／substring 的補丁式替換會生成混合語句。動態字串應改用穩定 key、語系 template 與已翻譯變數組合；對已格式化完成的任意句子做 substring 翻譯，無法保證語意與文法。

#### D. 工具與專案衛生

`tools/capture_screenshots.gd` 有個人環境路徑；`scratch_fix_json.py`、`scratch_fix_json_all.py`、`scratch_search.py` 是臨時工具，其中修補腳本會直接改 localization。它們不應出現在正式 release workflow，至少要標明用途、dry-run、輸入輸出與備份策略。

## 七、100 分加權評分

| 指標 | 權重 | 得分 | 證據與扣分理由 |
|---|---:|---:|---|
| 功能性與模擬深度 | 20 | **13** | **[本輪實測]** 基礎 loop、時間、人口、治理、建造與財政可跑；**[尚未驗證]** 缺長時平衡；人口雙權威待修。 |
| 資料、存檔及本地化完整度 | 15 | **9** | **[本輪實測]** 11/11 JSON、new/continue/autosave 通過；本地化 40 fail，存檔缺完整破壞復原矩陣。 |
| 整體架構與可維護性 | 15 | **9** | **[靜態檢查]** core 分層、determinism、atomic save 良好；`main.gd` 巨型化、狀態來源不一。 |
| 美術、音訊與風格一致性 | 15 | **6** | **[本輪實測]** 背景與 UI 有風格；NPC 碎片與地形穿插；沒有任何可交付音訊，授權台帳缺失。 |
| UI 可讀性與響應式設計 | 10 | **8** | **[本輪實測]** 2880×1800／1280×800 的 23 狀態通過；其他解析度、DPI 與預設 1280×720 尚未驗證。 |
| UX、教學、輸入與無障礙 | 10 | **5** | **[靜態檢查]** 主要頁面與離開確認齊；缺教學、手把、純鍵盤、色弱、減少動態與輔助科技證據。 |
| 測試、版本控制與發行工程 | 10 | **4** | **[本輪實測]** 15/17；沒有有效 Git history／CI、匯出模板、正式包或跨平台啟動證據。 |
| 內容量、平衡及文件一致性 | 5 | **3** | **[靜態檢查]** 26 建築、300 NPC、治理資料有量；長期平衡未測，5×5／23 建築／舊通過數等文件漂移。 |
| **總分** | **100** | **57** | **Internal Alpha** |

57 分不是「只完成一半程式」的機械換算，而是發行風險加權後的產品成熟度。專案在核心工程與 UI 廣度上高於一般 early prototype，但在內容驗收、發行工程、音訊與跨平台證據上明顯落後。

## 八、風險清單與處理順序

### P0：公開版前阻斷

| 風險 | 影響 | 最小完成條件 |
|---|---|---|
| 人口雙重權威與拆除不對稱 | 數值被覆寫、存檔後狀態不一致 | 先建 runtime regression test；確立單一權威；建造／拆除／跨日／讀檔全通過 |
| 26 vs 23 測試回歸 | CI／release gate 永遠紅燈 | 測試從 registry 或明確版本資料取得預期數，不再散落 magic number |
| 三個新建築造成五語失敗 | 玩家直接看到混合語言 | 補 key/template/變數翻譯；五語所有頁面與 runtime 字串通過 |
| 授權、CREDITS、來源台帳缺失 | 不能證明素材可合法散布 | 每項外部／生成資產列來源、授權、修改與歸屬；附 Godot 授權聲明 |
| 無匯出模板與正式包 | 目前沒有可交付執行檔 | 安裝相符 4.7 template；Windows／Linux export、乾淨機啟動、存讀檔、打包 hash |

### P1：可靠公開版

| 風險 | 改善 |
|---|---|
| 存檔只保留一代 backup，缺 checksum／migration 壓測 | 建 corrupt/truncate/old-schema/full-disk 測試與明確復原 UI |
| 單一解析度證據 | 建 1366×768、1080p、4K、125%–200% DPI 矩陣 |
| 缺教學、手把、完整鍵盤與無障礙 | 做 10–15 分鐘 onboarding、focus order、rebind、色弱與減少動態設定 |
| NPC 碎片、站水面與風格落差 | 修 animation atlas/anchor；建立地形 mask／walkable graph；逐畫面 QA |
| 完全無音訊 | 至少補 UI、建造、警告、天候與一組可循環背景音；提供總音量與靜音 |
| `main.gd` 過大、臨時工具混入 | 拆 UI presenter／input／economy adapter；隔離或移除 scratch workflow |
| 沒有有效 VCS／CI 證據 | 建 Git baseline、ignore `.godot`/tmp、每次提交跑 17-test gate 與 JSON parse |

### P2：接近商用品質

- 外部玩家的 3–5 輪 usability test 與缺陷追蹤；
- 12–24 個遊戲月的平衡模擬、極端稅率／費率／人口情境；
- 專業英文／日文／韓文校對與各語系畫面驗收；
- macOS Developer ID 簽章、公證、實機 Gatekeeper 測試；
- 建築個別視覺、完整音效／音樂、效能與低階硬體驗證；
- 30 人下議院模型整合（選配，不計入目前主遊戲完成度）。

## 九、後續工量

換算統一採 **1 人月＝160 小時**。以下是修到目標狀態的工作，不是重建既有成果。

| 階段 | 工時 | 人月 | 主要成果 |
|---|---:|---:|---|
| P0 發行阻斷 | 180–320 h | 1.1–2.0 | 狀態權威、兩回歸、授權、templates、Windows/Linux smoke |
| P1 可靠公開版 | 270–430 h | 1.7–2.7 | save recovery、教學、解析度／輸入、NPC 修復、基本音訊、CI |
| P2 接近商用品質 | 450–750 h | 2.8–4.7 | 外部 QA、專業校對、美術音訊 polish、macOS、長期平衡 |
| **累計** | **900–1,500 h** | **5.6–9.4** | 從目前 Internal Alpha 到接近商用品質 |

30 人下議院主遊戲整合另估 **80–160 小時（0.5–1.0 人月）**，包含 UI、存檔 migration、30 票可解釋性、效能與回歸；這是選配，不應在修完 P0 前插入主線。

## 十、市場重製價值

### 10.1 這個數字代表什麼

市場重製價值是假設第三方團隊今天從零重建出「目前可看到、可執行、可測試的成果」需要的工量與市場成本。它不是售價、融資估值、未來營收，也不是依程式碼行數乘單價。

### 10.2 官方基準與估算方法

1. 勞動部 2026-05-29 發布的 114 年職類別薪資調查，專業人員平均月薪約 NT$68,000；出版影音及資通訊業專業人員約 NT$71,000、主管約 NT$101,000。這些是受僱薪資基準，不是承攬報價。
2. 數位發展部與行政院公共工程委員會 2024 年《政府資訊服務採購經費估算編列手冊》要求以 WBS、人月、直接薪資、休假／福利／獎金、管理費、利潤與稅等組成估算，並檢查市場合理性。
3. 舊《資訊服務委外經費估算原則》已於 2023-02-07 停止參考，本報告不把它當現行費率表。

依此建立**本案假設單價**，不是政府公告價：工程 NT$190k–240k／人月、UI/UX NT$170k–220k、美術／音訊 NT$150k–220k、資料／本地化 NT$140k–190k、QA／發行／文件／PM NT$140k–190k。單價已含薪資之外的雇主負擔、管理、設備、風險、利潤與稅的概念性空間。

### 10.3 WBS 重建估算

| 工作包 | 工時 | 人月 | 假設單價／人月 | 未含風險成本 |
|---|---:|---:|---:|---:|
| 工程、模擬、存檔、治理 | 1,400–2,000 h | 8.75–12.50 | 190k–240k | 1.663M–3.000M |
| UI/UX 與互動流程 | 560–800 h | 3.50–5.00 | 170k–220k | 0.595M–1.100M |
| 現有美術、動畫與視覺整合 | 480–800 h | 3.00–5.00 | 150k–220k | 0.450M–1.100M |
| 資料、內容與五語基礎 | 320–480 h | 2.00–3.00 | 140k–190k | 0.280M–0.570M |
| QA、發行、文件與 PM | 760–1,040 h | 4.75–6.50 | 140k–190k | 0.665M–1.235M |
| **小計** | **3,520–5,120 h** | **22–32** | — | **3.653M–7.005M** |

公式：

`重製價值 = Σ（工作包人月 × 該角色承攬單價）×（1 + 風險準備）`

- 低案：NT$3.653M × 1.15 = **NT$4.20M**；
- 中案：約 NT$5.146M × 1.20 = **NT$6.18M**；
- 高案：NT$7.005M × 1.25 = **NT$8.76M**。

因此本報告給出 **NT$420 萬–876 萬，中位建議 NT$620 萬**。在沒有實際 timesheet、正式詢價與素材授權證明前，應把它視為約 ±30% 精度的 replacement-cost estimate。

## 十一、單人開發的實際現金預算

### 11.1 三個級距

自己的時間不列薪資，但必須另外揭露無薪工時。

| 級距 | 現金預算 | 無薪工時 | 適合目標 | 包含／限制 |
|---|---:|---:|---|---|
| 最低可發布 | **NT$0–15,000** | **180–320 h** | Windows-first 免費 itch.io，Linux best effort | Godot/templates/itch.io 為 0；使用既有硬體、免費 VM/Live USB、志願測試；只買必要備份或少量測試補貼。品質與語系覆蓋有限。 |
| 建議可靠版 | **NT$45,000–100,000** | **450–750 h** | Windows＋Linux 可重複驗證的免費公開版 | 獨立備份、外部 tester 補貼、授權音效／素材、語系校對、發行預備金。**建議保留 NT$80,000。** |
| 接近商用品質 | **NT$150,000–350,000** | **900–1,500 h** | 三平台、較完整美術音訊與外部 QA | 專業 QA、翻譯校對、美術／音訊 polish、macOS 簽章公證與實機測試；若無 Mac 可借／租，硬體另計。 |

建議可靠版的概念性拆分如下，不是報價單：

| 項目 | 建議區間 |
|---|---:|
| 獨立備份媒體與替換預備 | NT$3,000–7,000 |
| 外部 tester 補貼／測試設備借用 | NT$12,000–30,000 |
| 授權 UI SFX、環境音與基礎音樂 | NT$5,000–20,000 |
| 英／日／韓重點頁面母語校對 | NT$10,000–25,000 |
| 授權清理、發行雜支與風險預備 | NT$10,000–20,000 |

實際採購前仍應取得 2–3 份詢價；若找到可商用免費 CC0/MIT 資源或志願 tester，現金可下降，但授權台帳與驗證工時不會消失。

### 11.2 平台別判斷

| 平台 | 現況 | 必要成本 | 本輪結論 |
|---|---|---:|---|
| Windows | 有 preset；`export_path` 空白；沒有 4.7 templates；`codesign/enable=false` | Godot、templates、itch.io 可 NT$0；code signing 選配 | **尚未形成正式包**。先做 unsigned 免費版可行，但須測 SmartScreen、乾淨機啟動、存讀檔與移除流程。 |
| Linux | 有 preset；沒有 templates；只有 Windows 硬體 | 免費 VM、Live USB、志願 tester 可 NT$0 | **尚未實機驗證**。不要因沒有 Linux 主機就直接宣稱支援。 |
| macOS | 沒有 preset、沒有 templates、沒有 Mac 硬體 | 未簽章版可免費但有 Gatekeeper 摩擦；Developer ID 簽章／公證通常需 Apple Developer Program | **不應列為目前可發布**。可先從 Windows 產生 zip，但仍需 Mac 實機與公證流程驗證。 |

Apple Developer Program 為 **US$99／會員年**。以臺灣銀行 2026-07-24 USD 即期賣出 **32.46** 試算，純會員費約 **NT$3,214／年**；實際刷卡、稅費與 Apple 在地定價以付款日為準。

### 11.3 明確不建議的支出

- **VPS／雲端資料庫／常駐後端：NT$0。** 本專案是離線 JSON 單機遊戲，現階段新增後端只會增加資安、維運與個資成本。
- **Godot 授權費／權利金：NT$0。** 但散布 binary 必須附 Godot copyright 與 MIT license notice，或提供可存取的授權連結。
- **itch.io 上架費：NT$0。** 可設最低價格為 0；收入分成設定與付款處理費是發生收入後的商業決策。
- **Codex 月費：不列必需成本。** 只有它確實是為此專案新增、且原本不會支付的費用，才列入專案現金流。
- **立即購買 Mac：不建議。** 先用借機、租用、外部 tester 或測試服務證明 macOS 需求，再決定是否購入長期硬體。

## 十二、建議執行路線

### Gate 1：恢復可信基線（約 60–120 小時）

1. 為人口雙權威建立最小重現測試並修正單一來源；
2. 移除 23 的 magic number，讓 26 種建築 registry／測試一致；
3. 以 key/template 補完三個新增建築五語字串，讓 17/17 通過；
4. 建 Git baseline 與 ignore，確保 `.godot`、tmp、存檔不污染版本庫。

### Gate 2：做出可驗證 Windows／Linux 包（約 120–200 小時）

1. 安裝相符 Godot 4.7 export templates；
2. 產生 versioned build、SHA-256、授權檔、CREDITS、操作說明；
3. Windows 乾淨機與 Linux VM／Live USB 做啟動、建造、存檔、讀檔、離開 smoke；
4. 注入破損存檔並確認 `.bak` 復原及玩家提示。

### Gate 3：公開測試版（再投入約 270–430 小時）

1. 做 10–15 分鐘新手教學；
2. 完成解析度／DPI／鍵盤與基本無障礙矩陣；
3. 修 NPC 碎片與 walkable terrain，加入最低可接受音訊；
4. 找 5–10 名外部 tester，以 issue list 驗收 P0/P1；
5. 免費 itch.io 發布 Windows／Linux Internal Beta。

### Gate 4：再決定 macOS 與 30 人下議院

先看公開測試的真實需求。若 macOS 使用者與治理深度確有價值，再分別啟動 Developer ID／公證與下議院整合；不要在核心可信度尚未恢復前同時擴張兩條高風險支線。

## 十三、文件漂移與證據缺口

| 項目 | 舊文件／現況 | 判定 |
|---|---|---|
| 地圖大小 | `docs/development/godot_mvp_notes.md:5` 仍寫 5×5；目前主循環為 8×8 | 文件漂移 |
| 建築縮圖 | `BUILDING_BLUEPRINT_UX_REPORT.md:47` 寫 23 種；現為 26 | 文件漂移 |
| 完成度 | `INTERNAL_TEST_READINESS.md:10` 寫 88/100 | 歷史自評，不代表本輪 57/100 |
| 測試通過數 | 多份報告寫 1007／1012 全通過 | 已被本輪 2 fail 取代 |
| 美術定位 | style guide 要求 2.5D isometric city builder | 目前是 painted static map＋overlay，尚非完整 tile/isometric world |
| 三平台 | Windows/Linux preset、無 macOS preset；templates 為 0 檔 | 三平台均無正式 release artifact 證據 |
| UI 響應式 | 單一 2880×1800／1280×800 pass | 其他解析度、DPI、輸入法尚未驗證 |
| 本地化 | 五份 catalog 存在 | runtime 完整度 fail，不得以 key 數冒充完成 |

## 十四、限制

1. 本輪沒有 macOS／Linux 實體機，也沒有 Godot 4.7 export templates，因此沒有執行三平台正式匯出與簽章／公證。
2. 視覺驗收是單一實體／邏輯解析度，且測試自動化無法取代真人 usability test。
3. 市場重製價值沒有 timesheet、正式採購案、供應商報價與逐項素材授權成本，故保留約 ±30% 誤差。
4. 本報告沒有做長時間遊戲平衡、效能 profiling、惡意存檔／安全測試或外部玩家研究。
5. 本輪所有程式與資料缺陷都是「依現有檔案與測試」判定；人口雙權威屬高可信靜態風險，仍應以新增 runtime test 作最後定案。

## 十五、官方引用來源

- [勞動部：114 年職類別薪資調查統計結果](https://www.mol.gov.tw/1607/1632/1633/90814/)（2026-05-29）
- [數位發展部、行政院公共工程委員會：政府資訊服務採購經費估算編列手冊（2024-04）](https://general.chcg.gov.tw/files/12_20240507165605062_%E8%A1%8C%E6%94%BF%E9%99%A2%E5%85%AC%E5%85%B1%E5%B7%A5%E7%A8%8B%E5%A7%94%E5%93%A1%E6%9C%83113%E5%B9%B45%E6%9C%881%E6%97%A5%E5%B7%A5%E7%A8%8B%E4%BC%81%E5%AD%97%E7%AC%AC1130007769%E8%99%9F%E5%87%BD%E9%99%84%E4%BB%B6%E6%94%BF%E5%BA%9C%E8%B3%87%E8%A8%8A%E6%9C%8D%E5%8B%99%E6%8E%A1%E8%B3%BC%E7%B6%93%E8%B2%BB%E4%BC%B0%E7%AE%97%E7%B7%A8%E5%88%97%E6%89%8B%E5%86%8A.pdf)
- [Godot 官方授權說明](https://godotengine.org/license/)
- [Godot 4.7：Exporting for macOS](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)
- [Godot：Exporting projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)
- [Apple Developer Program：Membership Details](https://developer.apple.com/programs/whats-included/)
- [itch.io Creator FAQ](https://itch.io/docs/creators/faq)
- [臺灣銀行 2026-07-24 美金牌告匯率](https://rate.bot.com.tw/xrt/quote/ltm/USD/spot/1?Lang=zh-TW)

## 十六、最終決策建議

目前最理性的路線是：

1. 先投入 **180–320 小時**清掉 P0，做到 17/17、授權可追溯、Windows/Linux 可匯出；
2. 再以總計 **450–750 小時＋NT$45,000–100,000**完成可靠免費公開版；
3. 現金先保留 **NT$80,000**，優先花在備份、外部 QA、語系校對與合法音訊，不買 VPS；
4. macOS 與 30 人下議院維持獨立選項，待公開測試證明需求後再投資；
5. 對外描述應使用「Internal Alpha／免費公開測試準備中」，不可宣稱三平台已可發布或五語已完成。

這樣能用最低現金，把最大的風險先轉成可重複驗證的證據，而不是繼續增加功能數量。
