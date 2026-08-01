# 下議院資料模組

本模組包含 30 席下議會的第一階段實作。模組目前獨立於主遊戲運行，不會改動既有 `GovernanceSystem`，可先單獨驗證後再接入正式流程。

## 內容

| 路徑 | 用途 |
| --- | --- |
| `data/databases/governance/lower-council/councilors.json` | 30 位議員主檔、性格、關注點、行為參數與八項歷史投票 |
| `systems/governance/lower-council/lower_council_database.gd` | JSON 載入、資料驗證、動態狀態、追加式投票歷史與存檔往返 |
| `systems/governance/lower-council/lower_council_vote_model.gd` | 30 人個別評分、民意、黨團、歷史、風險、辯論與缺席模型 |
| `tests/unit/governance/lower_council_self_test.gd` | 獨立自我測試 |

## 已完成能力

- 30 位議員與固定 16 票過半門檻。
- 五個黨團，席次為 7、7、6、6、4。
- 每位議員三項關注點，權重合計 100。
- 每位議員四項行為參數。
- 8 項現有法案、共 240 筆初始化投票歷史。
- 追加式投票紀錄與重複 `vote_id` 防護。
- 議員動態狀態，包括市長關係、選區支持、黨團關係、廉政風險、疲勞、承諾與停職。
- 個別支持分數與可解釋的分數明細。
- 地區民意、城市財政、政策效果、黨團建議、歷史慣性、風險與辯論證據修正。
- 贊成、反對、棄權、缺席四種結果。
- JSON 存檔往返與穩定雜湊。

## 投票輸入契約

法案至少需要：

- `id`：法案識別碼。
- `type`：法案類型，對應 environment、traffic、business、welfare、security、utility、industry 或 housing。

可選資料：

- `version`：法案版本，預設為 1。
- `risk_level`：0 至 100，數字越大代表風險越高。
- `concern_impacts`：覆寫法案對特定關注點的影響，範圍為 -100 至 100。

城市情境可提供：

- `game_day`
- `public_support`
- `regional_support`
- `budget_health`
- `economic_health`
- `environment_health`
- `security_health`
- `housing_pressure`
- `traffic_pressure`
- `employment_pressure`
- `projected_roi`
- `feasibility`
- `regional_need`
- `caucus_recommendations`
- `absent_member_ids`
- `concern_signals`

辯論證據使用關注點 key 與 0 至 100 的證據強度。證據只在直接對應議員前三項關注點時產生效果，效果再受到個人說服阻力限制。

## 執行測試

在專案根目錄使用 Godot 4.7 的命令列版本執行：

`Godot_v4.7-stable_win64_console.exe --headless --path . --script "res://tests/unit/governance/lower_council_self_test.gd"`

測試成功時會輸出議員數、投票紀錄數與穩定雜湊，並以結束碼 0 離開。

## 下一階段整合點

1. 讓既有治理系統持有一個 `LowerCouncilDatabase` 與 `LowerCouncilVoteModel`。
2. 以 30 人投票結果取代目前七個 `_lower_house_profiles()`。
3. 將每次初審與複決結果寫入正式存檔。
4. 在政策介面加入議員名單、個人關注點、當前立場與歷史投票。
5. 最後才把議員 `member_id` 與 NPC 身分建立一對一關聯。
