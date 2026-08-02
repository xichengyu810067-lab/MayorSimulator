# Goal #8 凍結後最終 AC 追溯矩陣

複核日期：2026-08-03（Asia/Taipei）
權威設計契約：`docs/design/city_simulation_originality_contract.md`
Canonical manifest：`tests/assertion_matrix.json`（66 cases）

## 1. 判定方法與 fresh evidence

Production source 只證明產品行為有權威擁有者；test 證明特定語意被斷言；evidence 證明該測試在凍結工作樹實際通過。設計文件不是 runtime 實作證據，技術綠燈亦不能證明版權或公開散布權。

- **已直接證明**：有具體 source、直接斷言必要語意的 canonical test，以及凍結後 PASS／exit 0／product-clean evidence。
- **間接證明**：相鄰 source、test 或 evidence 支持結論，但沒有直接覆蓋整個宣稱。
- **仍未證明**：缺必要實作、直接測試或凍結證據。

| 代號 | 證據 | 結果與正確範圍 |
| --- | --- | --- |
| **ET3** | `artifacts/goal-visible-qa/t3/final-assertion-freeze-20260802/summary.json`、`final-save-freeze-20260802/summary.json`、`final-process-check.json` 與 `docs/acceptance/goal_visible_qa_t3.md` | Frozen assertions 66/66 product-clean、failed 0、environment-warning tests 0；OS-kill 5/5、173 semantic checks、forced termination 5、`all_processes_stopped=true`；最終 matching process 0。直接支持 canonical assertions、save infrastructure 與零殘留程序。 |
| **EUI-CURRENT** | `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/summary.json` | PASS、37/37、diagnostics 0、success marker 1、source pre/post fingerprint 相同。Native 是真正 Windows `native_fullscreen_root`：4/4，window／capture physical **1656×843**、logical 1414×720。Offscreen 是 `offscreen_subviewport`：33/33，physical **2880×1800**、logical 1280×800。2880×1800 不得稱為原生視窗解析度。 |
| **EUI-INDEPENDENT** | `.tmp/sdk/ui-qa/final-native-and-offscreen-20260802-v6/summary.json` | 中控獨立基準，同為 native 4/4＋offscreen 33/33、diagnostics 0、source unchanged；與 EUI-CURRENT 的 capture 類型、數量及 fingerprint `51d94e...fa90a` 一致。 |
| **歷史／superseded** | `.tmp/sdk/assertion-matrix/final-66-post-l10n-20260802T2105/summary.json`、`.tmp/sdk/save-qa/final-post-l10n-20260802T2130/summary.json`、`.tmp/sdk/ui-qa/transport-ui-20260802-v2/summary.json` | 舊 assertion／save 可作歷史交叉參考；舊 UI 33/33 早於 freeze 且已被 EUI-CURRENT／EUI-INDEPENDENT 取代。最終結論只依 ET3 與 EUI-CURRENT。 |

## 2. AC-01～AC-14 最終矩陣

| AC | Goal 交叉對應 | Production source | Canonical test ID／檔 | Evidence | 最終判定 |
| --- | --- | --- | --- | --- | --- |
| **AC-01 新局零權威交通** | #2、#6、#8、#9 | `scripts/systems/city/transport_network_system.gd`；`scripts/app/vertical_slice_coordinator.gd`；`scripts/world/transport_vehicle_controller.gd` | `transport_network_integration`；`transport_all_mode_lifecycle_contract`；`transport_visual_animation` | ET3：三項 PASS | **已直接證明。** 新局零權威路網／路線／服務；站點或 tile-local 動畫不自行生成車輛或收入。 |
| **AC-02 地形前置條件** | #3、#5、#7、#8、#9 | `scripts/world/city_terrain_map.gd`；`vertical_slice_coordinator.gd`；`scripts/systems/city/construction_system.gd`；`scripts/core/game_session.gd` | `terrain_flatten_lifecycle`／`tests/integration/terrain_flatten_lifecycle_test.gd`；`map_zoom_terrain_integration`；`city_terrain_map_unit`；`terrain_navigation_blocker` | ET3：四項 PASS、save 5/5 | **已直接證明。** Quote 有 fixed＋labor cost 與多日正工期；job 期間不可建／不可走且阻擋建築、交通；mid-job reload 保留 workers／remaining work，最後一天才解除 blocker，單次 ledger entry 與完成歷史可 reload。 |
| **AC-03 道路與軌道拓撲** | #2、#7、#8、#9 | `data/catalogs/transport_modes.gd`；`transport_network_system.gd`；`vertical_slice_coordinator.gd` | `transport_network_system`；`transport_network_integration`；`transport_coordinator_integration`；`transport_all_mode_lifecycle_contract` | ET3：四項 PASS | **已直接證明。** 玩家 path、連續性、端點相容、必要設施、施工 commit、平交道、拆除及非法／重複操作均有直接斷言。 |
| **AC-04 運輸完整生命週期** | #2、#6、#8、#9 | `transport_network_system.gd`；`vertical_slice_coordinator.gd`；`transport_vehicle_controller.gd`；`ui/shell/transport_planning_panel.gd` | `transport_all_mode_lifecycle_contract`；`transport_coordinator_integration`；`transport_network_integration`；`transport_planning_panel` | ET3：四項 PASS；EUI-CURRENT 37/37 | **已直接證明。** 公車、捷運、火車、航空與私有汽機車均由權威 topology 決定；建立、驗證、啟停、拆除停擺、刪除與存讀成立。 |
| **AC-05 成本與收入可追溯** | #2、#8、#9 | `scripts/core/ledger.gd`；`transport_network_system.gd`；`vertical_slice_coordinator.gd`；`scripts/app/city_simulation_service.gd`；`scripts/app/main.gd` | `transport_network_integration`；`transport_coordinator_integration`；`terrain_flatten_lifecycle`；`public_service_lifecycle`；`municipal_economy_service_self`；`city_simulation_service_self` | ET3：六項 PASS | **已直接證明契約所需範圍。** 交通不重複計站點維護、無有效線即零收入；整地只預付一次；醫療失效即零 medical revenue，修復回復同值。未推論所有 catalog 建築都有同等深度。 |
| **AC-06 公共服務不是放置即生效** | #1、#5、#8、#9 | `data/catalogs/buildings.gd`（醫院 `public_service`）；`scripts/app/city_simulation_service.gd`（healthcare result）；`vertical_slice_coordinator.gd`（authoritative input）；`main.gd`（bonus latch、UI、request context） | `public_service_lifecycle`／`tests/integration/public_service_lifecycle_test.gd`；`population_self` | ET3：兩項 PASS；EUI-CURRENT 含 public-affairs visible capture | **已直接證明醫療類。** 醫院完成不直接加分；缺路為 `road_missing` 且零 bonus／收入；道路完成後才運作；容量、人口需求、耐久與維護共同決定效果，維修後恢復相同 metric／收入。契約只要求至少一類，未宣稱教育／安全已有同等模型。 |
| **AC-07 居民請求閉環** | #1、#8、#9 | `scripts/systems/population/population_request.gd`；`population_system.gd`；`vertical_slice_coordinator.gd`；`ui/shell/public_affairs_panel.gd` | `context_requests_time`；`public_affairs_status_rendering`；`public_affairs_reload_lifecycle`；`population_self` | ET3：四項 PASS；EUI-CURRENT `fullscreen-public-affairs.png` | **已直接證明。** 真實 UI action 涵蓋 pending→accepted／rejected、accepted→completed；terminal history、日期、NPC presentation、autosave 與 Continue reload 不回退、不污染。 |
| **AC-08 NPC 導航一致性** | #3、#5、#6、#7、#8、#9 | `scripts/world/city_navigation_grid.gd`；`scripts/app/npc_map_controller.gd`；`city_terrain_map.gd`；`vertical_slice_coordinator.gd`；`main.gd` | `terrain_navigation_blocker`；`npc_navigation_grid_unit`；`npc_locomotion_navigation_acceptance`；`npc_authority_and_construction_sync`；`npc_walkability_and_name`；crossing navigation／interlock tests | ET3：全部相關 tests PASS | **已直接證明。** 樹木、水體、山丘、建築、施工、道路、軌道、設施與平交道狀態進入權威導航；動態變更不留 stale blocker，NPC 無路時等待或重算而非穿越。 |
| **AC-09 治理與問責** | #1、#8、#9 | `scripts/systems/governance/governance_system.gd`；`systems/governance/lower-council/`；`systems/governance/justice-oversight/`；`vertical_slice_coordinator.gd`；`ledger.gd` | `separation_of_powers`；`governance_terminal_state`；`lower_council_self`；`justice_oversight_self`；`justice_oversight_multi_case`；`governance_status_tabs` | ET3：六項 PASS；EUI-CURRENT 含 governance／judicial／oversight states | **已直接證明核心制衡。** 行政提案、30 人議會、強制施行、司法／監察、永久 history、終局一次事件、鎖定與 reload 均有斷言。每項政策的完整成本 UI exhaustiveness 仍只屬**間接證明**，不擴張宣稱。 |
| **AC-10 正向→破壞→修復** | #1、#2、#5、#7、#8、#9 | 醫療鏈：`city_simulation_service.gd`、`vertical_slice_coordinator.gd`、`durability_system.gd`、`main.gd`、road topology；交通失效鏈：`transport_network_system.gd`／vehicle controller | `public_service_lifecycle`；`transport_network_integration`；`transport_all_mode_lifecycle_contract` | ET3：三項 PASS | **已直接證明最小跨系統鏈。** 醫院無路→道路完工後服務／收入／居民 context 成立→耐久與停維護使服務失效→broken save/reload→恢復維護與 repair，使容量、metric、收入、request context 回復且 bonus 不重複。交通另直接證明拓撲拆除後 route／車輛／服務／收入歸零；不誤稱已測軌道原線重鋪。 |
| **AC-11 存檔與決定性** | #1、#2、#7、#8、#9 | `scripts/core/save_service.gd`、`game_session.gd`、`city_state.gd`；`vertical_slice_coordinator.gd`（schema 8／subsystems）；各 domain `to_dict/load_dict` | `save_recovery_self`；`terrain_flatten_lifecycle`；`public_service_lifecycle`；`public_affairs_reload_lifecycle`；`transport_network_integration`；`transport_coordinator_integration`；`governance_terminal_state`；`city_terrain_map_unit` | ET3：domain tests PASS；OS-kill 5/5、173 checks、process 0 | **已直接證明 domain round-trip 與 save infrastructure。** Terrain mid-job／completed、醫療 broken latch、請求 history、mixed transport topology／runtime、治理 terminal 與 ledger 語意都有直接 reload 斷言；OS-kill 是獨立分層證據，不取代 domain tests。 |
| **AC-12 UI 與動畫誠實性** | #1、#2、#4、#6、#8、#9 | `transport_planning_panel.gd`；`transport_network_layer.gd`；`transport_vehicle_controller.gd`；`city_tile_button.gd`；`public_affairs_panel.gd`；audio settings／director | `transport_planning_panel`；`transport_visual_animation`；`transport_network_layer`；`ambient_animation_contract`；`public_affairs_status_rendering`；`public_affairs_reload_lifecycle`；`audio_settings_integration`；crossing interlock tests | ET3 相關 tests PASS；EUI-CURRENT native 4/4＋offscreen 33/33；EUI-INDEPENDENT 同結構 PASS | **已直接證明。** 程式化狀態、權威 animation／vehicle、公共事務、平交道、音訊控制均通過；凍結 UI 又證明 4 個真實 Windows native states 與 33 個離屏狀態可見、diagnostics 0、source unchanged。 |
| **AC-13 縮放與空間對齊** | #3、#5、#8、#9 | `main.gd`（map-stage transform／hit test）；`city_terrain_map.gd`；NPC、transport layer／vehicle controller | `map_zoom_all_layers_acceptance`；`map_zoom_terrain_integration`；`city_terrain_map_unit`；`multi_resolution_ui_acceptance`；`transport_network_layer` | ET3：五項 PASS；EUI-CURRENT 支持可見 UI | **已直接證明。** 100%／175%／65% 下 terrain、building、NPC、transport topology、vehicle、navigation blocker 與 click target 共用一致 transform／identity。 |
| **AC-14 Fresh evidence** | #9，且為 #1～#8 完成 gate | SDK assertion／save／UI runners 與 process gate | 66-case manifest、所有上列 tests、canonical native＋offscreen UI、OS-kill QA | ET3 assertion 66/66；ET3 save 5/5；EUI-CURRENT 37/37；process 0 | **已直接證明，runtime／visible acceptance gap=0。** Assertion、native＋offscreen UI、OS-kill save 與 process cleanup 均來自 freeze-final evidence roots；UI source fingerprint 前後一致。 |

## 3. Goal #1～#9 交叉結論

| Goal | 已直接證明 | 不擴張的邊界 |
| --- | --- | --- |
| **#1 民情狀態** | 拒絕／受理／完成、actionability、NPC presentation、autosave、Continue reload 與可見 public-affairs 畫面。 | 未宣稱每種未來 request 都已有獨立端到端城市鏈。 |
| **#2 交通設施與圖標** | 全模式 topology、六車種、權威 path、設施／平交道、拆除失效、mixed reload、規劃 UI 與 freeze captures。 | 不宣稱裝飾資產本身能代替 topology。 |
| **#3 格子與縮放** | 10×10／100 cells、100%／175%／65% 下所有必要 layer transform 與 click target 對齊。 | Native capture 是 1656×843；2880×1800 僅為 offscreen evidence。 |
| **#4 音效／配樂** | Music／SFX slider、AudioDirector／AudioServer buses、enabled flags、新 Main persistence 與可見 settings。 | 不宣稱自動化測到喇叭聲壓或主觀混音品質。 |
| **#5 NPC 避障** | Terrain、building、construction、transport、crossing blockers、動態重算、no-route wait 與身份穩定。 | 不涵蓋未來尚未註冊的新 obstacle 類型。 |
| **#6 動畫** | Ambient、NPC locomotion、transport vehicle movement、停止狀態與 crossing interlock。 | 視覺藝術偏好不等同功能驗收。 |
| **#7 整地** | 多日 job、成本、workers、前置阻擋、mid-job／completed reload。 | 無剩餘 runtime 語意缺口。 |
| **#8 城市模擬深度** | 空間、交通、醫療、居民、財政、治理、破壞／恢復、跨域存讀與可見結果。 | 教育／安全未宣稱具有醫療同等深度；契約 AC-06 僅要求至少一類。 |
| **#9 SDK／skills** | Freeze assertion、UI、save 與 process gates 全部通過且使用不可覆寫 evidence roots。 | 技術 QA 不替代權利審查。 |

## 4. 原創差異化與防抄襲邊界

### 已建立並可追溯

- `docs/design/city_simulation_originality_contract.md` 禁止複製特定作品的名稱、圖像、UI、數值、文案、版面、色碼、教學順序與逐項配置，並定義 Mayor Simulator 的五個原創支柱。
- Production 與 ET3 tests 直接呈現本專案自有的市長承諾、居民 terminal history、議會／司法／監察、具名 NPC、權威交通及醫療因果。
- `docs/project-organization/RUNTIME_ASSET_LEDGER.md`／`.json`、`THIRD_PARTY_NOTICES.md`、建築／圖標 provenance，以及 `redundancy_audit`、`building_visual_catalog_contract`、`ui_icon_catalog_contract` 提供來源盤點；相關 tests 在 ET3 PASS。

### Public-release 仍保留的界線

ET3 與 EUI-CURRENT 能證明 runtime／visible acceptance，不能證明世界上不存在實質相似內容，也不能取代法律意見、獨立逐畫面 similarity review、素材散布權或專案 LICENSE。Runtime ledger／release 文件中標示未解的背景素材權利與專案層級授權，不得因技術全綠而改稱已解決；在權利證明或替換與 license 裁決完成前，仍不可宣稱可公開散布。

## 5. Remaining gaps

- **Goal #8 runtime／visible acceptance gap：0。** AC-01～AC-14 均有直接 source、canonical test 與 freeze-final evidence；EUI-CURRENT 已收口先前的 UI QA 漂移。
- **Goal #8 已知 runtime 產品阻擋：0。** 本複核沒有從凍結證據發現新的產品 defect。
- **Public-release originality／provenance／license gap：仍非 0。** 這是發佈治理阻擋，不回寫成 Goal #8 runtime 失敗。最小下一步是由未參與製作的人員依原創契約第 10 節完成名稱、流程、UI、圖標、素材、數值與版面的 similarity／provenance 審查；對 ledger 未解權利項目取得授權或替換，並完成專案 LICENSE 裁決。

## 6. 凍結後可驗收完成定義

Goal #8 可依目前 freeze 標記 runtime／visible acceptance complete，前提是：

- ET3 assertion 維持 66/66 product-clean、failed 0；ET3 save 維持 5/5、173 checks、all processes stopped；final process check 維持 0。
- EUI-CURRENT 維持 native 4/4 與 offscreen 33/33、diagnostics 0、success marker 1、source unchanged。Native 物理視窗／capture 是 1656×843；offscreen evidence 才是 2880×1800。
- 凍結後若 production、tests、manifest 或 canonical capture path 再變更，受影響 gate 必須用新 output root 重跑，不能沿用本次 freeze。
- 對外只宣稱已證明範圍：醫療具深層 service lifecycle；教育／安全不宣稱同等深度；OS-kill 證明 save infrastructure，domain round-trip 仍由各 canonical tests 證明。
- 「runtime／visible complete」不等於「可公開發行」；原創 similarity、provenance、背景素材散布權與 LICENSE 未解前，維持不可公開散布界線。

最終結論：**Goal #8 的 runtime 與 visible acceptance remaining gap 已為 0；public-release originality／provenance／license gap 仍保留。**
