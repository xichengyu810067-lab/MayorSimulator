# 《城諾之音》／CivicTale: Voices of Promise 全專案宣發總綱與第一批跨平台文案（審閱草案）

> **命名凍結通知（2026-08-03）：** `CivicTale: Voices of Promise` 因與已上市 `Civic Story` 高度近似，已重開英文命名。本文件所有英文名、`#CivicTale` 與 `#VoicesOfPromise` 僅為歷史草稿，**禁止原樣外發**。中文《城諾之音》暫作工作名稱；詳見 [碰撞稽核](./BRAND_NAME_AND_PROMOTION_COLLISION_AUDIT_2026-08-03.md)。

日期：2026-08-03（Asia/Taipei）  
適用階段：**MVP Alpha 0.1.0-alpha.1**  
文件狀態：內部審閱草案；不得視為已發布貼文、商店頁或正式承諾

命名狀態：中文《城諾之音》暫作工作名稱；英文名因 `Civic Story` 碰撞已重開，本文中的 `CivicTale: Voices of Promise` 與相關 hashtag 僅是歷史草稿，不得外發。`Mayor Simulator` 僅為內部專案名。

首波可執行素材包：`docs/marketing/campaign-01/CAMPAIGN_01_LAUNCH_KIT.md`  
視覺清單與生成紀錄：`docs/marketing/campaign-01/VISUAL_ASSET_MANIFEST.md`

## 0. 發布前提與本輪事實基線

- 當前產品階段是 **MVP Alpha**，不是 Beta、公開 Pre-release 或正式 Release。
- 本機 Git 實況：`main`／`origin/main` 位於 `65ceea3`，已有 tag `v0.1.0-alpha.1`；目前工作分支是 `agent/transport-vehicle-sprites`，HEAD `93273e9`，比 main 多一筆「authored transport vehicle sprites」提交。
- 車輛新圖像尚未出現在 main，因此只能稱為「開發中預覽」，不能寫成 Alpha 現有正式內容。
- 使用者已於 2026-08-03 以具 `repo` scope 的 GitHub CLI 實際核對：私有 repository 的 `v0.1.0-alpha.1` GitHub **Pre-release** 已發布，僅供授權成員驗收；Windows ZIP、Linux tar.gz、`SHA256SUMS`、release evidence、Windows evidence 與兩份 startup／smoke logs 共 7 個資產齊全。這不是公開發行，文案仍不得對一般大眾寫「現在下載」「已公開上架」。
- `v0.1.0-alpha.1` tag、`main`、PR #5 車輛圖像分支的 GitHub Actions 均為成功。較早的失敗 run 已被後續成功 run 取代，不得只截取舊紅燈或反向宣稱從未失敗。
- 技術驗收基線：凍結後 assertion matrix 66/66、OS-kill save QA 5/5 與 173 項語意檢查、canonical UI 37/37，且 Goal #8 runtime／visible acceptance gap 為 0。
- 公開散布仍受根 LICENSE/COPYING、88 項 runtime 素材分發權利、city-map background source rights、train-station provenance 阻擋。可以製作內部宣發草案；不得公開發送含受阻素材的 build、素材包或下載連結。
- 任何對外發布、廣告購買、媒體聯絡、商店頁上架或 GitHub Release 修改，都要由使用者另行明確確認。

## 1. 品牌定位

### 一句話定位

**《城諾之音》（CivicTale: Voices of Promise）是一款童話繪本風的城市治理模擬遊戲：玩家不只蓋城市，也要為每一項承諾、預算與權力選擇負責。**

### 核心敘事

大多數城市建造遊戲問「你能蓋多大？」；《城諾之音》更想問：「你答應了誰、花了多少、制度是否允許，而結果真的改善了居民生活嗎？」玩家從觀察城市問題開始，提出承諾、設計藍圖、整地施工、配置服務與交通，再面對居民、財政、議會、司法與監察的回應。明亮童話外觀與可追溯公共責任，形成專案最有辨識度的反差。

### 主要受眾

1. 喜歡城市建造、管理與系統因果的玩家。
2. 喜歡政策、公共治理、議會與制度取捨的玩家。
3. 偏好可愛 2.5D／繪本視覺，但期待比純裝飾建造更深層玩法的玩家。
4. 喜歡觀察 NPC、居民故事、請求與城市生活的玩家。
5. 願意追蹤獨立遊戲從 Alpha 逐步成形、提供具體回饋的核心社群。

### 不該主打的受眾期待

- 不宣稱目前已有超大型城市、完整逐車交通、逐戶經濟或 200,000 NPC 實機能力。
- 不包裝成 Cities: Skylines 等作品的替代品或一對一功能對標。
- 不以「完整政治模擬」「所有法律自由輸入」「100% 可自訂」吸引錯誤期待。

## 2. 成熟度標籤

| 標籤 | 公開使用方式 | 禁止用法 |
|---|---|---|
| **M1 已實作且驗證** | 可寫成「目前 Alpha 已包含」「已在 MVP Alpha 驗證」 | 不得擴大到未驗證規模、品質或相鄰系統 |
| **M2 已實作但在分支／PR、尚未合併** | 只可寫「開發中預覽」「正在測試」並附分支狀態 | 不得寫成目前版本已有或可下載 |
| **M3 已定案但未實作** | 只可列「開發路線圖」「預計探索的下一階段」 | 不得給確定日期、規模或保證 |
| **M4 草案／未回答／仍有技術阻擋** | 只可寫「長期願景」「研究方向」「尚在驗證」 | 不得列功能表、銷售賣點或募資承諾 |

## 3. 全專案賣點地圖

| 領域 | 可對外敘事 | 成熟度 | 依據與邊界 |
|---|---|---:|---|
| 城市治理總循環 | 觀察—承諾—建設—營運—問責—修正；城市決策留下財政、居民與治理結果 | M1 | `city_simulation_originality_contract.md`；Goal #8 AC-01～14 已由 66-case freeze evidence 覆蓋最小閉環。只宣稱 Alpha 規模。 |
| 建造與藍圖 | 六類建築選擇、五項藍圖參數、送審倒數、核准、施工、完工與重複案件防護 | M1 | `BUILDING_BLUEPRINT_UX_REPORT.md`、`blueprint_library`／`blueprint_library_service_self` PASS。不得宣稱每棟建築都有獨立縮圖或無限客製。 |
| 財政 | 稅率與公共收費分為六類，提供月收入、支出、淨額、安全緩衝與黃紅預警 | M1 | `FISCAL_UI_REPORT.md`、`fiscal_slider_pointer`、`municipal_economy_service_self` PASS。預測是遊戲模型，不是現實財政預測。 |
| 民情／公共事務 | 居民請求可拒絕、受理、完成；狀態、日期與歷史可存檔並在 Continue 後維持 | M1 | `public_affairs_status_rendering`、`public_affairs_reload_lifecycle`、`population_self` PASS。不可宣稱所有未來請求都有獨立城市鏈。 |
| 法律與行政權 | 法案、強制施行、司法與監察風險、信任／不滿與終局失敗構成真正制衡 | M1 | `separation_of_powers`、`governance_terminal_state`、司法／監察測試 PASS。不可稱為真實法律模擬或法律建議。 |
| 議會治理 | 30 席下議院、五黨團、個別關注點與投票模型；16 票過半 | M1（核心資料／測試） | `lower_council.md` 與 `lower_council_self` PASS；文件曾稱模組獨立，宣發應聚焦「議員模型已驗證」，避免宣稱全部議會 UI／流程都已最終完成。 |
| 司法與監察 | 15 席司法委員會、10 席監察委員會；案件、辯護／答辯、裁決、彈劾與存檔 | M1 | `justice_oversight.md`、專屬 UI 報告、self／multi-case／governance integration PASS。屬遊戲化制度，不是特定國家制度的精準重現。 |
| NPC 與人口 | 具名 NPC、職業／態度／請求／事件；300 人權威人口測試、24 個可見代理、避障與動態改道 | M1 | T3 `npc_locomotion_navigation_acceptance`：Population 300、Proxies 24、Frames 360。不可宣稱 200,000 NPC。 |
| NPC 家庭、親屬、收養、債務 | 高細節家庭與債務規則已有大量企劃，部分狀態機可進資料設計 | M4 | 《遊戲專案.md》明示仍有多個未回答問題，整體未通過發布審查。只能當長期研究方向。 |
| 企業與經濟 | 希望建立公司、工廠、雇用、學徒、產品與城市經濟的相互作用 | M4 | 公司收入、成本、欠薪、借款、停產、倒閉與市場閉環未定；不得當前賣點。 |
| 公共服務 | 醫療設施需完成、可達、維護與容量條件才能產生效果；失效與修復可追溯 | M1 | `public_service_lifecycle` PASS。只直接宣稱醫療深層 lifecycle；教育／安全不得宣稱同等深度。 |
| 交通 | 道路、公車、捷運、鐵路、航空拓撲；汽車、機車、公車、捷運列車、火車、飛機由有效網路產生，斷線撤車 | M1 | T3／Goal #8 全模式 lifecycle、network layer、planning panel PASS。不要把裝飾車流寫成模擬。 |
| 新車輛圖像 | 六種 authored vehicle sprites 已在 PR #5 feature branch，PR 與 push Actions 通過 | M2 | `agent/transport-vehicle-sprites` commit `93273e9`，截至核對時未併入 main。只能做開發中預覽。 |
| 地形與整地 | 樹木、水體、山丘等阻擋施工；整地有成本、工期、導航變更與存檔 | M1 | `terrain_flatten_lifecycle`、terrain/navigation tests PASS。 |
| 地圖與縮放 | 10×10／100 cells；100%、175%、65% 下地形、建築、NPC、交通與點選對齊 | M1 | `map_zoom_all_layers_acceptance` PASS。不得暗示目前是大型地圖。 |
| 天氣 | 有 weather visual layer 與視覺矩陣測試資產 | M1（視覺層） | `weather_visual_layer` 在 66-case matrix PASS。只能說「天氣視覺效果」，不可宣稱災害、農業、經濟或交通影響。 |
| 動畫 | NPC locomotion、ambient animation、車輛跨 tile 移動與平交道互鎖由權威狀態驅動 | M1 | 多項 UI／T3 tests PASS。停止時狀態同步；不可稱電影級動畫。 |
| 音效與配樂 | 原創音訊路徑、Music／SFX 分離控制、設定持久化 | M1 | `audio_settings_integration`、`tutorial_audio` PASS；不能宣稱自動化已量測喇叭聲壓或最終混音品質。 |
| 多語系 | 繁中、簡中、英文、日文、韓文五語資料與切換狀態保存 | M1 | `localization`、`locale_switch_state_preservation`、`localized_runtime_view_model` PASS。宣傳翻譯仍需母語校對後再發布。 |
| 存檔與恢復 | New／Continue、domain round-trip、五階段 OS-kill recovery 與再次儲存 | M1 | Save QA 5/5、173 semantic checks、5 次強制終止。不可宣稱「永不壞檔」或涵蓋所有硬體故障。 |
| 視覺方向 | 可愛、明亮、童話繪本風的 2.5D 等角城市；建築、NPC、UI、自然背景素材齊備 | M1（當前視覺） | Art guide、building/NPC/icon/ambient tests。city-map 背景權利與部分 runtime 素材分發權仍未閉環，未解前不可公開散布。 |
| 長期大型模擬 | 200,000 NPC、完整家庭經濟、自由文字法律、銀行、企業、災害等 | M4 | 《遊戲專案.md》列為技術／規格阻擋或未回答事項。只能描述為研究願景，不能承諾時程與落地。 |

## 4. 可公開／不可公開資訊

### 可用於內容草案

- 遊戲名稱、MVP Alpha 階段、版本 `0.1.0-alpha.1`。
- 已驗證的核心循環與上表 M1 項目，必須保留 Alpha 範圍限定。
- 66/66、5/5、173 checks、37/37 等 QA 數據，可用於開發日誌，不適合每則消費者貼文都堆疊。
- feature branch 的六種車輛圖像可作「開發中預覽」，前提是圖像本身的公開展示權另經確認。
- M3／M4 只能以 roadmap、research、design question 的語氣公開。

### 暫不可公開或不可作已完成宣稱

- 任何 build、下載包、商店頁或受阻 runtime 素材的公開散布。
- 未合併分支／PR 的內容不得作現行版本功能；已核實的私有 GitHub Pre-release 資產也不得當作公開下載。
- 200,000 NPC、完整家庭／債務／收養、完整企業與銀行經濟、自由文字法律 AI、災害等。
- 「100% 可自訂」「完整模擬」「真實到等同現實制度」「永不壞檔」「正式發行品質」。
- 把 2880×1800 offscreen evidence 說成 native 遊戲解析度；native capture 是 1656×843。

## 5. 宣發內容支柱

1. **每個承諾都有後果**：居民請求、預算、施工、服務、議會與監督形成可追溯鏈。
2. **童話外觀，嚴謹治理**：用暖色繪本城市承載財政與制度取捨。
3. **城市不是裝飾品**：車輛來自有效路線、醫療來自可達設施、動畫投影真實狀態。
4. **居民是城市的證人**：具名 NPC、請求、態度、事件與歷史，而非只顯示人口數字。
5. **公開開發的誠實進度**：用 M1～M4 標籤呈現已驗證、預覽、路線圖與研究方向。

## 6. 第一批跨平台文案

以下每則皆為草案，尚未發送。

### Facebook／Instagram：首次亮相（中版）

> 一座城市，不只由道路和建築組成，也由每一次承諾構成。  
>  
> 《城諾之音》（CivicTale: Voices of Promise）目前正在 **MVP Alpha 0.1.0-alpha.1** 階段。我們正在打造一款童話繪本風的城市治理模擬：設計建築藍圖、安排財政與公共服務、回應居民請求，也面對議會、司法與監察帶來的制度考驗。  
>  
> 在目前的 Alpha 中，交通必須真的連通才會有車輛與收入；醫院必須完成、可達並獲得維護才會發揮作用；居民的請求與你的回應也會被保存。  
>  
> 這還不是公開正式版。我們會清楚區分「已驗證內容」「開發中預覽」與「長期研究方向」，一步一步讓這座城市長出自己的故事。  
>  
> 想先看哪一部分：居民日常、建築藍圖，還是市長的議會攻防？

- 成熟度：M1（文中明示 MVP Alpha）
- 依據：Goal #8 AC matrix；blueprint、fiscal、public affairs、governance、transport、public-service tests。
- CTA：留言選擇下一篇開發日誌主題。
- 素材：native main 畫面＋市政中心／公共事務畫面；使用前須完成素材展示權確認。

### Instagram：短版圖說

> 蓋一座城，也要為它負責。🏛️🌿  
> 《城諾之音》MVP Alpha 正在把建造、財政、居民請求、公共服務與權力制衡連成同一座會回應你的城市。  
>  
> 目前仍是開發中 Alpha；畫面與系統都會持續調整。下一張想看藍圖、居民，還是議會？

- 成熟度：M1
- 依據：原創設計契約與 freeze-final evidence。
- Hashtag：`#城諾之音 #CivicTale #城市建造 #模擬遊戲 #獨立遊戲 #GameDev #IndieGame #MVPAlpha`

### Threads：互動短文

> 城市模擬裡，你最想被追問的是哪一件事？  
> A. 預算花去哪裡  
> B. 居民的承諾有沒有完成  
> C. 法案為什麼被議會擋下  
> D. 公車為什麼沒在跑  
>  
> 《城諾之音》目前是 MVP Alpha，我們正在把這些答案做成可追溯的遊戲系統，而不是只顯示一個分數。

- 成熟度：M1
- 依據：ledger、public affairs、governance、transport lifecycle 已驗證。
- CTA：回覆 A／B／C／D，作為後續內容排序依據。

### X：短版

> Build the city. Answer for every promise.  
> **CivicTale: Voices of Promise** is now in MVP Alpha: storybook city building meets budgets, resident requests, public services, transit, council votes, courts and oversight.  
>  
> Not a public release yet—just honest, evidence-backed development. Which system should we show first?

- 成熟度：M1
- 依據：全專案已驗證垂直切片；明示未公開發行。
- Hashtag：`#CivicTale #VoicesOfPromise #IndieDev #CityBuilder #GameDev #MVPAlpha`

### Discord：社群公告（長版）

> **城諾之音｜CivicTale: Voices of Promise｜MVP Alpha 開發近況**  
> 目前版本為 `0.1.0-alpha.1`。這是一個授權成員驗收用的 Alpha 階段，不是公開正式版。  
>  
> 現階段已驗證的核心包括：建築與藍圖流程、稅率與公共收費預警、居民請求的受理／拒絕／完成與存檔、議會與司法監察、醫療服務的可達與維護條件、全模式交通拓撲、地形整地、NPC 避障、天氣視覺、動畫、音效設定、五語系切換，以及 New／Continue 與 OS-kill 存檔恢復。  
>  
> 我們也有更長期的 NPC 家庭、企業經濟與法律研究，但其中仍有未回答規格與技術阻擋，因此不會把它們當成已承諾功能。  
>  
> 下一批開發日誌想先拆解哪條因果鏈？  
> 1️⃣ 居民請求 → 醫療改善  
> 2️⃣ 藍圖送審 → 施工完工  
> 3️⃣ 路線連通 → 車輛與收入  
> 4️⃣ 強制施行 → 司法／監察風險

- 成熟度：M1；家庭／企業／自由法律部分明確為 M4。
- 依據：66-case matrix、T3 acceptance、各 UX／governance reports、《遊戲專案.md》。
- CTA：用 emoji 投票；不得附公開 build。

### Reddit：開發日誌帖

標題：`[MVP Alpha] We are building a storybook city simulator where civic promises have traceable consequences`

> Hi! We’re developing **CivicTale: Voices of Promise**, currently at MVP Alpha `0.1.0-alpha.1`.  
>  
> Our design question is simple: can a city builder make the player accountable for the promises behind construction? In the current verified slice, a resident request can be accepted, rejected or completed and survives reload; healthcare only works when the facility is built, reachable, maintained and has capacity; transport vehicles only appear on valid authoritative networks; and governance decisions can move through council, judicial and oversight systems.  
>  
> The visual direction is a bright storybook-style 2.5D city, deliberately contrasted with readable budgets and institutional consequences.  
>  
> This is not a public release announcement. Licensing and asset-distribution gates are still open, and several ambitious ideas—large-scale population, deeper family systems, enterprise finance and free-form law processing—remain research topics rather than promised features.  
>  
> We’d love feedback on the premise: which consequence should a mayor feel most strongly—resident trust, fiscal pressure, service access, or institutional checks?

- 成熟度：M1；研究項目 M4。
- 依據：原創設計契約、Goal #8 matrix、公開發行阻擋清單。
- 風險控制：避免 self-promo-only；依各 subreddit 規則調整並先確認可發。

### YouTube：60–90 秒介紹稿

> 【0–5 秒】「蓋一座城市很容易；為每個決定負責，才是市長真正的工作。」  
> 【5–18 秒】《城諾之音》是一款開發中的童話繪本風城市治理模擬，目前處於 MVP Alpha。  
> 【18–35 秒】設計藍圖、整地施工、調整稅率與公共收費，再讓道路、交通與公共服務真正運作。  
> 【35–52 秒】居民會提出請求；你的受理、拒絕與完成結果會留下歷史。法案與強制施行，也可能面對議會、司法與監察。  
> 【52–68 秒】目前 Alpha 已完成一輪功能、介面、存檔與跨平台封裝驗收；但它仍不是公開正式版。  
> 【68–80 秒】訂閱開發日誌，和我們一起決定下一次要拆解的城市因果鏈。

- 成熟度：M1
- 依據：T3、release notes、governance／blueprint／fiscal reports。
- 畫面清單：開場城市全景、藍圖五卡、財政預警、居民請求、交通斷線撤車、司法／監察、Save／Continue。
- 避免：不要顯示受阻素材的原始檔、來源包或未授權下載連結。

### TikTok／Reels／Shorts：30 秒腳本

> 【0–3 秒／畫面：城市全景】「你蓋的，不只是一座城。」  
> 【3–8 秒／藍圖】「一張藍圖，要送審、等待、施工。」  
> 【8–13 秒／醫院與道路】「一間醫院，也要真的可達、被維護。」  
> 【13–18 秒／居民請求】「答應居民的事，不能關掉視窗就忘記。」  
> 【18–24 秒／議會與監察】「權力用得太快，制度會來問責。」  
> 【24–30 秒／標題卡】「城諾之音｜MVP Alpha 開發中。追蹤下一則開發日誌。」

- 成熟度：M1
- 依據：blueprint、healthcare、public affairs、governance verified lifecycle。
- CTA：追蹤／留言指定下一支系統短片。

### Steam／itch.io：商店短描述草案

> **在童話繪本般的城市裡，建設、治理，並為每一項承諾負責。**《城諾之音》（CivicTale: Voices of Promise）是一款開發中的城市治理模擬遊戲，將建築藍圖、財政、居民請求、公共服務、交通與權力制衡連成可追溯的城市因果。

- 成熟度：M1，但**目前不可上架或公開發布**。
- 依據：全專案 verified slice。

### Steam／itch.io：關於本遊戲（長版草案）

> 《城諾之音》把城市建造與公共責任放進同一個遊戲循環。觀察城市問題、回應居民、設計建築藍圖、整地施工、配置交通與公共服務，再從帳本、民意、議會、司法與監察看見決策結果。  
>  
> **目前 MVP Alpha 已驗證內容**  
> ・建築分類、藍圖送審、施工與完工流程  
> ・稅率、公共收費、月收支與風險預警  
> ・居民請求的受理、拒絕、完成、歷史與存檔  
> ・議會投票、司法案件與監察程序的遊戲化制衡  
> ・醫療服務的建造、可達、容量、維護、失效與修復  
> ・道路、公車、捷運、鐵路與航空的有效網路與營運生命週期  
> ・地形阻擋、整地、NPC 避障、天氣視覺與狀態驅動動畫  
> ・繁中、簡中、英文、日文、韓文，以及 New／Continue 存檔流程  
>  
> 本作仍在 Alpha 階段，內容、平衡與美術都可能調整。長期人口、家庭、企業經濟與自由法律等構想仍處於規格研究，不構成目前版本功能或確定承諾。

- 成熟度：M1；末段 M4。
- 上架前置：完成 LICENSE／provenance／素材分發權、商店素材、隱私／系統需求與實際 build 核對。

## 7. 通用文案長度模板

### 超短版（20–40 字）

> 傾聽一城之聲，兌現你許下的每個承諾。《城諾之音》MVP Alpha 開發中。

### 短版（60–100 字）

> 《城諾之音》是一款童話繪本風城市治理模擬。從建築藍圖、財政與公共服務，到居民請求、交通與權力制衡，每個決定都留下可追溯的結果。目前為 MVP Alpha 開發階段。

### 中版（120–220 字）

採用 Facebook／Instagram 首次亮相稿；按平台刪減 QA 細節。

### 長版（350–600 字）

採用 Discord／Reddit／商店頁版本；必須保留階段、未公開與研究方向的限定。

## 8. CTA、Hashtag 與節奏

### CTA 庫

- 想先看哪條城市因果鏈？
- 你會先解決居民、財政、交通，還是議會壓力？
- 留言選下一篇開發日誌主題。
- 追蹤 MVP Alpha 的誠實開發進度。
- 若你是城市模擬玩家，哪個介面最需要清楚解釋？

現階段避免：「立即下載」「加入願望清單」「現在購買」「搶先體驗」；除非對應頁面與權利狀態已另行核實。

### Hashtag

- 繁中核心：`#城諾之音 #CivicTale #城市建造 #城市模擬 #模擬遊戲 #獨立遊戲 #遊戲開發`
- 英文核心：`#IndieGame #IndieDev #CityBuilder #SimulationGame #GameDev #MVPAlpha`
- 每篇建議 3–7 個；X 以 2–4 個為宜，Instagram 可增加但避免無關熱門標籤。

### 建議首月節奏（尚未發布）

| 週次 | 主題 | 主要平台 | 成熟度 |
|---|---|---|---:|
| W1 | 品牌首次亮相＋Alpha 誠實聲明 | FB、IG、Threads、X、Discord | M1 |
| W1 | 60–90 秒總覽影片 | YouTube；Shorts 切版 | M1 |
| W2 | 藍圖送審到完工 | FB、IG carousel、TikTok | M1 |
| W2 | 財政預警互動題 | Threads、X、Discord | M1 |
| W3 | 居民請求→醫療改善因果鏈 | YouTube、Reddit、FB | M1 |
| W3 | 六車種圖像開發中預覽 | IG、X、Discord | M2，僅在仍未合併時 |
| W4 | 議會／司法／監察設計日誌 | Reddit、YouTube、Discord | M1，強調遊戲化制度 |
| W4 | 下月 roadmap／研究問答 | 全平台摘要 | M3／M4，無時程保證 |

頻率建議：每週 2 篇主內容＋2～3 則短互動；Discord 可同步一篇完整 changelog。Alpha 階段品質優先，不必每日填滿。

## 9. 圖片／影片素材清單

### 現有可候選素材

- Canonical native：start、main、settings、municipal overlay 四張。
- Offscreen：public affairs、building blueprint、fiscal、judicial、oversight、transport、weather 等驗收畫面；發布時不可稱為 native capture。
- 建築：storybook_v1 建築圖像與 catalog。
- NPC：resident、student、merchant、worker、civil servant、council member、elderly 等角色與四向 walk strips／GIF。
- 音訊：`mayors-dawn-loop`、UI click、page turn、success、warning、construction complete。
- 交通：main 尚未合併前，六種 vehicle sprites 只屬 M2 預覽素材。

### 第一批必製素材

1. 16:9 品牌主視覺：城市全景＋「MVP Alpha 開發中」角標。
2. 1:1／4:5 carousel：藍圖、居民、財政、交通、治理各一張。
3. 9:16 30 秒短片：五段因果鏈＋結尾階段聲明。
4. 16:9 60–90 秒總覽：實機畫面為主，不用概念圖冒充 gameplay。
5. 成熟度角標套件：`ALPHA VERIFIED`、`DEV PREVIEW`、`ROADMAP`、`RESEARCH`。
6. 中英字幕與無字幕 clean master。

### 每份素材的必要 metadata

- 擷取 commit／branch、日期、畫面類型（native／offscreen／concept）、產品版本、成熟度、權利狀態、是否可公開。
- 概念圖明顯標 `CONCEPT ART`；測試畫面標 `ALPHA GAMEPLAY`；feature branch 標 `WORK IN PROGRESS`。

## 10. 宣發風險表

| 風險 | 等級 | 容易踩雷的說法／行為 | 安全處理 |
|---|---:|---|---|
| 公開散布權未閉環 | 極高 | 公開 build、素材包、下載連結、商店上架 | 先完成 LICENSE/COPYING、88 項資產權利、背景與 train-station provenance；未完成前只做內部審閱 |
| 私有 Pre-release 被誤寫成公開發行 | 極高 | 對一般大眾寫「已上線」「立即下載 Windows/Linux」 | 可對授權成員說私有 Pre-release 與 7 個資產已核實；公開文案只能說 MVP Alpha 開發中，且不可提供一般大眾下載 |
| feature branch 冒充正式內容 | 高 | 六車種新圖已在 Alpha | PR #5 與 Actions 通過仍不等於已合併；標 M2／WIP，合併並以新基線核對後才能升 M1 |
| 長期企劃過度承諾 | 極高 | 200,000 NPC、完整家庭、企業、銀行、自由法律已完成 | 一律 M4「研究方向」，列出未回答與效能阻擋 |
| 公共服務範圍擴張 | 高 | 所有教育／安全／公用事業都有醫療同等深度 | 只主打醫療 lifecycle；其他建築存在不等於相同模擬深度 |
| 將遊戲化制度稱為現實模擬 | 高 | 「真實法律」「完整還原法院」 | 稱「遊戲化議會、司法與監察制衡」，避免現實精準性承諾 |
| 類型作品相似性 | 高 | 使用競品名稱、UI、色碼、教學與賣點對標 | 使用《城諾之音》原創五支柱；發布前做獨立 similarity review |
| 圖像權利／AI 素材來源 | 極高 | 未核權利即上傳截圖、原圖或宣傳片 | 每張素材先查 ledger、prompt/source、公開展示權；受阻項目替換或取得授權 |
| QA 數字誤導 | 中 | 「66/66＝遊戲零 bug」「永不壞檔」 | 寫明是特定 freeze matrix／OS-kill scenarios，不推論所有環境 |
| 解析度誤述 | 中 | 2880×1800 原生遊戲畫面 | 明示 native 1656×843；2880×1800 是 offscreen evidence |
| Alpha 階段不明 | 高 | 用「上市」「正式版」「完整遊戲」 | 首段或畫面固定放 `MVP Alpha / Work in Progress` |
| 商店 CTA 過早 | 高 | 「立即購買／願望清單」但頁面不存在或不可公開 | 先用「追蹤開發日誌／留言回饋」 |
| 多語翻譯品質 | 中 | 將機器／未校稿翻譯直接當品牌文案 | 五語功能可宣稱；對外文案另做母語審校 |
| 社群平台規範 | 中 | Reddit 過度自宣、Discord mass ping、重複洗版 | 逐平台遵守規則；所有外發前取得使用者確認 |

## 11. 對外亮相與里程碑規劃

### MVP Alpha 亮相

目標不是衝下載，而是建立「誠實、可追溯、會聽回饋」的開發品牌。首波以品牌總覽、四條已驗證因果鏈與 QA 方法為主，所有內容固定標 MVP Alpha。

### Alpha 開發日誌

- 每篇只拆一條因果鏈：藍圖、居民、醫療、交通、治理、存檔、多語或天氣視覺。
- 開頭列成熟度；結尾列目前限制與下一個驗證問題。
- M2 分支預覽在合併後發布 follow-up：「從 WIP 到 verified」，建立可信度。

### Beta

只有在中控正式把產品階段升為 Beta，並有對應 fresh evidence 後才使用 Beta 字樣。主題轉向系統整合、平衡、可用性、效能與更廣泛測試。

### Pre-release channel

只在散布權、LICENSE、provenance、build 與商店／GitHub 資產全部核實後宣告。`GitHub Pre-release` 是發行標記，不能反向把產品階段自動稱為 Beta 或 Release。

### Release

需另有正式 release gate、權利閉環、平台頁面與最終測試；不得沿用 Alpha 文案只替換版本號。

## 12. 發布審批清單

每則內容發布前逐項確認：

- [ ] 產品階段與版本正確。
- [ ] 每個功能都有 M1～M4 標籤與可查依據。
- [ ] 沒有把分支／PR／草案寫成已完成。
- [ ] 圖片是 gameplay、offscreen、concept 或 WIP，標示無誤。
- [ ] 圖像、音訊、字型與第三方素材公開展示／散布權已確認。
- [ ] 沒有公開 build 或受阻資產。
- [ ] 下載、商店、願望清單與 Release 連結實際存在且已核對。
- [ ] 中英／多語文案已校對。
- [ ] 平台格式、社群規則與 hashtag 合適。
- [ ] 使用者已明確批准這一次外部發送。
