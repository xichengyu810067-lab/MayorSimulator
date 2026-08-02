# Goal #2／#5／#6／#7：交通、NPC、地形驗收與實作缺口矩陣

審查日期：2026-08-02。範圍是當下 authoritative 工作樹的唯讀靜態審查；本次沒有啟動 Godot、沒有執行測試，也沒有把「測試檔存在」等同於「當前工作樹已通過」。工作樹在審查時已有大量未提交變更，包含交通核心、地形、整合測試及受保護共享檔，因此以下「已證明」只代表 source/test 對需求具直接、可讀的斷言；只有列出的既存 artifacts 才算歷史可視證據，且它們早於本次工作樹，不能單獨作 release gate。

## 判讀尺度

- **已證明（靜態）**：目前 source 有實作，且至少一個精確測試斷言該行為。
- **部分證明**：只有單一 mode、純模型、合成 snapshot 或歷史截圖；尚未覆蓋玩家 UI、真實 scene/runtime、reload 或所有運具。
- **未證明**：沒有找到直接斷言，或現有測試只驗文案/資料結構。
- 「預計擁有檔案」是後續 task 的建議修改邊界，不是本次修改清單。

## 可執行缺口矩陣

| ID / Goal | 驗收行為 | 現有 source / test / evidence | 判定 | 最小新測試（可直接交辦） | 預計擁有檔案 | 共享熱點需求 |
|---|---|---|---|---|---|---|
| T01 / #2 | 新遊戲零預設交通；玩家可建道路拓樸 | `transport_network_system.gd`（project/segment topology、`private_road_paths`）；`map_zoom_terrain_integration_test.gd:49-54` 驗零預植；unit test 覆蓋 road segment/crossing | 部分證明：模型有道路，但缺「玩家從 UI 選點→施工→完成→畫面連通」端到端 | 新增 `tests/integration/transport_player_build_modes_integration_test.gd`：由公開 UI/協調器命令建立 3+ 格道路，驗 selected path、施工期、完成後 layer 邊連通與 private traffic eligibility | 新測試；必要時 `ui/shell/transport_planning_panel.gd`、非受保護的 placement adapter | 若公開入口只在 `main.gd`/`vertical_slice_coordinator.gd`，先由整合 owner 提供窄 facade；本 task 不直接碰 |
| T02 / #2 | 玩家可建鐵路、捷運拓樸（站、軌、機廠、號誌） | `transport_modes.gd`；`transport_network_system.gd`；`transport_network_system_test.gd` 多 mode；`transport_network_integration_test.gd:60-177` 端到端只完整走 metro | 部分證明：捷運強；heavy rail 的 coordinator/UI 真實建造對稱性未證明 | 同一 table-driven integration 對 metro/train 各建兩站、連續軌道、相容 depot；train 額外缺號誌時必須拒絕，補齊後 operational | 新 integration test；模型缺陷才改 `scripts/systems/city/transport_network_system.gd` | 避免再寫一份 topology 算法；共享 fixture helper 可由 transport-model owner 建立 |
| T03 / #2 | 玩家可建機場拓樸（機場、滑行道、跑道） | `transport_modes.gd` air mode；`transport_network_system.gd:_validate_air_route/_air_path_result`；unit test 有 air route；panel test 只驗按鈕與假 snapshot | 部分證明：純模型存在，未證明真實玩家流程、跑道方向/連續性畫面 | integration：玩家建兩機場，各自 taxiway 接 straight runway endpoint；錯誤方向/孤立 runway 拒絕；成功後唯一 air line 的 path cardinally contiguous | 新 integration test；必要時 planning panel/placement adapter、network layer | 若需協調器接線，交 coordinator owner；不可由 mode task 改受保護檔 |
| T04 / #5 | 汽車、機車只在有效道路網運行 | `transport_activity_profiles.gd` 宣告 network-controller-only；`transport_network_system.gd:519-568`；`transport_vehicle_controller.gd` 限制 private actors；integration 只直接斷言 operational metro vehicles | 部分證明：policy/source 有，缺 car/motorcycle 的正反 runtime 斷言 | vehicle controller test：空網、孤立 road、單格 road 均 0；有效連通道路產生 car+motorcycle（各 actor 每幀 `on_authoritative_path`）；斷路下一 snapshot 立即 0 | `tests/ui/transport_vehicle_network_contract_test.gd`；必要時 controller/system | controller 是多 mode 共享熱點，先鎖 snapshot schema 再改 |
| T05 / #5 | 公車只在有效道路、站、車庫與有效 route 運行 | mode catalog + route validator；unit test 有 bus；integration 未走 bus 真實 runtime | 部分證明 | table case：缺站/斷路/缺 bus depot 各 0 vehicle、0 revenue；完整條件產生 fleet；拆一段路後同 frame/next snapshot 變 0 | 新 integration test；`transport_network_system.gd`、`transport_vehicle_controller.gd` 僅缺陷時 | 與 T04 共用 road fixture；先完成模型契約再畫面 |
| T06 / #5 | 火車、捷運只在各自有效軌道與設施運行，不能跨網 | catalog/validator；unit test 多 mode；`transport_network_integration_test.gd:73-177` 精確證明 metro；`transport_visual_animation_test.gd` 為合成 snapshot | 部分證明：metro 已靜態證明；train 及 cross-mode 污染未端到端證明 | table case：metro on rail、train on metro 必須 invalid/0；train 完整網 operational；每車 kind/path/route id 正確 | 新 integration test；必要時 system/controller | 同 T02/T05，避免平行 task 同改 system/controller |
| T07 / #5 | 飛機只在有效機場/滑行道/跑道網運行 | air validator + controller plane mapping；unit test 有 air 模型；現有兩張 transport animation JPG 不足以證明合法網路來源 | 部分證明 | 建有效/無效 air topology，controller actor 只能由 operational air line 生成；每個 sample 都在 authoritative air path；拆 runway 後 0 plane/0 revenue | 新 integration + visual runtime test；必要時 controller/layer | 先完成 T03 topology，後做 T07 runtime |
| T08 / #5 | 拆除/斷線後停駛、零車、零收入（所有 mode） | `transport_network_integration_test.gd:179-217` 已證 metro save/load 後拆軌→suspended/0 active lines/0 vehicles/0 revenue；unit `:317-323` 同樣證 metro | 部分證明：只有 metro；未驗 road private traffic、bus/train/air、設施拆除、reload 後仍停駛 | table-driven lifecycle：對 road/bus/metro/train/air 分別拆「關鍵 segment」與「關鍵 facility」，驗 route suspended、active actors=0、service revenue=0；save/reload 再驗一次 | 新 integration test；必要時 network/controller/economy adapter | 這是最高優先；需 transport model + economy owner 協調，先固定 zero semantics |
| T09 / #6 | 平交道僅由道路×鐵軌合法交會生成，拆任一側即移除 | `transport_network_system.gd:_recompute_crossings`；unit test 驗 crossing 建立及拆軌 orphan 消失；network layer 可畫 crossing | 已證明（靜態模型）；真實玩家建造畫面仍部分 | integration：以玩家建 road 再建 rail 交會，驗 crossing snapshot/layer；拆 road、另案拆 rail 均移除 | 新 integration/layer test | system + layer 共享；可與 T10 同 owner |
| T10 / #6 | 列車接近平交道才降柵欄；離開後升起；道路車輛在降桿時停、不穿越 | `transport_vehicle_controller.gd:_crossing_proximity_states/_must_stop_for_crossing`；`transport_network_layer.gd:set_crossing_states/_draw_level_crossing`；visual test 有合成動畫斷言 | 部分證明：有 sampler/source，缺真實 train approach 時序、汽機車互鎖、可視幀證據 | deterministic runtime test：固定 clock，採樣 far→approach→occupy→clear；驗 barrier false→true→true→false，car/motorcycle position 在 closed gate 前不越線，train 持續通過；另輸出 4-frame contact sheet | `tests/ui/level_crossing_runtime_acceptance_test.gd`、capture script；必要時 controller/layer | 最高共享熱點；單一 owner 同時處理 controller/layer，避免 T04/T06 平行修改 |
| T11 / #7 | NPC 不可走進樹木、河湖、建築、道路、鐵軌；施工/動態建築即時重規劃 | `city_terrain_map_unit_test.gd:42-95`；`terrain_navigation_blocker_test.gd` 五種 terrain + building；`npc_navigation_grid_unit_test.gd` static/dynamic detour；`npc_walkability_and_name_regression_test.gd:66-77,219-229`；integration transport 驗 completed transport blocker ids | 已證明（靜態）大部分；缺真實道路/鐵軌建拆與 NPC 連續軌跡同場驗收 | live scene test：NPC 路線穿過待建格；完成 road/rail 後下一次 replan 不進 polygon，拆除後恢復；逐 4px sample 驗 feet 不落 blocker | `tests/ui/npc_transport_obstacle_live_test.gd`；必要時 `npc_map_controller.gd` | 需 transport snapshot→NPC blocker adapter；避免碰 main/coordinator，要求 facade/fixture 注入 |
| T12 / #7 | NPC 只能在明確合法 crossing 穿越道路/鐵軌，且服從列車柵欄 | 現有 terrain/transport 將 road/rail 全格標為 navigation blocker；找到的測試只證不可走，沒有 pedestrian crossing/合法穿越語意 | 未證明，且可能尚未實作 | 先寫 model contract：無 crossing 時 path 不可跨；具 pedestrian/level-crossing aperture 時可沿指定 corridor 跨；train approach 時 corridor 暫停、clear 後恢復。再做 live feet sampling | 建議新增 `scripts/world/npc_crossing_policy.gd` + 對應 unit/UI test；`npc_map_controller.gd` adapter | **需要產品決策**：道路是否允許路口/人行穿越、鐵路是否只允許平交道；先定 contract，否則不可安全實作 |
| T13 / #7 | 地形限制：非平地不可建，整平付費且只改 effective terrain | `city_terrain_map.gd`；`city_terrain_map_unit_test.gd:42-67`；`map_zoom_terrain_integration_test.gd:95-114` 驗 blocked→quote→扣款→buildable/walkable | 已證明（靜態）；只完整走 trees，其他 kind 主要為 unit | table-driven integration 對 trees/rocky/river_lake/road_path/rail_track：建造拒絕、整平價格、完成後可建；不足款不改 terrain/treasury | 擴充 map/terrain integration test；必要時 terrain map | integration 目前依賴 `main.gd`，宜抽 fixture 或由 main owner 執行，不直接修改受保護檔 |
| T14 / #7 | 整平與地形/NPC blocker reload persistence | terrain unit `:72-95` dict round-trip；map integration `:118-121` save/load flattened terrain；terrain blocker test 驗 flatten 後 blocker 消失但未 reload live controller | 部分證明 | save flattened + unflattened mixed map，reload 新 coordinator/controller，重建 navigation；驗 flattened 無 blocker、河/樹仍 blocker、building/transport blocker 不遺失 | 新 integration test；terrain map、npc controller 僅缺陷時 | 與 T15 共用 reload harness；GameSession/save schema 是共享熱點 |
| T15 / #2/#5/#6 | 交通 topology、route 狀態、畫面層、vehicle 與 crossing animation reload persistence | network integration `:179-188` 證 metro model/runtime snapshot persistence；unit JSON round-trip；沒有 reload 後新 layer/controller 的 visible actor/crossing phase 驗收 | 部分證明 | 建含 road+metro+rail crossing+air 的 save；載入全新 session、layer/controller；驗 topology 相等、只有 operational fleet 重建、suspended 保持 0、crossing 初始 safe/open 並由接近列車驅動、畫面 debug snapshot 一致 | `tests/integration/transport_reload_visual_runtime_test.gd`；save/session/network/controller/layer 僅缺陷時 | 高優先；save owner 與 transport visual owner 串行，禁止各自改 schema |
| T16 / #5/#6/#7 | 可見動畫：六種運具移動、NPC 步行、柵欄狀態，不是靜態圖示 | `transport_visual_animation_test.gd` 檢查語意/合成 runtime；`transport_visible_acceptance.gd` 手動；歷史 `goal-20260801-transport-animation-a/b.jpg`、`npc-motion-contact-sheet-2880x1800.png`、`npc-live-navigation-2880x1800.png` | 部分證明：兩張時間點圖可支持「有位移」但未綁定當前 tree，也未完整覆蓋六種運具/斷線停止/reload | 自動 capture acceptance：同一 seed 產生 t0/t1/t2 contact sheet，標註 route id/kind/path；六種 actor 位置改變且保持合法 path；斷線後 actor 消失；reload 後合法 actor 重建 | capture + visual acceptance tests；controller/layer 僅缺陷時 | 最後執行；必須使用已通過 T04-T15 的 fixture，避免截圖掩蓋模型錯誤 |

## 現有證據總結

| 面向 | 已可主張 | 尚不可主張 |
|---|---|---|
| 拓樸 | 模型支援 road/metro/rail/taxiway/runway、設施與 routes；metro 有 coordinator lifecycle | 四種網路都能由玩家 UI 完整建造並在畫面正確連接 |
| 車輛 | operational line 是 fleet 唯一來源；metro 有 zero-before/positive-after/zero-after-break | car、motorcycle、bus、train、plane 全部都有相同強度的正反與拆除驗收 |
| 收入 | metro 斷線後為 0 | bus/train/air 及 reload 後 suspended 的 0 收入對稱性 |
| 平交道 | crossing 模型生成/移除、controller 有 proximity 與 stop 邏輯、layer 有 gate 畫法 | 真實列車時序驅動柵欄，且汽機車確實停在柵欄前 |
| NPC | 樹/岩/河湖/道路/鐵軌/建築/施工 blocker 與 detour 有直接斷言 | 合法道路/鐵路穿越 corridor 及其與列車柵欄互鎖 |
| 地形 | 不可建/不可走、整平、扣款、base/effective 分離與 save/load | 所有 terrain kind 的真實玩家流程及 reload 後 live navigation 全量重建 |
| 視覺/reload | 有歷史交通/NPC/整平截圖；metro model persistence | 當前精確工作樹的 pass log、六運具 contact sheet、reload 後新視覺控制器重建 |

## 建議 task 拆分與順序

1. **A — 契約與 mode 對稱測試（T02-T08）**：單一 transport-model owner，先建立 table-driven fixtures；優先證明所有 mode 的 invalid→operational→broken lifecycle、零車與零收入。只在測試揭露缺陷時改 `transport_network_system.gd`。
2. **B — 平交道 runtime（T09-T10）**：單一 crossing owner 擁有 `transport_vehicle_controller.gd` + `transport_network_layer.gd`，補 deterministic clock、道路車停等與四幀 capture；不可與 A 同時改 controller。
3. **C — NPC/地形（T11-T14）**：NPC navigation owner 先取得「合法穿越」產品決策；其餘 blocker、全 terrain 整平與 reload navigation 可獨立補測。
4. **D — reload 與可見驗收（T15-T16）**：在 A-C 綠燈後，用全新 session/controller/layer 驗 save/reload，最後才產生當前工作樹的 logs/contact sheets。
5. **E — 玩家 UI 建造（T01-T03）**：若公開 facade 已可用，可與 C 平行；若只能經 `main.gd`/`vertical_slice_coordinator.gd`，由其專屬 owner 串行接線，transport task 僅消費 facade。

共享檔鎖定建議：`transport_network_system.gd`（A）→ `transport_vehicle_controller.gd`/`transport_network_layer.gd`（B）→ save/session adapter（D）→ UI/coordinator facade（E）。`main.gd`、`vertical_slice_coordinator.gd`、`tests/assertion_matrix.json` 與 localization overrides 應由各自專屬整合 owner 最後處理，不分派給上述 feature tasks。

## 最優先三個缺口

1. **T08：所有 mode 在拆除/斷線後必須一致停駛、零車、零收入。** 現在只有 metro 具完整端到端證據；這是避免幽靈交通與憑空收入的核心 release invariant。
2. **T10：真實列車接近時序與平交道安全互鎖。** source 有 proximity/stop 函式，但缺 train→gate→road vehicle 的同場因果驗收及可視證據。
3. **T15：reload 後重建 topology、fleet、crossing 與 suspended 狀態。** 現有 persistence 主要停在 metro model/snapshot，尚未證明全新 visual/runtime controller 不會生成幽靈車或遺失柵欄狀態。

## 建議下一批 prompts

### Prompt A：全 mode 生命週期契約

> 在 authoritative 工作樹新增 table-driven transport lifecycle tests，覆蓋 road private traffic、bus、metro、train、air。每個 mode 都要驗證：缺必要 topology/facility 時 0 vehicle、0 revenue；完整網路才 operational；拆除關鍵 segment 與關鍵 facility 後 suspended、0 active line、0 vehicle、0 revenue；save/reload 後仍保持。先只改新測試與 transport model/controller 的必要缺陷，禁止碰 main.gd、vertical_slice_coordinator.gd、assertion_matrix/localization；回報每個 mode 的正反案例。

### Prompt B：平交道安全時序

> 建立 deterministic level-crossing runtime acceptance：真實 operational train 依固定 clock 從 far→approach→occupy→clear，柵欄依序 open→closed→closed→open；car 與 motorcycle 在 closed gate 前停止且不得穿越，列車通過不被道路車阻擋。輸出四幀 contact sheet 與 machine-readable snapshots。由單一 owner 處理 transport_vehicle_controller.gd 與 transport_network_layer.gd，禁止修改 coordinator/main/assertion matrix。

### Prompt C：reload 視覺/runtime 重建

> 建立混合 road+bus+metro+rail crossing+air 的存檔 fixture；載入全新 GameSession、TransportNetworkLayer、TransportVehicleController、NpcMapController。驗 topology/flattened terrain 持久化、只有 operational routes 重建 fleet、suspended routes 仍為 0 車/0 收入、crossing 起始安全且可再次受列車接近驅動、NPC blockers 無 stale/missing。先新增 integration test；若需跨 main/coordinator 接線，停下並列出窄 facade 需求，不直接改受保護檔。
