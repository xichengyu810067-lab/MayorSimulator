# 專案檔案用途索引

本索引是主要入口與人工閱讀指南，不是完整機器 manifest，也不聲稱逐列目前所有受管理檔案。完整來源集合與
逐檔 SHA-256 應由 `tools/source_fingerprint.ps1` 在當次驗收中產生；Godot 自動產生的 `.godot/` 快取不列入。
同名 `.uid`、`.import` 的規則見文末。

## 根設定與場景

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `project.godot` | 應用程式 | Godot 專案名稱、主場景、視窗與渲染設定；必須位於根目錄。 |
| `export_presets.cfg` | 發行 | 平台匯出選項與封裝設定；必須位於根目錄。 |
| `RELEASE_README.txt` | 發行 | 兩平台內測 staging 必附的啟動、存檔、法律與禁止公開散布說明。 |
| `scenes/Main.tscn` | 應用程式 | 唯一主場景，掛載 `scripts/app/main.gd`。 |

## 資料目錄與資料庫

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `data/catalogs/buildings.gd` | 城建 | 所有建築的成本、效果、維護與顯示資料。 |
| `data/catalogs/policies.gd` | 治理 | 可提出政策／法案的內容定義。 |
| `data/catalogs/content_registry.gd` | 共用資料 | 將舊內容轉成穩定 ID，集中提供建築、材料、區域、職業與平衡參數。 |
| `data/schemas/balance_parameters.gd` | 模擬核心 | 工人、施工、薪資與模擬平衡參數結構。 |
| `data/schemas/building_definition.gd` | 城建 | 單一建築定義的欄位與字典序列化格式。 |
| `data/schemas/law_template.gd` | 治理 | 法案模板欄位與序列化格式。 |
| `data/schemas/material_definition.gd` | 城建 | 建材成本、工作量與樓層能力的資料結構。 |
| `data/schemas/profession_definition.gd` | 人口 | 職業收入、教育門檻與標籤的資料結構。 |
| `data/schemas/zone_definition.gd` | 城建 | 分區允許建築類型的規則與資料結構。 |
| `data/databases/governance/lower-council/councilors.json` | 下議院 | 30 位議員、性別、性格、關注點、行為參數及歷史投票主資料。 |
| `data/databases/governance/justice-oversight/committee_members.json` | 司法與監察 | 15 位司法委員與 10 位監察委員的任期、性格及重大案件主資料。 |

## 應用程式與模擬核心

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `scripts/app/main.gd` | 應用程式 | 建立主畫面、城市格、NPC、各市政頁面並轉送玩家操作。 |
| `scripts/app/city_report_history_service.gd` | 應用程式 | 集中月報、重大事件、有限歷史、清理與快照／還原責任，避免由 Main 重複持有。 |
| `scripts/app/vertical_slice_coordinator.gd` | 應用程式 | 協調時間、城建、人口、治理、司法、存檔與 UI view model。 |
| `scripts/core/city_state.gd` | 模擬核心 | 保存城市財政、建築、治理、人口與日期等權威狀態。 |
| `scripts/core/domain_event.gd` | 模擬核心 | 表示可排序、可保存的領域事件。 |
| `scripts/core/game_session.gd` | 模擬核心 | 組合核心服務並提供新遊戲、載入、存檔與推進流程。 |
| `scripts/core/ledger.gd` | 財政 | 記錄資金交易與餘額。 |
| `scripts/core/save_envelope.gd` | 存檔 | 包裝存檔版本、校驗與遊戲狀態。 |
| `scripts/core/save_service.gd` | 存檔 | 負責存檔檔案寫入、讀取與格式驗證。 |
| `scripts/core/sim_command.gd` | 模擬核心 | 定義送入模擬核心的命令資料。 |
| `scripts/core/simulation_clock.gd` | 時間 | 管理遊戲日、年與時間推進。 |
| `scripts/core/simulation_kernel.gd` | 模擬核心 | 依序處理命令、修改城市狀態並發出事件。 |

## 城建、治理、人口系統

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `scripts/systems/city/construction_system.gd` | 城建 | 藍圖審核、施工工作量、工人配置、完工與拆除流程。 |
| `scripts/systems/city/durability_system.gd` | 建築耐久 | 建築耐久衰減、事故、效率、維護與修繕。 |
| `scripts/systems/governance/governance_system.gd` | 治理 | 法案審查、上下議院表決、強制施行、司法案件與監察案件整合。 |
| `scripts/systems/population/event_book.gd` | 人口 | 保存人口系統事件並提供穩定排序。 |
| `scripts/systems/population/npc_record.gd` | 人口 | 單一 NPC 的人口、職業、態度與關係資料。 |
| `scripts/systems/population/population_request.gd` | 人口 | 市民請求的生命週期、條件與序列化。 |
| `scripts/systems/population/population_system.gd` | 人口 | 建立人口、就業媒合、政策態度、市民請求、年度推進與存檔。 |

## 自治治理模組

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `systems/governance/lower-council/lower_council_database.gd` | 下議院 | 載入與驗證 30 位議員，管理動態狀態、投票歷史及存檔。 |
| `systems/governance/lower-council/lower_council_vote_model.gd` | 下議院 | 依議員關注點、黨團、民意、財政、風險與辯論計算個別票。 |
| `systems/governance/justice-oversight/justice_oversight_system.gd` | 司法與監察 | 管理委員任期、一人一職、審判、調查、彈劾、個別票與存檔。 |

## 世界與渲染

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `scripts/world/city_backdrop.gd` | 世界畫面 | 載入城市背景圖並繪製場景底層。 |
| `scripts/world/city_tile_button.gd` | 世界畫面 | 繪製可互動城市格與各類建築外觀。 |
| `scripts/world/npc_actor.gd` | 世界／人口 | 繪製可互動 NPC、職業服裝與步行狀態。 |
| `scripts/rendering/painterly.gdshader` | 渲染 | 提供繪本風格的畫面後製著色效果。 |

## UI 與 UX

| 檔案 | 系統 | 用途 |
| --- | --- | --- |
| `ui/shell/vertical_slice_panel.gd` | 主介面 | 顯示城市摘要、財政、治理、建築、請求與回報區塊。 |
| `ui/shell/municipal_overlay.gd` | 市政中心 | 建立市政中心導覽、頁面切換與模態視窗骨架。 |
| `ui/shell/building_context_panel.gd` | 建築情境操作 | 點擊既有建築後顯示樣式、屋頂、外觀、維護與拆除。 |
| `ui/shell/public_affairs_panel.gd` | 民情中心 | 自動彙整全部有效 NPC 陳情並提供受理操作。 |
| `ui/shell/exit_confirm_overlay.gd` | 應用程式 | 顯示離開遊戲確認視窗並處理確認／取消。 |
| `ui/shell/start_screen.gd` | 初始畫面 | 使用城市底圖顯示新遊戲、繼續遊戲與共用載入進度動畫。 |
| `ui/governance/justice_oversight_panel.gd` | 司法與監察 | 依模式建立獨立法院／監察頁，顯示大型插圖、案件、委員與辯護操作。 |
| `ux/specifications/美編規格書.md` | UX／美術 | 記錄色彩、字級、版面與視覺體驗規格。 |

## 測試程式

| 檔案 | 層級 | 用途 |
| --- | --- | --- |
| `tests/unit/systems/systems_self_test.gd` | 單元 | 驗證施工、耐久、治理、司法整合與存檔。 |
| `tests/unit/population/population_self_test.gd` | 單元 | 驗證人口生成、就業、關係、請求、年度推進與存檔。 |
| `tests/unit/governance/lower_council_self_test.gd` | 單元 | 驗證 30 位議員資料、投票模型、歷史與存檔。 |
| `tests/unit/governance/justice_oversight_self_test.gd` | 單元 | 驗證 15／10 委員、任期、一人一職、審判、彈劾與存檔。 |
| `tests/integration/vertical_slice_test.gd` | 整合 | 驗證內容目錄、建造／拆除、司法建築、長期模擬與存檔往返。 |
| `tests/integration/multiseed_long_soak_test.gd` | 整合 | 以多組種子長局驗證有限值、確定性與輸出分布；不把穩定性冒充正式平衡。 |
| `tests/integration/main_integration_test.gd` | 整合 | 實例化主場景並驗證 UI、建築、背景、司法頁與互動整合。 |
| `tests/integration/context_requests_time_test.gd` | 整合 | 驗證建築五功能、全部 NPC 陳情、120 秒換日與失焦暫停。 |
| `tests/integration/redundancy_audit_test.gd` | 整合 | 驗證功能唯一入口、資料唯一來源與人物資料無重複。 |
| `tests/integration/start_screen_flow_test.gd` | 整合 | 驗證空白新遊戲、無存檔提示、跨實例續玩、完整玩家狀態、進度動畫、時間暫停及三類自動儲存。 |
| `tests/ui/capture_main_ui.gd` | UI 擷取 | 啟動主場景並輸出主畫面截圖。 |
| `tests/ui/capture_ui_readability.gd` | UI 擷取 | 依序擷取主頁、市政中心、法院、監察、治理、財政、藍圖與離開視窗，並實際提交兩種辯護。 |
| `tests/ui/playtest_building_blueprint_flow.gd` | UI 實玩 | 使用實際按鈕完成選建築、藍圖送審、日期推進、地圖開工與完工。 |
| `tests/ui/playtest_fiscal_warnings.gd` | UI 實玩 | 驗證六個財政分類與低／建議／高費率的黃綠紅狀態；內容未溢出時不得出現虛假捲動範圍，短畫面溢出時則須能捲到底、逐一捲入全部 14 項財政控制，並在驗收後恢復頁籤與捲動位置。 |
| `tests/helpers/fiscal_scroll_contract.gd` | UI 共用契約 | 依實際內容高度判斷財政頁是否需要捲動，驗證 range、實體位移、14 個控制可達與狀態還原。 |

## 驗收與發行工具

| 檔案 | 用途 |
| --- | --- |
| `tools/run_assertion_matrix.ps1` | 依唯一 manifest 隔離執行完整斷言矩陣並產生 append-only summary。 |
| `tools/run_save_os_kill_qa.ps1` | 在五個原子存檔階段強制終止 writer，重啟驗證 primary／backup 與語意恢復。 |
| `tools/run_ui_capture_acceptance.ps1` | 產生本輪獨立 33 張 2880×1800 截圖，驗證 PNG／SHA／診斷與來源前後一致。 |
| `tools/source_fingerprint.ps1` | 對發行範圍內所有檔案建立 canonical path／bytes／SHA-256 總指紋。 |
| `tools/write_release_evidence.ps1` | 單次重跑矩陣、OS-kill、import、雙平台匯出、Windows smoke、封裝並原子發布證據。 |
| `tools/package_release.ps1` | 驗證精確五檔 staging，建立 Windows ZIP、Linux TAR.GZ 與 SHA256SUMS。 |
| `tools/generate_runtime_asset_ledger.ps1` | 從正式 registry／reference 重建 87 項 runtime 素材逐檔台帳。 |

## 執行圖片與設計圖片

| 檔案 | 類型 | 用途 |
| --- | --- | --- |
| `assets/images/world/backgrounds/city-map-background.png` | 執行素材 | 主遊戲實際載入的森林河谷城市背景。 |
| `ui/theme/ui_icon_catalog.gd` | 執行索引 | Storybook V2 中央圖示 catalog；所有 runtime UI 以 semantic key 解析圖示，未知 key 或缺檔統一使用 neutral fallback。 |
| `assets/images/ui/icons/storybook_v2/*.png` | 執行素材 | 37 張 canonical PNG（36 張功能圖示加 1 張 neutral fallback）；runtime 不再直接載入舊 `assets/images/ui/icons/` 根目錄圖示。 |
| `assets/images/world/concepts/city-layout-concept-01.png` | 概念圖 | 瀑布、城堡與環狀村莊構圖候選。 |
| `assets/images/world/concepts/city-layout-concept-02.png` | 概念圖 | 水岸大型城鎮與多建築密集配置候選。 |
| `assets/images/world/concepts/city-layout-concept-03.png` | 概念圖 | 島嶼城鎮與中央廣場構圖候選。 |
| `assets/images/world/concepts/city-layout-concept-04.png` | 概念圖 | 留白中央廣場與六棟功能建築構圖候選。 |
| `assets/images/reference/background-style/background_reference_01.png` | 參考圖 | 背景美術風格參考第 1 張。 |
| `assets/images/reference/background-style/background_reference_02.png` | 參考圖 | 背景美術風格參考第 2 張。 |
| `assets/images/reference/background-style/background_reference_03.png` | 參考圖 | 背景美術風格參考第 3 張。 |
| `assets/images/reference/background-style/background_reference_04.png` | 參考圖 | 背景美術風格參考第 4 張。 |
| `assets/images/reference/background-style/background_reference_05.png` | 參考圖 | 背景美術風格參考第 5 張。 |
| `assets/archives/MayorSimulator_BackgroundReference_Pack.zip` | 封存 | 原始背景參考包，保留原交付格式。 |

## 畫面擷取產物

| 檔案 | 用途 |
| --- | --- |
| `artifacts/screenshots/manual/mayor-simulator-after.png` | 人工檢視用的遊戲畫面成果。 |
| `artifacts/screenshots/ui-tests/fullscreen-main.png` | 全螢幕主畫面。 |
| `artifacts/screenshots/ui-tests/fullscreen-municipal-hub.png` | 市政中心入口。 |
| `artifacts/screenshots/ui-tests/fullscreen-buildings.png` | 建築頁。 |
| `artifacts/screenshots/ui-tests/fullscreen-governance.png` | 治理頁。 |
| `artifacts/screenshots/ui-tests/fullscreen-judicial.png` | 法院審判與已提交辯護狀態。 |
| `artifacts/screenshots/ui-tests/fullscreen-oversight.png` | 監察質詢與已提交彈劾答辯狀態。 |
| `artifacts/screenshots/ui-tests/fullscreen-blueprint.png` | 藍圖流程。 |
| `artifacts/screenshots/ui-tests/fullscreen-dark-blueprint.png` | 深色模式藍圖流程。 |
| `artifacts/screenshots/ui-tests/fullscreen-finance.png` | 財政頁。 |
| `artifacts/screenshots/ui-tests/fullscreen-city-data.png` | 城市資料頁。 |
| `artifacts/screenshots/ui-tests/fullscreen-report.png` | 回報頁。 |
| `artifacts/screenshots/ui-tests/fullscreen-exit-confirm.png` | 離開確認視窗。 |
| `artifacts/screenshots/ui-tests/main-ui-capture.png` | 早期主 UI 基準畫面。 |
| `artifacts/screenshots/ui-tests/main-ui-dark.png` | 深色模式基準畫面。 |
| `artifacts/screenshots/ui-tests/main-ui-expanded.png` | 展開狀態基準畫面。 |
| `artifacts/screenshots/ui-tests/main-ui-municipal.png` | 市政頁基準畫面。 |
| `artifacts/screenshots/ui-visualization/before/*.png` | 數據視覺化改造前的 10 張固定狀態基準畫面。 |
| `artifacts/screenshots/ui-visualization/after/*.png` | 數據視覺化改造後的 10 張固定狀態驗證畫面。 |
| `artifacts/screenshots/ui-visualization/picture-first/*.png` | 圖片主導 UI 的 10 張固定狀態驗證畫面。 |
| `artifacts/screenshots/ui-visualization/icon-contact-sheet.png` | 20 張透明 UI 插圖的目視檢查接觸表。 |

## 紀錄檔

紀錄檔是歷史驗證證據，不會被遊戲載入。每一檔依檔名保留當次執行目的：

| 位置／檔案 | 用途 |
| --- | --- |
| `artifacts/logs/parser/coordinator-parser.log` | 協調器語法檢查。 |
| `artifacts/logs/parser/final-parser-check.log` | 最終全域語法檢查。 |
| `artifacts/logs/parser/main-integration-parse.log`、`artifacts/logs/parser/main-integration-parse-2.log`、`artifacts/logs/parser/main-integration-parse-3.log` | 主整合測試的三次解析紀錄。 |
| `artifacts/logs/parser/municipal-overlay-parse.log` | 市政中心介面解析檢查。 |
| `artifacts/logs/parser/parser-check.log` | 一般解析檢查。 |
| `artifacts/logs/parser/ui-readability-parse.log` | UI 可讀性測試解析檢查。 |
| `artifacts/logs/runtime/final-main-runtime.log` | 最終主程式啟動紀錄。 |
| `artifacts/logs/runtime/godot-1280.log`、`godot-1600.log`、`godot-2860.log` | 三種視窗寬度的 Godot 啟動紀錄。 |
| `artifacts/logs/runtime/godot-check.log` | 一般 Godot 啟動檢查。 |
| `artifacts/logs/runtime/godot-legacy-smoke.log` | 舊版煙霧測試；保留供比較，不作目前通過依據。 |
| `artifacts/logs/runtime/godot-modal-check.log`、`godot-modal-run.log` | 模態視窗啟動檢查。 |
| `artifacts/logs/runtime/godot-run.log` | 一般執行紀錄。 |
| `artifacts/logs/runtime/godot-screenshot.log` | 截圖執行紀錄。 |
| `artifacts/logs/runtime/godot-z-check.log` | UI 層級／Z 軸檢查。 |
| `artifacts/logs/runtime/main-runtime-smoke.log` | 主程式煙霧測試。 |
| `artifacts/logs/tests/core-contract-rerun.log` | 核心資料契約重跑紀錄。 |
| `artifacts/logs/tests/final-main-integration-test.log` | 最終主畫面整合測試。 |
| `artifacts/logs/tests/final-population-test.log` | 最終人口測試。 |
| `artifacts/logs/tests/final-systems-test.log` | 最終系統測試。 |
| `artifacts/logs/tests/final-vertical-slice-test.log` | 最終垂直切片測試。 |
| `artifacts/logs/tests/main-integration-test.log` | 主畫面整合測試。 |
| `artifacts/logs/tests/organization-validation.log` | 本次目錄整理後六組正式驗證共用的 Godot 日誌。 |
| `artifacts/logs/tests/population-check.log` | 人口系統基礎檢查。 |
| `artifacts/logs/tests/population-self-test.log`、`artifacts/logs/tests/population-self-test-2.log`、`artifacts/logs/tests/population-self-test-3.log`、`artifacts/logs/tests/population-self-test-4.log`、`artifacts/logs/tests/population-self-test-5.log` | 人口自我測試五次迭代紀錄。 |
| `artifacts/logs/tests/population-self-rerun.log` | 人口測試修正後重跑。 |
| `artifacts/logs/tests/systems-self-rerun.log` | 系統自我測試重跑。 |
| `artifacts/logs/tests/vertical-slice-test.log`、`vertical-slice-test-rerun.log` | 垂直切片測試初跑與重跑。 |
| `artifacts/logs/tests/ui-visualization-lower-council.log`、`ui-visualization-justice-oversight.log`、`ui-visualization-population.log`、`ui-visualization-systems.log`、`ui-visualization-vertical-slice.log`、`ui-visualization-main-integration.log` | 數據視覺化改造後的六組獨立功能測試紀錄。 |
| `artifacts/logs/tests/picture-first-*.log` | 圖片主導 UI 完成後的六組獨立功能測試紀錄。 |
| `artifacts/logs/ui/fullscreen-main-validation.log` | 全螢幕主畫面驗證。 |
| `artifacts/logs/ui/fullscreen-ui-validation.log` | 全螢幕各 UI 頁驗證。 |
| `artifacts/logs/ui/main-integration-modal.log` | 主整合測試中的模態視窗紀錄。 |
| `artifacts/logs/ui/main-modal-integration.log`、`main-modal-integration-final.log` | 模態視窗整合初測與最終測試。 |
| `artifacts/logs/ui/ui-capture-gui.log`、`ui-capture-headless.log` | GUI 與無頭模式截圖紀錄。 |
| `artifacts/logs/ui/ui-readability-captures.log` | UI 可讀性截圖工作紀錄。 |
| `artifacts/logs/ui/ui-readability-integration.log` | UI 可讀性整合測試。 |
| `artifacts/logs/ui/ui-readability-legacy-smoke.log` | 舊版 UI 可讀性煙霧測試。 |
| `artifacts/logs/ui/ui-readability-vertical-slice.log` | 垂直切片 UI 可讀性測試。 |
| `artifacts/logs/ui/vertical-slice-modal.log`、`vertical-slice-modal-final.log` | 垂直切片模態視窗初測與最終測試。 |
| `artifacts/logs/ui/ui-visualization-before.log` | 數據視覺化改造前的固定狀態截圖紀錄。 |
| `artifacts/logs/ui/ui-visualization-preview.log` | 改造過程的中途視覺檢查紀錄。 |
| `artifacts/logs/ui/ui-visualization-parse.log` | 最終 UI 腳本解析檢查。 |
| `artifacts/logs/ui/ui-visualization-tests.log` | 改造期間的測試暫存紀錄；正式結果以 `artifacts/logs/tests/ui-visualization-*.log` 為準。 |
| `artifacts/logs/ui/ui-visualization-after.log` | 改造後 10 頁截圖與視覺規則驗證紀錄。 |
| `artifacts/logs/ui/picture-first-parse.log` | 圖片資產匯入與腳本解析紀錄。 |
| `artifacts/logs/ui/picture-first-capture.log` | 圖片主導 UI 的中途截圖紀錄。 |
| `artifacts/logs/ui/picture-first-final-capture.log` | 圖片主導 UI 的最終 10 頁截圖驗證紀錄。 |

## 文件

| 檔案 | 用途 |
| --- | --- |
| `docs/README.md` | 專案總覽與閱讀入口。 |
| `docs/design/art_direction_style_guide.md` | 美術方向、色彩與整體視覺原則。 |
| `docs/design/background_reference_guide.md` | 五張背景參考圖的使用說明。 |
| `docs/design/遊戲大更動.md` | 大型視覺與結構調整紀錄。 |
| `docs/development/godot_mvp_notes.md` | Godot MVP 開發備註。 |
| `docs/development/godot_reference.md` | Godot 相關參考資料。 |
| `docs/development/plugin_reference.md` | 外掛與工具參考資料。 |
| `docs/systems/governance/lower_council.md` | 下議院模組能力、資料契約與測試說明。 |
| `docs/systems/governance/lower_council_member_database.md` | 30 位議員資料庫設計與欄位說明。 |
| `docs/systems/governance/justice_oversight.md` | 司法與監察組織、職責、流程與整合說明。 |
| `docs/project-organization/MIGRATION_MAP.md` | 整理前後路徑與分類原則。 |
| `docs/project-organization/VALIDATION_REPORT.md` | 整理後靜態稽核、資源掃描與六組測試結果。 |
| `docs/project-organization/UI_VISUALIZATION_REPORT.md` | 數據視覺化 UI 的修改前觀察、實作範圍、截圖與測試結論。 |
| `docs/project-organization/PICTURE_FIRST_UI_REPORT.md` | 圖片主導 UI 的素材、版面、截圖及功能測試結論。 |
| `docs/project-organization/JUDICIAL_OVERSIGHT_UI_REPORT.md` | 法院／監察拆分、辯護流程、插圖與驗證結果。 |
| `docs/project-organization/BUILDING_BLUEPRINT_UX_REPORT.md` | 建築選擇與藍圖設計的改版內容、實玩數據與 UX 評分。 |
| `docs/project-organization/INTERNAL_TEST_READINESS.md` | 第一次受控內部測試的完成度、適用範圍、前置條件與停止標準。 |
| `docs/project-organization/FISCAL_UI_REPORT.md` | 稅率與公共收費分類、預警公式及低中高情境驗收結果。 |
| `docs/project-organization/RUNTIME_ASSET_LEDGER.md`、`.json` | 87 項實際 runtime 素材的逐檔 hash、用途、來源證據與權利狀態。 |
| `docs/project-organization/MAYOR_SIMULATOR_FINAL_AUDIT_2026-07-31_CLOSURE_2026-08-01.md` | 7 月最終稽核的閉環複驗版；固定權重 90/100、最終證據鎖、未閉環阻斷與 95 分門檻。 |
| `docs/project-organization/FILE_INDEX.md` | 本檔，逐項說明檔案用途。 |
| `ux/specifications/數據視覺化UI規格.md` | 圖示、狀態色、量表門檻與各頁資料呈現規格。 |
| `ux/specifications/圖片優先UI規格.md` | 插圖、短標籤、提示與畫面保護規格。 |
| `assets/images/ui/icons/storybook_v2/*.png` | Storybook V2 的 37 張 canonical PNG（36 張功能圖示加 1 張 neutral fallback）；runtime 一律透過 `ui/theme/ui_icon_catalog.gd` 載入，不再直接使用舊 icon root。 |
| `assets/images/ui/icons/README.md` | 插圖用途、生成方式、提示原則與研究來源。 |
| `assets/archives/picture-first-ui-icon-sources.zip` | 19 張洋紅去背原始生成圖封存。 |
| `assets/archives/municipal-justice-oversight-v2-sources.zip` | 法院與監察第二版的兩張洋紅去背原始生成圖封存。 |
| `assets/archives/building-blueprint-ui-icon-sources.zip` | 11 張建築分類／藍圖參數洋紅原始圖與提示摘要封存。 |

## 備份與中繼檔

| 檔案／規則 | 用途與處理方式 |
| --- | --- |
| `backups/mayor-simulator-pre-organization-20260722.zip` | 整理前完整快照；確認長期穩定後才考慮移出專案。 |
| 每個 `*.gd.uid`、`*.gdshader.uid` | Godot 穩定資源識別；用途等同同名來源檔，必須成對移動。 |
| 每個 `*.png.import` | 同名 PNG 的 Godot 匯入設定；必須與圖片同目錄。 |
| `.godot/**` | Godot 可再生的匯入與編輯器快取，不是來源資料。 |
| `.agents/`、`.codex/` | Codex／代理工具的工作區中繼資料。 |
| `.tmp.driveupload/`、`.tmp.drivedownload/` | 雲端同步工具暫存，可能隨同步狀態出現或消失。 |
| `.git/` | 目前是空目錄，並非有效 Git 儲存庫；本次不自行初始化。 |
