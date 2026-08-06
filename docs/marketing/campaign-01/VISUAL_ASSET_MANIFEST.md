# Campaign 01 視覺素材清單

狀態：內部審閱；生成式 AI 輔助宣傳概念視覺。`CivicTale: Voices of Promise` 已因名稱碰撞停止使用；所有既有文字規格禁止鎖版，無字 v2 底圖可沿用。詳見 [碰撞稽核](../BRAND_NAME_AND_PROMOTION_COLLISION_AUDIT_2026-08-03.md)。  
生成方式：Codex built-in image generation（非 CLI fallback）。

名稱注意：中文《城諾之音》暫作工作名稱；英文名已因 `Civic Story` 碰撞重開。本文中的 `CivicTale: Voices of Promise` 僅是歷史文字規格，不得鎖版或外發。現有 v1 圖像仍含內部代號 `MAYOR SIMULATOR`，全部列為 **待換版／禁止公開**；不得只靠檔名或貼文文案掩蓋舊字樣。

## 1. 交付檔案

| 檔案 | 用途 | 文字 | 注意事項 |
|---|---|---|---|
| `visuals/mayor-simulator-mvp-alpha-hero-16x9-v1.png` | 原始 16:9 campaign hero | `MAYOR SIMULATOR`、`MVP ALPHA 開發中` | 宣傳概念視覺，不是 gameplay |
| `visuals/mayor-simulator-mvp-alpha-hero-1920x1080-v1.jpg` | YouTube／Facebook／Discord 橫幅衍生版 | 同上 | 1920×1080 |
| `visuals/mayor-simulator-community-4x5-v1.png` | 原始 portrait social master | `不只建造城市，也要回應城市`、`MVP ALPHA 開發中` | 原始比例由生成器決定 |
| `visuals/mayor-simulator-community-1080x1350-v1.jpg` | Instagram／Facebook feed | 同上 | 1080×1350，模糊延伸填幅以保留完整構圖 |
| `visuals/mayor-simulator-promise-9x16-v1.png` | 原始直式短影音封面 | `每個承諾，都有後果`、`MVP ALPHA 開發中` | 宣傳概念視覺，不是 gameplay |
| `visuals/mayor-simulator-promise-1080x1920-v1.jpg` | TikTok／Reels／Shorts 影格 | 同上 | 1080×1920 |
| `visuals/mayor-simulator-itch-cover-source-v1.png` | itch.io cover 原始母版 | `MAYOR SIMULATOR`、`MVP ALPHA` | Campaign concept；不是已建立頁面 |
| `visuals/mayor-simulator-itch-cover-630x500-v1.jpg` | itch.io Draft cover | 同上 | 630×500；僅供 Draft／內部審閱 |

## 2. 權利與標示

- 所有圖像均應在內部素材管理中標示 `AI-assisted campaign concept art`。
- 不得將本批 campaign art 當成遊戲內實機畫面。
- 若用於 itch.io，必須依平台 AI Disclosure 正確揭露。
- 若未來做 Steam capsule，只能保留遊戲 artwork、遊戲名稱與官方副標；需移除 `MVP ALPHA 開發中` 等額外文字，並另經權利審核。
- 目前不得對外發布，直到專案公開素材權與使用者審批都完成。

建議替代文字：

- Hero：`童話繪本風城市坐落在河谷中，市長與居民站在公告板前查看藍圖、居民來信與平衡帳本；左側標示 Mayor Simulator、MVP Alpha 開發中。`
- Community：`市長在城市公告板前聆聽三位居民提出公園、醫療與學校需求，背景是市政廳、醫院與河谷城鎮；上方寫著不只建造城市，也要回應城市。`
- Promise：`市長手持藍圖與居民信件站在三岔路口，三條路通往醫療住宅、市政中心與施工中的交通道路；上方寫著每個承諾都有後果。`
- itch.io cover：`Mayor Simulator MVP Alpha 標題下方是一座河谷童話城市，市長與居民在公告板前查看藍圖、來信與平衡帳本。`

## 3. v1 生成紀錄 Prompt Set

### Hero 16:9

```text
Use case: ads-marketing
Asset type: 16:9 landscape launch campaign key visual for the indie game Mayor Simulator
Input images: native main, blueprint and public-affairs captures as visual/game-system references only.
Primary request: Create a polished launch key visual expressing that the player builds a city and is accountable for civic promises.
Scene/backdrop: bright 2.5D isometric storybook town in a green clearing, with civic center, hospital, homes, road, residents, blueprint, resident letter and balanced budget ledger.
Style/medium: premium hand-painted children's-book game illustration, soft watercolor and painterly texture.
Composition/framing: wide cinematic 16:9; city on the right two-thirds, headline space on the left.
Text (verbatim): "MAYOR SIMULATOR" and "MVP ALPHA 開發中"
Constraints: no UI, platform logos, download buttons, release claims, trademarks or watermark; no feature-branch vehicle sprites.
```

### Community portrait

```text
Use case: ads-marketing
Asset type: portrait social-feed campaign artwork
Input images: campaign hero as style anchor; public-affairs capture as system reference only.
Primary request: Show the human side of city governance: a mayor listening to residents beside a civic notice board.
Scene/backdrop: storybook town; three resident letters represent park, healthcare and school needs; blueprint and balanced budget ledger on the board.
Style/medium: same premium hand-painted children's-book style as the hero.
Text (verbatim): "不只建造城市，也要回應城市" and "MVP ALPHA 開發中"
Constraints: no UI, download/purchase CTA, platform logos, release claim, trademarks, watermark or feature-branch vehicles.
```

### Promise 9:16

```text
Use case: ads-marketing
Asset type: 9:16 vertical cover for TikTok, Instagram Reels and YouTube Shorts
Input images: campaign hero as style anchor; judicial capture as accountability theme reference only.
Primary request: Create a vertical cover showing that every civic promise has consequences.
Scene/backdrop: mayor at a crossroads holding blueprint and resident letter; paths lead to healthcare/homes, civic hall, and an operating road/transit corridor.
Style/medium: premium hand-painted children's-book game illustration.
Text (verbatim): "每個承諾，都有後果" and "MVP ALPHA 開發中"
Constraints: no UI, purchase/download CTA, platform logos, release claim, trademarks, watermark or feature-branch vehicle sprites.
```

### itch.io cover

```text
Use case: ads-marketing
Asset type: itch.io project cover art, designed for a final 5:4 crop (630x500)
Input images: campaign hero as the approved style anchor.
Primary request: Create a compact cover that instantly reads as a storybook city-governance simulation.
Scene/backdrop: isometric valley town centered around a civic hall, hospital, homes, greenery and river; mayor and residents at a notice board with blueprint, letter and balanced budget symbol.
Style/medium: premium hand-painted children's-book game illustration.
Text (verbatim): "MAYOR SIMULATOR" and "MVP ALPHA"
Constraints: no UI, CTA, platform logos, public release claim, trademarks, watermark or feature-branch vehicle sprites; campaign concept art, not gameplay.
```

## 4. v2 工作名稱換版規格

換版統一品牌：

- 中文：`城諾之音`
- 英文：`CivicTale: Voices of Promise`
- 繁中標語：`傾聽一城之聲，兌現你許下的每個承諾。`
- 英文標語：`Hear the city. Answer for every promise.`
- 階段：`MVP ALPHA 開發中`

版面原則：

1. 社群首圖以中文《城諾之音》為主標、英文完整名為小型副標；不得把兩組長字塞成同等大小。
2. 英文市場版本以 `CivicTale` 為主標、`Voices of Promise` 為副標；保留可讀安全區。
3. itch.io cover 優先保留品牌名稱，不放完整標語，避免 630×500 縮圖不可讀。
4. `MVP ALPHA 開發中` 必須與品牌名分層，不能產生「已發布」或「現已下載」暗示。
5. v2 完成後仍須逐張核對中英文字形；生成式影像中的文字若失真，必須重新排字，不得直接發布。
