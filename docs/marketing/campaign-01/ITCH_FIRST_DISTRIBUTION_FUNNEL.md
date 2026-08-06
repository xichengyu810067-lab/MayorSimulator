# 《城諾之音》／CivicTale: Voices of Promise｜itch-first 宣發與 Steam 決策漏斗

日期：2026-08-03  
來源：策畫「超級不開心的小菜雞」與開發／多用途協作者「localhost」的討論  
狀態：內部決策草案；不構成上架承諾

> **命名凍結通知（2026-08-03）：** 英文 `CivicTale: Voices of Promise` 已重開命名。本文件的通路策略仍可審閱，但所有舊英文名稱與 hashtag 禁止外發；詳見 [碰撞稽核](../BRAND_NAME_AND_PROMOTION_COLLISION_AUDIT_2026-08-03.md)。

## 1. 已形成的團隊共識

1. 現在談 Steam 上架與分潤太早。
2. 至少要讓產品通過目前 Alpha，並走到可對外 Pre-release 的成熟度，才考慮 Steam。
3. 先以宣發導流到 itch.io，觀察真實需求，再決定是否支付 Steam Direct fee。
4. 初步口頭門檻是 itch.io 達到 100 點閱。
5. 團隊不打算在現階段開放大量測試者，且預算非常有限。

這個方向合理；需要修正的是：**100 次 raw page views 只能當第一個訊號，不能單獨作 Steam 投資決策。**

## 2. 費用事實

- Steam Direct fee 是每個新 app **100 美元或當地等值金額**。
- 它不是可直接退還的押金；當產品在 Steam Store／in-app purchases 達到至少 **1,000 美元 Adjusted Gross Revenue** 後，才會在後續付款中 recoup。
- 只有 Steamworks partner 中具 Admin 權限的使用者能支付；app credit 綁定於付款帳號，只有付款者能啟用。
- itch.io 可免費建立頁面並上傳內容；平台提供 page views、downloads 與 purchases 等使用統計。

來源：

- [Steam Direct Fee 官方說明](https://partner.steamgames.com/doc/gettingstarted/appfee?language=english)
- [itch.io Creator FAQ](https://itch.io/docs/creators/faq)

## 3. 建議漏斗

### Gate 0｜公開權利閉環

在任何公開 itch.io 頁面或下載前完成：

- 根 LICENSE／COPYING 決策。
- 88 項 runtime 素材分發權利。
- city-map background source rights。
- train-station provenance。
- Campaign art 與遊戲內生成式 AI 使用揭露策略。

未完成前，只能準備頁面內容；可使用 itch.io Draft 由擁有者編輯，或 Restricted＋download keys 做少量受控測試。Restricted 頁面不會出現在 browse、search、profile 或外部搜尋引擎。[itch.io access control](https://itch.io/docs/creators/access-control)

### Gate 1｜itch.io Draft／Restricted 預演

目的：不花 Steam 費用，先確認頁面敘事、build 下載與回饋流程。

建議規模：5–15 名受邀測試者，不做大規模開放。

驗收：

- Windows／Linux build 能從 itch.io 正確下載與啟動。
- 每名測試者收到版本、Alpha 風險、回報方式與不得轉傳說明。
- 至少 5 份有效回饋；不得只計算「拿了 key」。
- 阻斷性 crash／save／啟動問題完成分級。

### Gate 2｜公開 itch.io 試水溫

只有 Gate 0 已通過才能公開。若暫時不開放 build，可以先用公開 devlog 建立內容，但不要建立空白或誤導性的公開 project page。itch.io 提醒首次公開的時間點不會因重建頁面而重新獲得 Most Recent 曝光，應等頁面準備好再公開。

30 天觀察窗建議門檻：

| 指標 | 最低觀察值 | 為什麼 |
|---|---:|---|
| 合格頁面瀏覽 | 100 unique／可辨識訪客 | 保留團隊原本的 100 點閱共識，但排除自己重整與明顯 bot |
| 社群高意圖行為 | 10 次 | itch follow／collection、Discord 加入、明確測試登記或具體留言合計 |
| 若有 build：下載 | 10 次 | 以約 10% view→download 作最小需求訊號，不是正式 benchmark |
| 有效回饋 | 5 份 | 至少包含可理解性、興趣點或問題，不只「好玩」 |
| 來源可追蹤 | 80% 以上 | 用 UTM／平台專屬連結辨認哪些宣發有效 |
| 嚴重公開風險 | 0 | 無權利、惡意軟體、重大存檔或錯誤版本事件 |

「達標」代表可以進入 Steam 商業評估，不代表自動付款或上架。

### Gate 3｜Steam Go／No-Go

全部滿足才進一步討論：

- 產品階段至少達到團隊同意的 public Pre-release readiness，不再只是私有 MVP Alpha。
- itch.io Gate 2 在 30 天內達標，且流量不是單一朋友或一次轉貼造成。
- 已有可供 Steam 頁面使用的權利乾淨 capsule、實機 screenshot 與 trailer。
- 團隊能說清楚 Steam 頁面的目的：收 wishlist、招募測試或準備銷售。
- 100 美元費用來源、付款帳號、稅務文件與責任歸屬已書面確認。
- Steam 上線後至少有 8–12 週的內容與社群維護能力。

## 4. 團隊分工建議

| 工作 | 策畫（小菜雞） | 開發／多用途（localhost） | 宣發中控 |
|---|---|---|---|
| 產品階段與可公開範圍 | 最終決策 | 提供技術與 build 證據 | 核對文案不超範圍 |
| itch.io 頁面定位／價格 | 最終決策 | 平台實作建議 | 起草頁面與追蹤方案 |
| build／patch／下載驗證 | 驗收體驗 | 主要負責 | 整理測試說明 |
| Campaign 素材與文案 | 審批 | 核實畫面／功能 | 主要準備 |
| Steam 上架決策 | 最終決策 | 提供技術與平台資訊 | 提供需求驗證資料 |
| 任何公開發布 | 明確批准 | 執行前確認 | 不自行外發 |

## 5. 現在可以做、但不花錢的工作

1. 完成 itch.io Draft 頁面文案、cover、screenshot 順序與 FAQ。
2. 建立 UTM 命名：`utm_source`、`utm_medium`、`utm_campaign=civictale_alpha_01`。
3. 建立 5–15 人 Restricted 測試流程與回饋表。
4. 完成素材權利與 AI disclosure 清單。
5. 用 Campaign 01 社群內容先測「居民／藍圖／財政／治理」哪一支柱吸引力最高。
