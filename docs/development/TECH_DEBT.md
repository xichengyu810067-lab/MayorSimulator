# 技術債清單

我知道這份程式碼哪裡不好、為什麼會變成這樣、打算怎麼改。數字以 2026-10-01 的 main 為準。

| 編號 | 問題 | 證據 | 影響 | 改善計畫 | 狀態 |
| --- | --- | --- | --- | --- | --- |
| TD-01 | `main.gd` 是巨型檔案：UI、狀態與遊戲規則混在一起 | [`scripts/app/main.gd`](../../scripts/app/main.gd) 9,623 行、520 個函式 | 難以閱讀、測試與分工 | 依頁面拆成 scene + controller，從財政頁開始 | 進行中：三個財政列建構函式已合併為 `_build_fiscal_row()`（−71 行） |
| TD-02 | 中文顯示文字被當成程式 ID（例：`_building_count("公園")`） | `main.gd`、[`city_tile_button.gd`](../../scripts/world/city_tile_button.gd)；正式程式碼約 1,750 行含中文 | 改字會改壞邏輯；翻譯需靠 regex 與子字串取代 | 建立穩定英文 ID 對照表；翻譯改用 key-based 的 `tr()` | 未開始 |
| TD-03 | 大量未型別化的 `Dictionary` 與字串呼叫 | 4,660 個 `.get("…")`、118 個 `.call("方法名")` | 編輯器跳轉、重構與靜態檢查失效 | 核心資料改用有型別的 class／Resource | 未開始 |
| TD-04 | UI 與核心各有一份狀態，靠 `_sync_vertical_state()` 同步；部分指標由 UI 直接寫入 | `main.gd` 的 `funds`、`population` 等屬性包裝 | 狀態不一致的風險；預設值（如資金 250,000）藏在 getter 裡 | UI 只讀取 view model，所有寫入經過指令 | 未開始 |
| TD-05 | 每支測試各自實作一份 `_check()` | 96 份重複的檢查函式 | 輸出格式不一、難以統一改進 | 抽出共用 helper，或改用 GUT／gdUnit4 | 未開始 |
| TD-06 | 人工驗收與截圖模式沒有在 CI 執行，部分已失效 | [`tests/manual/`](../../tests/manual) 的交通路線、下議院腳本會在 `municipal_overlay` 尚未建立時呼叫 `open_page()` 而中止；`building_footprint_visual_navigation_test` 的截圖模式在 9/12 地形改版後找不到可放置大型建築的平地 | 這些截圖證據目前無法重現 | 修正腳本，並在 CI 至少執行一次載入檢查 | 未開始 |
| TD-07 | CI 中同一段私有 SDK 驗證重複 3 次 | [`.github/workflows/godot-ci.yml`](../../.github/workflows/godot-ci.yml) | 改一處容易漏兩處 | 抽成 composite action | 未開始 |
| TD-08 | 儲存庫約 520 MB，大型影片與歷史 zip 未使用 Git LFS | `assets/video/`、歷史中的 `assets/archives/*.zip` | clone 很慢 | 新的大型素材改用 LFS 或 Release 附件 | 未開始 |
| TD-09 | 核心協調器以開發階段命名 | `VerticalSliceCoordinator`，`vertical_slice` 在正式程式碼出現 500 多次 | 新成員會誤以為是原型程式 | 更名為 `CityCoordinator`（需同步存檔欄位遷移） | 未開始 |
| TD-10 | 測試用的 `debug_*` 函式放在正式程式碼 | `main.gd` 的 `debug_set_npc_destination()` 等 | 公開 API 變多 | 移到測試專用 helper | 未開始 |
| TD-11 | 遊戲內仍有「Mayor Simulator」字樣 | 離開確認視窗的翻譯字串 | 品牌名稱不一致 | 更新五語系翻譯與相關測試 | 未開始（開始畫面已改為「城諾之音」） |

為什麼會變成這樣，見[專案歷程與反思](PROJECT_HISTORY.md)。
