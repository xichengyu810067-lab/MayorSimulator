# Goal Visible QA T3 — freeze-final acceptance

執行時間：2026-08-02 23:42 至 2026-08-03 00:17（Asia/Taipei）
權威工作區：`<workspace>\MayorSimulator_Authoritative_2026-08-02`
Godot：`<local Godot 4.7.1 executable>`，`4.7.1.stable.official.a13da4feb`
最終結論：**PASS**

## Gate 結果

| Gate | 結果 | 可稽核證據 |
|---|---|---|
| Canonical native + offscreen UI | PASS | `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/summary.json`：native 4/4、offscreen 33/33、總計 37；產品 diagnostics 0；來源指紋前後一致 |
| Frozen assertion matrix | PASS | `artifacts/goal-visible-qa/t3/final-assertion-freeze-20260802/summary.json`：66/66 product-clean、failed 0、environment-warning tests 0 |
| Save OS-kill recovery | PASS | `artifacts/goal-visible-qa/t3/final-save-freeze-20260802/summary.json`：5/5、173 semantic checks、forced termination 5、`all_processes_stopped=true` |
| 人工影像抽查 | PASS | 原生 start/main/settings/municipal-overlay 與離屏 public-affairs 均非空白、無錯誤覆蓋層、主要操作與文字可見 |

Native capture 為真正 Windows DisplayServer 視窗：1656×843 window/capture、logical 1414×720、root backing 1939×987。Offscreen evidence 為 2880×1800、logical 1280×800。所有 final runner 均使用各自新建且隔離的 APPDATA/LOCALAPPDATA；runner 拒絕覆寫既有 output root。

## 逐項驗收

| # | 結果 | 驗收內容與證據 |
|---|---|---|
| 1 | PASS | 原生 Windows 視窗、正確尺寸、UI 非空白；開始、HUD、設定、市政面板直接見 `final-ui-freeze-20260802/native-window/native-start-screen.png`、`native-main.png`、`native-settings.png`、`native-municipal-overlay.png`。Summary 記錄 `display_server=Windows`、native 4/4。 |
| 2 | PASS | 10×10/100 cells、極端 wheel zoom 100%→175%→65%，tile/building/NPC/transport network/vehicle 各 layer transform 與 click target 對齊。`04-map_zoom_all_layers_acceptance/stdout.log`：`Checks=253 Zooms=100/175/65`；另 `03-map_zoom_terrain_integration` PASS。 |
| 3 | PASS | 六車種 `car`、`motorcycle`、`bus`、`metro_train`、`train`、`plane` 全部由有效 authoritative network 產生，路線斷開後撤車。`09-transport_all_mode_lifecycle_contract/stdout.log`：route modes 4、private kinds 2、checks 167；公共車 route ID/path 與 network path 逐台相等，私人車 path 屬於 `private_road_paths()` 發布集合。 |
| 4 | PASS | road、metro track、heavy rail、runway、taxiway、level crossing 均受 topology/layer contract 覆蓋。`07-transport_coordinator_integration`、`08-transport_network_integration`、`36-transport_network_system`、`52-transport_network_layer` 全 PASS；後者同時驗 crossing close/reopen 與 road-vehicle interlock。 |
| 5 | PASS | NPC 避開 trees/river-lake/hill/building/construction/transport blockers，動態阻擋後重新規劃且身份不變。`62-npc_locomotion_navigation_acceptance/stdout.log`：Population 300、Proxies 24、Frames 360、DynamicReplan 1、NoRouteWait 1；`56-terrain_navigation_blocker` 與 `63-npc_navigation_grid_unit` PASS。 |
| 6 | PASS | 非平地建造先被拒絕，整平扣除正確費用、解除 navigation blocker、完成後才能進入建造，並可 save/load。`05-terrain_flatten_lifecycle/stdout.log`：checks 61；`03-map_zoom_terrain_integration` PASS。 |
| 7 | PASS | NPC distance-driven locomotion、ambient animation、transport vehicle 跨 tile movement 均有多幀狀態差異；停止時 frame/phase 不再錯誤循環。`51-transport_visual_animation`、`52-transport_network_layer`、`54-ambient_animation_contract`、`59-npc_actor_rig_contract`、`62-npc_locomotion_navigation_acceptance` 全 PASS。 |
| 8 | PASS | 民情案件 refused、accepted、completed 各自 lifecycle、按鈕 actionability 與 reload persistence。`12-public_affairs_status_rendering/stdout.log`：Requests 2、Snapshots 3、checks 64；`13-public_affairs_reload_lifecycle/stdout.log`：Requests 3、checks 142。可見畫面：`screenshots/fullscreen-public-affairs.png`。 |
| 9 | PASS | Healthcare 在 public-service lifecycle 中與其他公共服務一樣走建造、容量/效果、財政及 persistence 契約；`06-public_service_lifecycle/stdout.log`：checks 63。民情畫面亦直接顯示「醫療就在身邊」案件。 |
| 10 | PASS | Settings 的配樂/音效 slider 可見；37%/62% 變更到 Main、AudioDirector 與 AudioServer Music/SFX buses，enabled flags 與新 Main instance persistence 均驗證。`02-audio_settings_integration/stdout.log`：checks 17；`49-tutorial_audio` PASS，證明實際音訊資源/播放觸發路徑。此結論是可播放音訊管線與增益的程式驗收，不宣稱以麥克風量測喇叭聲壓。 |
| 11 | PASS | 新隔離資料中的 start/new/Continue flow、一般 save recovery 與實際 OS-kill 五階段全部通過。`34-start_screen_flow/stdout.log`、`31-save_recovery_self` PASS；save summary 為 5/5、forced termination 5，且每案恢復後可再次儲存。 |
| 12 | PASS | 結束後 `godot_4.7.1`/MayorSimulator 殘留程序數為 0；`artifacts/goal-visible-qa/t3/final-process-check.json` 保存最終檢查，save summary 另記錄 `all_processes_stopped=true`。 |

## 代表性畫面

- `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/native-window/native-start-screen.png`
- `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/native-window/native-main.png`
- `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/native-window/native-settings.png`
- `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/native-window/native-municipal-overlay.png`
- `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/screenshots/fullscreen-public-affairs.png`
- 完整 37 張 capture 與逐檔 SHA-256 位於 UI `summary.json`。

## 邊界與 provisional 排除

本報告只採用 `final-*-freeze-20260802` 三個新 evidence roots。先前的 `build-visible.log`、`engine-probe-console.log`、`ui-capture-console.log`、`ui-capture-godot.log` 及 `PROVISIONAL_STATUS.md` 是凍結前 runner 探測，明確不構成本次 PASS 證據。基準 `.tmp/sdk/...` 只用於交叉比對，沒有覆寫或納入本次 fresh 結論。

## 寫入範圍

- `artifacts/goal-visible-qa/t3/final-ui-freeze-20260802/`（canonical runner 產生的 summary、logs、隔離 appdata、4 native PNG、33 offscreen PNG）
- `artifacts/goal-visible-qa/t3/final-assertion-freeze-20260802/`（66 項結果 summary 與逐項 stdout/stderr/Godot logs、隔離 appdata）
- `artifacts/goal-visible-qa/t3/final-save-freeze-20260802/`（5 階段 OS-kill summary、markers、save images/logs、隔離 appdata）
- `artifacts/goal-visible-qa/t3/final-process-check.json`（最終 Godot/MayorSimulator 零殘留程序檢查）
- `artifacts/goal-visible-qa/t3/written-files.txt`（本次 T3 artifacts 相對檔案清單）
- `docs/acceptance/goal_visible_qa_t3.md`（本報告）

沒有修改 production、tests、tools、manifest、assertion matrix 或任何既有基準證據；沒有 commit/fetch/pull/push。
