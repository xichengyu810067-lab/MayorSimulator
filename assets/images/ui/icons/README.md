# 圖片主導 UI 插圖資產

> 2026-07-30：遊戲執行期已切換至 `storybook_v2/`。新版包含 36 張功能圖示與 1 張中性 fallback，統一由 `ui/theme/ui_icon_catalog.gd` 載入；本目錄原有 32 張 PNG 與 `settings.svg` 保留為可回復的 V1 資產。新版提示、語意、建置方式與驗收規格請見 [`storybook_v2/README.md`](storybook_v2/README.md)。以下內容是 V1 的歷史製作紀錄。

## 資產說明

本目錄包含 32 張 256 × 256 透明 PNG，供頂部狀態列、右下操作列、市政中心、建築選擇、藍圖設計、民情中心、城市數據與月度報告使用。所有最終圖片皆為本專案原創生成圖，沒有直接複製或下載網路圖示。

| 圖片 | 用途 |
| --- | --- |
| `city_hall.png` | 市政中心。 |
| `population.png` | 人口與居民群體。 |
| `treasury.png` | 城市資金與財政。 |
| `wellbeing.png` | 滿意度。 |
| `complaint.png` | 民怨。 |
| `trust.png` | 市政信任。 |
| `score.png` | 評分。 |
| `city_level.png` | 城市等級。 |
| `time.png` | 日期、推進一日與月底。 |
| `city_data.png` | 城市數據。 |
| `report.png` | 月度報告。 |
| `buildings.png` | 選擇建築。 |
| `governance.png` | 政策與法案。 |
| `justice.png` | 法院審判：法官審理、市長與辯護人提出證據。 |
| `oversight.png` | 監察質詢：監察委員質詢、市長進行彈劾答辯。 |
| `blueprint.png` | 設計藍圖。 |
| `public_affairs.png` | 民情中心：居民請求、民怨、市政信任與風險預警。 |
| `theme.png` | 明暗模式。 |
| `customize.png` | 建築樣式、屋頂與牆色。 |
| `demolish.png` | 拆除。 |
| `exit.png` | 離開遊戲。 |
| `building_housing.png` | 居住建築分類。 |
| `building_economy.png` | 商業與產業分類。 |
| `building_community.png` | 休閒、教育與醫療分類。 |
| `building_mobility.png` | 安全與交通分類。 |
| `building_utilities.png` | 水電、能源與廢棄物等基礎設施分類。 |
| `building_civic.png` | 行政、司法與監察等市政分類。 |
| `blueprint_material.png` | 藍圖材質。 |
| `blueprint_size.png` | 藍圖規模。 |
| `blueprint_floors.png` | 藍圖樓層。 |
| `blueprint_workers.png` | 藍圖施工人力。 |
| `blueprint_decoration.png` | 藍圖裝飾。 |

## 美術與製作方式

- 生成方式：Codex 內建圖片生成工具。
- 使用者提供的圖一：只作為「市政建築」的功能語意參考。
- 使用者提供的圖二：只作為溫暖、多元居民與兒童繪本氣氛參考。
- 共通提示：原創兒童繪本式遊戲 UI 插圖、粗而乾淨的深色輪廓、柔和手繪陰影、暖色粉彩、48–64 像素仍可辨識、無文字、無浮水印。
- 背景處理：先生成純洋紅去背底，再以柔和遮罩與去色溢轉為透明 PNG。
- 最終處理：依透明範圍裁切、加入 6% 安全留白、置中縮放為 256 × 256。

原始洋紅生成圖封存於 `assets/archives/picture-first-ui-icon-sources.zip`，供未來重新去背或放大輸出。

法院與監察兩張第二版原始洋紅圖另封存於 `assets/archives/municipal-justice-oversight-v2-sources.zip`。

建築分類與藍圖參數圖示的原始洋紅圖及完整提示摘要封存於 `assets/archives/building-blueprint-ui-icon-sources.zip`。

民情中心圖示的原始洋紅圖與完整提示保留於 `assets/images/ui/icons/sources/public_affairs/`。

### 建築與藍圖視覺化提示組

- 生成方式：Codex 內建圖片生成工具，沒有使用 CLI 後備模式。
- 共通風格：延續既有童書式市政遊戲圖示、粗深棕輪廓、暖色高飽和、柔和手繪陰影、金色功能焦點、縮小後仍能辨識。
- 建築分類：住宅群、商店與工廠、樹木與書本及診所、安全公車、公共設施塔、市政廳與天秤及放大鏡。
- 藍圖參數：木磚鋼環保材質、三種建築規模、樓層剖面、兩名工程人員、花草旗幟與窗框裝飾。
- 背景與輸出：純洋紅去背、柔和遮罩與去色溢，透明範圍裁切後保留安全邊界，置中輸出為 256 × 256 RGBA PNG。

### 法院與監察第二版提示組

- 生成方式：Codex 內建圖片生成工具，沒有使用 CLI 後備模式。
- 共通風格：延續既有可愛童書式休閒遊戲圖示、粗深色輪廓、暖色高飽和、圓潤比例、柔和手繪陰影、金色功能焦點，64 像素仍可辨識。
- 法院主題：法官在高位審判席，市長與辯護人在答辯席提出文件，保留法槌與司法天秤；不出現監察委員席。
- 監察主題：三位監察委員在弧形質詢席使用麥克風，市長於獨立答辯席提出證據，以文件放大鏡表達調查；不出現法官、法槌或司法天秤。
- 背景與輸出：純洋紅去背、柔和遮罩與去色溢，透明範圍裁切後置中輸出為 256 × 256 RGBA PNG。

## 網路研究紀錄

製作前曾比較 Kenney Game Icons、OpenGameArt Lucid Icon Pack 與 Free Game GUI；這些來源的 CC0 授權清楚，但像素風或通用介面風格與本專案不一致，因此只用於確認功能符號習慣，沒有直接整合其圖片。

- https://kenney.nl/assets/game-icons
- https://opengameart.org/content/lucid-icon-pack
- https://opengameart.org/content/free-game-gui
