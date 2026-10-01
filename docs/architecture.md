# 系統架構

這份文件用 5 張圖說明遊戲怎麼組成、資料怎麼流動、存檔怎麼保護。圖中的名稱都對應到實際檔案，點連結可以直接看程式碼。

## 1. 系統脈絡

```mermaid
flowchart LR
    Player(["玩家"]) -->|滑鼠操作| Game["《城諾之音》<br/>Godot 4.7 桌面程式"]
    Game -->|讀寫| Save[("本機存檔<br/>user://mayor_simulator/")]
    Dev(["開發者"]) -->|push / PR| Repo["GitHub 儲存庫"]
    Repo --> CI["GitHub Actions<br/>測試、匯出、封裝"]
    SDK["私有 SDK 儲存庫<br/>（開發工具）"] -.->|只在 CI 與本機工具使用| CI
    CI -->|內部測試封裝| Tester(["內部測試者"])
```

遊戲在執行時**沒有**網路、帳號或後端服務；所有資料都在玩家本機（[隱私說明](../PRIVACY_NOTICE.md)）。

## 2. 模組關係

```mermaid
flowchart TB
    subgraph UI["介面層"]
        Main["main.gd<br/>主畫面與 HUD"]
        Panels["ui/*<br/>市政、財政、治理、交通面板"]
    end
    subgraph App["應用層"]
        Coord["VerticalSliceCoordinator<br/>協調各系統、組裝畫面資料"]
    end
    subgraph Core["核心層"]
        Session["GameSession"]
        Kernel["SimulationKernel<br/>指令 → 事件"]
        State["CityState<br/>城市狀態"]
        SaveSvc["SaveService<br/>原子存檔"]
    end
    subgraph Systems["領域系統"]
        Construction["建設"]
        Governance["治理"]
        Population["人口"]
        Transport["交通"]
    end
    subgraph World["地圖與繪製"]
        Terrain["地形與導航"]
        Actors["居民與車輛"]
    end
    Data[("data/*<br/>建築、政策、翻譯")]
    Main --> Panels
    Main --> Coord
    Main --> World
    Coord --> Session
    Coord --> Systems
    Session --> Kernel
    Session --> SaveSvc
    Kernel --> State
    Systems --> Data
    Panels --> Data
```

| 層 | 主要檔案 |
| --- | --- |
| 介面 | [`scripts/app/main.gd`](../scripts/app/main.gd)、[`ui/`](../ui) |
| 應用 | [`scripts/app/vertical_slice_coordinator.gd`](../scripts/app/vertical_slice_coordinator.gd) |
| 核心 | [`game_session.gd`](../scripts/core/game_session.gd)、[`simulation_kernel.gd`](../scripts/core/simulation_kernel.gd)、[`city_state.gd`](../scripts/core/city_state.gd)、[`save_service.gd`](../scripts/core/save_service.gd) |
| 領域系統 | [`scripts/systems/`](../scripts/systems)、[`systems/governance/`](../systems/governance)（下議院、司法與監察） |
| 地圖與繪製 | [`scripts/world/`](../scripts/world) |
| 資料 | [`data/catalogs/`](../data/catalogs)、[`data/databases/`](../data/databases)、[`data/localization/`](../data/localization) |

## 3. 一次操作怎麼改變城市

核心狀態只透過「指令 → 事件」改變：介面送出指令，`SimulationKernel` 驗證後產生領域事件，再套用到 `CityState`。同一個亂數種子會得到同一個結果，所以測試可以重現。

```mermaid
sequenceDiagram
    actor P as 玩家
    participant UI as main.gd
    participant C as Coordinator
    participant K as SimulationKernel
    participant S as CityState
    P->>UI: 確認建造
    UI->>C: 送出建造請求
    C->>K: SimCommand（例：upsert_construction、ledger_post）
    K->>K: 驗證（地形、占地、資金）
    K->>S: DomainEvent（例：ledger.posted）
    S-->>C: 新狀態
    C-->>UI: 畫面資料（view model）
    UI-->>P: 更新地圖與 HUD
```

指令種類見 [`simulation_kernel.gd`](../scripts/core/simulation_kernel.gd)（推進日期、記帳、建築、施工、居民、排程事件、治理等）。例外：部分城市指標仍由 `main.gd` 直接寫入，列在[技術債](development/TECH_DEBT.md)。

## 4. 存檔資料模型

```mermaid
erDiagram
    SaveEnvelope ||--|| CityState : state
    SaveEnvelope ||--|| KernelSnapshot : kernel
    SaveEnvelope ||--|| ClockSnapshot : clock
    CityState ||--|| Ledger : ledger
    CityState ||--o{ Building : buildings
    CityState ||--o{ ConstructionJob : construction_jobs
    CityState ||--o{ ScheduledEvent : scheduled_events
    CityState ||--o{ EventBookEntry : event_book
    CityState ||--|| Governance : governance
    CityState ||--|| VerticalSliceSnapshot : "metadata.vertical_slice"
    VerticalSliceSnapshot ||--|| TerrainLayout : terrain
    VerticalSliceSnapshot ||--|| PopulationRecords : population
    VerticalSliceSnapshot ||--|| TransportNetwork : transport
    VerticalSliceSnapshot ||--|| TransportPlanningSession : transport_planning_session
    VerticalSliceSnapshot ||--|| ConstructionSystem : construction
    SaveEnvelope {
        int schema_version
        string content_version
        string rng_seed
        int game_time
        int event_sequence
    }
```

每個區塊各自有版本號，讀檔時會逐版遷移；比目前程式更新的版本會被拒絕。版本與可讀範圍集中在 [`data/save_schema_authority_registry.json`](../data/save_schema_authority_registry.json)：

| 區塊 | 目前版本 | 可讀版本 |
| --- | --- | --- |
| 存檔外層（SaveEnvelope） | 1 | 1 |
| 城市狀態（CityState） | 2 | 1–2 |
| 遊戲主體（vertical_slice） | 12 | 4–12 |
| 地形配置 | 4 | 見登錄表 |
| 人口、居民紀錄、交通網路、交通規劃 | 2 | 見登錄表 |

## 5. 原子存檔：程式被強制關掉也不壞檔

```mermaid
sequenceDiagram
    participant G as 遊戲
    participant T as 暫存檔
    participant P as 主存檔
    participant B as 備份 (.bak)
    G->>T: 1. 寫入完整內容
    G->>T: 2. 讀回並比對 SHA-256
    G->>B: 3. 主存檔輪替成備份
    G->>P: 4. 暫存檔安裝成主存檔
    Note over G,B: 任一步驟中斷 → 下次讀檔先驗證主存檔，壞了就改用備份，並隔離損壞檔案
```

實作在 [`save_service.gd`](../scripts/core/save_service.gd)，驗收方式是在 5 個寫檔階段用作業系統強制終止程序，再重啟檢查能否復原（[`run_save_os_kill_qa.ps1`](../tools/run_save_os_kill_qa.ps1)）。

## 6. 目錄對照

| 目錄 | 內容 |
| --- | --- |
| `scenes/` | 主場景 `Main.tscn` |
| `scripts/` | 應用、核心、領域系統、地圖繪製 |
| `systems/governance/` | 下議院、司法與監察（各自有資料與測試的獨立模組） |
| `ui/` | 面板、元件、教學、主題 |
| `data/` | 建築與政策目錄、資料結構、治理資料、翻譯 |
| `assets/` | 圖片、音訊、影片 |
| `tests/` | 單元、整合、UI、QA 專項、人工驗收腳本 |
| `tools/` | 測試執行器、封裝、素材與翻譯工具 |
| `docs/` | 文件（[文件導覽](README.md)） |
