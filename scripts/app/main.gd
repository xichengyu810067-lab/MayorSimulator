extends Control

signal application_quit_requested

const Buildings = preload("res://data/catalogs/buildings.gd")
const BuildingVisuals = preload("res://data/catalogs/building_visuals.gd")
const Policies = preload("res://data/catalogs/policies.gd")
const CityBackdrop = preload("res://scripts/world/city_backdrop.gd")
const CityTileButton = preload("res://scripts/world/city_tile_button.gd")
const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const NpcMapControllerScript = preload("res://scripts/app/npc_map_controller.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")
const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CitySimulationServiceScript = preload("res://scripts/app/city_simulation_service.gd")
const CityReportHistoryServiceScript = preload("res://scripts/app/city_report_history_service.gd")
const MunicipalEconomyServiceScript = preload("res://scripts/app/municipal_economy_service.gd")
const VerticalSlicePanelScript = preload("res://ui/shell/vertical_slice_panel.gd")
const MunicipalOverlayScript = preload("res://ui/shell/municipal_overlay.gd")
const JusticeOversightPanelScript = preload("res://ui/governance/justice_oversight_panel.gd")
const LowerCouncilStageScript = preload("res://ui/governance/lower_council_stage.gd")
const PublicAffairsPanelScript = preload("res://ui/shell/public_affairs_panel.gd")
const BuildingContextPanelScript = preload("res://ui/shell/building_context_panel.gd")
const ExitConfirmOverlayScript = preload("res://ui/shell/exit_confirm_overlay.gd")
const ConstructionConfirmOverlayScript = preload("res://ui/shell/construction_confirm_overlay.gd")
const StartScreenScript = preload("res://ui/shell/start_screen.gd")
const WeatherVisualLayerScript = preload("res://ui/effects/weather_visual_layer.gd")
const SettingsOverlayScript = preload("res://ui/shell/settings_overlay.gd")
const IntroCinematicScript = preload("res://ui/tutorial/intro_cinematic.gd")
const OnboardingProgressScript = preload("res://scripts/app/onboarding_progress.gd")
const OnboardingActionRouterScript = preload("res://scripts/app/onboarding_action_router.gd")
const OnboardingGuideScript = preload("res://ui/tutorial/onboarding_guide.gd")
const AudioDirectorScript = preload("res://scripts/audio/audio_director.gd")
const UserSettingsServiceScript = preload("res://scripts/app/user_settings_service.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const CityDataDashboardScript = preload("res://ui/shell/city_data_dashboard.gd")
const TransportPlanningPanelScript = preload("res://ui/shell/transport_planning_panel.gd")
const TransportNetworkLayerScript = preload("res://scripts/world/transport_network_layer.gd")
const TransportVehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const ProgressiveChoicePagerScript = preload("res://ui/components/progressive_choice_pager.gd")
const ModalPointerGuardScript = preload("res://ui/components/modal_pointer_guard.gd")
const NpcDialogueCardScript = preload("res://ui/components/npc_dialogue_card.gd")
const CityMetricCardScript = preload("res://ui/components/city_metric_card.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")
const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")
const VERSION_UPDATES_PATH := "res://data/version_updates.json"
const QA_RELEASE_SMOKE_ARG_PREFIX := "--qa-release-smoke-frames="
# Resident records store personal currency units. City treasury calculations
# use a documented scale so tax revenue follows real resident income without
# destabilizing the existing municipal-budget balance.
const RESIDENT_INCOME_TREASURY_SCALE := 0.0005

const GRID_SIZE := CityTerrainMapScript.GRID_COLUMNS
const CELL_COUNT := CityTerrainMapScript.CELL_COUNT
const GRID_CELL_SIZE := SquareGridLayoutScript.CELL_SIZE
# Compatibility aliases for existing integrations. Their values now describe
# the square grid, not an isometric projection.
const ISO_TILE_SIZE := GRID_CELL_SIZE
const ISO_TILE_STEP := GRID_CELL_SIZE
const ISO_MAP_ORIGIN := SquareGridLayoutScript.GRID_ORIGIN
const MAP_STAGE_SIZE := SquareGridLayoutScript.STAGE_SIZE
const MAP_BACKGROUND_PATH := "res://assets/images/world/backgrounds/city-map-background.png"
const MAP_ZOOM_MIN := 0.65
const MAP_ZOOM_MAX := 1.75
const MAP_ZOOM_STEP := 0.10
const MAP_LEFT_DRAG_THRESHOLD := 8.0
const TERRAIN_LABELS := {
	"flat_grass": "平坦草地",
	"trees": "樹林",
	"hill_cliff": "山丘",
	"river_lake": "河流／湖泊",
	"road_path": "道路",
	"rail_track": "軌道",
}
const BUILDING_CATEGORIES := [
	"住宅類",
	"商業類",
	"產業類",
	"休閒類",
	"教育文化類",
	"醫療類",
	"安全類",
	"交通類",
	"基礎建設類",
	"行政類"
]
const BUILDING_GROUPS := [
	{"id": "housing", "title": "居住", "icon": "building_housing", "categories": ["住宅類"]},
	{"id": "economy", "title": "經濟", "icon": "building_economy", "categories": ["商業類", "產業類"]},
	{"id": "community", "title": "生活服務", "icon": "building_community", "categories": ["休閒類", "教育文化類", "醫療類"]},
	{"id": "mobility", "title": "安全交通", "icon": "building_mobility", "categories": ["安全類", "交通類"]},
	{"id": "utilities", "title": "基礎設施", "icon": "building_utilities", "categories": ["基礎建設類"]},
	{"id": "civic", "title": "市政", "icon": "building_civic", "categories": ["行政類"]}
]
const BUILDING_FAMILIES := [
	{"id": "daily", "title": "生活發展", "groups": ["housing", "economy"]},
	{"id": "services", "title": "公共服務", "groups": ["community", "mobility"]},
	{"id": "systems", "title": "城市系統", "groups": ["utilities", "civic"]},
]

const UTILITY_DEFS := {
	"garbage": {"name": "垃圾處理費", "min": 0, "max": 100, "default": 20, "reasonable": 20, "unit": "戶", "basis": "按住戶", "building": "垃圾處理場"},
	"water": {"name": "水費", "min": 0, "max": 120, "default": 25, "reasonable": 25, "unit": "戶", "basis": "按住戶", "building": "自來水廠"},
	"electricity": {"name": "電費", "min": 0, "max": 150, "default": 30, "reasonable": 30, "unit": "戶", "basis": "按住戶與商業/工業用量", "building": "發電廠"},
	"gas": {"name": "瓦斯費", "min": 0, "max": 120, "default": 20, "reasonable": 20, "unit": "戶", "basis": "按住戶", "building": "瓦斯場"}
}

const TAX_DEFS := {
	"income": {"name": "所得稅", "min": 0, "max": 30, "default": 10, "reasonable": 10, "unit": "所得 %", "basis": "居民所得"},
	"consumption": {"name": "消費稅", "min": 0, "max": 20, "default": 5, "reasonable": 5, "unit": "消費額 %", "basis": "居民與商業消費"},
	"business": {"name": "商業營業稅", "min": 0, "max": 25, "default": 8, "reasonable": 8, "unit": "商業營業額 %", "basis": "商店與大型商場營業額"},
	"industry": {"name": "工業營業稅", "min": 0, "max": 25, "default": 10, "reasonable": 10, "unit": "工業營業額 %", "basis": "工廠與產業營業額"}
}

const SERVICE_DEFS := {
	"bus": {"name": "公車票", "min": 0, "max": 80, "default": 15, "reasonable": 15, "unit": "次", "basis": "按搭乘次數", "building": "公車站", "base_uses": 18},
	"metro": {"name": "捷運票", "min": 0, "max": 120, "default": 30, "reasonable": 30, "unit": "次", "basis": "按搭乘次數", "building": "捷運站", "base_uses": 24},
	"train": {"name": "火車票", "min": 0, "max": 180, "default": 45, "reasonable": 45, "unit": "次", "basis": "按搭乘次數", "building": "火車站", "base_uses": 20},
	"air": {"name": "機場旅客服務費", "min": 0, "max": 500, "default": 120, "reasonable": 120, "unit": "人次", "basis": "按有效航線旅客", "building": "機場", "base_uses": 8},
	"parking": {"name": "停車費", "min": 0, "max": 100, "default": 20, "reasonable": 20, "unit": "次", "basis": "按停車次數", "building": "停車場", "base_uses": 14},
	"medical": {"name": "看病費", "min": 0, "max": 180, "default": 50, "reasonable": 50, "unit": "次", "basis": "按就診次數", "building": "醫院", "base_uses": 8},
	"tuition": {"name": "學費", "min": 0, "max": 240, "default": 100, "reasonable": 100, "unit": "人", "basis": "按學生人數", "building": "學校", "base_uses": 0.22},
	"stadium": {"name": "體育館門票", "min": 0, "max": 160, "default": 80, "reasonable": 80, "unit": "次", "basis": "按入場次數", "building": "體育館", "base_uses": 10}
}

const FISCAL_CATEGORY_SPECS := [
	{"id": "resident_tax", "title": "居民稅", "items": [{"kind": "tax", "key": "income"}, {"kind": "tax", "key": "consumption"}]},
	{"id": "industry_tax", "title": "產業稅", "items": [{"kind": "tax", "key": "business"}, {"kind": "tax", "key": "industry"}]},
	{"id": "utilities", "title": "水電", "items": [{"kind": "utility", "key": "water"}, {"kind": "utility", "key": "electricity"}]},
	{"id": "environment_energy", "title": "環境能源", "items": [{"kind": "utility", "key": "garbage"}, {"kind": "utility", "key": "gas"}]},
	{"id": "city_services", "title": "城市服務", "items": [{"kind": "service", "key": "parking"}, {"kind": "service", "key": "medical"}]},
	{"id": "education_leisure", "title": "教育休閒", "items": [{"kind": "service", "key": "tuition"}, {"kind": "service", "key": "stadium"}]},
]

const GOVERNANCE_STATUS_ORDER := ["implemented", "review", "unimplemented"]
const GOVERNANCE_STATUS_TITLES := {
	"unimplemented": "未實施",
	"review": "審核中",
	"implemented": "已實施",
}
const GOVERNANCE_DOMAIN_LABELS := {
	"environment": "環境",
	"traffic": "交通",
	"business": "經濟",
	"welfare": "社福",
	"security": "治安",
	"utility": "公共費用",
	"industry": "產業",
	"housing": "住宅",
}

const BUILDING_VISUALS := BuildingVisuals.BY_DISPLAY_NAME

const CUSTOMIZABLE_BUILDINGS := ["住宅", "社會住宅", "商店", "大型商場", "市政府", "公園", "學校"]
const CUSTOM_VARIANTS := ["花草", "旗幟", "窗框"]
const CUSTOM_ROOF_COLORS := ["藍頂", "紅頂", "綠頂", "紫頂", "粉頂"]
const CUSTOM_WALL_COLORS := ["米白牆", "淡黃牆", "淡藍牆", "淡粉牆", "薄荷牆"]
const NPC_TYPES := ["一般居民", "學生", "商人", "老年居民", "工人", "公務人員", "議員"]
const TRANSPORT_SESSION_STATIONS := ["公車站", "捷運站", "火車站", "機場"]

const COLOR_APP_BG := Color(0.86, 0.91, 0.95)
const COLOR_PANEL := Color(0.98, 0.99, 1.0)
const COLOR_PANEL_ALT := Color(0.93, 0.97, 0.99)
const COLOR_NAVY := Color(0.07, 0.17, 0.26)
const COLOR_TEXT := Color(0.07, 0.12, 0.18)
const COLOR_MUTED := Color(0.24, 0.31, 0.38)
const COLOR_ACCENT := Color(0.05, 0.43, 0.70)
const COLOR_ACCENT_DARK := Color(0.03, 0.31, 0.52)
const COLOR_SUCCESS := Color(0.05, 0.42, 0.23)
const COLOR_WARNING := Color(0.77, 0.18, 0.08)
const COLOR_CAUTION := Color(0.82, 0.55, 0.05)
const COLOR_INFO := Color(0.05, 0.43, 0.70)
const COLOR_GOLD := Color(0.95, 0.72, 0.16)
const DATA_ICONS := {
	"month": "◷", "funds": "$", "population": "人", "satisfaction": "♥",
	"grievance": "!", "trust": "◆", "score": "★", "rating": "◈",
	"治安": "安", "環境": "環", "交通": "交", "教育": "教", "醫療": "醫",
	"security": "安", "environment": "環", "traffic": "交", "education": "教", "healthcare": "醫",
	"tax_income": "$", "business_income": "商", "commercial_income": "商", "industrial_income": "工",
	"utility_income": "公", "service_income": "服", "maintenance": "修", "monthly_expense": "支",
	"policy_expense": "策", "law_expense": "法", "net_income": "Σ", "job_attraction": "業",
	"score_bonus": "★", "business_bonus": "商", "industrial_bonus": "工"
}

# Full-screen readability baseline. Persistent controls are compact floating HUDs;
# they never reserve layout space away from the map.
const UI_MIN_FONT_SIZE := 19
const UI_CONTROL_FONT_SIZE := 21
const UI_HUD_BUTTON_SIZE := 72
const UI_STATUS_HEIGHT := 72
const UI_HUD_EDGE_INSET := 12.0
const UI_HUD_GAP := 12
const UI_HUD_PANEL_PADDING := 12
const UI_MAP_SAFE_TOP_PADDING := 10.0
const UI_MAP_VISUAL_TOP_MARGIN := 18.0
const TOAST_SUCCESS_TEXT := Color(0.68, 1.0, 0.80)
const TOAST_WARNING_TEXT := Color(1.0, 0.74, 0.62)
const AUTOSAVE_INTERVAL_SECONDS := 600.0
const NPC_DIALOGUE_DURATION_SECONDS := 4.5

var buildings: Dictionary = Buildings.all()
var policies: Dictionary = Policies.all()
var selected_building := "住宅"
var city_grid: Array[String] = []
var grid_buttons: Array[Button] = []
var building_buttons: Dictionary = {}
var building_group_buttons: Dictionary = {}
var building_group_pages: Dictionary = {}
var building_card_pagers: Dictionary = {}
var building_family_tabs: TabContainer
var selected_building_group := "housing"
var policy_checks: Dictionary = {}
var labels: Dictionary = {}
var bars: Dictionary = {}
var header_bars: Dictionary = {}
var group_bars: Dictionary = {}
var finance_bars: Dictionary = {}
var tax_sliders: Dictionary = {}
var utility_sliders: Dictionary = {}
var service_sliders: Dictionary = {}
var tax_inputs: Dictionary = {}
var utility_inputs: Dictionary = {}
var service_inputs: Dictionary = {}
var fiscal_apply_button: Button
var fiscal_discard_button: Button
var fiscal_preview_button: Button
var fiscal_back_to_edit_button: Button
var fiscal_draft_status_label: Label
var fiscal_category_surface: VBoxContainer
var fiscal_category_grid: GridContainer
var fiscal_plan_surface: VBoxContainer
var fiscal_plan_title: Label
var fiscal_plan_hint: Label
var fiscal_custom_editor: VBoxContainer
var fiscal_custom_pages: Dictionary = {}
var fiscal_draft_preview: PanelContainer
var fiscal_draft_change_list: Label
var fiscal_draft_risk_label: Label
var fiscal_responsive_layout: GridContainer
var fiscal_page_scroll: ScrollContainer
var _selected_fiscal_category := ""
var _selected_fiscal_plan := ""
var _fiscal_draft_active := false
var _fiscal_draft_tax_rates: Dictionary = {}
var _fiscal_draft_utility_fees: Dictionary = {}
var _fiscal_draft_service_fees: Dictionary = {}
var _fiscal_draft_base_tax_rates: Dictionary = {}
var _fiscal_draft_base_utility_fees: Dictionary = {}
var _fiscal_draft_base_service_fees: Dictionary = {}
var _fiscal_apply_generation := 0
var _fiscal_flow_step := "edit"
var _fiscal_draft_revision := 0
var _fiscal_preview_revision := -1
var bill_buttons: Dictionary = {}
var governance_status_tabs: TabContainer
var governance_status_grids: Dictionary = {}
var governance_status_pagers: Dictionary = {}
var governance_status_sections: Dictionary = {}
var governance_status_empty_labels: Dictionary = {}
var governance_bill_cards: Dictionary = {}
var governance_policy_cards: Dictionary = {}
var governance_catalog_title: Control
var governance_catalog_legend: Control
var governance_force_panel: Control
var lower_council_stage
var _lower_council_final_decision: Dictionary = {}
var settings_button: Button
var municipal_button: Button
var exit_button: Button
var language_selector: OptionButton
var selected_label: Label
var hint_label: Label
var report_label: Label
var report_details_label: Label
var report_details_panel: Control
var report_details_button: Button
var announcement_label: Label
var bill_status_label: Label
var map_viewport: Control
var map_stage: Control
var city_backdrop: Control
var map_viewport_background: TextureRect
var tile_layer: Control
var npc_layer: Control
var transport_network_layer
var transport_vehicle_controller
var weather_visual_layer: Control
var npc_dialogue_card
var npc_dialogue_label: Label
var npc_map_controller
var building_info_label: Label
var customization_label: Label
var vertical_slice_panel
var judicial_panel
var oversight_panel
var public_affairs_panel
var building_context_panel
var city_data_dashboard
var transport_planning_panel
var governance_force_label: Label
var governance_force_button: Button
var vertical_slice
var city_report_history_service = CityReportHistoryServiceScript.new()
var municipal_overlay
var exit_confirmation
var start_screen
var settings_overlay
var tutorial_overlay
var onboarding_guide
var onboarding_progress = OnboardingProgressScript.new()
var onboarding_action_router = OnboardingActionRouterScript.new(onboarding_progress)
var audio_director
var construction_confirmation
var action_dock: Control
var status_hud: Control
var feedback_toast: Control
var placement_banner: Control
var placement_label: Label
var placement_cancel_button: Button
var placement_level_button: Button
var placement_confirm_button: Button
var placement_rotate_button: Button
var _hint_tween: Tween
var quit_application_on_confirm := true
var _quit_shutdown_in_progress := false
var _qa_release_smoke_active := false
var _qa_release_smoke_frames_remaining := -1
var _modal_grid_intent_block_until_process_frame := -1
var _npc_keyboard_dismiss_waiting_for_cancel_release := false
var _start_save_path := ""
var start_save_path: String:
	get:
		return _start_save_path
	set(value):
		_start_save_path = value
		if vertical_slice != null:
			vertical_slice.set_save_path(value)
var _game_started := false
var tutorial_completed := false
var _tutorial_replay_active := false
var music_enabled := true
var sfx_enabled := true
var music_volume := 1.0
var sfx_volume := 1.0
var _audio_preferences_found := false
var _pending_start_success := false
var _pending_start_message := ""
var _autosave_elapsed_seconds := 0.0
var _autosave_in_progress := false
var _autosave_count := 0
var _last_autosave_reason := ""
var placement_mode_active := false
var placement_building_name := ""
var placement_rotation_quarter_turns_ccw := 0
var _placement_preview_anchor := -1
var _placement_preview: Dictionary = {}
var _pending_construction_tile := -1
var _pending_construction_workers := 5
var _pending_construction_rotation_quarter_turns_ccw := 0
var _pending_terrain_tile := -1
var map_action_mode := "inspect"
var transport_plan_kind := ""
var transport_plan_operation := ""
var transport_plan_tiles: Array[int] = []
var transport_route_mode := ""
var transport_route_station_tiles: Array[int] = []
var transport_route_fleet_size := 2
var transport_route_headway_minutes := 10
var transport_route_fare := 30
var map_zoom := 1.0
var map_pan_offset := Vector2.ZERO
var _map_pan_drag_active := false
var _map_pan_drag_pending := false
var _map_pan_drag_uses_left_button := false
var _map_button_release_cancellation_pending := false
var _map_buttons_waiting_for_cancelled_release: Dictionary = {}
var _map_pan_drag_origin := Vector2.ZERO
var _map_pan_drag_last_position := Vector2.ZERO
var _npc_dialogue_remaining_seconds := 0.0
var _active_npc_dialogue_index := -1
var _npc_proxy_refresh_pending := false

var month := 1
var day := 1
var funds: int:
	get:
		return vertical_slice.treasury_balance() if vertical_slice != null else 250_000
var population: int:
	get:
		return _authoritative_metric_value("population", 300)
var month_start_population := 300
var tax_rate := 10
var total_satisfaction: int:
	get:
		return _authoritative_metric_value("satisfaction", 70)
	set(value):
		_set_authoritative_metric_value("satisfaction", value)
var security: int:
	get:
		return _authoritative_metric_value("security", 70)
	set(value):
		_set_authoritative_metric_value("security", value)
var environment: int:
	get:
		return _authoritative_metric_value("environment", 70)
	set(value):
		_set_authoritative_metric_value("environment", value)
var traffic: int:
	get:
		return _authoritative_metric_value("traffic", 70)
	set(value):
		_set_authoritative_metric_value("traffic", value)
var education: int:
	get:
		return _authoritative_metric_value("education", 70)
	set(value):
		_set_authoritative_metric_value("education", value)
var healthcare: int:
	get:
		return _authoritative_metric_value("healthcare", 70)
	set(value):
		_set_authoritative_metric_value("healthcare", value)
var ranking_score := 0
var best_score := 0
var city_rating := "B 級城市"
var last_report := "歡迎市長上任。請選擇建築、調整稅率與政策，然後進入下個月。"
var last_report_details := "尚無月度明細。"
var last_month_summary: Dictionary:
	get:
		return city_report_history_service.last_month_summary
	set(value):
		city_report_history_service.set_last_month_summary(value)
var monthly_report_history: Array[Dictionary]:
	get:
		return city_report_history_service.monthly_report_history
	set(value):
		city_report_history_service.replace_monthly_report_history(value, _city_report_metric_snapshot())
var major_event_history: Array[Dictionary]:
	get:
		return city_report_history_service.major_event_history
	set(value):
		city_report_history_service.replace_major_event_history(value)
var version_updates: Array[Dictionary] = []
var active_policies: Dictionary = {}
var city_metric_cards: Dictionary = {}
var city_metric_primary_grid: GridContainer
var city_metric_secondary_grid: GridContainer
var city_metric_priority_label: Label
var city_metric_details_button: Button
var city_data_show_all := false
var _city_metric_layout_signature := ""
var benchmark_charts: Dictionary = {}
var monthly_data_kpi_charts: Dictionary = {}
var monthly_data_service_charts: Dictionary = {}
var is_dark_mode := false
var tax_rates := {"income": 10, "consumption": 5, "business": 8, "industry": 10}
var utility_fees := {"garbage": 20, "water": 25, "electricity": 30, "gas": 20}
var service_fees := {"parking": 20, "medical": 50, "tuition": 100, "stadium": 80}
var announcements: Array[String] = []
var last_population_reason := "人口維持穩定。"
var selected_cell_index := -1
var building_customizations: Dictionary = {}
var healthcare_applied_bonus := 0
var _healthcare_legacy_migration_applied := true
var ambient_time := 0.0
var group_satisfaction := {
	"一般居民": 70,
	"學生家庭": 70,
	"商人": 70,
	"老年居民": 70
}


func _authoritative_city_state():
	if vertical_slice == null or vertical_slice.session == null:
		return null
	return vertical_slice.session.state


func _authoritative_metric_value(metric_name: String, fallback: int) -> int:
	var city_state = _authoritative_city_state()
	if city_state == null:
		return fallback
	return int(city_state.metric_value(metric_name, fallback))


func _set_authoritative_metric_value(metric_name: String, value: int) -> void:
	var city_state = _authoritative_city_state()
	if city_state == null:
		return
	city_state.set_metric_value(metric_name, _clamp_score(value))


func _city_metrics_snapshot() -> Dictionary:
	return {
		"population": population,
		"satisfaction": total_satisfaction,
		"security": security,
		"environment": environment,
		"traffic": traffic,
		"education": education,
		"healthcare": healthcare,
	}


func _city_report_metric_snapshot() -> Dictionary:
	var snapshot := _city_metrics_snapshot()
	snapshot["score"] = ranking_score
	return snapshot


func _apply_city_metric_patch(patch: Dictionary) -> void:
	var city_state = _authoritative_city_state()
	if city_state == null:
		return
	var normalized: Dictionary = {}
	for metric_name_variant: Variant in patch.keys():
		var metric_name := str(metric_name_variant)
		if metric_name in ["satisfaction", "security", "environment", "traffic", "education", "healthcare"]:
			normalized[metric_name] = _clamp_score(int(patch[metric_name_variant]))
	city_state.set_metric_values(normalized)


func _initialize_city_metric_defaults() -> void:
	_apply_city_metric_patch({
		"satisfaction": 70,
		"security": 70,
		"environment": 70,
		"traffic": 70,
		"education": 70,
		"healthcare": 70,
	})

func _ready() -> void:
	get_tree().auto_accept_quit = false
	if not L10n.locale_changed.is_connected(Callable(self, "_on_locale_changed")):
		L10n.locale_changed.connect(Callable(self, "_on_locale_changed"))
	var audio_preferences: Dictionary = UserSettingsServiceScript.load_audio_preferences()
	_audio_preferences_found = bool(audio_preferences.get("found", false))
	music_enabled = bool(audio_preferences.get("music_enabled", true))
	sfx_enabled = bool(audio_preferences.get("sfx_enabled", true))
	music_volume = clampf(float(audio_preferences.get("music_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(audio_preferences.get("sfx_volume", 1.0)), 0.0, 1.0)
	vertical_slice = VerticalSliceCoordinatorScript.new(20_260_715, funds)
	_initialize_city_metric_defaults()
	vertical_slice.set_save_path(start_save_path)
	for i in CELL_COUNT:
		city_grid.append("")
	for policy_name in policies.keys():
		active_policies[policy_name] = false
	_sync_vertical_state()
	audio_director = AudioDirectorScript.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	audio_director.set_music_enabled(music_enabled)
	audio_director.set_sfx_enabled(sfx_enabled)
	audio_director.set_music_volume(music_volume)
	audio_director.set_sfx_volume(sfx_volume)

	_build_ui()
	audio_director.start_music()
	_recalculate_satisfaction()
	_recalculate_score()
	_update_ui()
	vertical_slice.set_time_paused(true)
	_configure_release_smoke_from_user_args()

func _process(delta: float) -> void:
	_layout_map_stage()
	_update_ambient(delta)
	if npc_map_controller != null:
		npc_map_controller.step(delta)
	if vertical_slice != null:
		var previous_game_day: int = vertical_slice.game_day()
		var events: Array[Dictionary] = vertical_slice.process_frame(delta, _vertical_city_context(), false)
		var day_changed: bool = vertical_slice.game_day() != previous_game_day
		if day_changed or not events.is_empty():
			_consume_vertical_events(events)
			_sync_vertical_state()
			_update_ui()
			if day_changed:
				_refresh_onboarding_guide()
			if day_changed and events.is_empty():
				_autosave("event:day_advanced")
	_update_autosave_timer(delta)
	_process_release_smoke_frame()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = _theme_bg()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var map := _build_map_panel()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(map)
	weather_visual_layer = WeatherVisualLayerScript.new()
	weather_visual_layer.set_game_day(vertical_slice.game_day() if vertical_slice != null else 0)
	add_child(weather_visual_layer)

	status_hud = _build_compact_status_hud()
	add_child(status_hud)
	feedback_toast = _build_feedback_toast()
	add_child(feedback_toast)
	placement_banner = _build_placement_banner()
	add_child(placement_banner)
	action_dock = _build_action_dock()
	add_child(action_dock)
	building_context_panel = BuildingContextPanelScript.new()
	building_context_panel.set_dark_mode(is_dark_mode)
	building_context_panel.action_requested.connect(Callable(self, "_on_building_context_action"))
	add_child(building_context_panel)

	settings_overlay = SettingsOverlayScript.new()
	settings_overlay.set_dark_mode(is_dark_mode)
	settings_overlay.set_audio_enabled(music_enabled, sfx_enabled, music_volume, sfx_volume)
	settings_overlay.theme_selected.connect(func(dark_mode: bool) -> void: _set_theme(dark_mode, true))
	settings_overlay.music_selected.connect(Callable(self, "_on_music_selected"))
	settings_overlay.sfx_selected.connect(Callable(self, "_on_sfx_selected"))
	settings_overlay.music_volume_selected.connect(Callable(self, "_on_music_volume_selected"))
	settings_overlay.sfx_volume_selected.connect(Callable(self, "_on_sfx_volume_selected"))
	settings_overlay.tutorial_requested.connect(Callable(self, "_replay_tutorial"))
	add_child(settings_overlay)
	language_selector = settings_overlay.language_selector
	construction_confirmation = ConstructionConfirmOverlayScript.new()
	construction_confirmation.set_dark_mode(is_dark_mode)
	construction_confirmation.confirmed.connect(Callable(self, "_confirm_pending_construction"))
	construction_confirmation.cancelled.connect(Callable(self, "_on_construction_confirmation_cancelled"))
	add_child(construction_confirmation)
	exit_confirmation = ExitConfirmOverlayScript.new()
	exit_confirmation.confirmed.connect(Callable(self, "_confirm_application_quit"))
	exit_confirmation.discard_confirmed.connect(Callable(self, "_confirm_discard_and_quit"))
	add_child(exit_confirmation)
	if not _game_started:
		start_screen = StartScreenScript.new()
		start_screen.set_continue_available(_has_start_save())
		start_screen.game_requested.connect(Callable(self, "_begin_start_flow"))
		start_screen.load_action_requested.connect(Callable(self, "_perform_start_load"))
		start_screen.loading_finished.connect(Callable(self, "_finish_start_load"))
		add_child(start_screen)
	# Keep the established property name for save/test compatibility, but the
	# formal entry now owns the multi-shot CG rather than the text-only overlay.
	tutorial_overlay = IntroCinematicScript.new()
	tutorial_overlay.completed.connect(Callable(self, "_on_tutorial_completed"))
	tutorial_overlay.audio_cue.connect(Callable(self, "_on_tutorial_audio_cue"))
	add_child(tutorial_overlay)
	onboarding_guide = OnboardingGuideScript.new()
	onboarding_guide.set_dark_mode(is_dark_mode)
	onboarding_guide.advanced.connect(Callable(self, "_on_onboarding_advanced"))
	onboarding_guide.defer_requested.connect(Callable(self, "_on_onboarding_defer_requested"))
	onboarding_guide.result_review_confirmed.connect(Callable(self, "_on_onboarding_result_review_confirmed"))
	add_child(onboarding_guide)
	call_deferred("_refresh_onboarding_guide")
	for blocking_surface in [municipal_overlay, settings_overlay, construction_confirmation, exit_confirmation, tutorial_overlay, onboarding_guide]:
		if blocking_surface != null:
			blocking_surface.visibility_changed.connect(Callable(self, "_sync_time_pause_for_ui"))
			blocking_surface.visibility_changed.connect(Callable(self, "_sync_map_interaction_for_ui"))
	_wire_ui_sounds()
	# The map is constructed before the start screen. Apply the initial blocked
	# state immediately so an already-hovered resident cannot leak an engine-owned
	# tooltip above the start screen before any visibility signal has fired.
	_sync_map_interaction_for_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		_request_application_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_npc_keyboard_dismiss_waiting_for_cancel_release = false
		_begin_map_button_release_cancellation()
		_clear_map_pan_drag_state()
		if vertical_slice != null:
			vertical_slice.set_time_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and vertical_slice != null:
		_sync_time_pause_for_ui()


func _sync_time_pause_for_ui(skip_terminal_failure_sync: bool = false) -> void:
	if vertical_slice == null:
		return
	var should_pause := not _game_started
	should_pause = should_pause or (municipal_overlay != null and municipal_overlay.is_open())
	should_pause = should_pause or (settings_overlay != null and settings_overlay.is_open())
	should_pause = should_pause or (construction_confirmation != null and construction_confirmation.is_open())
	should_pause = should_pause or (exit_confirmation != null and exit_confirmation.visible)
	should_pause = should_pause or (tutorial_overlay != null and tutorial_overlay.is_open())
	should_pause = should_pause or (
		onboarding_guide != null
		and onboarding_guide.is_open()
		and not onboarding_guide.is_product_mode()
	)
	# A lazily added municipal overlay can emit visibility_changed while it is
	# merely being attached.  Keep that presentation-only transition from using
	# the coordinator's terminal-failure sealing method, which writes CityState.
	if skip_terminal_failure_sync:
		vertical_slice.session.clock.paused = should_pause
	else:
		vertical_slice.set_time_paused(should_pause)
	_refresh_time_hud()


func _input(event: InputEvent) -> void:
	if (
		_npc_keyboard_dismiss_waiting_for_cancel_release
		and event.is_action_released("ui_cancel")
	):
		_npc_keyboard_dismiss_waiting_for_cancel_release = false
		get_viewport().set_input_as_handled()
		return
	if (
		_npc_keyboard_dismiss_waiting_for_cancel_release
		and event.is_action_pressed("ui_cancel")
	):
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed("ui_cancel")
		and is_instance_valid(npc_dialogue_card)
		and npc_dialogue_card.visible
	):
		_dismiss_npc_dialogue_from_keyboard()
		return
	if event is InputEventMouseButton:
		var zoom_event := event as InputEventMouseButton
		if (
			zoom_event.button_index == MOUSE_BUTTON_LEFT
			and _map_button_release_cancellation_pending
		):
			_map_button_release_cancellation_pending = false
			if zoom_event.pressed:
				# No release reached this window after focus loss. Restore the current
				# UI policy before dispatching a new, intentional press.
				_restore_map_buttons_after_cancelled_release()
			else:
				# Keep captured controls disabled throughout this release's GUI dispatch.
				# Their stale BaseButton capture is cleared before their prior state returns.
				call_deferred("_restore_map_buttons_after_cancelled_release")
		if zoom_event.button_index == MOUSE_BUTTON_MIDDLE:
			if zoom_event.pressed and _can_zoom_map_at(zoom_event.position):
				_map_pan_drag_active = true
				_map_pan_drag_pending = false
				_map_pan_drag_uses_left_button = false
				_map_pan_drag_origin = zoom_event.position
				_map_pan_drag_last_position = zoom_event.position
				get_viewport().set_input_as_handled()
				return
			if not zoom_event.pressed and _map_pan_drag_active and not _map_pan_drag_uses_left_button:
				_clear_map_pan_drag_state()
				get_viewport().set_input_as_handled()
				return
		if zoom_event.button_index == MOUSE_BUTTON_LEFT:
			if zoom_event.pressed and _can_left_drag_map_at(zoom_event.position):
				# Leave the press unhandled. A tile/NPC/UI control must still receive a
				# normal short click; motion only becomes a camera capture after the
				# player deliberately crosses this threshold.
				_map_pan_drag_pending = true
				_map_pan_drag_uses_left_button = true
				_map_pan_drag_origin = zoom_event.position
				_map_pan_drag_last_position = zoom_event.position
			elif not zoom_event.pressed and _map_pan_drag_uses_left_button:
				if _map_pan_drag_active:
					_clear_map_pan_drag_state()
					get_viewport().set_input_as_handled()
					return
				_clear_map_pan_drag_state()
		if (
			zoom_event.pressed
			and zoom_event.button_index == MOUSE_BUTTON_RIGHT
			and _can_reset_map_at(zoom_event.position)
		):
			_reset_map_camera()
			get_viewport().set_input_as_handled()
			return
		if (
			zoom_event.pressed
			and zoom_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
			and _can_zoom_map_at(zoom_event.position)
		):
			var direction := 1.0 if zoom_event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			_zoom_map_at(zoom_event.position, direction * MAP_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and (_map_pan_drag_active or _map_pan_drag_pending):
		var pan_event := event as InputEventMouseMotion
		if not _can_zoom_map_at(pan_event.position):
			_clear_map_pan_drag_state()
			return
		if _map_pan_drag_pending:
			if pan_event.position.distance_to(_map_pan_drag_origin) < MAP_LEFT_DRAG_THRESHOLD:
				return
			_map_pan_drag_pending = false
			_map_pan_drag_active = true
		var pan_delta := pan_event.position - _map_pan_drag_last_position
		_map_pan_drag_last_position = pan_event.position
		map_pan_offset += pan_delta
		_clamp_map_pan(_base_map_scale() * map_zoom)
		_layout_map_stage()
		get_viewport().set_input_as_handled()
		return
	if not placement_mode_active and not _is_transport_map_action_active():
		return
	if municipal_overlay != null and municipal_overlay.is_open():
		return
	if settings_overlay != null and settings_overlay.is_open():
		return
	if construction_confirmation != null and construction_confirmation.is_open():
		return
	if exit_confirmation != null and exit_confirmation.visible:
		return
	if tutorial_overlay != null and tutorial_overlay.is_open():
		return
	var cancel_requested := event.is_action_pressed("ui_cancel")
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		cancel_requested = cancel_requested or (mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT)
	if not cancel_requested:
		return
	_cancel_active_map_action(true)
	get_viewport().set_input_as_handled()


func _can_zoom_map_at(global_position: Vector2) -> bool:
	if map_viewport == null or map_stage == null or not map_viewport.get_global_rect().has_point(global_position):
		return false
	if not _game_started:
		return false
	for blocking_surface in [municipal_overlay, settings_overlay, construction_confirmation, exit_confirmation, tutorial_overlay]:
		if blocking_surface != null and blocking_surface.visible:
			return false
	if onboarding_guide != null and onboarding_guide.is_open():
		return false
	return true


func _can_left_drag_map_at(global_position: Vector2) -> bool:
	if map_zoom <= 1.0 or not _can_zoom_map_at(global_position):
		return false
	# HUD and ordinary controls are outside map_viewport's child tree. Keeping
	# them out of the drag candidate boundary prevents a left UI click becoming a
	# camera gesture, while tiles/NPCs remain eligible for thresholded map drag.
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return true
	return hovered_control == map_viewport or map_viewport.is_ancestor_of(hovered_control)


func _can_reset_map_at(global_position: Vector2) -> bool:
	return _can_zoom_map_at(global_position) and _camera_reset_is_needed()


func _camera_reset_is_needed() -> bool:
	return not is_equal_approx(map_zoom, 1.0) or not map_pan_offset.is_equal_approx(Vector2.ZERO)


func _clear_map_pan_drag_state() -> void:
	_map_pan_drag_active = false
	_map_pan_drag_pending = false
	_map_pan_drag_uses_left_button = false
	_map_pan_drag_origin = Vector2.ZERO
	_map_pan_drag_last_position = Vector2.ZERO


func _reset_map_camera() -> void:
	map_zoom = 1.0
	map_pan_offset = Vector2.ZERO
	_clear_map_pan_drag_state()
	_layout_map_stage()
	_set_hint("地圖已回到 100% 原始視角", false)


func _zoom_map_at(global_position: Vector2, zoom_delta: float) -> void:
	var previous_zoom := map_zoom
	map_zoom = clampf(map_zoom + zoom_delta, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	if is_equal_approx(previous_zoom, map_zoom):
		return
	var viewport_local := map_viewport.get_global_transform_with_canvas().affine_inverse() * global_position
	var previous_scale := maxf(0.001, map_stage.scale.x)
	var stage_anchor := (viewport_local - map_stage.position) / previous_scale
	var next_scale := _base_map_scale() * map_zoom
	var centered_position := (map_viewport.size - MAP_STAGE_SIZE * next_scale) * 0.5
	map_pan_offset = viewport_local - stage_anchor * next_scale - centered_position
	_clamp_map_pan(next_scale)
	_layout_map_stage()
	_set_hint("地圖縮放 %d%%｜建築與居民同步縮放" % int(round(map_zoom * 100.0)), false)

func _has_start_save() -> bool:
	return vertical_slice.has_save_game(start_save_path) if not start_save_path.is_empty() else vertical_slice.has_save_game()

func _begin_start_flow(mode: String) -> void:
	if start_screen == null or start_screen.is_loading():
		return
	_pending_start_success = false
	_pending_start_message = ""
	vertical_slice.set_time_paused(true)
	start_screen.play_loading(mode)

func _perform_start_load(mode: String) -> void:
	match mode:
		"new":
			_initialize_fresh_game()
			_pending_start_success = true
			_pending_start_message = ""
		"continue":
			_pending_start_success = vertical_slice.load_game(start_save_path) if not start_save_path.is_empty() else vertical_slice.load_game()
			if _pending_start_success:
				_consume_vertical_events(vertical_slice.drain_ui_events())
				var shell_restore_ok := _restore_player_shell_state(vertical_slice.get_player_shell_state())
				if shell_restore_ok:
					_sync_vertical_state()
					_update_ui()
				else:
					_pending_start_success = false
					_pending_start_message = "存檔的導覽狀態無法安全讀取，未套用介面資料。"
			else:
				_pending_start_message = "找不到可讀取的存檔，請選擇新遊戲。"
	vertical_slice.set_time_paused(true)

func _finish_start_load(mode: String) -> void:
	if start_screen == null:
		return
	if not _pending_start_success:
		start_screen.show_failure(_pending_start_message)
		vertical_slice.set_time_paused(true)
		return
	_game_started = true
	start_screen.complete_success()
	if mode == "continue" and is_dark_mode:
		_rebuild_ui()
	_tutorial_replay_active = false
	if onboarding_progress.is_story_pending() and tutorial_overlay != null:
		tutorial_overlay.open(true)
	call_deferred("_refresh_onboarding_guide")
	_sync_time_pause_for_ui()
	# A completed tutorial does not open another blocking surface, so there is no
	# visibility signal that would otherwise restore map input after Continue.
	_sync_map_interaction_for_ui()
	_update_ui()
	if mode == "new":
		_autosave("new_game_created")


func _initialize_fresh_game() -> void:
	vertical_slice.new_game(20_260_715, 250_000)
	_initialize_city_metric_defaults()
	vertical_slice.set_time_paused(true)
	city_grid.clear()
	for _index in CELL_COUNT:
		city_grid.append("")
	building_customizations.clear()
	healthcare_applied_bonus = 0
	_healthcare_legacy_migration_applied = true
	selected_cell_index = -1
	selected_building = "住宅"
	selected_building_group = "housing"
	placement_mode_active = false
	placement_building_name = ""
	_placement_preview_anchor = -1
	_placement_preview.clear()
	_pending_construction_tile = -1
	_pending_terrain_tile = -1
	map_action_mode = "inspect"
	transport_plan_kind = ""
	transport_plan_operation = ""
	transport_plan_tiles.clear()
	transport_route_mode = ""
	transport_route_station_tiles.clear()
	map_zoom = 1.0
	map_pan_offset = Vector2.ZERO
	_npc_dialogue_remaining_seconds = 0.0
	tax_rates = {"income": 10, "consumption": 5, "business": 8, "industry": 10}
	utility_fees = {"garbage": 20, "water": 25, "electricity": 30, "gas": 20}
	service_fees = {"parking": 20, "medical": 50, "tuition": 100, "stadium": 80}
	_fiscal_draft_active = false
	tax_rate = 10
	active_policies.clear()
	for policy_name in policies.keys():
		active_policies[policy_name] = false
	is_dark_mode = false
	ranking_score = 0
	best_score = 0
	city_rating = "B 級城市"
	last_report = "新城市尚無月度收支紀錄。"
	last_report_details = "新城市尚無可展開的月度明細。"
	onboarding_progress.reset_for_new_game()
	onboarding_action_router.bind_progress(onboarding_progress)
	tutorial_completed = false
	_tutorial_replay_active = false
	if audio_director != null:
		audio_director.set_music_enabled(music_enabled)
		audio_director.set_sfx_enabled(sfx_enabled)
		audio_director.set_music_volume(music_volume)
		audio_director.set_sfx_volume(sfx_volume)
	city_data_show_all = false
	_city_metric_layout_signature = ""
	city_report_history_service.reset()
	announcements.clear()
	last_population_reason = "新遊戲尚無人口變動紀錄。"
	group_satisfaction = {"一般居民": 70, "學生家庭": 70, "商人": 70, "老年居民": 70}
	_autosave_elapsed_seconds = 0.0
	_last_autosave_reason = ""
	_sync_vertical_state()
	month_start_population = population
	vertical_slice.initialize_requests_without_history(_vertical_city_context())
	refresh_visible_npc_proxies()
	_recalculate_satisfaction()
	_recalculate_score()


func _capture_player_shell_state() -> Dictionary:
	_reconcile_healthcare_service()
	_sync_city_metrics_to_core()
	var serialized_customizations: Dictionary = {}
	for tile_variant in building_customizations.keys():
		serialized_customizations[str(tile_variant)] = Dictionary(building_customizations[tile_variant]).duplicate(true)
	var report_history_snapshot := city_report_history_service.snapshot()
	return {
		"schema_version": OnboardingProgressScript.SHELL_SCHEMA_VERSION,
		"tax_rates": tax_rates.duplicate(true),
		"utility_fees": utility_fees.duplicate(true),
		"service_fees": service_fees.duplicate(true),
		"active_policies": active_policies.duplicate(true),
		"is_dark_mode": is_dark_mode,
		# Kept as the legacy story-seen flag for schema-8 readers. Schema 9 uses
		# the separate onboarding snapshot as the authoritative nine-step state.
		"tutorial_completed": tutorial_completed,
		"onboarding": onboarding_progress.snapshot(),
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"map_zoom": map_zoom,
		"selected_building": selected_building,
		"selected_building_group": selected_building_group,
		"selected_cell_index": selected_cell_index,
		"building_customizations": serialized_customizations,
		"healthcare_applied_bonus": healthcare_applied_bonus,
		"healthcare_service_base": clampi(healthcare - healthcare_applied_bonus, 0, 100),
		"security": security,
		"environment": environment,
		"traffic": traffic,
		"education": education,
		"healthcare": healthcare,
		"total_satisfaction": total_satisfaction,
		"month_start_population": month_start_population,
		"group_satisfaction": group_satisfaction.duplicate(true),
		"ranking_score": ranking_score,
		"best_score": best_score,
		"city_rating": city_rating,
		"last_report": last_report,
		"last_report_details": last_report_details,
		"last_month_summary": report_history_snapshot["last_month_summary"],
		"monthly_report_history": report_history_snapshot["monthly_report_history"],
		"major_event_history": report_history_snapshot["major_event_history"],
		"announcements": announcements.duplicate(),
		"last_population_reason": last_population_reason
	}


func _restore_player_shell_state(state: Dictionary) -> bool:
	var onboarding_restore: Dictionary = onboarding_progress.restore_from_shell_state(state)
	if not bool(onboarding_restore.get("ok", false)):
		if onboarding_guide != null:
			onboarding_guide.invalidate_target()
		return false
	onboarding_action_router.bind_progress(onboarding_progress)
	if state.is_empty():
		tutorial_completed = not onboarding_progress.is_story_pending()
		return true
	_fiscal_draft_active = false
	var saved_tax: Dictionary = state.get("tax_rates", {})
	for key in tax_rates.keys():
		if saved_tax.has(key):
			tax_rates[key] = clampi(int(saved_tax[key]), int(TAX_DEFS[key]["min"]), int(TAX_DEFS[key]["max"]))
	tax_rate = int(tax_rates["income"])
	var saved_utility: Dictionary = state.get("utility_fees", {})
	for key in utility_fees.keys():
		if saved_utility.has(key):
			utility_fees[key] = clampi(int(saved_utility[key]), int(UTILITY_DEFS[key]["min"]), int(UTILITY_DEFS[key]["max"]))
	var saved_service: Dictionary = state.get("service_fees", {})
	for key in service_fees.keys():
		if saved_service.has(key):
			service_fees[key] = clampi(int(saved_service[key]), int(SERVICE_DEFS[key]["min"]), int(SERVICE_DEFS[key]["max"]))
	var saved_policies: Dictionary = state.get("active_policies", {})
	for policy_name in active_policies.keys():
		active_policies[policy_name] = bool(saved_policies.get(policy_name, false))
	is_dark_mode = bool(state.get("is_dark_mode", false))
	tutorial_completed = not onboarding_progress.is_story_pending()
	# Audio preferences are user settings shared by every save.  Only migrate
	# legacy per-save values when no global audio section exists yet.
	if not _audio_preferences_found:
		music_enabled = bool(state.get("music_enabled", true))
		sfx_enabled = bool(state.get("sfx_enabled", true))
		music_volume = clampf(float(state.get("music_volume", 1.0)), 0.0, 1.0)
		sfx_volume = clampf(float(state.get("sfx_volume", 1.0)), 0.0, 1.0)
		_audio_preferences_found = true
		_save_audio_preferences()
	if audio_director != null:
		audio_director.set_music_enabled(music_enabled)
		audio_director.set_sfx_enabled(sfx_enabled)
		audio_director.set_music_volume(music_volume)
		audio_director.set_sfx_volume(sfx_volume)
	if settings_overlay != null:
		settings_overlay.set_audio_enabled(music_enabled, sfx_enabled, music_volume, sfx_volume)
	map_zoom = clampf(float(state.get("map_zoom", 1.0)), MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	map_pan_offset = Vector2.ZERO
	selected_building = str(state.get("selected_building", "住宅"))
	if not buildings.has(selected_building):
		selected_building = "住宅"
	selected_building_group = str(state.get("selected_building_group", "housing"))
	selected_cell_index = clampi(int(state.get("selected_cell_index", -1)), -1, CELL_COUNT - 1)
	var saved_customizations: Dictionary = state.get("building_customizations", {})
	for tile_key in saved_customizations.keys():
		var tile_index := int(str(tile_key))
		if tile_index >= 0 and tile_index < CELL_COUNT and city_grid[tile_index] != "":
			building_customizations[tile_index] = Dictionary(saved_customizations[tile_key]).duplicate(true)
	# Schema 5 makes CityState.metrics authoritative. Older saves used only the
	# player shell, so they intentionally migrate from the legacy fields once.
	var metric_source: Dictionary = state
	var metric_key_satisfaction := "total_satisfaction"
	if int(state.get("schema_version", 0)) >= 5 and vertical_slice != null and vertical_slice.session != null:
		metric_source = vertical_slice.session.state.metrics
		metric_key_satisfaction = "satisfaction"
	security = clampi(int(metric_source.get("security", state.get("security", security))), 0, 100)
	environment = clampi(int(metric_source.get("environment", state.get("environment", environment))), 0, 100)
	traffic = clampi(int(metric_source.get("traffic", state.get("traffic", traffic))), 0, 100)
	education = clampi(int(metric_source.get("education", state.get("education", education))), 0, 100)
	healthcare = clampi(int(metric_source.get("healthcare", state.get("healthcare", healthcare))), 0, 100)
	total_satisfaction = clampi(int(metric_source.get(metric_key_satisfaction, state.get("total_satisfaction", total_satisfaction))), 0, 100)
	month_start_population = maxi(1, int(state.get("month_start_population", population)))
	var saved_groups: Dictionary = state.get("group_satisfaction", {})
	for group_name in group_satisfaction.keys():
		group_satisfaction[group_name] = clampi(int(saved_groups.get(group_name, group_satisfaction[group_name])), 0, 100)
	ranking_score = clampi(int(state.get("ranking_score", ranking_score)), 0, 100)
	best_score = clampi(int(state.get("best_score", best_score)), 0, 100)
	city_rating = str(state.get("city_rating", city_rating))
	last_report = str(state.get("last_report", last_report))
	last_report_details = str(state.get("last_report_details", last_report_details))
	city_report_history_service.restore(
		state.get("last_month_summary", {}),
		state.get("monthly_report_history", []),
		state.get("major_event_history", []),
		_city_report_metric_snapshot()
	)
	announcements.clear()
	for announcement in state.get("announcements", []):
		announcements.append(str(announcement))
	last_population_reason = str(state.get("last_population_reason", last_population_reason))
	var shell_schema := int(state.get("schema_version", 0))
	if shell_schema >= 8:
		var expected_bonus := maxi(0, int(_healthcare_service_result().get("metric_bonus", 0)))
		var maximum_bonus := _healthcare_max_metric_bonus()
		var saved_base := clampi(int(state.get("healthcare_service_base", healthcare - expected_bonus)), 0, 100)
		var recovered_effective_bonus := clampi(healthcare - saved_base, 0, maximum_bonus)
		if not state.has("healthcare_applied_bonus"):
			# Fail-safe recovery for a partial schema-8 shell: the authoritative
			# metric plus its persisted service-less base recover the effective
			# (possibly saturation-limited) amount without applying it twice.
			healthcare_applied_bonus = recovered_effective_bonus
		else:
			var saved_bonus := int(state.get("healthcare_applied_bonus", 0))
			var saved_bonus_is_consistent := (
				saved_bonus >= 0
				and saved_bonus <= maximum_bonus
				and saved_bonus <= expected_bonus
				and saved_bonus == recovered_effective_bonus
			)
			healthcare_applied_bonus = (
				saved_bonus if saved_bonus_is_consistent else recovered_effective_bonus
			)
		_healthcare_legacy_migration_applied = true
	elif not _healthcare_legacy_migration_applied:
		healthcare_applied_bonus = 0
		_migrate_legacy_hospital_direct_effects()
		_healthcare_legacy_migration_applied = true
	_reconcile_healthcare_service()
	return true


func _update_autosave_timer(delta: float) -> void:
	if not _game_started or vertical_slice == null or vertical_slice.is_time_paused():
		return
	_autosave_elapsed_seconds += maxf(0.0, delta)
	if _autosave_elapsed_seconds >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_elapsed_seconds = fmod(_autosave_elapsed_seconds, AUTOSAVE_INTERVAL_SECONDS)
		_autosave("interval:10_real_minutes")


func _autosave(reason: String) -> Error:
	if not _game_started or vertical_slice == null:
		return ERR_UNAVAILABLE
	if onboarding_progress.is_locked():
		return ERR_INVALID_DATA
	if _autosave_in_progress:
		return ERR_BUSY
	_autosave_in_progress = true
	vertical_slice.set_player_shell_state(_capture_player_shell_state())
	var error: Error = vertical_slice.save_game(start_save_path) if not start_save_path.is_empty() else vertical_slice.save_game()
	if error == OK:
		_autosave_count += 1
		_last_autosave_reason = reason
	_autosave_in_progress = false
	return error

func _build_compact_status_hud() -> PanelContainer:
	var panel := _panel(Color("332a25") if is_dark_mode else Color("fff4d7"), 12, 7)
	panel.name = "StatusHud"
	panel.z_index = 3000
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = UI_HUD_EDGE_INSET
	panel.offset_top = UI_HUD_EDGE_INSET
	panel.offset_right = -UI_HUD_EDGE_INSET
	panel.offset_bottom = UI_HUD_EDGE_INSET + UI_STATUS_HEIGHT

	var row := HBoxContainer.new()
	row.name = "StatusMetricRow"
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var title := _label("城諾之音", 20, Color("fff4d7") if is_dark_mode else Color("35291f"))
	title.name = "StatusBrand"
	title.custom_minimum_size = Vector2(150, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = L10n.text("療癒城市治理模擬")
	row.add_child(title)

	for key in ["month", "funds", "population", "satisfaction", "grievance", "trust", "score", "rating"]:
		row.add_child(_header_metric_card(key))
	return panel

func _on_locale_changed(_locale: String) -> void:
	if not is_node_ready():
		return
	var reopen_settings: bool = settings_overlay != null and settings_overlay.is_open()
	_update_ui()
	if vertical_slice_panel != null and vertical_slice_panel.has_method("refresh_localization"):
		vertical_slice_panel.call("refresh_localization")
	if transport_planning_panel != null and transport_planning_panel.has_method("refresh_localization"):
		transport_planning_panel.call("refresh_localization")
	if city_data_dashboard != null and is_instance_valid(city_data_dashboard):
		city_data_dashboard.refresh_localization()
	if onboarding_guide != null and is_instance_valid(onboarding_guide):
		onboarding_guide.refresh_localization()
	call_deferred("_refresh_onboarding_guide")
	if reopen_settings and settings_overlay != null:
		settings_overlay.open()


func _build_feedback_toast() -> PanelContainer:
	var panel := _panel(Color(0.04, 0.12, 0.19, 0.95) if not is_dark_mode else Color(0.02, 0.07, 0.11, 0.96), 10, 8)
	panel.name = "FeedbackToast"
	panel.z_index = 3200
	panel.anchor_left = 0.5
	panel.anchor_top = 0.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.0
	panel.offset_left = -330.0
	panel.offset_top = 78.0
	panel.offset_right = 330.0
	panel.offset_bottom = 130.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	hint_label = _label("", 16, Color.WHITE)
	hint_label.set_meta("l10n_skip", true)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.max_lines_visible = 2
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.04, 0.98))
	hint_label.add_theme_constant_override("outline_size", 3)
	panel.add_child(hint_label)
	return panel


func _build_placement_banner() -> PanelContainer:
	var panel := _panel(Color(0.035, 0.12, 0.16, 0.96), 12, 12)
	panel.name = "PlacementBanner"
	panel.z_index = 3150
	panel.anchor_left = 0.5
	panel.anchor_top = 0.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.0
	panel.offset_left = -470.0
	panel.offset_top = 140.0
	panel.offset_right = 470.0
	panel.offset_bottom = 214.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	placement_label = _label("", 18, Color.WHITE)
	placement_label.name = "PlacementModeLabel"
	placement_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_label.max_lines_visible = 2
	placement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(placement_label)
	placement_rotate_button = _button("逆時針旋轉 90°", "secondary")
	placement_rotate_button.name = "RotateBuildingButton"
	placement_rotate_button.custom_minimum_size = Vector2(190, 44)
	placement_rotate_button.add_theme_font_size_override("font_size", 18)
	placement_rotate_button.tooltip_text = "每按一次將建築占格逆時針旋轉 90 度"
	placement_rotate_button.visible = false
	placement_rotate_button.pressed.connect(Callable(self, "_rotate_building_placement_ccw"))
	row.add_child(placement_rotate_button)
	placement_level_button = _button("整平地形", "primary")
	placement_level_button.name = "FlattenTerrainButton"
	placement_level_button.custom_minimum_size = Vector2(190, 44)
	placement_level_button.add_theme_font_size_override("font_size", 18)
	placement_level_button.tooltip_text = "移除樹木、山丘、河流、道路或軌道，使地格恢復可興建"
	placement_level_button.visible = false
	placement_level_button.pressed.connect(Callable(self, "_flatten_pending_terrain"))
	row.add_child(placement_level_button)
	placement_confirm_button = _button("確認規劃", "primary")
	placement_confirm_button.name = "ConfirmMapPlanButton"
	placement_confirm_button.custom_minimum_size = Vector2(176, 44)
	placement_confirm_button.add_theme_font_size_override("font_size", 18)
	placement_confirm_button.tooltip_text = "確認目前選取的交通路廊或站序"
	placement_confirm_button.visible = false
	placement_confirm_button.pressed.connect(Callable(self, "_confirm_transport_map_plan"))
	row.add_child(placement_confirm_button)
	placement_cancel_button = _button("取消放置", "danger")
	placement_cancel_button.name = "CancelPlacementButton"
	placement_cancel_button.custom_minimum_size = Vector2(176, 44)
	placement_cancel_button.add_theme_font_size_override("font_size", 18)
	placement_cancel_button.tooltip_text = "取消目前的建築放置（Esc／右鍵）"
	placement_cancel_button.pressed.connect(Callable(self, "_cancel_active_map_action").bind(true))
	row.add_child(placement_cancel_button)
	return panel


func _set_placement_banner_layout(compact_transport_layout: bool) -> void:
	if placement_banner == null:
		return
	if compact_transport_layout:
		# Route planning keeps the map in view for a longer continuous session.
		# Dock its controls beside the map rather than spanning its centre, while
		# retaining the established button sizes and two-line instruction label.
		placement_banner.anchor_left = 1.0
		placement_banner.anchor_top = 0.0
		placement_banner.anchor_right = 1.0
		placement_banner.anchor_bottom = 0.0
		placement_banner.offset_left = -732.0
		placement_banner.offset_top = UI_STATUS_HEIGHT + 20.0
		placement_banner.offset_right = -UI_HUD_EDGE_INSET
		placement_banner.offset_bottom = UI_STATUS_HEIGHT + 112.0
		return
	placement_banner.anchor_left = 0.5
	placement_banner.anchor_top = 0.0
	placement_banner.anchor_right = 0.5
	placement_banner.anchor_bottom = 0.0
	placement_banner.offset_left = -470.0
	placement_banner.offset_top = 140.0
	placement_banner.offset_right = 470.0
	placement_banner.offset_bottom = 214.0

func _build_action_dock() -> PanelContainer:
	var panel := _panel(Color(0.04, 0.12, 0.19, 0.94), 12, UI_HUD_PANEL_PADDING)
	panel.name = "ActionDock"
	panel.z_index = 3100
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -276.0
	panel.offset_top = -108.0
	panel.offset_right = -UI_HUD_EDGE_INSET
	panel.offset_bottom = -UI_HUD_EDGE_INSET

	var grid := GridContainer.new()
	grid.name = "ActionButtonRow"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", UI_HUD_GAP)
	grid.add_theme_constant_override("v_separation", UI_HUD_GAP)
	panel.add_child(grid)

	municipal_button = _hud_picture_button("municipal", "市政", "開啟市政中心：建築、政策法案、藍圖與財政", "primary")
	municipal_button.name = "MunicipalButton"
	municipal_button.pressed.connect(Callable(self, "_open_municipal_center"))
	grid.add_child(municipal_button)
	settings_button = _hud_picture_button("settings", "設定", "調整語言與顯示模式")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(Callable(self, "_open_settings"))
	grid.add_child(settings_button)
	exit_button = _hud_picture_button("exit", "離開", "離開城諾之音", "danger")
	exit_button.name = "ExitButton"
	exit_button.pressed.connect(Callable(self, "_request_application_quit"))
	grid.add_child(exit_button)
	return panel


func _hud_picture_button(icon_key: String, label_text: String, tooltip: String, variant: String = "normal") -> Button:
	var button := _button("", variant)
	button.custom_minimum_size = Vector2(UI_HUD_BUTTON_SIZE, UI_HUD_BUTTON_SIZE)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = tooltip
	button.set_meta("semantic_label", label_text)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 8
	stack.offset_top = 8
	stack.offset_right = -8
	stack.offset_bottom = -8
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	var picture := _icon_texture_rect(icon_key, Vector2(0, 28))
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(picture)
	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.max_lines_visible = 2
	caption.custom_minimum_size = Vector2(0, 26)
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color.WHITE if variant in ["primary", "danger"] else _theme_text())
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	return button

func _request_application_quit() -> void:
	if exit_confirmation != null:
		_set_map_interaction_enabled(false)
		exit_confirmation.open()

func _confirm_application_quit() -> void:
	if vertical_slice != null:
		vertical_slice.set_time_paused(true)
	if _game_started:
		var save_error := _autosave("application_exit")
		if save_error != OK:
			if exit_confirmation != null:
				exit_confirmation.show_save_error(int(save_error))
			_set_hint("儲存失敗（錯誤 %d）" % int(save_error), true)
			return
	if exit_confirmation != null:
		exit_confirmation.close()
	if vertical_slice != null:
		# Closing the modal emits visibility_changed, which normally resumes time.
		# Keep the session frozen while the application is in EXIT_PENDING.
		vertical_slice.set_time_paused(true)
	application_quit_requested.emit()
	if quit_application_on_confirm:
		_begin_graceful_application_quit()


func _confirm_discard_and_quit() -> void:
	if vertical_slice != null:
		vertical_slice.set_time_paused(true)
	application_quit_requested.emit()
	if quit_application_on_confirm:
		_begin_graceful_application_quit()


func _configure_release_smoke_from_user_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with(QA_RELEASE_SMOKE_ARG_PREFIX):
			continue
		var frame_text := argument.trim_prefix(QA_RELEASE_SMOKE_ARG_PREFIX)
		if not frame_text.is_valid_int():
			continue
		_qa_release_smoke_frames_remaining = clampi(frame_text.to_int(), 2, 36_000)
		_qa_release_smoke_active = true
		print("QA_RELEASE_SMOKE_ARMED frames=%d" % _qa_release_smoke_frames_remaining)
		return


func _process_release_smoke_frame() -> void:
	if not _qa_release_smoke_active or _quit_shutdown_in_progress:
		return
	_qa_release_smoke_frames_remaining -= 1
	if _qa_release_smoke_frames_remaining <= 0:
		_begin_graceful_application_quit()


func _begin_graceful_application_quit() -> void:
	if _quit_shutdown_in_progress:
		return
	_quit_shutdown_in_progress = true
	call_deferred("_shutdown_audio_and_quit")


func _shutdown_audio_and_quit() -> void:
	if is_instance_valid(audio_director):
		await audio_director.settle_for_shutdown(get_tree())
		audio_director.free()
		audio_director = null
	for _frame in range(AudioDirectorScript.SHUTDOWN_FREE_SETTLE_FRAMES):
		await get_tree().process_frame
	if _qa_release_smoke_active:
		print("QA_RELEASE_SMOKE_COMPLETED")
	get_tree().call_deferred("quit")


func _build_management_overlay() -> Control:
	var overlay := MunicipalOverlayScript.new()
	overlay.register_page("buildings", "選擇建築", _build_building_tab(), true)
	overlay.register_page("governance", "政策與法案", _build_bill_tab(), true)
	overlay.register_page("judicial", "法院審判與辯護", _build_judicial_tab(), true)
	overlay.register_page("oversight", "監察質詢與彈劾辯護", _build_oversight_tab(), true)
	overlay.register_page("blueprint", "設計藍圖", _build_vertical_slice_tab(), true)
	overlay.register_page("finance", "稅率與公共事業費", _build_fiscal_tab(), true)
	overlay.register_page("public_affairs", "民情中心", _build_public_affairs_tab(), true)
	overlay.register_page("transport_planning", "城市交通規劃", _build_transport_planning_tab(), false)
	overlay.register_page("city_data", "城市數據", _build_city_data_page(), true)
	overlay.register_page("report", "月度報告", _build_report_page(), true)
	overlay.set_dark_mode(is_dark_mode)
	return overlay


func _ensure_municipal_overlay() -> Control:
	if municipal_overlay != null and is_instance_valid(municipal_overlay):
		return municipal_overlay
	# The municipal hub owns several large, page-specific control trees.  Do not
	# build them during startup, and do not use _update_ui() here: its authority
	# synchronization path can record governance state while the player only
	# asked to present the hub.
	municipal_overlay = _build_management_overlay()
	municipal_overlay.page_opened.connect(Callable(self, "_on_municipal_page_opened"))
	municipal_overlay.overlay_closed.connect(Callable(self, "_on_municipal_overlay_closed"))
	municipal_overlay.visibility_changed.connect(Callable(self, "_sync_time_pause_for_ui").bind(true))
	municipal_overlay.visibility_changed.connect(Callable(self, "_sync_map_interaction_for_ui"))
	add_child(municipal_overlay)
	_wire_ui_sounds()
	return municipal_overlay


func _build_judicial_tab() -> Control:
	judicial_panel = JusticeOversightPanelScript.new("judicial")
	judicial_panel.set_dark_mode(is_dark_mode)
	judicial_panel.defense_submitted.connect(Callable(self, "_on_defense_submitted"))
	if vertical_slice != null:
		judicial_panel.refresh(vertical_slice.governance.justice_system)
	return judicial_panel


func _build_oversight_tab() -> Control:
	oversight_panel = JusticeOversightPanelScript.new("oversight")
	oversight_panel.set_dark_mode(is_dark_mode)
	oversight_panel.defense_submitted.connect(Callable(self, "_on_defense_submitted"))
	if vertical_slice != null:
		oversight_panel.refresh(vertical_slice.governance.justice_system)
	return oversight_panel


func _build_public_affairs_tab() -> ScrollContainer:
	public_affairs_panel = PublicAffairsPanelScript.new()
	public_affairs_panel.set_dark_mode(is_dark_mode)
	public_affairs_panel.accept_request_requested.connect(Callable(self, "_accept_request_by_id"))
	public_affairs_panel.reject_request_requested.connect(Callable(self, "_reject_request_by_id"))
	if vertical_slice != null:
		public_affairs_panel.set_view_model(vertical_slice.get_view_model(selected_cell_index))
	return public_affairs_panel


func _build_transport_planning_tab() -> ScrollContainer:
	transport_planning_panel = TransportPlanningPanelScript.new()
	transport_planning_panel.set_dark_mode(is_dark_mode)
	transport_planning_panel.infrastructure_requested.connect(Callable(self, "_on_transport_infrastructure_requested"))
	transport_planning_panel.route_planning_requested.connect(Callable(self, "_on_transport_route_planning_requested"))
	transport_planning_panel.route_toggle_requested.connect(Callable(self, "_on_transport_route_toggle_requested"))
	transport_planning_panel.route_delete_requested.connect(Callable(self, "_on_transport_route_delete_requested"))
	transport_planning_panel.session_continue_requested.connect(Callable(self, "_on_transport_session_continue_requested"))
	transport_planning_panel.session_close_requested.connect(Callable(self, "_on_transport_session_close_requested"))
	_refresh_transport_planning_panel()
	return transport_planning_panel

func _open_municipal_center() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	var overlay := _ensure_municipal_overlay()
	if overlay == null:
		return
	_set_map_interaction_enabled(false)
	var session := _transport_session_snapshot()
	if str(session.get("state", "")) == "route_edit" and _transport_session_is_route_package(session):
		overlay.open_hub()
		_refresh_transport_planning_panel()
		overlay.open_page("transport_planning")
		return
	overlay.open_hub()


func _open_transport_planning() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	var overlay := _ensure_municipal_overlay()
	if overlay == null:
		return
	_refresh_transport_planning_panel()
	_set_map_interaction_enabled(false)
	overlay.open_page("transport_planning")


func _set_map_npc_tooltips_enabled(enabled: bool) -> void:
	if npc_map_controller != null:
		npc_map_controller.set_interaction_enabled(
			enabled,
			Callable(self, "format_npc_display_name"),
			Callable(self, "_dismiss_hovered_map_control")
		)


func _set_map_tile_tooltips_enabled(enabled: bool) -> void:
	for button_variant in grid_buttons:
		var button := button_variant as Button
		if button == null or not is_instance_valid(button):
			continue
		if enabled:
			button.tooltip_text = str(button.get_meta("map_tooltip_backup", button.tooltip_text))
			button.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			if not button.tooltip_text.is_empty():
				button.set_meta("map_tooltip_backup", button.tooltip_text)
			button.tooltip_text = ""
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_dismiss_hovered_map_control(button)


func _dismiss_hovered_map_control(control: BaseButton) -> void:
	if not control.visible or not control.is_hovered():
		return
	# Godot owns tooltip popups outside this CanvasItem hierarchy. Briefly
	# removing the hovered source forces the existing popup to be destroyed;
	# the control returns on the next idle step with interaction disabled.
	control.hide()
	control.call_deferred("show")


func _begin_map_button_release_cancellation() -> void:
	if not _map_pan_drag_uses_left_button:
		return
	_map_button_release_cancellation_pending = true
	if npc_map_controller != null:
		for actor: Button in npc_map_controller.get_actors():
			_hold_pressed_map_button_until_release(actor)
	for button_variant in grid_buttons:
		_hold_pressed_map_button_until_release(button_variant as Button)


func _hold_pressed_map_button_until_release(button: Button) -> void:
	if button == null or not is_instance_valid(button) or not button.is_pressed():
		return
	var instance_id := button.get_instance_id()
	if not _map_buttons_waiting_for_cancelled_release.has(instance_id):
		_map_buttons_waiting_for_cancelled_release[instance_id] = {
			"button": button,
			"disabled": button.disabled,
		}
	button.disabled = true


func _restore_map_buttons_after_cancelled_release() -> void:
	for record_variant in _map_buttons_waiting_for_cancelled_release.values():
		var record := record_variant as Dictionary
		var button := record.get("button") as Button
		if button != null and is_instance_valid(button):
			button.disabled = bool(record.get("disabled", false))
	_map_buttons_waiting_for_cancelled_release.clear()


func _set_map_interaction_enabled(enabled: bool) -> void:
	if not enabled:
		_begin_map_button_release_cancellation()
		_clear_map_pan_drag_state()
	_set_map_npc_tooltips_enabled(enabled)
	_set_map_tile_tooltips_enabled(enabled)


func _sync_map_interaction_for_ui() -> void:
	var blocked := not _game_started
	blocked = blocked or (municipal_overlay != null and municipal_overlay.is_open())
	blocked = blocked or (settings_overlay != null and settings_overlay.is_open())
	blocked = blocked or (construction_confirmation != null and construction_confirmation.is_open())
	blocked = blocked or (exit_confirmation != null and exit_confirmation.visible)
	blocked = blocked or (tutorial_overlay != null and tutorial_overlay.is_open())
	blocked = blocked or (
		onboarding_guide != null
		and onboarding_guide.is_open()
		and not onboarding_guide.is_product_mode()
	)
	if blocked:
		_set_map_interaction_enabled(false)
		return
	# Transport planning owns tile clicks, but never NPC clicks. Keeping these
	# controls separate prevents a moving resident from stealing a route/track
	# tile while preserving ordinary map interaction.
	_set_map_tile_tooltips_enabled(true)
	_set_map_npc_tooltips_enabled(not _transport_planning_owns_map_input())


func _on_municipal_overlay_closed() -> void:
	if _fiscal_draft_active:
		_discard_fiscal_draft(false, false)
	_sync_map_interaction_for_ui()
	call_deferred("_refresh_onboarding_guide")


func _on_municipal_page_opened(page_id: String) -> void:
	_set_map_npc_tooltips_enabled(false)
	call_deferred("_refresh_onboarding_guide")
	if page_id == "finance":
		_begin_fiscal_draft()
		return
	if _fiscal_draft_active:
		_discard_fiscal_draft(false, true)
	if page_id == "city_data":
		var fiscal_tax_values: Dictionary = _fiscal_draft_tax_rates if _fiscal_draft_active else tax_rates
		var fiscal_utility_values: Dictionary = _fiscal_draft_utility_fees if _fiscal_draft_active else utility_fees
		var fiscal_service_values: Dictionary = _fiscal_draft_service_fees if _fiscal_draft_active else service_fees
		_refresh_city_data_dashboard(_city_data_finance_snapshot_for(
			fiscal_tax_values,
			fiscal_utility_values,
			fiscal_service_values,
			_maintenance_cost(),
			_policy_expense(),
			_active_law_expense()
		))
		if city_data_dashboard != null:
			city_data_dashboard.restart_animations()
		return
	if page_id == "transport_planning":
		_refresh_transport_planning_panel()
		return
	if page_id != "governance":
		return
	_lower_council_final_decision.clear()
	_refresh_governance_catalog()
	_refresh_lower_council_stage()
	_select_governance_status(
		"unimplemented"
		if onboarding_progress.is_active() and onboarding_progress.current_target() == "governance"
		else _preferred_governance_status()
	)


func _refresh_onboarding_guide() -> void:
	if onboarding_guide == null or not is_instance_valid(onboarding_guide):
		return
	if not _game_started or not onboarding_progress.is_active() or not onboarding_action_router.supports_current_target():
		onboarding_guide.invalidate_target()
		_sync_time_pause_for_ui()
		_sync_map_interaction_for_ui()
		return
	var current_game_day: int = int(vertical_slice.game_day()) if vertical_slice != null else 0
	if onboarding_progress.is_waiting(current_game_day):
		onboarding_guide.show_waiting(
			onboarding_progress,
			_onboarding_waiting_message(onboarding_progress.due_game_day())
		)
		_sync_time_pause_for_ui()
		_sync_map_interaction_for_ui()
		return
	var route_waiting_message := _route_onboarding_unavailable_message()
	if not route_waiting_message.is_empty():
		onboarding_guide.show_waiting(onboarding_progress, route_waiting_message)
		_sync_time_pause_for_ui()
		_sync_map_interaction_for_ui()
		return
	var case_presentation := _onboarding_case_non_target_presentation()
	if not case_presentation.is_empty():
		if str(case_presentation.get("mode", "")) == "result_review":
			onboarding_guide.show_result_review(onboarding_progress, str(case_presentation.get("message", "")))
		else:
			onboarding_guide.show_waiting(onboarding_progress, str(case_presentation.get("message", "")))
		_sync_time_pause_for_ui()
		_sync_map_interaction_for_ui()
		return
	var target := _resolve_onboarding_target()
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		onboarding_guide.invalidate_target()
		_sync_time_pause_for_ui()
		_sync_map_interaction_for_ui()
		return
	_ensure_onboarding_target_visible(target)
	if target is BaseButton and (target as BaseButton).disabled:
		onboarding_guide.invalidate_target()
		_sync_time_pause_for_ui()
		_sync_map_interaction_for_ui()
		return
	if onboarding_guide.is_product_mode() and onboarding_guide.target_control() == target:
		return
	onboarding_guide.open_product_target(
		onboarding_progress,
		target,
		OnboardingGuideScript.INPUT_MOUSE_LEFT,
		KEY_NONE,
		_onboarding_target_message(target)
	)
	_sync_time_pause_for_ui()
	_sync_map_interaction_for_ui()


func _resolve_onboarding_target() -> Control:
	match onboarding_progress.current_target():
		"build":
			return _resolve_build_onboarding_target()
		"blueprint":
			return _resolve_blueprint_onboarding_target()
		"route":
			return _resolve_route_onboarding_target()
		"fiscal":
			return _resolve_fiscal_onboarding_target()
		"city_data":
			return _resolve_city_data_onboarding_target()
		"public_affairs":
			return _resolve_public_affairs_onboarding_target()
		"governance":
			return _resolve_governance_onboarding_target()
		"judicial":
			return _resolve_justice_onboarding_target("judicial")
		"oversight":
			return _resolve_justice_onboarding_target("oversight")
	return null


func _resolve_build_onboarding_target() -> Control:
	if construction_confirmation != null and construction_confirmation.is_open():
		return _visible_control_named("ConfirmConstructionButton")
	if placement_mode_active:
		return _first_build_onboarding_grid_target()
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	match municipal_overlay.current_page():
		"hub":
			return _visible_control_named("BuildingsButton")
		"buildings":
			return _building_picker_target("住宅", "housing", 0)
		"blueprint":
			if selected_building == "住宅":
				return _visible_control_named("SubmitBlueprintButton")
	return municipal_button


func _resolve_blueprint_onboarding_target() -> Control:
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	match municipal_overlay.current_page():
		"hub":
			return _visible_control_named("BuildingsButton")
		"buildings":
			return _building_picker_target("公園", "community", 1)
		"blueprint":
			if selected_building == "公園" and vertical_slice_panel != null:
				var payload: Dictionary = vertical_slice_panel.current_design_payload()
				onboarding_action_router.begin_blueprint_design(payload)
				if onboarding_action_router.blueprint_design_changed():
					var custom_submit := _visible_control_named("SubmitCustomBlueprintButton")
					return custom_submit if custom_submit != null else _visible_control_named("SubmitBlueprintButton")
				return _visible_control_named("BlueprintMaterial")
	return municipal_button


func _resolve_route_onboarding_target() -> Control:
	if construction_confirmation != null and construction_confirmation.is_open():
		return _visible_control_named("ConfirmConstructionButton")
	var session := _transport_session_snapshot()
	var state := str(session.get("state", "inactive"))
	if placement_mode_active:
		var minimum_stops := 1 if str(session.get("mode", "")) == "air" else 2
		if _transport_session_station_count(session) >= minimum_stops:
			return placement_confirm_button
		if _transport_session_is_route_package(session):
			return _route_package_station_onboarding_target(session)
		return _first_onboarding_grid_target()
	if map_action_mode in ["transport_infrastructure", "transport_route_stops"]:
		if (
			map_action_mode == "transport_infrastructure"
			and state == "network_placement"
			and _transport_session_is_route_package(session)
		):
			return _route_package_network_onboarding_target(session)
		if not transport_plan_tiles.is_empty() or transport_route_station_tiles.size() >= 2:
			return placement_confirm_button
		return _first_onboarding_grid_target()
	if state not in ["inactive", "closed"]:
		if municipal_overlay == null or not municipal_overlay.is_open():
			if not _route_package_resource_wait_quote(session).is_empty():
				return null
			return municipal_button
		var back_target := _visible_municipal_back_target()
		if municipal_overlay.current_page() == "hub":
			return _visible_control_named("BuildingsButton")
		if municipal_overlay.current_page() != "transport_planning":
			return back_target
		if state == "network_placement" and Dictionary(session.get("network_draft", {})).get("tile_ids", []).is_empty():
			var infrastructure_target := _visible_control_named("InfrastructureAdd_road")
			return infrastructure_target if infrastructure_target != null else back_target
		if state == "route_edit" and _transport_session_is_route_package(session):
			var package_continue_target := _visible_enabled_control_named("TransportPlanningSessionContinue")
			if package_continue_target != null:
				return package_continue_target
			if not _route_package_resource_wait_quote(session).is_empty():
				return _visible_enabled_control_named("CloseButton")
			return null
		if state == "route_edit" and Dictionary(session.get("route_draft", {})).get("station_tile_ids", []).is_empty():
			var route_target := _visible_control_named("PlanRoute_bus")
			return route_target if route_target != null else back_target
		var continue_target := _visible_control_named("TransportPlanningSessionContinue")
		return continue_target if continue_target != null else back_target
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	match municipal_overlay.current_page():
		"hub":
			return _visible_control_named("BuildingsButton")
		"buildings":
			return _building_picker_target("公車站", "mobility", 1)
		"blueprint":
			if selected_building == "公車站":
				return _visible_control_named("SubmitBlueprintButton")
	return _visible_municipal_back_target()


func _route_package_resource_wait_quote(session: Dictionary) -> Dictionary:
	if (
		str(session.get("state", "")) != "route_edit"
		or not _transport_session_is_route_package(session)
		or vertical_slice == null
		or not vertical_slice.has_method("transport_session_package_quote")
	):
		return {}
	var quote: Dictionary = vertical_slice.call("transport_session_package_quote", city_grid)
	if not bool(quote.get("ok", false)) or bool(quote.get("can_start", false)):
		return {}
	var available_workers := int(quote.get("available_workers", -1))
	var requested_workers := int(quote.get("requested_workers", -1))
	var insufficient_workers := requested_workers > 0 and available_workers < requested_workers
	var insufficient_funds := not bool(quote.get("can_afford", false))
	return quote if insufficient_workers or insufficient_funds else {}


func _route_onboarding_unavailable_message() -> String:
	if onboarding_progress.current_target() != "route":
		return ""
	var session := _transport_session_snapshot()
	if (
		str(session.get("state", "")) != "route_edit"
		or not _transport_session_is_route_package(session)
		or vertical_slice == null
		or not vertical_slice.has_method("transport_session_package_quote")
	):
		return ""
	var quote: Dictionary = vertical_slice.call("transport_session_package_quote", city_grid)
	if not bool(quote.get("ok", false)):
		var repair_context := (
			"請在目前交通規劃中檢查站點、道路與營運設定"
			if municipal_overlay != null and municipal_overlay.is_open()
			else "請重新開啟市政中心，在交通規劃中檢查站點、道路與營運設定"
		)
		return "交通套案資料尚未完整（%s）。%s；也可延後教學。" % [
			_vertical_error_text(str(quote.get("error", "transport_route_invalid"))),
			repair_context,
		]
	quote = _route_package_resource_wait_quote(session)
	if quote.is_empty():
		return ""
	var available_workers := int(quote.get("available_workers", 0))
	var requested_workers := int(quote.get("requested_workers", 0))
	var insufficient_workers := requested_workers > 0 and available_workers < requested_workers
	var insufficient_funds := not bool(quote.get("can_afford", false))
	if insufficient_funds and insufficient_workers:
		return "交通套案目前資金與人力不足（總工程費 $%d；人力 %d/%d）。可先處理城市財政與工程，再繼續；也可延後教學。" % [
			int(quote.get("total_cost", 0)), available_workers, requested_workers,
		]
	if insufficient_funds:
		return "交通套案目前資金不足（總工程費 $%d）。可先處理城市財政，再繼續；也可延後教學。" % int(quote.get("total_cost", 0))
	return "交通套案目前人力不足（%d/%d）。可先處理城市與工程，準備完成後再繼續；也可延後教學。" % [
		available_workers,
		requested_workers,
	]


func _resolve_fiscal_onboarding_target() -> Control:
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	if municipal_overlay.current_page() == "hub":
		return _visible_control_named("FinanceButton")
	if municipal_overlay.current_page() != "finance":
		return _visible_municipal_back_target()
	if _fiscal_flow_step == "preview":
		return fiscal_apply_button
	if _fiscal_dirty_count() > 0:
		return fiscal_preview_button
	return _visible_control_named("FiscalSlider_tax_income")


func _resolve_city_data_onboarding_target() -> Control:
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	if municipal_overlay.current_page() == "hub":
		return _visible_control_named("City DataButton")
	if municipal_overlay.current_page() != "city_data" or city_data_dashboard == null:
		return _visible_municipal_back_target()
	onboarding_action_router.note_city_data_opened(city_data_dashboard.current_tab, city_data_dashboard.get_tab_count())
	return city_data_dashboard.get_tab_bar()


func _resolve_public_affairs_onboarding_target() -> Control:
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	if municipal_overlay.current_page() == "hub":
		return _visible_control_named("Public AffairsButton")
	if municipal_overlay.current_page() != "public_affairs":
		return _visible_municipal_back_target()
	for request_variant: Variant in vertical_slice.get_view_model(selected_cell_index).get("citizen_requests", []):
		if request_variant is Dictionary and str(Dictionary(request_variant).get("status", "")) == "pending":
			var request_id := str(Dictionary(request_variant).get("request_id", ""))
			var target := _visible_control_named("AcceptRequest_%s" % request_id)
			if target != null:
				return target
	return null


func _resolve_governance_onboarding_target() -> Control:
	if vertical_slice == null or vertical_slice.governance == null:
		return null
	var governance = vertical_slice.governance
	var pending: Dictionary = governance.pending_bill
	if municipal_overlay == null or not municipal_overlay.is_open():
		# A submitted bill advances only through the real game clock. Keep the guide
		# closed while the council is deliberating so time is not accidentally held.
		if not pending.is_empty() and str(pending.get("status", "")) != "awaiting_mayor_response":
			return null
		return municipal_button
	if municipal_overlay.current_page() == "hub":
		return _visible_control_named("GovernanceButton")
	if municipal_overlay.current_page() != "governance":
		return _visible_municipal_back_target()
	var visible_stage_signature: Dictionary = lower_council_stage.debug_signature() if lower_council_stage != null else {}
	if str(visible_stage_signature.get("stage_state", "")) == "final_vote":
		return _visible_control_named("BackButton")
	if not pending.is_empty():
		if str(pending.get("status", "")) != "awaiting_mayor_response":
			return _visible_control_named("CloseButton")
		var response_id := _onboarding_governance_response_id(pending)
		if response_id.is_empty():
			return null
		if str(visible_stage_signature.get("selected_response_id", "")) == response_id:
			return _visible_control_named("LowerCouncilConfirmResponse")
		return _visible_control_named("LowerCouncilResponse_%s" % response_id)
	if not _onboarding_governance_bill_resolved("environment_act"):
		return _visible_control_named("GovernanceBill_環境保護法案")
	if not _onboarding_governance_bill_resolved("transit_act"):
		return _visible_control_named("GovernanceBill_交通建設法案")
	if not _onboarding_governance_bill_resolved("commerce_act"):
		return _visible_control_named("GovernanceBill_商業促進法案")
	if (
		governance.rejected_bills.has("commerce_act")
		and vertical_slice.latest_rejected_bill_id() == "commerce_act"
	):
		return governance_force_button
	return null


func _onboarding_governance_response_id(pending: Dictionary) -> String:
	var bill_id := str(pending.get("bill_id", ""))
	if bill_id in ["transit_act", "commerce_act"]:
		return "focus_primary"
	if bill_id != "environment_act":
		return ""
	var response_options: Array = pending.get("lower_house_hearing", {}).get("response_options", [])
	for option_variant: Variant in response_options:
		if not (option_variant is Dictionary):
			continue
		var response_id := str(Dictionary(option_variant).get("id", ""))
		var preview: Dictionary = vertical_slice.preview_lower_house_response(response_id, _vertical_city_context())
		if bool(preview.get("ok", false)) and not bool(preview.get("passed", true)):
			return response_id
	return str(Dictionary(response_options[0]).get("id", "")) if not response_options.is_empty() and response_options[0] is Dictionary else ""


func _onboarding_governance_bill_resolved(bill_id: String) -> bool:
	for decision_variant: Variant in vertical_slice.governance.legislative_history:
		if decision_variant is Dictionary and str(Dictionary(decision_variant).get("bill_id", "")) == bill_id:
			return true
	return false


func _resolve_justice_onboarding_target(mode: String) -> Control:
	if mode not in ["judicial", "oversight"] or vertical_slice == null:
		return null
	if municipal_overlay == null or not municipal_overlay.is_open():
		return municipal_button
	if municipal_overlay.current_page() == "hub":
		return _visible_control_named("JudicialButton" if mode == "judicial" else "OversightButton")
	if municipal_overlay.current_page() != mode:
		return _visible_municipal_back_target()
	var panel = judicial_panel if mode == "judicial" else oversight_panel
	var expected_case_id := onboarding_action_router.linked_case_id(
		mode,
		vertical_slice.session.state.event_book
	)
	if expected_case_id.is_empty() or panel == null:
		return null
	if str(panel.call("selected_case_id")) != expected_case_id:
		var selection_result: Variant = panel.call("select_case_by_id", expected_case_id)
		if selection_result == null or not bool(selection_result):
			return null
	return _visible_control_named(
		"PublicInterestDefenseButton" if mode == "judicial" else "FullDisclosureDefenseButton"
	)


func _building_picker_target(building_name: String, group_id: String, family_tab: int) -> Control:
	if building_family_tabs != null and building_family_tabs.current_tab != family_tab:
		return building_family_tabs.get_tab_bar()
	if selected_building_group != group_id:
		return _visible_control_named("BuildingGroup_%s" % group_id)
	return _visible_control_named("BuildingCard_%s" % building_name)


func _visible_control_named(control_name: String) -> Control:
	var node := find_child(control_name, true, false)
	return node as Control if node is Control and (node as Control).is_visible_in_tree() else null


func _visible_enabled_control_named(control_name: String) -> Control:
	var control := _visible_control_named(control_name)
	if control is BaseButton and (control as BaseButton).disabled:
		return null
	return control


func _visible_municipal_back_target() -> Control:
	if municipal_overlay == null or not municipal_overlay.is_open():
		return null
	return _visible_control_named("BackButton")


func _ensure_onboarding_target_visible(target: Control) -> void:
	var ancestor := target.get_parent()
	while ancestor != null and ancestor != self:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(target)
		ancestor = ancestor.get_parent()


func _first_onboarding_grid_target() -> Control:
	for button_variant: Variant in grid_buttons:
		var button := button_variant as Button
		if button != null and is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled:
			return button
	return null


func _first_build_onboarding_grid_target() -> Control:
	if vertical_slice == null or placement_building_name.is_empty():
		return null
	var workers: int = int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel else 5
	for index in grid_buttons.size():
		var button := grid_buttons[index] as Button
		if button == null or not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
			continue
		if placement_banner != null and placement_banner.is_visible_in_tree() and button.get_global_rect().intersects(placement_banner.get_global_rect()):
			continue
		if not _is_tile_inside_hud_safe_area(index):
			continue
		var quote: Dictionary = vertical_slice.placement_footprint_quote(
			placement_building_name,
			index,
			workers,
			placement_rotation_quarter_turns_ccw
		)
		if not bool(quote.get("ok", false)) or str(quote.get("status", "")) != "approved" or not bool(quote.get("can_afford", false)):
			continue
		var occupied_tile_ids: Array = quote.get("occupied_tile_ids", [])
		var footprint_is_hud_safe := not occupied_tile_ids.is_empty()
		for tile_variant: Variant in occupied_tile_ids:
			if not _is_tile_inside_hud_safe_area(int(tile_variant)):
				footprint_is_hud_safe = false
				break
		if footprint_is_hud_safe:
			return button
	return null


func _route_package_station_onboarding_target(session: Dictionary) -> Control:
	if vertical_slice == null or str(session.get("state", "")) != "station_placement":
		return null
	var placements: Array = Dictionary(session.get("route_draft", {})).get("station_placements", [])
	if placements.size() > 1:
		return null
	var selected: Array[Dictionary] = []
	if placements.size() == 1:
		if not placements[0] is Dictionary:
			return null
		var current := _route_package_current_station_candidate(session, placements[0])
		if current.is_empty():
			return null
		selected.append(current)
	var candidates := _route_package_station_candidates(session, selected)
	if selected.is_empty():
		for first: Dictionary in candidates:
			for second: Dictionary in candidates:
				if not _route_package_station_candidates_are_distinct(first, second):
					continue
				var corridor := _route_package_corridor_completion(session, [first, second], [])
				if corridor.size() > 1:
					return grid_buttons[int(first.get("anchor_tile_id", -1))] as Control
		return null
	var first: Dictionary = selected[0]
	for second: Dictionary in candidates:
		if not _route_package_station_candidates_are_distinct(first, second):
			continue
		var corridor := _route_package_corridor_completion(session, [first, second], [])
		if corridor.size() > 1:
			return grid_buttons[int(second.get("anchor_tile_id", -1))] as Control
	return null


func _route_package_network_onboarding_target(session: Dictionary) -> Control:
	var stations := _route_package_current_station_candidates(session)
	if stations.size() < 2:
		return null
	var completion := _route_package_corridor_completion(session, stations, transport_plan_tiles)
	if completion.is_empty():
		return null
	if completion.size() == transport_plan_tiles.size():
		return placement_confirm_button if (
			placement_confirm_button != null
			and placement_confirm_button.is_visible_in_tree()
			and not placement_confirm_button.disabled
		) else null
	var next_tile := int(completion[transport_plan_tiles.size()])
	return grid_buttons[next_tile] as Control if _route_onboarding_grid_button_is_safe(next_tile) else null


func _route_package_station_candidates(
	session: Dictionary,
	excluded: Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile_id in grid_buttons.size():
		var candidate := _route_package_station_candidate(session, tile_id, excluded)
		if not candidate.is_empty():
			result.append(candidate)
	return result


func _route_package_current_station_candidates(session: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement_value: Variant in Dictionary(session.get("route_draft", {})).get("station_placements", []):
		if not placement_value is Dictionary:
			return []
		var candidate := _route_package_current_station_candidate(session, placement_value)
		if candidate.is_empty():
			return []
		for existing: Dictionary in result:
			if not _route_package_station_candidates_are_distinct(existing, candidate):
				return []
		result.append(candidate)
	return result


func _route_package_current_station_candidate(session: Dictionary, placement: Dictionary) -> Dictionary:
	if bool(placement.get("reuse_existing_station", false)):
		return {}
	var anchor_tile_id := int(placement.get("anchor_tile_id", -1))
	var candidate := _route_package_station_candidate(session, anchor_tile_id, [])
	if candidate.is_empty():
		return {}
	var quote: Dictionary = candidate.get("quote", {})
	if (
		str(placement.get("footprint_id", "")) != str(quote.get("footprint_id", ""))
		or str(placement.get("library_id", "")) != str(quote.get("library_id", ""))
		or _route_onboarding_int_array(placement.get("occupied_tile_ids", [])) != _route_onboarding_int_array(quote.get("occupied_tile_ids", []))
		or int(placement.get("building_cost", -1)) != int(quote.get("total_cost", -2))
	):
		return {}
	return candidate


func _route_package_station_candidate(
	session: Dictionary,
	anchor_tile_id: int,
	excluded: Array
) -> Dictionary:
	if vertical_slice == null or anchor_tile_id < 0 or anchor_tile_id >= grid_buttons.size():
		return {}
	var station_name := str(session.get("station_blueprint_name", ""))
	if station_name.is_empty():
		return {}
	var workers := int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel != null else 5
	var quote: Dictionary = vertical_slice.placement_footprint_quote(station_name, anchor_tile_id, workers)
	if (
		not bool(quote.get("ok", false))
		or str(quote.get("status", "")) != "approved"
		or not bool(quote.get("can_place", false))
		or not bool(quote.get("can_afford", false))
	):
		return {}
	var occupied_tile_ids := _route_onboarding_int_array(quote.get("occupied_tile_ids", []))
	if occupied_tile_ids.is_empty() or not occupied_tile_ids.has(anchor_tile_id):
		return {}
	var terrain = _terrain_map()
	if terrain == null:
		return {}
	for occupied_tile_id: int in occupied_tile_ids:
		if not terrain.is_buildable(occupied_tile_id):
			return {}
	if not _route_onboarding_grid_footprint_is_safe(occupied_tile_ids):
		return {}
	for existing: Dictionary in excluded:
		for occupied_tile_id: int in _route_onboarding_int_array(existing.get("occupied_tile_ids", [])):
			if occupied_tile_ids.has(occupied_tile_id):
				return {}
	return {
		"anchor_tile_id": anchor_tile_id,
		"occupied_tile_ids": occupied_tile_ids,
		"total_cost": int(quote.get("total_cost", 0)),
		"quote": quote,
	}


func _route_package_station_candidates_are_distinct(first: Dictionary, second: Dictionary) -> bool:
	if int(first.get("anchor_tile_id", -1)) == int(second.get("anchor_tile_id", -1)):
		return false
	var first_tiles := _route_onboarding_int_array(first.get("occupied_tile_ids", []))
	for tile_id: int in _route_onboarding_int_array(second.get("occupied_tile_ids", [])):
		if first_tiles.has(tile_id):
			return false
	return true


func _route_package_corridor_completion(
	session: Dictionary,
	stations: Array,
	selected_tiles: Array
) -> Array[int]:
	if vertical_slice == null or stations.size() < 2:
		return []
	var reserved: Array[int] = []
	var station_cost := 0
	for station: Dictionary in stations:
		station_cost += int(station.get("total_cost", 0))
		for tile_id: int in _route_onboarding_int_array(station.get("occupied_tile_ids", [])):
			if not reserved.has(tile_id):
				reserved.append(tile_id)
	var first_anchor := int(stations[0].get("anchor_tile_id", -1))
	var second_anchor := int(stations[1].get("anchor_tile_id", -1))
	var first_access := _route_package_corridor_access_tiles(first_anchor, reserved)
	var second_access := _route_package_corridor_access_tiles(second_anchor, reserved)
	if first_access.is_empty() or second_access.is_empty():
		return []
	var prefix := _route_onboarding_int_array(selected_tiles)
	var starts: Array[int] = first_access
	var goals: Array[int] = second_access
	if not prefix.is_empty():
		if first_access.has(prefix[0]):
			pass
		elif second_access.has(prefix[0]):
			starts = second_access
			goals = first_access
		else:
			return []
		for index in prefix.size():
			var tile_id := prefix[index]
			if not _route_package_corridor_tile_is_available(tile_id, reserved):
				return []
			if index > 0 and _transport_direction_pair(prefix[index - 1], tile_id).is_empty():
				return []
	var candidate: Array[int]
	if prefix.is_empty():
		candidate = _route_package_shortest_corridor(starts, goals, reserved, [])
	elif goals.has(prefix.back()):
		candidate = prefix.duplicate()
	else:
		var suffix := _route_package_shortest_corridor([prefix.back()], goals, reserved, prefix)
		if suffix.is_empty():
			return []
		candidate = prefix.duplicate()
		for suffix_index in range(1, suffix.size()):
			candidate.append(suffix[suffix_index])
	if candidate.is_empty() or not _route_package_corridor_plan_is_approved(session, stations, candidate, reserved, station_cost):
		return []
	return candidate


func _route_package_shortest_corridor(
	starts: Array,
	goals: Array,
	reserved: Array,
	blocked_path: Array
) -> Array[int]:
	var queue: Array[int] = []
	var previous: Dictionary = {}
	var seen: Dictionary = {}
	for start: int in starts:
		if not _route_package_corridor_tile_is_available(start, reserved):
			continue
		if blocked_path.has(start) and (blocked_path.is_empty() or start != blocked_path.back()):
			continue
		queue.append(start)
		seen[start] = true
		previous[start] = -1
	var cursor := 0
	var reached := -1
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		if goals.has(current):
			reached = current
			break
		for neighbour: int in _route_package_cardinal_neighbours(current):
			if seen.has(neighbour) or not _route_package_corridor_tile_is_available(neighbour, reserved):
				continue
			if blocked_path.has(neighbour) and (blocked_path.is_empty() or neighbour != blocked_path.back()):
				continue
			seen[neighbour] = true
			previous[neighbour] = current
			queue.append(neighbour)
	if reached < 0:
		return []
	var reversed: Array[int] = []
	var current := reached
	while current >= 0:
		reversed.append(current)
		current = int(previous.get(current, -1))
	reversed.reverse()
	return reversed


func _route_package_corridor_plan_is_approved(
	session: Dictionary,
	stations: Array,
	path: Array[int],
	reserved: Array[int],
	station_cost: int
) -> bool:
	var transport = vertical_slice.transport
	var terrain = _terrain_map()
	if transport == null or terrain == null:
		return false
	var construction_tiles: Array[int] = []
	for tile_id in city_grid.size():
		if not vertical_slice.active_construction_for_tile(tile_id).is_empty():
			construction_tiles.append(tile_id)
	var model_quote: Dictionary = transport.quote_completed_corridor(
		str(session.get("mode", "")), path, terrain, reserved, construction_tiles
	)
	if not bool(model_quote.get("ok", false)):
		return false
	var workers := int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel != null else 5
	var project_quote: Dictionary = vertical_slice.transport_project_quote(
		_transport_session_guideway(str(session.get("mode", ""))),
		"build",
		path,
		workers,
		city_grid
	)
	if not bool(project_quote.get("ok", false)) or not bool(project_quote.get("can_afford", false)):
		return false
	var combined_cost := station_cost + int(project_quote.get("total_cost", 0))
	return vertical_slice.treasury_balance() >= combined_cost and stations.size() >= 2


func _route_package_corridor_access_tiles(anchor_tile_id: int, reserved: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for neighbour: int in _route_package_cardinal_neighbours(anchor_tile_id):
		if _route_package_corridor_tile_is_available(neighbour, reserved):
			result.append(neighbour)
	return result


func _route_package_cardinal_neighbours(tile_id: int) -> Array[int]:
	var result: Array[int] = []
	var terrain = _terrain_map()
	if terrain == null or not terrain.is_valid_tile_id(tile_id):
		return result
	var coordinate: Vector2i = terrain.coordinate_for_tile_id(tile_id)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbour := int(terrain.tile_id_for_coordinate(coordinate + offset))
		if neighbour >= 0:
			result.append(neighbour)
	return result


func _route_package_corridor_tile_is_available(tile_id: int, reserved: Array[int]) -> bool:
	var terrain = _terrain_map()
	return (
		terrain != null
		and terrain.is_valid_tile_id(tile_id)
		and terrain.is_buildable(tile_id)
		and not reserved.has(tile_id)
		and tile_id >= 0
		and tile_id < city_grid.size()
		and str(city_grid[tile_id]).is_empty()
		and vertical_slice.get_building_by_tile(tile_id).is_empty()
		and vertical_slice.active_construction_for_tile(tile_id).is_empty()
		and _route_onboarding_grid_button_is_safe(tile_id)
	)


func _route_onboarding_grid_footprint_is_safe(tile_ids: Array[int]) -> bool:
	for tile_id: int in tile_ids:
		if not _route_onboarding_grid_button_is_safe(tile_id):
			return false
	return true


func _route_onboarding_grid_button_is_safe(tile_id: int) -> bool:
	if tile_id < 0 or tile_id >= grid_buttons.size():
		return false
	var button := grid_buttons[tile_id] as Button
	if button == null or not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		return false
	if not _is_tile_inside_hud_safe_area(tile_id):
		return false
	var button_rect := button.get_global_rect()
	if not button_rect.has_area() or not get_viewport().get_visible_rect().encloses(button_rect):
		return false
	var ancestor := button.get_parent()
	while ancestor != null and ancestor != self:
		if ancestor is Control and (ancestor as Control).clip_contents and not (ancestor as Control).get_global_rect().encloses(button_rect):
			return false
		ancestor = ancestor.get_parent()
	for overlay_value: Variant in [status_hud, placement_banner, action_dock]:
		var overlay := overlay_value as Control
		if overlay != null and overlay.is_visible_in_tree() and button_rect.intersects(overlay.get_global_rect()):
			return false
	return true


func _route_onboarding_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array and not value is PackedInt32Array and not value is PackedInt64Array:
		return result
	for tile_value: Variant in value:
		var tile_id := int(tile_value)
		if not result.has(tile_id):
			result.append(tile_id)
	return result


func _onboarding_target_message(target: Control) -> String:
	if target == null:
		return ""
	if not target.tooltip_text.is_empty():
		return target.tooltip_text
	if target.has_meta("semantic_label"):
		return str(target.get_meta("semantic_label"))
	if target is BaseButton:
		return (target as BaseButton).text
	return ""


func _onboarding_waiting_message(due_game_day: int) -> String:
	return "教學預定於%s繼續；等待期間可正常遊玩。" % _onboarding_date_label(due_game_day)


func _onboarding_date_label(game_day: int) -> String:
	var bounded_day := maxi(0, game_day)
	var days_per_year := CityStateScript.DAYS_PER_MONTH * CityStateScript.MONTHS_PER_YEAR
	var year := int(bounded_day / days_per_year) + 1
	var year_day := bounded_day % days_per_year
	var month := int(year_day / CityStateScript.DAYS_PER_MONTH) + 1
	var day := year_day % CityStateScript.DAYS_PER_MONTH + 1
	return "第 %d 年 %d 月 %d 日" % [year, month, day]


func _onboarding_case_non_target_presentation() -> Dictionary:
	var mode := onboarding_progress.current_target()
	if mode not in ["judicial", "oversight"] or vertical_slice == null:
		return {}
	var event_book: Array = vertical_slice.session.state.event_book
	var case_id := onboarding_action_router.linked_case_id(mode, event_book)
	if case_id.is_empty():
		return {}
	var cases: Dictionary = (
		vertical_slice.governance.judiciary_cases
		if mode == "judicial"
		else vertical_slice.governance.oversight_cases
	)
	if not cases.has(case_id) or not (cases[case_id] is Dictionary):
		return {}
	var case_payload: Dictionary = Dictionary(cases[case_id])
	if str(case_payload.get("status", "")) == "resolved":
		return {
			"mode": "result_review",
			"message": _onboarding_case_result_message(mode, case_payload),
		}
	if (
		mode == "judicial"
		and str(case_payload.get("status", "")) == "investigating"
		and str(case_payload.get("procedural_stage", "")) in ["deliberation", "judgment"]
	):
		return {
			"mode": "waiting",
			"message": "司法案件 %s 已進入合議，答辯收件已結束。可正常遊玩，待裁決完成後將顯示真實結果；也可延後教學。" % case_id,
		}
	return {}


func _onboarding_case_result_message(mode: String, case_payload: Dictionary) -> String:
	var case_id := str(case_payload.get("id", ""))
	var result_label := _onboarding_case_result_label(mode, str(case_payload.get("outcome", "")))
	var resolved_date := _onboarding_date_label(int(case_payload.get("resolved_day", 0)))
	var case_kind := "司法案件" if mode == "judicial" else "監察案件"
	return "%s %s 已結案。結果：%s；結案日期：%s。案件已結案，無法再提交答辯；請閱讀結果後繼續教學。" % [
		case_kind,
		case_id,
		result_label,
		resolved_date,
	]


func _onboarding_case_result_label(mode: String, outcome: String) -> String:
	if mode == "judicial":
		return {
			"fine": "裁處罰款",
			"stop_order": "發布停止命令",
			"prison": "判處監禁",
		}.get(outcome, "司法裁決完成")
	return {
		"impeached": "彈劾成立",
		"cleared": "調查後不予彈劾",
	}.get(outcome, "監察調查完成")


func _on_city_data_tab_changed(tab_index: int) -> void:
	if city_data_dashboard == null or vertical_slice == null:
		return
	if onboarding_action_router.record_city_data_tab_changed(
		tab_index, city_data_dashboard.get_tab_count(), vertical_slice.game_day()
	):
		_autosave("action:onboarding_city_data_tab_changed")
		call_deferred("_refresh_onboarding_guide")


func _preferred_governance_status() -> String:
	for enabled_variant: Variant in active_policies.values():
		if bool(enabled_variant):
			return "implemented"
	if vertical_slice != null and vertical_slice.governance != null:
		if not vertical_slice.governance.active_laws.is_empty():
			return "implemented"
		if not vertical_slice.governance.pending_bill.is_empty():
			return "review"
	return "unimplemented"

func _open_city_data() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	var overlay := _ensure_municipal_overlay()
	if overlay == null:
		return
	_set_map_interaction_enabled(false)
	overlay.open_page("city_data")

func _open_monthly_report() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	var overlay := _ensure_municipal_overlay()
	if overlay == null:
		return
	_set_map_interaction_enabled(false)
	overlay.open_page("report")


func _open_settings() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	if settings_overlay != null:
		_set_map_interaction_enabled(false)
		settings_overlay.open()

func _build_city_data_page() -> Control:
	city_metric_cards.clear()
	city_metric_primary_grid = null
	city_metric_secondary_grid = null
	city_metric_priority_label = null
	city_metric_details_button = null
	city_data_dashboard = CityDataDashboardScript.new()
	city_data_dashboard.configure({
		"dark_mode": is_dark_mode,
		"viewport_width": get_viewport_rect().size.x,
		"metric_specs": _city_metric_specs(),
		"resident_group_names": group_satisfaction.keys(),
	})
	city_data_dashboard.tab_changed.connect(Callable(self, "_on_city_data_tab_changed"))
	monthly_data_kpi_charts = city_data_dashboard.monthly_data_kpi_charts
	monthly_data_service_charts = city_data_dashboard.monthly_data_service_charts
	benchmark_charts = city_data_dashboard.benchmark_charts
	group_bars = city_data_dashboard.group_bars
	labels.merge(city_data_dashboard.labels, true)
	finance_bars.merge(city_data_dashboard.finance_bars, true)
	return city_data_dashboard

func _build_report_page() -> ScrollContainer:
	report_details_button = null
	report_details_panel = null
	report_details_label = null
	_load_version_updates()
	var scroll := ScrollContainer.new()
	scroll.name = "月度報告"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)

	var summary_panel := _panel(_theme_panel_alt(), 10, 20)
	summary_panel.name = "MonthlySummary"
	var summary_content := VBoxContainer.new()
	summary_content.add_theme_constant_override("separation", 16)
	summary_panel.add_child(summary_content)
	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 14)
	summary_content.add_child(summary_row)
	summary_row.add_child(_icon_texture_rect("report", Vector2(72, 72)))
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 8)
	summary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(summary_box)
	var title := _label("本月摘要", 23, _theme_text())
	title.custom_minimum_size = Vector2(0, 34)
	summary_box.add_child(title)
	report_label = _label("", 18, _theme_muted())
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.custom_minimum_size = Vector2(0, 118)
	summary_box.add_child(report_label)
	content.add_child(summary_panel)

	var announcement_panel := _panel(_theme_panel_alt(), 10, 20)
	announcement_panel.name = "VersionUpdateAnnouncements"
	var announcement_box := VBoxContainer.new()
	announcement_box.add_theme_constant_override("separation", 12)
	announcement_panel.add_child(announcement_box)
	announcement_box.add_child(_section_title("版本更新公告"))
	announcement_label = _label("", 18, _theme_accent_text())
	announcement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	announcement_label.custom_minimum_size = Vector2(0, 150)
	announcement_box.add_child(announcement_label)
	content.add_child(announcement_panel)

	return scroll


func _toggle_report_details() -> void:
	if report_details_panel == null or report_details_button == null:
		return
	report_details_panel.visible = not report_details_panel.visible
	report_details_button.text = L10n.text("收起完整明細") if report_details_panel.visible else L10n.text("展開完整收支與人口明細")

func _header_metric_card(key: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "StatusMetric_%s" % key.capitalize()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var minimum_widths := {
		"month": 126.0,
		"funds": 116.0,
		"population": 108.0,
		"satisfaction": 108.0,
		"grievance": 108.0,
		"trust": 100.0,
		"score": 96.0,
		"rating": 122.0,
	}
	card.custom_minimum_size = Vector2(float(minimum_widths.get(key, 100.0)), 0)
	if key == "rating":
		card.size_flags_stretch_ratio = 1.15
	var style := StyleBoxFlat.new()
	style.bg_color = Color("493b32") if is_dark_mode else Color("fffbef")
	style.border_color = Color("8d7055") if is_dark_mode else Color("b38a55")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	card.add_child(stack)
	var visual_row := HBoxContainer.new()
	visual_row.add_theme_constant_override("separation", 3)
	stack.add_child(visual_row)
	visual_row.add_child(_icon_texture_rect(key, Vector2(24, 24)))
	var item := _label("", 14, Color("fff4d7") if is_dark_mode else Color("35291f"))
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.max_lines_visible = 2
	item.clip_text = false
	item.custom_minimum_size = Vector2(0, 40)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels[key] = item
	visual_row.add_child(item)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	_style_progress_bar(bar)
	var header_bar_background := StyleBoxFlat.new()
	header_bar_background.bg_color = Color("655448") if is_dark_mode else Color("ded2b6")
	header_bar_background.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", header_bar_background)
	header_bars[key] = bar
	stack.add_child(bar)
	return card


func _build_vertical_slice_tab() -> ScrollContainer:
	vertical_slice_panel = VerticalSlicePanelScript.new()
	vertical_slice_panel.set_dark_mode(is_dark_mode)
	vertical_slice_panel.set_selected_building(selected_building)
	vertical_slice_panel.blueprint_submit_requested.connect(Callable(self, "_on_blueprint_submit_requested"))
	vertical_slice_panel.placement_requested.connect(Callable(self, "_on_blueprint_placement_requested"))
	vertical_slice_panel.worker_count_changed.connect(Callable(self, "_on_blueprint_worker_count_changed"))
	vertical_slice_panel.design_changed.connect(Callable(self, "_on_blueprint_design_changed"))
	vertical_slice_panel.blueprint_library_selection_requested.connect(Callable(self, "_on_blueprint_library_selection_requested"))
	return vertical_slice_panel

func _build_building_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "建築選擇"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(900, 0)
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)

	content.add_child(_illustrated_section_title("buildings", "選擇建築"))
	var selected_card := _panel(_theme_panel_alt(), 12, 12)
	selected_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_row := HBoxContainer.new()
	selected_row.add_theme_constant_override("separation", 12)
	selected_card.add_child(selected_row)
	selected_row.add_child(_icon_texture_rect("blueprint", Vector2(58, 58)))
	selected_label = _label("", 18, _theme_accent_text())
	selected_label.custom_minimum_size = Vector2(0, 58)
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_row.add_child(selected_label)
	content.add_child(selected_card)

	building_family_tabs = TabContainer.new()
	building_family_tabs.name = "BuildingFamilyTabs"
	building_family_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_family_tabs.add_theme_font_size_override("font_size", 19)
	_style_tabs(building_family_tabs)
	content.add_child(building_family_tabs)
	for family: Dictionary in BUILDING_FAMILIES:
		var family_groups := HBoxContainer.new()
		family_groups.name = str(family["title"])
		family_groups.alignment = BoxContainer.ALIGNMENT_CENTER
		family_groups.add_theme_constant_override("separation", 10)
		family_groups.set_meta("progressive_choice_group", true)
		for group_id_variant in family["groups"]:
			var group_id := str(group_id_variant)
			var group := _building_group_definition(group_id)
			if group.is_empty():
				continue
			var group_button := _button(str(group["title"]))
			group_button.name = "BuildingGroup_%s" % group_id
			group_button.icon = _icon_texture(str(group["icon"]))
			group_button.add_theme_constant_override("icon_max_width", 44)
			group_button.expand_icon = true
			group_button.custom_minimum_size = Vector2(280, 78)
			group_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			group_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			group_button.add_theme_font_size_override("font_size", 18)
			group_button.tooltip_text = "%s：%s" % [group["title"], "、".join(PackedStringArray(group["categories"]))]
			group_button.pressed.connect(_select_building_group.bind(group_id))
			group_button.set_meta("progressive_choice", true)
			building_group_buttons[group_id] = group_button
			family_groups.add_child(group_button)
		building_family_tabs.add_child(family_groups)
	building_family_tabs.tab_changed.connect(_on_building_family_changed)

	var group_pages := VBoxContainer.new()
	group_pages.name = "BuildingGroupPages"
	group_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(group_pages)
	for group: Dictionary in BUILDING_GROUPS:
		var group_id := str(group["id"])
		var page := VBoxContainer.new()
		page.name = "BuildingPage_%s" % group_id
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 10)
		var category_names: Array = group["categories"]
		var heading := _category_title("%s｜%s" % [group["title"], "、".join(PackedStringArray(category_names))])
		page.add_child(heading)
		var category_grid = ProgressiveChoicePagerScript.new(3, 6)
		category_grid.name = "BuildingChoices_%s" % group_id
		category_grid.call("set_balanced_page_layout", true)
		category_grid.call("set_minimum_choice_width", 300.0)
		page.add_child(category_grid)
		for category: String in category_names:
			for building_name in _buildings_in_category(category):
				var data: Dictionary = buildings[building_name]
				var button := _button(_building_visual_text(building_name, data))
				button.name = "BuildingCard_%s" % building_name
				button.add_theme_font_size_override("font_size", 18)
				button.icon = _building_texture(building_name)
				button.add_theme_constant_override("icon_max_width", 76)
				button.expand_icon = true
				button.custom_minimum_size = Vector2(300, 120)
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.tooltip_text = "%s\n%s\n%s" % [L10n.text(building_name), L10n.text(str(data.get("description", ""))), _visual_effects(data, 8)]
				button.pressed.connect(Callable(self, "_select_building_from_catalog").bind(building_name))
				building_buttons[building_name] = button
				category_grid.call("add_choice", button)
		building_card_pagers[group_id] = category_grid
		building_group_pages[group_id] = page
		group_pages.add_child(page)

	_select_building_group(selected_building_group)

	return scroll

func _build_fiscal_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "稅率與公共事業費"
	fiscal_page_scroll = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	content.add_child(_illustrated_section_title("funds", "稅率與公共收費"))
	var instruction := _label("先選一個分類，再選現行、合理建議或自訂方案；完成後再預覽整份草稿。", 16, _theme_muted())
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(instruction)

	fiscal_responsive_layout = GridContainer.new()
	fiscal_responsive_layout.name = "FiscalResponsiveLayout"
	fiscal_responsive_layout.columns = 1
	fiscal_responsive_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiscal_responsive_layout.add_theme_constant_override("h_separation", 14)
	fiscal_responsive_layout.add_theme_constant_override("v_separation", 14)
	content.add_child(fiscal_responsive_layout)

	var choice_panel := _panel(_theme_panel_alt(), 9, 14)
	choice_panel.name = "FiscalChoicePanel"
	choice_panel.custom_minimum_size = Vector2(560, 0)
	choice_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var choice_box := VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 12)
	choice_panel.add_child(choice_box)
	fiscal_responsive_layout.add_child(choice_panel)

	fiscal_category_surface = VBoxContainer.new()
	fiscal_category_surface.name = "FiscalCategorySurface"
	fiscal_category_surface.add_theme_constant_override("separation", 10)
	choice_box.add_child(fiscal_category_surface)
	fiscal_category_surface.add_child(_section_title("選擇調整分類"))
	var category_help := _label("六個分類各自提供三種方案；切換分類不會清除其他草稿變更。", 15, _theme_muted())
	category_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fiscal_category_surface.add_child(category_help)
	fiscal_draft_status_label = _label("正式設定｜尚未變更\n可先調整多項，再預覽一次套用。", 16, _theme_muted())
	fiscal_draft_status_label.name = "FiscalDraftStatus"
	fiscal_draft_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fiscal_draft_status_label.custom_minimum_size = Vector2(0, 48)
	fiscal_category_surface.add_child(fiscal_draft_status_label)
	fiscal_preview_button = _button(L10n.text("預覽變更（%d）") % 0, "primary")
	fiscal_preview_button.name = "FiscalPreviewButton"
	fiscal_preview_button.custom_minimum_size = Vector2(0, 50)
	fiscal_preview_button.pressed.connect(_show_fiscal_preview)
	fiscal_category_surface.add_child(fiscal_preview_button)
	fiscal_category_grid = GridContainer.new()
	fiscal_category_grid.name = "FiscalCategoryCardGrid"
	fiscal_category_grid.columns = 2
	fiscal_category_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiscal_category_grid.add_theme_constant_override("h_separation", 10)
	fiscal_category_grid.add_theme_constant_override("v_separation", 10)
	fiscal_category_surface.add_child(fiscal_category_grid)
	for spec: Dictionary in FISCAL_CATEGORY_SPECS:
		var category_button := _button(str(spec["title"]))
		category_button.name = "FiscalCategoryCard_%s" % str(spec["id"])
		category_button.tooltip_text = _fiscal_category_hint(str(spec["title"]))
		category_button.custom_minimum_size = Vector2(250, 104)
		category_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_button.add_theme_font_size_override("font_size", 18)
		category_button.pressed.connect(Callable(self, "_select_fiscal_category").bind(str(spec["id"])))
		fiscal_category_grid.add_child(category_button)

	fiscal_plan_surface = VBoxContainer.new()
	fiscal_plan_surface.name = "FiscalPlanSurface"
	fiscal_plan_surface.add_theme_constant_override("separation", 10)
	fiscal_plan_surface.hide()
	choice_box.add_child(fiscal_plan_surface)
	var back_button := _button("← 返回六個分類")
	back_button.name = "FiscalBackToCategories"
	back_button.custom_minimum_size = Vector2(0, 44)
	back_button.pressed.connect(_show_fiscal_categories)
	fiscal_plan_surface.add_child(back_button)
	fiscal_plan_title = _section_title("分類方案")
	fiscal_plan_title.name = "FiscalSelectedCategoryTitle"
	fiscal_plan_title.set_meta("l10n_skip", true)
	fiscal_plan_surface.add_child(fiscal_plan_title)
	fiscal_plan_hint = _label("", 15, _theme_muted())
	fiscal_plan_hint.name = "FiscalSelectedCategoryHint"
	fiscal_plan_hint.set_meta("l10n_skip", true)
	fiscal_plan_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fiscal_plan_surface.add_child(fiscal_plan_hint)
	var plan_grid := GridContainer.new()
	plan_grid.name = "FiscalPlanCardGrid"
	plan_grid.columns = 3
	plan_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan_grid.add_theme_constant_override("h_separation", 8)
	fiscal_plan_surface.add_child(plan_grid)
	var plan_specs: Array[Dictionary] = [
		{"id": "current", "title": "現行設定", "help": "恢復此分類正式值"},
		{"id": "reasonable", "title": "合理值建議", "help": "套用既有合理值"},
		{"id": "custom", "title": "自訂方案", "help": "顯示滑桿與數字輸入"},
	]
	for plan_spec: Dictionary in plan_specs:
		var plan_button := _button(str(plan_spec["title"]))
		plan_button.name = "FiscalPlanCard_%s" % str(plan_spec["id"])
		plan_button.tooltip_text = str(plan_spec["help"])
		plan_button.custom_minimum_size = Vector2(150, 86)
		plan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plan_button.add_theme_font_size_override("font_size", 16)
		plan_button.pressed.connect(Callable(self, "_select_fiscal_plan").bind(str(plan_spec["id"])))
		plan_grid.add_child(plan_button)

	fiscal_custom_editor = VBoxContainer.new()
	fiscal_custom_editor.name = "FiscalCustomEditor"
	fiscal_custom_editor.add_theme_constant_override("separation", 10)
	fiscal_custom_editor.hide()
	fiscal_plan_surface.add_child(fiscal_custom_editor)
	for spec: Dictionary in FISCAL_CATEGORY_SPECS:
		var page := VBoxContainer.new()
		page.name = "FiscalCustomPage_%s" % str(spec["id"])
		page.add_theme_constant_override("separation", 10)
		page.hide()
		for item: Dictionary in spec["items"]:
			match str(item["kind"]):
				"tax":
					page.add_child(_build_tax_row(str(item["key"])))
				"utility":
					page.add_child(_build_utility_fee_row(str(item["key"])))
				"service":
					page.add_child(_build_service_fee_row(str(item["key"])))
		fiscal_custom_pages[str(spec["id"])] = page
		fiscal_custom_editor.add_child(page)

	var summary_panel := _panel(_theme_panel_alt(), 9, 14)
	summary_panel.name = "FiscalDraftPreview"
	fiscal_draft_preview = summary_panel
	summary_panel.custom_minimum_size = Vector2(0, 0)
	summary_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_panel.hide()
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 9)
	summary_panel.add_child(summary_box)
	var forecast_title := _section_title("預覽變更")
	forecast_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_title.max_lines_visible = 2
	summary_box.add_child(forecast_title)
	var forecast_help := _label("核對六個分類的正式值、新草稿、預估影響與風險；只有執行才會寫入正式設定。", 15, _theme_muted())
	forecast_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(forecast_help)
	var action_row := HBoxContainer.new()
	action_row.name = "FiscalDraftActions"
	action_row.add_theme_constant_override("separation", 8)
	fiscal_back_to_edit_button = _button(L10n.text("返回修改"))
	fiscal_back_to_edit_button.name = "FiscalBackToEditButton"
	fiscal_back_to_edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiscal_back_to_edit_button.pressed.connect(_return_to_fiscal_edit)
	action_row.add_child(fiscal_back_to_edit_button)
	fiscal_discard_button = _button("放棄變更")
	fiscal_discard_button.name = "FiscalDiscardButton"
	fiscal_discard_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiscal_discard_button.pressed.connect(Callable(self, "_discard_fiscal_draft").bind(true, true))
	action_row.add_child(fiscal_discard_button)
	fiscal_apply_button = _button(L10n.text("執行變更（%d）") % 0, "primary")
	fiscal_apply_button.name = "FiscalApplyAllButton"
	fiscal_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiscal_apply_button.pressed.connect(Callable(self, "_apply_fiscal_draft"))
	action_row.add_child(fiscal_apply_button)
	summary_box.add_child(action_row)
	fiscal_draft_change_list = _label("", 14, _theme_text())
	fiscal_draft_change_list.name = "FiscalDraftChangeList"
	fiscal_draft_change_list.set_meta("l10n_skip", true)
	fiscal_draft_change_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(fiscal_draft_change_list)
	fiscal_draft_risk_label = _label("", 15, _theme_muted())
	fiscal_draft_risk_label.name = "FiscalDraftRisk"
	fiscal_draft_risk_label.set_meta("l10n_skip", true)
	fiscal_draft_risk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(fiscal_draft_risk_label)
	summary_box.add_child(_finance_visual_row("fiscal_total_income", "預估月收入", "$"))
	summary_box.add_child(_finance_visual_row("fiscal_total_expense", "市政月支出", "支"))
	summary_box.add_child(_finance_visual_row("fiscal_net_income", "預估月淨額", "Σ"))
	summary_box.add_child(_finance_visual_row("fiscal_safety_buffer", "安全緩衝", "盾"))
	var operating_status := _label("", 17, _theme_text())
	operating_status.name = "FiscalOperatingStatus"
	operating_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operating_status.custom_minimum_size = Vector2(0, 82)
	labels["fiscal_operating_status"] = operating_status
	summary_box.add_child(operating_status)
	fiscal_responsive_layout.add_child(summary_panel)
	scroll.resized.connect(Callable(self, "_layout_fiscal_surface").bind(scroll))
	call_deferred("_layout_fiscal_surface", scroll)

	return scroll

func _build_bill_tab() -> Control:
	lower_council_stage = LowerCouncilStageScript.new()
	lower_council_stage.response_selected.connect(_on_lower_council_response_selected)
	lower_council_stage.response_confirmed.connect(_on_lower_council_response_confirmed)
	lower_council_stage.set_dark_mode(is_dark_mode)
	var content := lower_council_stage.catalog_host() as VBoxContainer
	var catalog_header := lower_council_stage.catalog_header_host() as HBoxContainer
	governance_catalog_title = _label("政策與法案目錄", 18, _theme_text())
	governance_catalog_title.name = "GovernanceCatalogTitle"
	governance_catalog_title.custom_minimum_size = Vector2(140, 44)
	governance_catalog_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	catalog_header.add_child(governance_catalog_title)
	var legend := HFlowContainer.new()
	legend.name = "GovernanceTagLegend"
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_theme_constant_override("separation", 8)
	legend.add_child(_governance_tag_chip("政策", Color(0.05, 0.43, 0.70), "LegendPolicyTag"))
	legend.add_child(_governance_tag_chip("法案", Color(0.78, 0.49, 0.08), "LegendBillTag"))
	catalog_header.add_child(legend)
	governance_catalog_legend = legend

	bill_status_label = _label("", 15, _theme_text())
	bill_status_label.name = "GovernanceStatusSummary"
	bill_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bill_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bill_status_label.custom_minimum_size = Vector2(180, 90)
	bill_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	catalog_header.add_child(bill_status_label)

	governance_status_tabs = TabContainer.new()
	governance_status_tabs.name = "GovernanceStatusTabs"
	governance_status_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	governance_status_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	governance_status_tabs.custom_minimum_size = Vector2(0, 154)
	governance_status_tabs.add_theme_font_size_override("font_size", 17)
	_style_tabs(governance_status_tabs)
	content.add_child(governance_status_tabs)
	for status_id: String in GOVERNANCE_STATUS_ORDER:
		var page_content := VBoxContainer.new()
		page_content.name = str(GOVERNANCE_STATUS_TITLES[status_id])
		page_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page_content.add_theme_constant_override("separation", 4)
		page_content.set_meta("status_id", status_id)
		var empty_label := _label("此分類目前沒有項目。", 17, _theme_muted())
		empty_label.name = "GovernanceEmpty_%s" % status_id
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, 44)
		page_content.add_child(empty_label)
		governance_status_empty_labels[status_id] = empty_label
		var kind_tabs := TabContainer.new()
		kind_tabs.name = "%s_GovernanceKindTabs" % status_id
		kind_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		kind_tabs.add_theme_font_size_override("font_size", 17)
		kind_tabs.set_meta("progressive_choice_group", true)
		_style_tabs(kind_tabs)
		page_content.add_child(kind_tabs)
		for kind_id in ["policy", "bill"]:
			var section := VBoxContainer.new()
			section.name = "政策" if kind_id == "policy" else "法案"
			section.add_theme_constant_override("separation", 8)
			var pager = ProgressiveChoicePagerScript.new(3, 3)
			pager.name = "%s_%s_Pager" % [status_id, kind_id]
			pager.set_dark_mode(is_dark_mode)
			var grid := pager.call("choice_grid") as GridContainer
			grid.name = "%s_%s_Grid" % [status_id, kind_id]
			section.add_child(pager)
			kind_tabs.add_child(section)
			var key := "%s:%s" % [status_id, kind_id]
			governance_status_grids[key] = grid
			governance_status_pagers[key] = pager
			governance_status_sections[key] = section
		governance_status_tabs.add_child(page_content)

	for policy_name in policies.keys():
		var policy: Dictionary = policies[policy_name]
		var policy_card := _build_governance_policy_card(policy_name, policy)
		governance_policy_cards[policy_name] = policy_card
		(governance_status_pagers["unimplemented:policy"] as Control).call("add_choice", policy_card)
		policy_card.set_meta("governance_pager_key", "unimplemented:policy")

	for bill_name in _governance_bill_catalog().keys():
		var bill: Dictionary = _governance_bill_catalog()[bill_name]
		var bill_card := _build_governance_bill_card(bill_name, bill)
		governance_bill_cards[bill_name] = bill_card
		(governance_status_pagers["unimplemented:bill"] as Control).call("add_choice", bill_card)
		bill_card.set_meta("governance_pager_key", "unimplemented:bill")

	var force_panel := _panel(_theme_panel_alt(), 10, 14)
	force_panel.name = "GovernanceForcePanel"
	governance_force_panel = force_panel
	var force_row := HBoxContainer.new()
	force_row.add_theme_constant_override("separation", 14)
	force_panel.add_child(force_row)
	force_row.add_child(_icon_texture_rect("governance", Vector2(64, 64)))
	governance_force_label = _label("目前沒有遭否決的法案。", 17, _theme_text())
	governance_force_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	governance_force_label.max_lines_visible = 3
	governance_force_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	governance_force_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_row.add_child(governance_force_label)
	governance_force_button = _button("強制執行最近否決法案", "primary")
	governance_force_button.name = "ForceRejectedBillButton"
	governance_force_button.custom_minimum_size = Vector2(250, 64)
	governance_force_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	governance_force_button.pressed.connect(Callable(self, "_force_latest_rejected_bill"))
	force_row.add_child(governance_force_button)
	force_panel.visible = false
	content.add_child(force_panel)
	_refresh_governance_catalog()

	return lower_council_stage


func _build_governance_policy_card(policy_name: String, policy: Dictionary) -> PanelContainer:
	var card := _panel(_theme_panel_alt(), 9, 10)
	card.name = "GovernanceCard_Policy_%s" % policy_name
	card.custom_minimum_size = Vector2(300, 122)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	card.add_child(stack)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(_governance_tag_chip("政策", Color(0.05, 0.43, 0.70), "GovernanceKindTag_Policy_%s" % policy_name))
	tags.add_child(_governance_tag_chip(str(policy.get("tag", "市政")), Color(0.20, 0.48, 0.38), "GovernanceDomainTag_Policy_%s" % policy_name))
	stack.add_child(tags)
	var check := CheckBox.new()
	var effects := _visual_effects(policy, 3)
	check.name = "GovernancePolicy_%s" % policy_name
	check.text = "%s\n%s" % [policy_name, effects if not effects.is_empty() else policy["description"]]
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.custom_minimum_size = Vector2(0, 68)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.add_theme_font_size_override("font_size", 18)
	check.add_theme_color_override("font_color", _theme_text())
	check.toggled.connect(Callable(self, "_toggle_policy").bind(policy_name))
	policy_checks[policy_name] = check
	stack.add_child(check)
	return card


func _build_governance_bill_card(bill_name: String, bill: Dictionary) -> PanelContainer:
	var card := _panel(_theme_panel_alt(), 9, 10)
	card.name = "GovernanceCard_Bill_%s" % bill_name
	card.custom_minimum_size = Vector2(300, 122)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	card.add_child(stack)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(_governance_tag_chip("法案", Color(0.78, 0.49, 0.08), "GovernanceKindTag_Bill_%s" % bill_name))
	tags.add_child(_governance_tag_chip(_governance_domain_label(str(bill.get("type", ""))), Color(0.42, 0.34, 0.66), "GovernanceDomainTag_Bill_%s" % bill_name))
	stack.add_child(tags)
	var button := _button(_governance_bill_card_text(bill_name, bill))
	button.name = "GovernanceBill_%s" % bill_name
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 68)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(Callable(self, "_submit_bill").bind(bill_name))
	bill_buttons[bill_name] = button
	stack.add_child(button)
	return card


func _governance_tag_chip(text: String, color: Color, node_name: String) -> Label:
	var chip := _label(text, 14, Color.WHITE)
	chip.name = node_name
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.custom_minimum_size = Vector2(74, 28)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 10
	chip.add_theme_stylebox_override("normal", style)
	return chip


func _governance_bill_card_text(bill_name: String, bill: Dictionary) -> String:
	var effects := _visual_effects(bill.get("effects", {}), 3)
	return "%s　● %s　◷ %d 天\n%s" % [
		bill_name,
		str(bill.get("impact", "中影響")),
		int(bill.get("review_days", 0)),
		effects if not effects.is_empty() else str(bill.get("description", "")),
	]


func _governance_domain_label(domain: String) -> String:
	return str(GOVERNANCE_DOMAIN_LABELS.get(domain, "市政"))


func _governance_bill_catalog() -> Dictionary:
	var catalog := {}
	if vertical_slice == null or vertical_slice.governance == null:
		return catalog
	for bill_id in vertical_slice.governance.bill_definitions.keys():
		var definition: Dictionary = vertical_slice.governance.bill_definitions[bill_id].duplicate(true)
		definition["id"] = str(bill_id)
		catalog[str(definition.get("name", bill_id))] = definition
	return catalog


func _governance_bill_id(bill_name: String) -> String:
	var definition: Dictionary = _governance_bill_catalog().get(bill_name, {})
	return str(definition.get("id", bill_name))


func _refresh_governance_catalog() -> void:
	if governance_status_tabs == null:
		return
	var counts := {"unimplemented": 0, "review": 0, "implemented": 0}
	for policy_name in policies.keys():
		var policy_status_id := "implemented" if bool(active_policies.get(policy_name, false)) else "unimplemented"
		counts[policy_status_id] = int(counts[policy_status_id]) + 1
		_move_governance_card(governance_policy_cards.get(policy_name), policy_status_id, "policy")
		var check := policy_checks.get(policy_name) as CheckBox
		if check:
			check.set_pressed_no_signal(bool(active_policies.get(policy_name, false)))
	for bill_name in _governance_bill_catalog().keys():
		var bill_status_id := _governance_bill_status(bill_name)
		counts[bill_status_id] = int(counts[bill_status_id]) + 1
		_move_governance_card(governance_bill_cards.get(bill_name), bill_status_id, "bill")
	for index in GOVERNANCE_STATUS_ORDER.size():
		var tab_status_id: String = GOVERNANCE_STATUS_ORDER[index]
		var localized_status_title := L10n.text(str(GOVERNANCE_STATUS_TITLES[tab_status_id]))
		governance_status_tabs.set_tab_title(index, "%s（%d）" % [localized_status_title, int(counts[tab_status_id])])
		var empty_label := governance_status_empty_labels.get(tab_status_id) as Label
		if empty_label:
			empty_label.visible = int(counts[tab_status_id]) == 0
		for kind_id in ["policy", "bill"]:
			var pager = governance_status_pagers.get("%s:%s" % [tab_status_id, kind_id])
			var section := governance_status_sections.get("%s:%s" % [tab_status_id, kind_id]) as VBoxContainer
			if pager != null and section:
				section.visible = int(pager.call("choice_count")) > 0
	if is_instance_valid(governance_force_panel):
		var force_available: bool = (
			vertical_slice != null
			and vertical_slice.governance != null
			and not vertical_slice.governance.rejected_bills.is_empty()
			and vertical_slice.governance.pending_bill.is_empty()
		)
		governance_force_panel.visible = force_available
		if is_instance_valid(governance_catalog_legend):
			governance_catalog_legend.visible = not force_available


func _refresh_lower_council_stage() -> void:
	if lower_council_stage == null or vertical_slice == null or vertical_slice.governance == null:
		return
	var pending: Dictionary = vertical_slice.governance.pending_bill
	var hearing_active := str(pending.get("status", "")) == "awaiting_mayor_response"
	var force_available: bool = not vertical_slice.governance.rejected_bills.is_empty() and pending.is_empty()
	var latest_decision: Dictionary = {}
	if pending.is_empty() and not _lower_council_final_decision.is_empty():
		latest_decision = _lower_council_final_decision.duplicate(true)
	var workflow_active := hearing_active or not latest_decision.is_empty()
	for catalog_control in [
		governance_catalog_title,
		bill_status_label,
		governance_status_tabs,
	]:
		if is_instance_valid(catalog_control):
			(catalog_control as Control).visible = not workflow_active
	if is_instance_valid(governance_catalog_legend):
		governance_catalog_legend.visible = not workflow_active and not force_available
	if is_instance_valid(governance_force_panel):
		governance_force_panel.visible = not workflow_active and force_available
	var bill_id := str(pending.get("bill_id", ""))
	var definition: Dictionary = vertical_slice.governance.bill_definitions.get(bill_id, {})
	lower_council_stage.refresh(pending, definition, latest_decision)


func _move_governance_card(card_variant: Variant, status_id: String, kind_id: String) -> void:
	var card := card_variant as PanelContainer
	var target_key := "%s:%s" % [status_id, kind_id]
	var target_pager = governance_status_pagers.get(target_key)
	if card == null or target_pager == null:
		return
	var current_key := str(card.get_meta("governance_pager_key", ""))
	if current_key == target_key:
		return
	if governance_status_pagers.has(current_key):
		governance_status_pagers[current_key].call("remove_choice", card)
	target_pager.call("add_choice", card)
	card.set_meta("governance_pager_key", target_key)


func _governance_bill_status(bill_name: String) -> String:
	var bill_id := _governance_bill_id(bill_name)
	if str(vertical_slice.governance.pending_bill.get("bill_id", "")) == bill_id:
		return "review"
	if vertical_slice.governance.active_laws.has(bill_id):
		return "implemented"
	return "unimplemented"


func _select_governance_status(status_id: String) -> void:
	var index := GOVERNANCE_STATUS_ORDER.find(status_id)
	if governance_status_tabs != null and index >= 0:
		governance_status_tabs.current_tab = index

func _build_map_panel() -> Control:
	var panel := Control.new()
	panel.name = "MapWorld"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	map_viewport = Control.new()
	map_viewport.name = "MapViewport"
	map_viewport.clip_contents = true
	map_viewport.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_viewport.resized.connect(Callable(self, "_layout_map_stage"))
	panel.add_child(map_viewport)
	# Keep a non-interactive viewport-sized copy of the existing terrain art
	# behind map_stage. At zooms below one it fills only the newly exposed edges;
	# buildings, tiles, vehicles, and residents retain their shared stage
	# transform and hit targets.
	map_viewport_background = TextureRect.new()
	map_viewport_background.name = "ViewportTerrainBackground"
	map_viewport_background.texture = load(MAP_BACKGROUND_PATH) as Texture2D
	map_viewport_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_viewport_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_viewport_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_viewport_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Keep the cover art in the viewport's normal canvas layer. A negative
	# z-index places this descendant behind the root theme background as well,
	# so the exposed area at zooms below 100% is still rendered white. Child
	# order already keeps this node behind map_stage without crossing that
	# sibling boundary.
	map_viewport_background.z_index = 0
	map_viewport.add_child(map_viewport_background)

	map_stage = Control.new()
	map_stage.custom_minimum_size = MAP_STAGE_SIZE
	map_stage.size = MAP_STAGE_SIZE
	map_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	map_viewport.add_child(map_stage)

	city_backdrop = CityBackdrop.new()
	city_backdrop.custom_minimum_size = MAP_STAGE_SIZE
	city_backdrop.size = MAP_STAGE_SIZE
	city_backdrop.call("set_dark_mode", is_dark_mode)
	map_stage.add_child(city_backdrop)
	var terrain = _terrain_map()
	if terrain != null:
		city_backdrop.call("set_terrain_snapshot", terrain.to_dict())

	transport_network_layer = TransportNetworkLayerScript.new()
	transport_network_layer.custom_minimum_size = MAP_STAGE_SIZE
	transport_network_layer.size = MAP_STAGE_SIZE
	transport_network_layer.set_dark_mode(is_dark_mode)
	map_stage.add_child(transport_network_layer)

	tile_layer = Control.new()
	tile_layer.custom_minimum_size = MAP_STAGE_SIZE
	tile_layer.size = MAP_STAGE_SIZE
	tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_stage.add_child(tile_layer)

	grid_buttons.resize(CELL_COUNT)
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var index: int = int(terrain.tile_id_for_coordinate(Vector2i(col, row))) if terrain != null else row * GRID_SIZE + col
			var cell: Button = CityTileButton.new()
			cell.custom_minimum_size = ISO_TILE_SIZE
			cell.size = ISO_TILE_SIZE
			cell.position = _iso_tile_position(index)
			# Buildings and residents share a feet/ground depth axis.  A resident
			# naturally disappears behind a building whose base is farther south.
			cell.z_index = int(_iso_tile_center(index).y)
			cell.pressed.connect(Callable(self, "_on_grid_pressed").bind(index))
			cell.mouse_entered.connect(Callable(self, "_refresh_placement_preview").bind(index))
			cell.focus_entered.connect(Callable(self, "_refresh_placement_preview").bind(index))
			grid_buttons[index] = cell
			tile_layer.add_child(cell)

	transport_vehicle_controller = TransportVehicleControllerScript.new()
	transport_vehicle_controller.custom_minimum_size = MAP_STAGE_SIZE
	transport_vehicle_controller.size = MAP_STAGE_SIZE
	transport_vehicle_controller.crossing_states_changed.connect(
		func(states: Dictionary) -> void:
			if transport_network_layer != null:
				transport_network_layer.set_crossing_states(states)
			if npc_map_controller != null:
				npc_map_controller.set_crossing_states(states)
	)
	map_stage.add_child(transport_vehicle_controller)

	npc_layer = Control.new()
	npc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	npc_layer.custom_minimum_size = MAP_STAGE_SIZE
	npc_layer.size = MAP_STAGE_SIZE
	map_stage.add_child(npc_layer)
	npc_map_controller = NpcMapControllerScript.new()
	npc_map_controller.name = "NpcMapController"
	npc_layer.add_child(npc_map_controller)
	npc_map_controller.npc_activated.connect(Callable(self, "_show_npc_dialogue"))
	var initial_npc_proxies: Array[Dictionary] = []
	if vertical_slice != null:
		initial_npc_proxies = vertical_slice.visible_npc_proxies(24)
	else:
		# Preserve the development-only fallback when no coordinator exists. A
		# valid zero-population authoritative city supplies an empty array above.
		for npc_type in NPC_TYPES:
			initial_npc_proxies.append({
				"npc_id": "legacy_%s" % npc_type,
				"display_name": npc_type,
				"archetype": npc_type,
			})
	npc_map_controller.mount(
		npc_layer,
		_npc_map_snapshot(),
		is_dark_mode,
		initial_npc_proxies
	)
	_build_npc_dialogue_card()
	_layout_map_stage()
	_update_transport_runtime()

	return panel




func _iso_tile_position(index: int) -> Vector2:
	return SquareGridLayoutScript.rect_for_coordinate(_terrain_coordinate(index)).position

func _iso_tile_center(index: int) -> Vector2:
	return SquareGridLayoutScript.center_for_coordinate(_terrain_coordinate(index))


func _terrain_map():
	return vertical_slice.terrain_map if vertical_slice != null else null


func _terrain_coordinate(index: int) -> Vector2i:
	var terrain = _terrain_map()
	if terrain != null:
		var coordinate: Vector2i = terrain.coordinate_for_tile_id(index)
		if coordinate != CityTerrainMapScript.INVALID_COORDINATE:
			return coordinate
	return Vector2i(index % GRID_SIZE, int(index / GRID_SIZE))


func _transport_tile_centers() -> Dictionary:
	var centers: Dictionary = {}
	for tile_index in CELL_COUNT:
		centers[str(tile_index)] = _iso_tile_center(tile_index)
	return centers


func _update_transport_runtime(refresh_tile_overlays: bool = true) -> void:
	if vertical_slice == null:
		return
	var runtime: Dictionary = {}
	if vertical_slice.has_method("transport_visual_snapshot"):
		runtime = vertical_slice.call("transport_visual_snapshot", city_grid)
	if runtime.is_empty():
		runtime = {"tile_states": {}, "operational_lines": [], "private_road_paths": [], "crossings": {}}
	var preview_runtime := runtime.duplicate(true)
	if map_action_mode == "transport_infrastructure" and not transport_plan_tiles.is_empty():
		_apply_transport_preview(preview_runtime)
	elif map_action_mode == "transport_route_stops" and not transport_route_station_tiles.is_empty():
		var route_stop_preview: Array[Dictionary] = []
		for stop_index in transport_route_station_tiles.size():
			route_stop_preview.append({
				"tile_id": transport_route_station_tiles[stop_index],
				"order": stop_index + 1,
				"mode": transport_route_mode,
			})
		preview_runtime["route_stop_preview"] = route_stop_preview
	var centers := _transport_tile_centers()
	if transport_network_layer != null:
		transport_network_layer.set_network_snapshot(preview_runtime, centers)
	if transport_vehicle_controller != null:
		transport_vehicle_controller.set_runtime_snapshot(runtime, centers)
	if refresh_tile_overlays and grid_buttons.size() == CELL_COUNT:
		for tile_index in CELL_COUNT:
			_update_tile_visual(tile_index, city_grid[tile_index])


func _transport_planning_overlay_for_tile(tile_index: int) -> Dictionary:
	var session := _transport_session_snapshot()
	if (
		_transport_session_is_route_package(session)
		and str(session.get("state", "")) in ["station_placement", "network_placement", "route_edit", "paused"]
	):
		var placements: Array = Dictionary(session.get("route_draft", {})).get("station_placements", [])
		for placement_index in range(placements.size()):
			var placement_value: Variant = placements[placement_index]
			if not placement_value is Dictionary:
				continue
			var placement: Dictionary = placement_value
			var occupied_tile_ids: Array = placement.get("occupied_tile_ids", [])
			var footprint_index := occupied_tile_ids.find(tile_index)
			if footprint_index < 0:
				continue
			var reused_station := bool(placement.get("reuse_existing_station", false))
			return {
				"kind": "station_draft",
				"non_authoritative": not reused_station,
				"reuse_existing_station": reused_station,
				"building_name": str(session.get("station_blueprint_name", "交通站點")),
				"mode": str(session.get("mode", "")),
				"draft_order": placement_index + 1,
				"anchor_tile_id": int(placement.get("anchor_tile_id", -1)),
				"footprint_index": footprint_index,
				"footprint_count": occupied_tile_ids.size(),
				"footprint_role": "anchor" if tile_index == int(placement.get("anchor_tile_id", -1)) else "secondary",
			}
	if map_action_mode == "transport_infrastructure" and tile_index in transport_plan_tiles:
		return {
			"kind": "route_draft",
			"non_authoritative": true,
			"route_kind": transport_plan_kind,
			"draft_order": transport_plan_tiles.find(tile_index) + 1,
		}
	if map_action_mode == "transport_route_stops" and tile_index in transport_route_station_tiles:
		return {
			"kind": "route_stop",
			"non_authoritative": true,
			"mode": transport_route_mode,
			"draft_order": transport_route_station_tiles.find(tile_index) + 1,
		}
	return {}


func _apply_transport_preview(runtime: Dictionary) -> void:
	var tile_states: Dictionary = Dictionary(runtime.get("tile_states", {})).duplicate(true)
	var segment_kinds := ["road", "metro_track", "rail_track", "runway", "taxiway"]
	for tile_index: int in transport_plan_tiles:
		var key := str(tile_index)
		var state: Dictionary = Dictionary(tile_states.get(key, {})).duplicate(true)
		var segments: Array = Array(state.get("segments", [])).duplicate()
		var facilities: Array = Array(state.get("facilities", [])).duplicate()
		if transport_plan_operation == "build":
			if transport_plan_kind in segment_kinds and transport_plan_kind not in segments:
				segments.append(transport_plan_kind)
			elif transport_plan_kind not in segment_kinds and transport_plan_kind not in facilities:
				facilities.append(transport_plan_kind)
		state["segments"] = segments
		state["facilities"] = facilities
		state["project_status"] = "planned" if transport_plan_operation == "build" else "demolishing"
		state["connections"] = Dictionary(state.get("connections", {})).duplicate(true)
		state["neighbours"] = Dictionary(state.get("neighbours", {})).duplicate(true)
		tile_states[key] = state
	if transport_plan_kind in segment_kinds and transport_plan_operation == "build":
		for index in transport_plan_tiles.size() - 1:
			var from_tile := transport_plan_tiles[index]
			var to_tile := transport_plan_tiles[index + 1]
			var directions := _transport_direction_pair(from_tile, to_tile)
			if directions.is_empty():
				continue
			_add_preview_connection(tile_states, from_tile, to_tile, str(directions[0]))
			_add_preview_connection(tile_states, to_tile, from_tile, str(directions[1]))
	runtime["tile_states"] = tile_states


func _add_preview_connection(tile_states: Dictionary, from_tile: int, to_tile: int, direction: String) -> void:
	var key := str(from_tile)
	var state: Dictionary = Dictionary(tile_states.get(key, {})).duplicate(true)
	var connections: Dictionary = Dictionary(state.get("connections", {})).duplicate(true)
	var kind_connections: Array = Array(connections.get(transport_plan_kind, [])).duplicate()
	if direction not in kind_connections:
		kind_connections.append(direction)
	connections[transport_plan_kind] = kind_connections
	var neighbours: Dictionary = Dictionary(state.get("neighbours", {})).duplicate(true)
	neighbours[direction] = to_tile
	state["connections"] = connections
	state["neighbours"] = neighbours
	tile_states[key] = state


func _transport_direction_pair(from_tile: int, to_tile: int) -> PackedStringArray:
	var delta := _terrain_coordinate(to_tile) - _terrain_coordinate(from_tile)
	if delta == Vector2i(0, -1):
		return PackedStringArray(["n", "s"])
	if delta == Vector2i(1, 0):
		return PackedStringArray(["e", "w"])
	if delta == Vector2i(0, 1):
		return PackedStringArray(["s", "n"])
	if delta == Vector2i(-1, 0):
		return PackedStringArray(["w", "e"])
	return PackedStringArray()

func _npc_map_snapshot() -> Dictionary:
	var tile_centers := PackedVector2Array()
	var tile_ids_by_display_order := PackedInt32Array()
	var building_centers := {}
	var construction_centers := {}
	var blocked_tiles := {}
	var terrain_blockers := {}
	var flattened_terrain_centers := {}
	var terrain = _terrain_map()
	if terrain != null:
		tile_ids_by_display_order = terrain.tile_ids_in_display_order()
	else:
		for tile_index in CELL_COUNT:
			tile_ids_by_display_order.append(tile_index)
	var transport_blocked_tiles := PackedInt32Array()
	var crossing_tile_ids := PackedInt32Array()
	if vertical_slice != null and vertical_slice.has_method("transport_navigation_blocked_tile_ids"):
		transport_blocked_tiles = vertical_slice.call("transport_navigation_blocked_tile_ids")
	if vertical_slice != null and vertical_slice.has_method("transport_visual_snapshot"):
		var transport_runtime: Dictionary = vertical_slice.call("transport_visual_snapshot", city_grid)
		var crossing_records: Dictionary = transport_runtime.get("crossings", {})
		var tile_states: Dictionary = transport_runtime.get("tile_states", {})
		for crossing_variant: Variant in crossing_records.values():
			if not crossing_variant is Dictionary:
				continue
			var crossing: Dictionary = crossing_variant
			var crossing_tile_id := int(crossing.get("tile_id", -1))
			if (
				crossing_tile_id < 0
				or crossing_tile_id >= city_grid.size()
				or str(crossing.get("status", "completed")) != "completed"
				or (
					vertical_slice != null
					and not vertical_slice.get_building_by_tile(crossing_tile_id).is_empty()
				)
				or (terrain != null and not terrain.is_walkable(crossing_tile_id))
				or not vertical_slice.active_construction_for_tile(crossing_tile_id).is_empty()
			):
				continue
			var tile_state_variant: Variant = tile_states.get(
				str(crossing_tile_id), tile_states.get(crossing_tile_id, {})
			)
			var tile_state: Dictionary = (
				tile_state_variant if tile_state_variant is Dictionary else {}
			)
			var crossing_segments: Array = tile_state.get("segments", [])
			if (
				str(tile_state.get("crossing", "")).is_empty()
				or not crossing_segments.has("road")
				or (not crossing_segments.has("rail_track") and not crossing_segments.has("metro_track"))
			):
				continue
			# A facility or station remains a physical obstacle even if malformed
			# transport data also points a crossing record at the same tile.
			if not Array(tile_state.get("facilities", [])).is_empty():
				continue
			crossing_tile_ids.append(crossing_tile_id)
	for tile_index in mini(CELL_COUNT, city_grid.size()):
		var center := _iso_tile_center(tile_index)
		tile_centers.append(center)
		if terrain != null and not terrain.is_walkable(tile_index):
			terrain_blockers[tile_index] = {
				"center": center,
				"kind": terrain.effective_kind(tile_index),
			}
			blocked_tiles[tile_index] = true
		elif terrain != null and terrain.is_flattened(tile_index):
			flattened_terrain_centers[tile_index] = center
		if transport_blocked_tiles.has(tile_index):
			terrain_blockers[tile_index] = {
				"center": center,
				"kind": "transport_network",
			}
			blocked_tiles[tile_index] = true
		if vertical_slice != null and not vertical_slice.get_building_by_tile(tile_index).is_empty():
			building_centers[tile_index] = center
			blocked_tiles[tile_index] = true
		if vertical_slice != null and not vertical_slice.active_construction_for_tile(tile_index).is_empty():
			construction_centers[tile_index] = center
			blocked_tiles[tile_index] = true
	return {
		"tile_centers": tile_centers,
		"tile_ids_by_display_order": tile_ids_by_display_order,
		"building_centers": building_centers,
		"construction_centers": construction_centers,
		"terrain_blockers": terrain_blockers,
		"flattened_terrain_centers": flattened_terrain_centers,
		"blocked_tiles": blocked_tiles,
		"crossing_tile_ids": crossing_tile_ids,
		"grid_cell_size": GRID_CELL_SIZE,
		"grid_origin": SquareGridLayoutScript.GRID_ORIGIN,
		"iso_tile_size": GRID_CELL_SIZE,
		"iso_tile_step": GRID_CELL_SIZE,
		"terrain_blocker_half_extents": GRID_CELL_SIZE * 0.5,
		"structure_blocker_half_extents": GRID_CELL_SIZE * 0.5,
	}

func _layout_map_stage() -> void:
	if map_viewport == null or map_stage == null:
		return
	var viewport_size := map_viewport.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var target_scale := _base_map_scale() * map_zoom
	_clamp_map_pan(target_scale)
	map_stage.scale = Vector2(target_scale, target_scale)
	map_stage.position = (viewport_size - MAP_STAGE_SIZE * target_scale) * 0.5 + map_pan_offset


func _base_map_scale() -> float:
	if map_viewport == null or map_viewport.size.x <= 0.0 or map_viewport.size.y <= 0.0:
		return 1.0
	var viewport_size := map_viewport.size
	var fill_scale: float = maxf(viewport_size.x / MAP_STAGE_SIZE.x, viewport_size.y / MAP_STAGE_SIZE.y)
	var fit_scale: float = minf(viewport_size.x / MAP_STAGE_SIZE.x, viewport_size.y / MAP_STAGE_SIZE.y)
	return maxf(0.72, minf(2.55, maxf(fill_scale * 1.04, fit_scale)))


func _clamp_map_pan(target_scale: float) -> void:
	if map_viewport == null:
		return
	var overflow := Vector2(
		maxf(0.0, MAP_STAGE_SIZE.x * target_scale - map_viewport.size.x),
		maxf(0.0, MAP_STAGE_SIZE.y * target_scale - map_viewport.size.y)
	)
	var limit := overflow * 0.5 + map_viewport.size * 0.18
	map_pan_offset.x = clampf(map_pan_offset.x, -limit.x, limit.x)
	map_pan_offset.y = clampf(map_pan_offset.y, -limit.y, limit.y)


func _is_tile_inside_hud_safe_area(index: int) -> bool:
	if index < 0 or index >= grid_buttons.size() or not is_instance_valid(grid_buttons[index]):
		return false
	var safe_top := float(UI_STATUS_HEIGHT + 20) + UI_MAP_SAFE_TOP_PADDING
	if is_instance_valid(status_hud):
		safe_top = status_hud.get_global_rect().end.y + UI_MAP_SAFE_TOP_PADDING
	var map_scale := maxf(1.0, absf(map_stage.scale.y)) if is_instance_valid(map_stage) else 1.0
	var visual_top := grid_buttons[index].get_global_rect().position.y - UI_MAP_VISUAL_TOP_MARGIN * map_scale
	return visual_top >= safe_top

func _build_npc_dialogue_card() -> void:
	if is_instance_valid(npc_dialogue_card):
		if npc_dialogue_card.get_parent() != null:
			npc_dialogue_card.get_parent().remove_child(npc_dialogue_card)
		npc_dialogue_card.queue_free()
	npc_dialogue_card = null
	npc_dialogue_label = null
	_active_npc_dialogue_index = -1
	_npc_dialogue_remaining_seconds = 0.0
	if npc_layer == null:
		return
	npc_dialogue_card = NpcDialogueCardScript.new()
	npc_dialogue_card.set_dark_mode(is_dark_mode)
	npc_dialogue_card.dismiss_requested.connect(Callable(self, "_dismiss_npc_dialogue_from_pointer"))
	npc_dialogue_card.primary_action_requested.connect(Callable(self, "_open_selected_npc_request"))
	npc_dialogue_card.position = Vector2(326, 520)
	npc_dialogue_card.z_index = 2000
	npc_dialogue_card.hide()
	npc_layer.add_child(npc_dialogue_card)
	# Keep the established label facade for accessibility and localization tests.
	npc_dialogue_label = npc_dialogue_card.message_label
	npc_dialogue_label.visible = false



func refresh_visible_npc_proxies() -> void:
	if vertical_slice == null or npc_layer == null:
		return
	# Rebinding the clicked slot while its card is open would make the portrait
	# and request action refer to different people.  Apply the authoritative
	# roster as soon as that short conversation closes instead.
	if (
		_active_npc_dialogue_index >= 0
		and is_instance_valid(npc_dialogue_card)
		and npc_dialogue_card.visible
	):
		_npc_proxy_refresh_pending = true
		return
	_npc_proxy_refresh_pending = false
	if vertical_slice == null or npc_layer == null or npc_map_controller == null:
		return
	var desired: Array[Dictionary] = vertical_slice.visible_npc_proxies(24)
	# A population crossing the 24-proxy boundary needs a different number of
	# controls.  Rebuild only for that rare case; ordinary request reprioritizing
	# reuses every button and preserves each slot's locomotion state in the map
	# controller.
	if not npc_map_controller.reconcile_proxy_pool(desired, is_dark_mode):
		npc_map_controller.rebuild_actor_pool(desired, is_dark_mode)
	# Proxy reconciliation refreshes display names on the actor controls. Re-apply
	# the current input owner so transport planning cannot regain NPC tooltips or
	# pointer capture when the authoritative roster changes mid-session.
	_sync_map_interaction_for_ui()


func _update_ambient(delta: float) -> void:
	ambient_time += delta
	if weather_visual_layer != null and vertical_slice != null:
		weather_visual_layer.set_game_day(vertical_slice.game_day())
	if (
		_npc_dialogue_remaining_seconds > 0.0
		and not placement_mode_active
		and not _is_transport_map_action_active()
	):
		_npc_dialogue_remaining_seconds = maxf(0.0, _npc_dialogue_remaining_seconds - delta)
		if _npc_dialogue_remaining_seconds <= 0.0:
			_hide_npc_dialogue()

func debug_step_npc_simulation(delta: float) -> void:
	if npc_map_controller != null:
		npc_map_controller.step(delta)


func debug_set_npc_destination(
	npc_index: int,
	target: Vector2,
	snap_to_nearest: bool = true
) -> bool:
	return (
		bool(npc_map_controller.debug_set_destination(npc_index, target, snap_to_nearest))
		if npc_map_controller != null
		else false
	)


func debug_force_npc_repath(npc_index: int, snap_to_nearest: bool = true) -> bool:
	return (
		bool(npc_map_controller.debug_force_repath(npc_index, snap_to_nearest))
		if npc_map_controller != null
		else false
	)


func get_npc_navigation_grid():
	return npc_map_controller.get_navigation_grid() if npc_map_controller != null else null


func get_npc_acceptance_snapshot(npc_index: int) -> Dictionary:
	return (
		npc_map_controller.get_acceptance_snapshot(npc_index)
		if npc_map_controller != null
		else {}
	)


func debug_sync_npc_navigation_obstacles() -> void:
	if npc_map_controller != null:
		npc_map_controller.sync_map_snapshot(_npc_map_snapshot())


func get_npc_route_slots_snapshot() -> Array[Dictionary]:
	return (
		npc_map_controller.get_route_slots_snapshot()
		if npc_map_controller != null
		else []
	)


func is_npc_position_scenery_safe(position: Vector2) -> bool:
	return (
		bool(npc_map_controller.is_position_scenery_safe(position))
		if npc_map_controller != null
		else false
	)


func is_npc_tile_blocked(tile_index: int) -> bool:
	return (
		bool(npc_map_controller.is_tile_blocked(tile_index))
		if npc_map_controller != null
		else false
	)


func get_visible_npc_count() -> int:
	return npc_map_controller.visible_count() if npc_map_controller != null else 0


func get_visible_npc_snapshot(npc_index: int) -> Dictionary:
	return (
		npc_map_controller.get_proxy_snapshot(npc_index)
		if npc_map_controller != null
		else {}
	)


func get_visible_npc_snapshots() -> Array[Dictionary]:
	return (
		npc_map_controller.get_proxy_snapshots()
		if npc_map_controller != null
		else []
	)


func get_visible_npc_actor(npc_index: int) -> Button:
	return npc_map_controller.get_actor(npc_index) if npc_map_controller != null else null


func get_visible_npc_actors() -> Array[Button]:
	return npc_map_controller.get_actors() if npc_map_controller != null else []


func get_npc_dialogue_card_control():
	return npc_dialogue_card


func get_npc_dialogue_snapshot() -> Dictionary:
	return {
		"visible": npc_dialogue_card != null and npc_dialogue_card.visible,
		"active_index": _active_npc_dialogue_index,
		"remaining_seconds": _npc_dialogue_remaining_seconds,
		"body_text": npc_dialogue_label.text if npc_dialogue_label != null else "",
	}


func debug_show_npc_dialogue(npc_index: int) -> void:
	_show_npc_dialogue(npc_index)


func dismiss_npc_dialogue() -> void:
	_hide_npc_dialogue()


func debug_override_visible_npc_proxy(npc_index: int, proxy: Dictionary) -> bool:
	return (
		bool(npc_map_controller.debug_override_proxy(npc_index, proxy))
		if npc_map_controller != null
		else false
	)



func format_npc_display_name(npc: Dictionary) -> String:
	var fallback := str(npc.get("display_name", npc.get("type", "居民")))
	return L10n.person_name(
		str(npc.get("family_name", "")),
		str(npc.get("given_name", "")),
		fallback,
		str(npc.get("latin_display_name", ""))
	)


func _show_npc_dialogue(npc_index: int) -> void:
	if _transport_planning_owns_map_input():
		return
	var npc: Dictionary = get_visible_npc_snapshot(npc_index)
	if npc.is_empty():
		return
	_active_npc_dialogue_index = npc_index
	var npc_type := str(npc["type"])
	var npc_id := str(npc.get("record_id", ""))
	var display_name := format_npc_display_name(npc)
	var portrait_texture: Texture2D = null
	var actor := get_visible_npc_actor(npc_index)
	if actor != null:
		portrait_texture = actor.get("actor_texture") as Texture2D
	var dialogue_text := L10n.text(_npc_dialogue(npc_type))
	if vertical_slice != null and not npc_id.is_empty() and not npc_id.begins_with("legacy_"):
		vertical_slice.select_npc(npc_id, _vertical_city_context())
		var view_model: Dictionary = vertical_slice.get_view_model(selected_cell_index)
		if npc_dialogue_card != null:
			var has_request := bool(view_model.get("can_accept_request", false))
			var request_notice := "有一項陳情，請到民情中心處理。" if has_request else "目前沒有待處理陳情。"
			npc_dialogue_card.set_content(
				display_name,
				L10n.text(npc_type),
				dialogue_text,
				L10n.text(request_notice),
				portrait_texture,
				L10n.text("居民請求") if has_request else ""
			)
			npc_dialogue_label.visible = true
			npc_dialogue_card.show()
			_position_npc_dialogue(npc_index)
			_settle_npc_dialogue_layout(npc_index)
			_npc_dialogue_remaining_seconds = NPC_DIALOGUE_DURATION_SECONDS
		_update_scoped_municipal_pages(view_model)
		refresh_visible_npc_proxies()
		return
	if npc_dialogue_card != null:
		npc_dialogue_card.set_content(display_name, L10n.text(npc_type), dialogue_text, "", portrait_texture, "")
		npc_dialogue_label.visible = true
		npc_dialogue_card.show()
		_position_npc_dialogue(npc_index)
		_settle_npc_dialogue_layout(npc_index)
		_npc_dialogue_remaining_seconds = NPC_DIALOGUE_DURATION_SECONDS


func _position_npc_dialogue(npc_index: int) -> void:
	if (
		npc_dialogue_card == null
		or npc_layer == null
		or map_viewport == null
		or npc_index < 0
		or npc_index >= get_visible_npc_count()
		or not npc_dialogue_card.visible
	):
		return
	# A previous long locale can leave a direct Control child larger than its
	# current minimum. Shrink it before measuring so one language cannot make the
	# next dialogue spill outside the viewport.
	npc_dialogue_card.reset_size()
	npc_dialogue_card.size = npc_dialogue_card.get_combined_minimum_size()
	var actor_position: Vector2 = get_visible_npc_snapshot(npc_index).get("pos", Vector2.ZERO)
	var card_size: Vector2 = npc_dialogue_card.size.max(npc_dialogue_card.get_combined_minimum_size())
	var safe_rect := _npc_dialogue_safe_rect()
	var bubble_position := actor_position + Vector2(-200.0, -card_size.y - 18.0)
	var maximum_x := maxf(safe_rect.position.x, safe_rect.end.x - card_size.x)
	var maximum_y := maxf(safe_rect.position.y, safe_rect.end.y - card_size.y)
	bubble_position.x = clampf(bubble_position.x, safe_rect.position.x, maximum_x)
	bubble_position.y = clampf(bubble_position.y, safe_rect.position.y, maximum_y)
	npc_dialogue_card.position = bubble_position


func _npc_dialogue_safe_rect() -> Rect2:
	# The map stage deliberately overscans the viewport. Convert the actually
	# visible viewport and top-HUD clearance back into NPC-layer coordinates so
	# dialogue cards cannot be clipped on wide or short displays.
	var viewport_rect := map_viewport.get_global_rect()
	var safe_left := viewport_rect.position.x + 14.0
	var safe_top := viewport_rect.position.y + 14.0
	var safe_right := viewport_rect.end.x - 14.0
	var safe_bottom := viewport_rect.end.y - 14.0
	if is_instance_valid(status_hud):
		safe_top = maxf(safe_top, status_hud.get_global_rect().end.y + 12.0)
	var to_local := npc_layer.get_global_transform_with_canvas().affine_inverse()
	var local_top_left := to_local * Vector2(safe_left, safe_top)
	var local_bottom_right := to_local * Vector2(safe_right, safe_bottom)
	return Rect2(local_top_left, local_bottom_right - local_top_left)


func _settle_npc_dialogue_layout(npc_index: int) -> void:
	# Containers need two layout passes after a previously hidden chip becomes
	# visible. Refit only if this is still the active conversation.
	await get_tree().process_frame
	await get_tree().process_frame
	if _active_npc_dialogue_index == npc_index:
		_position_npc_dialogue(npc_index)


func _hide_npc_dialogue() -> void:
	var refresh_after_close := _npc_proxy_refresh_pending
	_npc_proxy_refresh_pending = false
	_npc_dialogue_remaining_seconds = 0.0
	_active_npc_dialogue_index = -1
	if npc_dialogue_label != null:
		npc_dialogue_label.visible = false
	if npc_dialogue_card != null:
		npc_dialogue_card.hide()
	if refresh_after_close:
		refresh_visible_npc_proxies()


func _dismiss_npc_dialogue_from_pointer() -> void:
	get_viewport().set_input_as_handled()
	_arm_modal_pointer_guard()
	_hide_npc_dialogue()


func _dismiss_npc_dialogue_from_keyboard() -> void:
	_npc_keyboard_dismiss_waiting_for_cancel_release = true
	get_viewport().set_input_as_handled()
	_hide_npc_dialogue()


func _arm_modal_pointer_guard() -> void:
	var guard := get_node_or_null(ModalPointerGuardScript.GUARD_NODE_NAME)
	if guard == null:
		guard = ModalPointerGuardScript.new()
		add_child(guard)
	guard.call("arm", get_viewport().get_mouse_position())
	_modal_grid_intent_block_until_process_frame = Engine.get_process_frames() + 1


func _modal_pointer_guard_blocks_grid_intent() -> bool:
	var guard := get_node_or_null(ModalPointerGuardScript.GUARD_NODE_NAME) as Control
	return (
		guard != null
		and is_instance_valid(guard)
		and guard.visible
		and Engine.get_process_frames() <= _modal_grid_intent_block_until_process_frame
	)


func _open_selected_npc_request() -> void:
	if _transport_planning_owns_map_input():
		return
	_hide_npc_dialogue()
	_close_building_context()
	var overlay := _ensure_municipal_overlay()
	if overlay != null:
		overlay.open_page("public_affairs")

func _npc_dialogue(npc_type: String) -> String:
	if total_satisfaction >= 82:
		return "最近城市真漂亮，我很喜歡住在這裡！"
	if total_satisfaction <= 45:
		return "最近生活壓力有點大，希望市長能改善一下。"
	if _tax_pressure_score() > 82:
		return "最近繳的稅有點重呢，大家都在討論。"
	if int(utility_fees["water"]) > int(UTILITY_DEFS["water"]["reasonable"]) * 2:
		return "水費變得好貴呀，我有點吃不消。"
	if traffic < 45:
		return "每天出門都好不方便喔，希望道路更順。"
	if environment < 45 or _building_count("工廠") >= 3:
		return "空氣好像沒有以前清新了，花園也需要照顧。"
	if security >= 80 and npc_type in ["一般居民", "老年居民", "公務人員"]:
		return "最近晚上出門也很安心，巡守做得不錯。"
	if education >= 80 and npc_type == "學生":
		return "孩子在這裡讀書真的不錯，鐘樓學院很受歡迎。"
	if _building_count("公園") >= 2:
		return "公園真漂亮，好適合散步！"
	if vertical_slice != null and not vertical_slice.governance.active_laws.is_empty():
		return "聽說新的政策要開始實施了，希望會更好！"
	match npc_type:
		"商人":
			return "街上的店舖越來越熱鬧，客人也變多了。"
		"工人":
			return "工坊和基礎設施讓大家有工作，也要注意環境。"
		"公務人員":
			return "市政廳正在整理公告，王國運作很穩定。"
		"老年居民":
			return "醫療和治安好一點，住起來就更安心。"
		_:
			return "今天的城鎮很有精神，路邊花草也很好看。"


func _build_utility_fee_row(fee_key: String) -> VBoxContainer:
	var def: Dictionary = UTILITY_DEFS[fee_key]
	var box := VBoxContainer.new()
	box.name = "FiscalRow_utility_%s" % fee_key
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _label("%s（%s）" % [def["name"], def["basis"]], 16, _theme_text())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	row.add_child(name_label)
	var value := _label("", 18, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(72, 0)
	labels["utility_%s" % fee_key] = value
	row.add_child(value)
	box.add_child(row)

	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.name = "FiscalSlider_utility_%s" % fee_key
	slider.min_value = float(def["min"])
	slider.max_value = float(def["max"])
	slider.step = 1
	slider.value = float(utility_fees[fee_key])
	slider.custom_minimum_size = Vector2(0, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.scrollable = false
	slider.value_changed.connect(Callable(self, "_on_utility_fee_changed").bind(fee_key))
	utility_sliders[fee_key] = slider
	_apply_fee_slider_visual(slider, "normal")
	control_row.add_child(slider)
	var input := _number_input(str(utility_fees[fee_key]))
	input.text_submitted.connect(Callable(self, "_on_utility_input_submitted").bind(fee_key))
	input.focus_exited.connect(Callable(self, "_on_utility_input_focus_exited").bind(fee_key))
	utility_inputs[fee_key] = input
	control_row.add_child(input)
	var unit_label := _label("/ %s" % def["unit"], 14, _theme_muted())
	unit_label.custom_minimum_size = Vector2(96, 44)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.max_lines_visible = 2
	control_row.add_child(unit_label)
	box.add_child(control_row)

	var detail := _label("", 15, _theme_muted())
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels["utility_detail_%s" % fee_key] = detail
	box.add_child(detail)

	return box

func _build_tax_row(tax_key: String) -> VBoxContainer:
	var def: Dictionary = TAX_DEFS[tax_key]
	var box := VBoxContainer.new()
	box.name = "FiscalRow_tax_%s" % tax_key
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _label("%s（%s）" % [def["name"], def["basis"]], 16, _theme_text())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	row.add_child(name_label)
	var value := _label("", 18, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(82, 0)
	labels["tax_value_%s" % tax_key] = value
	row.add_child(value)
	box.add_child(row)

	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.name = "FiscalSlider_tax_%s" % tax_key
	slider.min_value = float(def["min"])
	slider.max_value = float(def["max"])
	slider.step = 1
	slider.value = float(tax_rates[tax_key])
	slider.custom_minimum_size = Vector2(0, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.scrollable = false
	slider.value_changed.connect(Callable(self, "_on_tax_changed").bind(tax_key))
	tax_sliders[tax_key] = slider
	_apply_fee_slider_visual(slider, "normal")
	control_row.add_child(slider)
	var input := _number_input(str(tax_rates[tax_key]))
	input.text_submitted.connect(Callable(self, "_on_tax_input_submitted").bind(tax_key))
	input.focus_exited.connect(Callable(self, "_on_tax_input_focus_exited").bind(tax_key))
	tax_inputs[tax_key] = input
	control_row.add_child(input)
	# Keep the Traditional-Chinese source on the node.  This row can be rebuilt
	# while another locale is active (for example after changing the theme); if
	# it stores that translation as its source, switching back leaks English tax
	# units into an otherwise Chinese finance page.
	var unit_source := str(def["unit"]).replace(" %", "")
	var unit_label := _label("% / " + unit_source, 14, _theme_muted())
	unit_label.name = "FiscalTaxUnit_%s" % tax_key
	unit_label.custom_minimum_size = Vector2(96, 44)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.max_lines_visible = 2
	control_row.add_child(unit_label)
	box.add_child(control_row)

	var detail := _label("", 15, _theme_muted())
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels["tax_detail_%s" % tax_key] = detail
	box.add_child(detail)

	return box

func _build_service_fee_row(service_key: String) -> VBoxContainer:
	var def: Dictionary = SERVICE_DEFS[service_key]
	var box := VBoxContainer.new()
	box.name = "FiscalRow_service_%s" % service_key
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _label("%s（%s）" % [def["name"], def["basis"]], 16, _theme_text())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	row.add_child(name_label)
	var value := _label("", 18, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(72, 0)
	labels["service_%s" % service_key] = value
	row.add_child(value)
	box.add_child(row)

	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.name = "FiscalSlider_service_%s" % service_key
	slider.min_value = float(def["min"])
	slider.max_value = float(def["max"])
	slider.step = 1
	slider.value = float(service_fees[service_key])
	slider.custom_minimum_size = Vector2(0, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.scrollable = false
	slider.value_changed.connect(Callable(self, "_on_service_fee_changed").bind(service_key))
	service_sliders[service_key] = slider
	_apply_fee_slider_visual(slider, "normal")
	control_row.add_child(slider)
	var input := _number_input(str(service_fees[service_key]))
	input.text_submitted.connect(Callable(self, "_on_service_input_submitted").bind(service_key))
	input.focus_exited.connect(Callable(self, "_on_service_input_focus_exited").bind(service_key))
	service_inputs[service_key] = input
	control_row.add_child(input)
	var unit_label := _label("/ %s" % def["unit"], 14, _theme_muted())
	unit_label.custom_minimum_size = Vector2(96, 44)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.max_lines_visible = 2
	control_row.add_child(unit_label)
	box.add_child(control_row)

	var detail := _label("", 15, _theme_muted())
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels["service_detail_%s" % service_key] = detail
	box.add_child(detail)

	return box


func _metric_bar(metric: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var row := HBoxContainer.new()
	var title := _label(metric, 17, _theme_text())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var value := _label("", 18, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(124, 0)
	labels["metric_%s" % metric] = value
	row.add_child(value)
	box.add_child(row)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	_style_progress_bar(bar)
	bars[metric] = bar
	box.add_child(bar)
	return box

func _finance_visual_row(label_key: String, title: String, icon: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	var name_label := _label(title, 16, _theme_text())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	row.add_child(name_label)
	var value := _label("", 18, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(108, 0)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels[label_key] = value
	row.add_child(value)
	box.add_child(row)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	_style_progress_bar(bar)
	finance_bars[label_key] = bar
	box.add_child(bar)
	return box


func _icon_texture(icon_key: String) -> Texture2D:
	return UiIconCatalog.texture(icon_key)

func _icon_texture_rect(icon_key: String, minimum_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _icon_texture(icon_key)
	icon.custom_minimum_size = minimum_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _illustrated_section_title(icon_key: String, title_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.add_child(_icon_texture_rect(icon_key, Vector2(44, 44)))
	var title := _section_title(title_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	return row


func _refresh_city_data_dashboard(finance_snapshot: Dictionary) -> void:
	if city_data_dashboard == null:
		return
	# CityReportHistoryService appends the freshly settled period before Main
	# refreshes the dashboard. Mark that tail explicitly as the current period so
	# comparisons and warning streaks only consume completed prior periods.
	var current_period_index := 0
	if not monthly_report_history.is_empty():
		var current_snapshot: Variant = monthly_report_history[monthly_report_history.size() - 1]
		if current_snapshot is Dictionary:
			current_period_index = int((current_snapshot as Dictionary).get("period_index", 0))
	city_data_dashboard.refresh({
		"has_previous_month": monthly_report_history.size() >= 2,
		"previous_month": city_report_history_service.latest_monthly_report_snapshot(),
		"monthly_report_history": monthly_report_history.duplicate(true),
		"history_includes_current": not monthly_report_history.is_empty(),
		"current_period_index": current_period_index,
		"population": population,
		"month_start_population": month_start_population,
		"satisfaction": total_satisfaction,
		"score": ranking_score,
		"rating": city_rating,
		"metrics": {
			"security": security,
			"environment": environment,
			"traffic": traffic,
			"education": education,
			"healthcare": healthcare,
		},
		"resident_groups": group_satisfaction.duplicate(true),
		"finance": finance_snapshot.duplicate(true),
	})


func _city_data_finance_snapshot_for(
		fiscal_tax_values: Dictionary,
		fiscal_utility_values: Dictionary,
		fiscal_service_values: Dictionary,
		maintenance: int,
		policy_expense: int,
		law_expense: int
) -> Dictionary:
	var tax_income := _total_tax_income_for(fiscal_tax_values)
	var business_income := _business_income_for(fiscal_tax_values)
	var industrial_income := _industrial_income_for(fiscal_tax_values)
	var utility_income := _utility_income_for(fiscal_utility_values)
	var service_income := _service_income_for(fiscal_service_values)
	var total_income := tax_income + business_income + industrial_income + utility_income + service_income
	var total_expense := maintenance + policy_expense + law_expense
	var net_income := tax_income + business_income + industrial_income + utility_income + service_income - maintenance - policy_expense - law_expense
	return {
		"tax_income": tax_income,
		"business_income": business_income,
		"industrial_income": industrial_income,
		"utility_income": utility_income,
		"service_income": service_income,
		"total_income": total_income,
		"total_expense": total_expense,
		"net_income": net_income,
	}


func _update_city_metric_cards() -> void:
	for spec_variant in _city_metric_specs():
		var spec: Dictionary = spec_variant
		var metric_id := str(spec["id"])
		if not city_metric_cards.has(metric_id):
			continue
		var value := _city_metric_value(metric_id)
		var status := _city_metric_status(value)
		var building_name := str(spec["building"])
		var relevant_count := _building_count(building_name)
		var localized_status := L10n.text(str(status["label"]))
		var comparison_text := _benchmark_gap_text(float(value), 60.0)
		var interpretation_text := "%s：%s × %d  ·  %s" % [L10n.text("主要服務"), L10n.text(building_name), relevant_count, localized_status]
		var action_text := _city_metric_action_text(building_name, relevant_count, value)
		if metric_id == "healthcare":
			var healthcare_result := _healthcare_service_result()
			var service_status := str(healthcare_result.get("status", "unavailable"))
			status = {
				"key": "good" if service_status == "operational" else ("attention" if service_status == "degraded" else "critical"),
				"label": _healthcare_service_status_text(service_status),
			}
			localized_status = str(status["label"])
			interpretation_text = _healthcare_service_visible_text(healthcare_result)
			action_text = _healthcare_service_action_text(healthcare_result)
		var config := {
			"id": metric_id,
			"icon_key": str(spec["icon_key"]),
			"label": L10n.text(str(spec["label"])),
			"unit": "%",
			"status": str(status["key"]),
			"status_label": localized_status,
			"period_label": L10n.text("本月摘要"),
			"delta_unavailable_text": L10n.text("新城市，尚無上月資料。"),
			"interpretation_text": interpretation_text,
			"action_text": action_text,
			"baseline": 60.0,
			"baseline_text": L10n.text("安全線 60%"),
			"chart_current_text": "%s %d%%" % [L10n.text(str(spec["label"])), value],
			"comparison_text": comparison_text,
			"chart_minimum_text": "0%",
			"chart_maximum_text": "100%",
			"chart_tooltip": comparison_text,
		}
		if metric_id == "healthcare":
			var service_result := _healthcare_service_result()
			config["service_status_code"] = str(service_result.get("status", "unavailable"))
			config["service_reason_code"] = str(service_result.get("reason_code", "facility_missing"))
		city_metric_cards[metric_id].set_metric_from_month_summary(
			config,
			value,
			last_month_summary,
			str(spec["delta_key"])
		)
	_refresh_city_metric_layout()


func _toggle_city_metric_details() -> void:
	city_data_show_all = not city_data_show_all
	_refresh_city_metric_layout(true)


func _refresh_city_metric_layout(force: bool = false) -> void:
	if city_metric_primary_grid == null or city_metric_secondary_grid == null:
		return
	var prioritized := _prioritized_city_metric_specs()
	var ordered_ids: Array[String] = []
	for spec_variant in prioritized:
		ordered_ids.append(str((spec_variant as Dictionary)["id"]))
	var signature := "%s|%s" % [",".join(ordered_ids), city_data_show_all]
	if not force and signature == _city_metric_layout_signature:
		return
	_city_metric_layout_signature = signature
	for index in ordered_ids.size():
		var metric_id := ordered_ids[index]
		if not city_metric_cards.has(metric_id):
			continue
		var card: Control = city_metric_cards[metric_id]
		var target: GridContainer = city_metric_primary_grid if index < 3 else city_metric_secondary_grid
		if card.get_parent() != target:
			card.reparent(target)
		target.move_child(card, mini(index if index < 3 else index - 3, target.get_child_count() - 1))
	city_metric_secondary_grid.visible = city_data_show_all
	if city_metric_details_button != null:
		city_metric_details_button.text = L10n.text("隱藏其他 2 項") if city_data_show_all else L10n.text("顯示其他 2 項")
	if city_metric_priority_label != null and prioritized.size() >= 2:
		var first: Dictionary = prioritized[0]
		var second: Dictionary = prioritized[1]
		city_metric_priority_label.text = L10n.text("優先關注：%s、%s｜主畫面僅保留安全餘裕最小的 3 項。") % [
			"%s %s" % [L10n.text(str(first["label"])), _benchmark_gap_text(float(_city_metric_value(str(first["id"]))), 60.0)],
			"%s %s" % [L10n.text(str(second["label"])), _benchmark_gap_text(float(_city_metric_value(str(second["id"]))), 60.0)],
		]


func _prioritized_city_metric_specs() -> Array[Dictionary]:
	return CitySimulationServiceScript.prioritized_metric_specs(
		_city_metric_specs(),
		_city_metrics_snapshot()
	)


func _city_metric_specs() -> Array[Dictionary]:
	return [
		{"id": "security", "label": "治安", "icon_key": "security", "building": "警局", "delta_key": "security_change"},
		{"id": "environment", "label": "環境", "icon_key": "environment", "building": "公園", "delta_key": "environment_change"},
		{"id": "traffic", "label": "交通", "icon_key": "traffic", "building": "公車站", "delta_key": "traffic_change"},
		{"id": "education", "label": "教育", "icon_key": "education", "building": "學校", "delta_key": "education_change"},
		{"id": "healthcare", "label": "醫療", "icon_key": "healthcare", "building": "醫院", "delta_key": "healthcare_change"},
	]


func _city_metric_action_text(building_name: String, relevant_count: int, value: int) -> String:
	if relevant_count <= 0:
		return L10n.text("優先建造：%s") % L10n.text(building_name)
	if value >= 75:
		return L10n.text("設施充足，維持目前配置。")
	return L10n.text("視需求增建：%s") % L10n.text(building_name)


func _city_metric_value(metric_id: String) -> int:
	return _authoritative_metric_value(metric_id, 0)


func _city_metric_status(value: int) -> Dictionary:
	if value >= 75:
		return {"key": "good", "label": "良好"}
	if value >= 55:
		return {"key": "neutral", "label": "穩定"}
	if value >= 35:
		return {"key": "attention", "label": "留意"}
	return {"key": "critical", "label": "危險"}


func _record_major_event(
		event_type: String,
		subject: String = "",
		details: String = "",
		event_key: String = "",
		game_time: int = -1,
		actor_id: String = ""
) -> void:
	var resolved_time := game_time
	if resolved_time < 0:
		resolved_time = (
			vertical_slice.game_day()
			if vertical_slice != null
			else city_report_history_service.game_time_for_calendar(month, day)
		)
	if city_report_history_service.record_major_event(
		event_type,
		subject,
		details,
		event_key,
		resolved_time,
		actor_id
	):
		_animate_label_flash(report_label)


func _major_event_actor_name(actor_id: String) -> String:
	if actor_id.is_empty() or vertical_slice == null:
		return L10n.text("居民")
	var proxy: Dictionary = vertical_slice.population.materialize_proxy(actor_id)
	if proxy.is_empty():
		return actor_id
	return L10n.person_name(
		str(proxy.get("family_name", "")),
		str(proxy.get("given_name", "")),
		str(proxy.get("display_name", actor_id)),
		str(proxy.get("latin_display_name", ""))
	)


func _current_month_major_event_summary() -> String:
	var current_date: Dictionary = vertical_slice.current_date() if vertical_slice != null else {"year": 1, "month": month}
	return city_report_history_service.current_month_major_event_summary(
		int(current_date.get("year", 1)),
		int(current_date.get("month", month)),
		Callable(self, "_major_event_actor_name"),
		Callable(L10n, "text")
	)


func _request_major_event_data(request_id: String) -> Dictionary:
	if vertical_slice == null or not vertical_slice.population.requests.has(request_id):
		return {}
	var request = vertical_slice.population.requests[request_id]
	return request.to_dict() if request != null else {}


func _record_governance_failure_if_needed() -> void:
	if vertical_slice == null:
		return
	var reason := str(vertical_slice.governance.failure_reason())
	if reason.is_empty():
		return
	var game_time: int = int(vertical_slice.game_day())
	var event_key := "governance_failure:%d:%s" % [game_time, reason]
	if reason == "grievance_above_80":
		_record_major_event("rebellion", "", "", event_key, game_time)
	else:
		var reason_text := L10n.text("市政信任低於 40，治理授權失效。") if reason == "municipal_trust_below_40" else L10n.text("市長遭判處監禁，遊戲失敗。")
		_record_major_event("governance_failure", "", reason_text, event_key, game_time)


func _load_version_updates() -> void:
	version_updates.clear()
	if not FileAccess.file_exists(VERSION_UPDATES_PATH):
		return
	var file := FileAccess.open(VERSION_UPDATES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var raw_updates: Variant = parsed.get("updates", [])
	if not raw_updates is Array:
		return
	var seen_ids := {}
	for update_variant in raw_updates:
		if not update_variant is Dictionary:
			continue
		var update: Dictionary = update_variant
		var update_id := str(update.get("update_id", "")).strip_edges()
		var title := str(update.get("title", "")).strip_edges()
		var changes: Variant = update.get("changes", [])
		if update_id.is_empty() or title.is_empty() or seen_ids.has(update_id) or not changes is Array or changes.is_empty():
			continue
		seen_ids[update_id] = true
		version_updates.append({
			"update_id": update_id,
			"version": str(update.get("version", "")).strip_edges(),
			"date": str(update.get("date", "")).strip_edges(),
			"title": title,
			"changes": Array(changes).duplicate(),
		})
	version_updates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%s:%s" % [a.get("date", ""), a.get("update_id", "")] > "%s:%s" % [b.get("date", ""), b.get("update_id", "")]
	)


func _version_update_announcement_text() -> String:
	if version_updates.is_empty():
		return L10n.text("目前尚無版本更新公告。")
	var blocks := PackedStringArray()
	for update in version_updates:
		var version_text := str(update.get("version", ""))
		var date_text := str(update.get("date", ""))
		var heading_prefix := version_text if not version_text.is_empty() else date_text
		if not version_text.is_empty() and not date_text.is_empty():
			heading_prefix = "%s｜%s" % [version_text, date_text]
		var lines := PackedStringArray(["【%s】%s" % [heading_prefix, L10n.text(str(update.get("title", "")))]])
		for change_variant in update.get("changes", []):
			lines.append("• %s" % L10n.text(str(change_variant)))
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)


func _make_monthly_report_snapshot(income: int, expense: int, population_rate: float) -> Dictionary:
	return city_report_history_service.make_monthly_report_snapshot(
		income,
		expense,
		population_rate,
		_city_report_metric_snapshot()
	)


func _report_percentage_number(value: float, decimals: int) -> String:
	return ("%.*f" % [decimals, value]) if decimals > 0 else str(roundi(value))


func _report_baseline_text(previous_value: float, safety_value: float, safety_name: String, decimals: int) -> String:
	if not monthly_report_history.is_empty():
		return L10n.text("上月 %s%%") % _report_percentage_number(previous_value, decimals)
	return L10n.text("%s %s%%") % [L10n.text(safety_name), _report_percentage_number(safety_value, decimals)]


func _report_comparison_text(current: float, baseline: float, safety_name: String, decimals: int) -> String:
	if monthly_report_history.is_empty():
		return _benchmark_gap_text(current, baseline, safety_name, decimals)
	var difference := current - baseline
	if absf(difference) < pow(10.0, -float(decimals)) * 0.5:
		return L10n.text("與上月相同")
	var magnitude := _report_percentage_number(absf(difference), decimals)
	if difference > 0.0:
		return L10n.text("較上月高 +%s 個百分點") % magnitude
	return L10n.text("較上月低 −%s 個百分點") % magnitude


func _report_safety_warning_text(current: float, safety: float, safety_name: String, decimals: int) -> String:
	if current >= safety:
		return ""
	var magnitude := _report_percentage_number(absf(current - safety), decimals)
	return L10n.text("⚠ 安全線警告：低於%s −%s 個百分點") % [L10n.text(safety_name), magnitude]


func _benchmark_gap_text(current: float, baseline: float, baseline_name: String = "安全線", decimals: int = 0) -> String:
	var difference := current - baseline
	var localized_baseline := L10n.text(baseline_name)
	if absf(difference) < pow(10.0, -float(decimals)) * 0.5:
		return L10n.text("恰好位於%s") % localized_baseline
	var magnitude := ("%.*f" % [decimals, absf(difference)]) if decimals > 0 else str(roundi(absf(difference)))
	if difference > 0.0:
		return L10n.text("高於%s +%s 個百分點") % [localized_baseline, magnitude]
	return L10n.text("低於%s −%s 個百分點") % [localized_baseline, magnitude]


func restart_benchmark_charts(chart_registry: Dictionary) -> void:
	for chart_variant in chart_registry.values():
		if is_instance_valid(chart_variant) and chart_variant.has_method("restart_animation"):
			chart_variant.restart_animation()


func _score_state(value: int, inverse: bool = false) -> String:
	var normalized := 100 - value if inverse else value
	if normalized >= 75:
		return "良好"
	if normalized >= 50:
		return "留意"
	return "危險"

func _score_color(value: int, inverse: bool = false) -> Color:
	var normalized := 100 - value if inverse else value
	if normalized >= 75:
		return COLOR_SUCCESS
	if normalized >= 50:
		return COLOR_CAUTION
	return COLOR_WARNING

func _set_bar_visual(bar: ProgressBar, value: float, color: Color) -> void:
	if bar == null:
		return
	bar.value = clampf(value, bar.min_value, bar.max_value)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)


func _update_metric_visual(metric: String, value: int) -> void:
	var color := _score_color(value)
	var label_key := "metric_%s" % metric
	if labels.has(label_key):
		labels[label_key].text = "%d  %s" % [value, _score_state(value)]
		labels[label_key].add_theme_color_override("font_color", color)
	if bars.has(metric):
		_set_bar_visual(bars[metric], float(value), color)

func _update_finance_visual(label_key: String, amount: int, scale: int, color: Color, signed_value: bool = false) -> void:
	if labels.has(label_key):
		labels[label_key].text = "%s$%d" % ["+" if amount >= 0 else "-", absi(amount)] if signed_value else "$%d" % amount
		labels[label_key].add_theme_color_override("font_color", color)
	if finance_bars.has(label_key):
		var ratio := absf(float(amount)) / maxf(1.0, float(scale)) * 100.0
		_set_bar_visual(finance_bars[label_key], ratio, color)



func _fiscal_category_spec(category_id: String) -> Dictionary:
	for spec: Dictionary in FISCAL_CATEGORY_SPECS:
		if str(spec.get("id", "")) == category_id:
			return spec
	return {}


func _layout_fiscal_surface(scroll: ScrollContainer) -> void:
	if scroll == null or fiscal_responsive_layout == null:
		return
	fiscal_responsive_layout.columns = 1
	if fiscal_category_grid != null:
		fiscal_category_grid.columns = 2 if scroll.size.x >= 720.0 else 1


func _show_fiscal_categories() -> void:
	_fiscal_flow_step = "edit"
	_fiscal_preview_revision = -1
	_selected_fiscal_category = ""
	_selected_fiscal_plan = ""
	if fiscal_category_surface != null:
		fiscal_category_surface.show()
	if fiscal_plan_surface != null:
		fiscal_plan_surface.hide()
	if fiscal_custom_editor != null:
		fiscal_custom_editor.hide()
	if fiscal_draft_preview != null:
		fiscal_draft_preview.hide()
	for page_variant in fiscal_custom_pages.values():
		var page := page_variant as Control
		if page != null:
			page.hide()
	_refresh_fiscal_draft_actions()


func _return_to_fiscal_edit() -> void:
	if _fiscal_flow_step != "preview":
		return
	_fiscal_flow_step = "edit"
	_fiscal_preview_revision = -1
	if fiscal_draft_preview != null:
		fiscal_draft_preview.hide()
	if _selected_fiscal_category.is_empty():
		if fiscal_category_surface != null:
			fiscal_category_surface.show()
	else:
		if fiscal_plan_surface != null:
			fiscal_plan_surface.show()
		if fiscal_custom_editor != null:
			fiscal_custom_editor.visible = _selected_fiscal_plan == "custom"
		for category_id_variant in fiscal_custom_pages.keys():
			var category_id := str(category_id_variant)
			var page := fiscal_custom_pages[category_id] as Control
			if page != null:
				page.visible = _selected_fiscal_plan == "custom" and category_id == _selected_fiscal_category
	_refresh_fiscal_draft_actions()


func _show_fiscal_preview() -> void:
	var changed := _fiscal_dirty_count()
	if not _fiscal_draft_active or changed == 0:
		_set_hint("請先調整至少一項稅務或收費設定。", true)
		return
	_fiscal_flow_step = "preview"
	_fiscal_preview_revision = _fiscal_draft_revision
	if fiscal_category_surface != null:
		fiscal_category_surface.hide()
	if fiscal_plan_surface != null:
		fiscal_plan_surface.hide()
	if fiscal_custom_editor != null:
		fiscal_custom_editor.hide()
	if fiscal_draft_preview != null:
		fiscal_draft_preview.show()
	_refresh_fiscal_draft_actions()
	_update_ui()
	call_deferred("_refresh_onboarding_guide")


func _select_fiscal_category(category_id: String) -> void:
	var spec := _fiscal_category_spec(category_id)
	if spec.is_empty():
		return
	_selected_fiscal_category = category_id
	_selected_fiscal_plan = ""
	if fiscal_category_surface != null:
		fiscal_category_surface.hide()
	if fiscal_plan_surface != null:
		fiscal_plan_surface.show()
	if fiscal_plan_title != null:
		fiscal_plan_title.text = L10n.text("%s｜選擇方案") % L10n.text(str(spec["title"]))
	if fiscal_plan_hint != null:
		fiscal_plan_hint.text = L10n.text(_fiscal_category_hint(str(spec["title"])))
	if fiscal_custom_editor != null:
		fiscal_custom_editor.hide()
	for page_variant in fiscal_custom_pages.values():
		var page := page_variant as Control
		if page != null:
			page.hide()
	_refresh_fiscal_draft_actions()


func _select_fiscal_plan(plan_id: String) -> void:
	if not plan_id in ["current", "reasonable", "custom"]:
		return
	var spec := _fiscal_category_spec(_selected_fiscal_category)
	if spec.is_empty():
		return
	_selected_fiscal_plan = plan_id
	var show_custom := plan_id == "custom"
	if fiscal_custom_editor != null:
		fiscal_custom_editor.visible = show_custom
	for category_id_variant in fiscal_custom_pages.keys():
		var category_id := str(category_id_variant)
		var page := fiscal_custom_pages[category_id] as Control
		if page != null:
			page.visible = show_custom and category_id == _selected_fiscal_category
	if show_custom:
		_refresh_fiscal_draft_actions()
		return
	for item: Dictionary in spec["items"]:
		var kind := str(item["kind"])
		var key := str(item["key"])
		var value := int(_fiscal_draft_base_dictionary(kind).get(key, _fiscal_value(kind, key)))
		if plan_id == "reasonable":
			value = int(_fiscal_definition(kind, key).get("reasonable", value))
		_set_fiscal_draft_value(kind, key, value, false)
	_refresh_fiscal_draft_actions()
	_update_ui()


func _fiscal_preview_value(kind: String, key: String, value: int) -> String:
	var definition := _fiscal_definition(kind, key)
	var unit := str(definition.get("unit", ""))
	return "%d%s" % [value, "%" if kind == "tax" else " / %s" % unit]


func _refresh_fiscal_draft_preview() -> void:
	if fiscal_draft_change_list == null or fiscal_draft_risk_label == null:
		return
	var lines := PackedStringArray()
	var elevated_count := 0
	var pressure_total := 0
	for spec: Dictionary in FISCAL_CATEGORY_SPECS:
		var item_text := PackedStringArray()
		for item: Dictionary in spec["items"]:
			var kind := str(item["kind"])
			var key := str(item["key"])
			var definition := _fiscal_definition(kind, key)
			var base := int(_fiscal_draft_base_dictionary(kind).get(key, _fiscal_value(kind, key)))
			var draft := int(_fiscal_draft_dictionary(kind).get(key, base))
			item_text.append(L10n.text("%s %s → %s") % [L10n.text(str(definition.get("name", key))), _fiscal_preview_value(kind, key, base), _fiscal_preview_value(kind, key, draft)])
			var pressure := _fiscal_item_public_pressure(kind, draft, int(definition.get("reasonable", draft)))
			pressure_total += pressure
			if pressure > 0:
				elevated_count += 1
		lines.append(L10n.text("%s｜%s") % [L10n.text(str(spec["title"])), "；".join(item_text)])
	fiscal_draft_change_list.text = "\n".join(lines)
	if elevated_count == 0:
		fiscal_draft_risk_label.text = L10n.text("民意／負擔風險｜目前草稿皆在合理負擔範圍。")
		fiscal_draft_risk_label.add_theme_color_override("font_color", COLOR_SUCCESS)
	else:
		fiscal_draft_risk_label.text = L10n.text("民意／負擔風險｜%d 項高於合理範圍，預估壓力 +%d。") % [elevated_count, pressure_total]
		fiscal_draft_risk_label.add_theme_color_override("font_color", COLOR_WARNING if elevated_count >= 3 else COLOR_CAUTION)


func _begin_fiscal_draft() -> void:
	# Input routes can create a draft before the lazy municipal overlay has built
	# its finance controls. Materializing the page later must attach those controls
	# to that draft, not silently replace the pending values with authoritative
	# state.
	if not _fiscal_draft_active:
		_fiscal_draft_active = true
		_fiscal_draft_base_tax_rates = tax_rates.duplicate(true)
		_fiscal_draft_base_utility_fees = utility_fees.duplicate(true)
		_fiscal_draft_base_service_fees = service_fees.duplicate(true)
		_fiscal_draft_tax_rates = tax_rates.duplicate(true)
		_fiscal_draft_utility_fees = utility_fees.duplicate(true)
		_fiscal_draft_service_fees = service_fees.duplicate(true)
		_fiscal_flow_step = "edit"
		_fiscal_draft_revision = 0
		_fiscal_preview_revision = -1
	_sync_fiscal_controls_from_draft()
	_show_fiscal_categories()
	_update_ui()
	if fiscal_page_scroll != null:
		_layout_fiscal_surface(fiscal_page_scroll)
		call_deferred("_layout_fiscal_surface", fiscal_page_scroll)


func _fiscal_draft_dictionary(kind: String) -> Dictionary:
	match kind:
		"tax":
			return _fiscal_draft_tax_rates
		"utility":
			return _fiscal_draft_utility_fees
		"service":
			return _fiscal_draft_service_fees
	return {}


func _fiscal_draft_base_dictionary(kind: String) -> Dictionary:
	match kind:
		"tax":
			return _fiscal_draft_base_tax_rates
		"utility":
			return _fiscal_draft_base_utility_fees
		"service":
			return _fiscal_draft_base_service_fees
	return {}


func _fiscal_dirty_count() -> int:
	if not _fiscal_draft_active:
		return 0
	var changed := 0
	for kind in ["tax", "utility", "service"]:
		var draft := _fiscal_draft_dictionary(kind)
		var base := _fiscal_draft_base_dictionary(kind)
		for key in draft.keys():
			if int(draft[key]) != int(base.get(key, draft[key])):
				changed += 1
	return changed


func _fiscal_display_value(kind: String, key: String, suffix: String) -> String:
	var authoritative_value := _fiscal_value(kind, key)
	if not _fiscal_draft_active:
		return "%d%s" % [authoritative_value, suffix]
	var draft_value := int(_fiscal_draft_dictionary(kind).get(key, authoritative_value))
	var base := int(_fiscal_draft_base_dictionary(kind).get(key, authoritative_value))
	if base == draft_value:
		return "%d%s" % [draft_value, suffix]
	return "%d%s → %d%s" % [base, suffix, draft_value, suffix]


func _set_fiscal_draft_value(kind: String, key: String, value: int, do_refresh: bool = true) -> void:
	if not _fiscal_draft_active:
		_begin_fiscal_draft()
	var definition := _fiscal_definition(kind, key)
	var normalized := clampi(value, int(definition["min"]), int(definition["max"]))
	var draft := _fiscal_draft_dictionary(kind)
	var previous := int(draft.get(key, normalized))
	draft[key] = normalized
	if previous != normalized:
		_fiscal_draft_revision += 1
	match kind:
		"tax":
			var tax_slider := _cached_fiscal_slider(tax_sliders, key)
			if tax_slider != null:
				tax_slider.set_value_no_signal(normalized)
			_sync_number_input(tax_inputs, key, normalized, true)
		"utility":
			var utility_slider := _cached_fiscal_slider(utility_sliders, key)
			if utility_slider != null:
				utility_slider.set_value_no_signal(normalized)
			_sync_number_input(utility_inputs, key, normalized, true)
		"service":
			var service_slider := _cached_fiscal_slider(service_sliders, key)
			if service_slider != null:
				service_slider.set_value_no_signal(normalized)
			_sync_number_input(service_inputs, key, normalized, true)
	if do_refresh:
		_update_ui()
	call_deferred("_refresh_onboarding_guide")


func _sync_fiscal_controls_from_draft() -> void:
	if not _fiscal_draft_active:
		return
	for key in _fiscal_draft_tax_rates.keys():
		var tax_slider := _cached_fiscal_slider(tax_sliders, key)
		if tax_slider != null:
			tax_slider.set_value_no_signal(int(_fiscal_draft_tax_rates[key]))
		_sync_number_input(tax_inputs, key, int(_fiscal_draft_tax_rates[key]), true)
	for key in _fiscal_draft_utility_fees.keys():
		var utility_slider := _cached_fiscal_slider(utility_sliders, key)
		if utility_slider != null:
			utility_slider.set_value_no_signal(int(_fiscal_draft_utility_fees[key]))
		_sync_number_input(utility_inputs, key, int(_fiscal_draft_utility_fees[key]), true)
	for key in _fiscal_draft_service_fees.keys():
		var service_slider := _cached_fiscal_slider(service_sliders, key)
		if service_slider != null:
			service_slider.set_value_no_signal(int(_fiscal_draft_service_fees[key]))
		_sync_number_input(service_inputs, key, int(_fiscal_draft_service_fees[key]), true)


func _refresh_fiscal_draft_actions() -> void:
	var changed := _fiscal_dirty_count()
	if fiscal_draft_status_label != null:
		# This label is composed from already-localized dynamic templates below.
		# Prevent the tree-wide fallback replacement pass from rewriting substrings
		# inside a translated value when the active locale changes.
		fiscal_draft_status_label.set_meta("l10n_skip", true)
		var safety_buffer := _fiscal_safety_buffer()
		var projected_net_income := _projected_net_income()
		var operating_status_source := "● 財政安全\n預估淨額已覆蓋市政支出與安全緩衝。" if projected_net_income >= safety_buffer else ("● 緩衝不足\n可運作，但無法承受收入波動。" if projected_net_income >= 0 else "● 赤字預警\n目前收費不足以支應每月市政運作。")
		var operating_status := L10n.text(operating_status_source)
		var draft_status := (
			L10n.text("尚未套用：%d 項變更\n可預覽整組草稿後再執行。") % changed
			if changed > 0
			else L10n.text("正式設定｜尚未變更\n可先調整多項，再預覽一次套用。")
		)
		fiscal_draft_status_label.text = "%s\n%s" % [operating_status, draft_status]
		fiscal_draft_status_label.add_theme_color_override("font_color", COLOR_CAUTION if changed > 0 or projected_net_income < safety_buffer else _theme_muted())
	if fiscal_preview_button != null:
		fiscal_preview_button.disabled = changed == 0 or _fiscal_flow_step != "edit"
		fiscal_preview_button.text = L10n.text("預覽變更（%d）") % changed
	if fiscal_apply_button != null:
		fiscal_apply_button.disabled = changed == 0 or _fiscal_flow_step != "preview" or _fiscal_preview_revision != _fiscal_draft_revision
		fiscal_apply_button.text = L10n.text("執行變更（%d）") % changed
	if fiscal_discard_button != null:
		fiscal_discard_button.disabled = changed == 0
	_refresh_fiscal_draft_preview()


func _discard_fiscal_draft(explicit_action: bool = true, keep_active: bool = true) -> void:
	if not _fiscal_draft_active:
		return
	_fiscal_draft_base_tax_rates = tax_rates.duplicate(true)
	_fiscal_draft_base_utility_fees = utility_fees.duplicate(true)
	_fiscal_draft_base_service_fees = service_fees.duplicate(true)
	_fiscal_draft_tax_rates = tax_rates.duplicate(true)
	_fiscal_draft_utility_fees = utility_fees.duplicate(true)
	_fiscal_draft_service_fees = service_fees.duplicate(true)
	_fiscal_draft_active = keep_active
	_fiscal_flow_step = "edit"
	_fiscal_draft_revision = 0
	_fiscal_preview_revision = -1
	if keep_active:
		_sync_fiscal_controls_from_draft()
		_show_fiscal_categories()
	_update_ui()
	if explicit_action:
		_set_hint("已放棄尚未套用的稅務與收費變更。", false)


func _apply_fiscal_draft() -> void:
	var changed := _fiscal_dirty_count()
	if not _fiscal_draft_active or changed == 0 or _fiscal_flow_step != "preview" or _fiscal_preview_revision != _fiscal_draft_revision:
		_set_hint("草稿預覽已失效；請返回修改後重新預覽。", true)
		return
	var accepted_preview_revision := _fiscal_preview_revision
	var accepted_draft_revision := _fiscal_draft_revision
	var commit_tax := _fiscal_draft_tax_rates.duplicate(true)
	var commit_utility := _fiscal_draft_utility_fees.duplicate(true)
	var commit_service := _fiscal_draft_service_fees.duplicate(true)
	tax_rates = commit_tax
	utility_fees = commit_utility
	service_fees = commit_service
	tax_rate = int(tax_rates["income"])
	_fiscal_draft_base_tax_rates = tax_rates.duplicate(true)
	_fiscal_draft_base_utility_fees = utility_fees.duplicate(true)
	_fiscal_draft_base_service_fees = service_fees.duplicate(true)
	_fiscal_draft_tax_rates = tax_rates.duplicate(true)
	_fiscal_draft_utility_fees = utility_fees.duplicate(true)
	_fiscal_draft_service_fees = service_fees.duplicate(true)
	_fiscal_apply_generation += 1
	var onboarding_recorded := onboarding_action_router.record_fiscal_apply_success(
		accepted_preview_revision,
		accepted_draft_revision,
		changed,
		_fiscal_apply_generation,
		vertical_slice.game_day()
	)
	_fiscal_flow_step = "edit"
	_fiscal_draft_revision = 0
	_fiscal_preview_revision = -1
	_recalculate_satisfaction()
	_recalculate_score()
	_reconcile_resident_request_completion(false)
	_consume_vertical_events(vertical_slice.drain_ui_events(), false)
	_sync_fiscal_controls_from_draft()
	_show_fiscal_categories()
	_update_ui()
	_set_hint("已一次套用 %d 項稅務與收費變更。" % changed, false)
	_autosave("action:fiscal_draft_applied")
	if onboarding_recorded:
		call_deferred("_refresh_onboarding_guide")


func _fiscal_projection_snapshot(use_draft: bool) -> Dictionary:
	var projection_tax := _fiscal_draft_tax_rates if use_draft and _fiscal_draft_active else tax_rates
	var projection_utility := _fiscal_draft_utility_fees if use_draft and _fiscal_draft_active else utility_fees
	var projection_service := _fiscal_draft_service_fees if use_draft and _fiscal_draft_active else service_fees
	return _fiscal_projection_snapshot_for(projection_tax, projection_utility, projection_service)


func _fiscal_projection_snapshot_for(projection_tax: Dictionary, projection_utility: Dictionary, projection_service: Dictionary) -> Dictionary:
	var income := (
		_total_tax_income_for(projection_tax)
		+ _business_income_for(projection_tax)
		+ _industrial_income_for(projection_tax)
		+ _utility_income_for(projection_utility)
		+ _service_income_for(projection_service)
	)
	var expense := _projected_total_expense()
	return {
		"income": income,
		"expense": expense,
		"net": income - expense,
		"safety_buffer": maxi(100, int(ceil(float(expense) * 0.10))),
	}


func debug_fiscal_draft_state() -> Dictionary:
	var authoritative := _fiscal_projection_snapshot(false)
	var projected := _fiscal_projection_snapshot(true)
	var category_ids := PackedStringArray()
	for spec: Dictionary in FISCAL_CATEGORY_SPECS:
		category_ids.append(str(spec["id"]))
	return {
		"active": _fiscal_draft_active,
		"dirty_count": _fiscal_dirty_count(),
		"tax": _fiscal_draft_tax_rates.duplicate(true),
		"utility": _fiscal_draft_utility_fees.duplicate(true),
		"service": _fiscal_draft_service_fees.duplicate(true),
		"authoritative_net": int(authoritative["net"]),
		"projected_net": int(projected["net"]),
		"authoritative_income": int(authoritative["income"]),
		"projected_income": int(projected["income"]),
		"authoritative_expense": int(authoritative["expense"]),
		"projected_expense": int(projected["expense"]),
		"projected_safety_buffer": int(projected["safety_buffer"]),
		"apply_generation": _fiscal_apply_generation,
		"flow_step": _fiscal_flow_step,
		"draft_revision": _fiscal_draft_revision,
		"preview_revision": _fiscal_preview_revision,
		"ui": {
			"category_ids": Array(category_ids),
			"category_count": category_ids.size(),
			"plan_ids": ["current", "reasonable", "custom"],
			"selected_category": _selected_fiscal_category,
			"selected_plan": _selected_fiscal_plan,
			"category_surface_visible": fiscal_category_surface != null and fiscal_category_surface.visible,
			"plan_surface_visible": fiscal_plan_surface != null and fiscal_plan_surface.visible,
			"custom_editor_visible": fiscal_custom_editor != null and fiscal_custom_editor.visible,
			"preview_visible": fiscal_draft_preview != null and fiscal_draft_preview.visible,
			"edit_visible": (fiscal_category_surface != null and fiscal_category_surface.visible) or (fiscal_plan_surface != null and fiscal_plan_surface.visible),
			"responsive_columns": fiscal_responsive_layout.columns if fiscal_responsive_layout != null else 0,
			"preview_placement": "exclusive",
			"preview_changes": fiscal_draft_change_list.text if fiscal_draft_change_list != null else "",
			"risk_text": fiscal_draft_risk_label.text if fiscal_draft_risk_label != null else "",
		},
	}


func _fiscal_category_hint(category_title: String) -> String:
	match category_title:
		"居民稅":
			return "居民所得與消費相關稅率；過高會直接提高民意壓力。"
		"產業稅":
			return "商業與工業稅率；過高可能同時降低產業活動收入。"
		"水電":
			return "水費與電費；低價可補貼，但不能形成營運缺口。"
		"環境能源":
			return "瓦斯與垃圾處理費；依住戶與城市設施用量預估。"
		"城市服務":
			return "停車與醫療服務收費；過高會增加居民負擔並降低使用率。"
		"教育休閒":
			return "學費與場館票價；過高會降低服務使用與居民滿意。"
	return "調整後會立即以其餘條件不變的方式重新估算。"

func _fiscal_definition(kind: String, key: String) -> Dictionary:
	match kind:
		"tax":
			return TAX_DEFS[key]
		"utility":
			return UTILITY_DEFS[key]
		"service":
			return SERVICE_DEFS[key]
	return {}

func _fiscal_value(kind: String, key: String) -> int:
	match kind:
		"tax":
			return int(tax_rates[key])
		"utility":
			return int(utility_fees[key])
		"service":
			return int(service_fees[key])
	return 0

func _projected_total_income() -> int:
	return _total_tax_income() + _business_income() + _industrial_income() + _utility_income() + _service_income()

func _projected_total_expense() -> int:
	return _maintenance_cost() + _policy_expense() + _active_law_expense()

func _projected_net_income() -> int:
	return _projected_total_income() - _projected_total_expense()

func _fiscal_safety_buffer() -> int:
	return maxi(100, int(ceil(float(_projected_total_expense()) * 0.10)))

func _fiscal_item_public_pressure(kind: String, value: int, reasonable: int) -> int:
	var ratio := float(value) / maxf(1.0, float(reasonable))
	if ratio <= 1.25:
		return 0
	if kind == "utility":
		return 7 if ratio > 1.75 else 3
	if kind == "service":
		return 3 if ratio > 1.75 else 1
	return 10 if ratio > 1.75 else 5

func _signed_currency(value: int) -> String:
	return "+$%d" % value if value >= 0 else "-$%d" % absi(value)

func _fiscal_item_forecast(kind: String, key: String) -> Dictionary:
	var definition := _fiscal_definition(kind, key)
	var reasonable := int(definition.get("reasonable", 0))
	var projection_tax: Dictionary = _fiscal_draft_tax_rates if _fiscal_draft_active else tax_rates
	var projection_utility: Dictionary = _fiscal_draft_utility_fees if _fiscal_draft_active else utility_fees
	var projection_service: Dictionary = _fiscal_draft_service_fees if _fiscal_draft_active else service_fees
	var current_values: Dictionary
	match kind:
		"tax":
			current_values = projection_tax
		"utility":
			current_values = projection_utility
		"service":
			current_values = projection_service
		_:
			current_values = {}
	var current_value := int(current_values.get(key, 0))
	var current_snapshot := _fiscal_projection_snapshot_for(projection_tax, projection_utility, projection_service)
	var reference_tax := projection_tax.duplicate(true)
	var reference_utility := projection_utility.duplicate(true)
	var reference_service := projection_service.duplicate(true)
	match kind:
		"tax":
			reference_tax[key] = reasonable
		"utility":
			reference_utility[key] = reasonable
		"service":
			reference_service[key] = reasonable
	var reference_snapshot := _fiscal_projection_snapshot_for(reference_tax, reference_utility, reference_service)
	var current_net := int(current_snapshot["net"])
	var reference_net := int(reference_snapshot["net"])

	var ratio := float(current_value) / maxf(1.0, float(reasonable))
	var net_delta := current_net - reference_net
	var public_pressure := _fiscal_item_public_pressure(kind, current_value, reasonable)
	var safety_buffer := int(current_snapshot["safety_buffer"])
	var funding_gap := maxi(0, safety_buffer - current_net)
	var contribution_gap := maxi(0, reference_net - current_net)
	var material_gap := maxi(25, int(ceil(float(safety_buffer) / 14.0)))
	var state := "normal"
	var state_text := "正常"
	if ratio > 1.25:
		state = "high"
		state_text = "負擔過高"
	elif ratio < 0.75 and reference_net > current_net and (current_net < safety_buffer or contribution_gap >= material_gap):
		state = "low"
		state_text = "收入不足"
	elif ratio < 0.75:
		state_text = "可補貼"

	var summary_prefix := L10n.text("淨額較建議 %s") % _signed_currency(net_delta)
	var summary := summary_prefix
	if state == "low":
		var gap_name := L10n.text("安全缺口") if funding_gap > 0 else L10n.text("單項收入缺口")
		var gap_amount := funding_gap if funding_gap > 0 else contribution_gap
		summary += "｜" + (L10n.text("%s $%d") % [gap_name, gap_amount])
	elif state == "high":
		summary += "｜" + (L10n.text("民意 -%d") % public_pressure)
	else:
		summary += "｜" + L10n.text("民意穩定")
	return {
		"state": state,
		"state_text": state_text,
		"color": COLOR_CAUTION if state == "low" else (COLOR_WARNING if state == "high" else COLOR_SUCCESS),
		"summary": summary,
		"net_delta": net_delta,
		"public_pressure": public_pressure,
		"current_net": current_net,
		"reference_net": reference_net,
		"safety_buffer": safety_buffer
	}

func _apply_fee_slider_visual(slider: HSlider, state: String) -> void:
	var color := COLOR_CAUTION if state == "low" else (COLOR_WARNING if state == "high" else COLOR_SUCCESS)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.78, 0.83, 0.86) if not is_dark_mode else Color(0.22, 0.29, 0.35)
	track.set_corner_radius_all(7)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(7)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	var highlight := fill.duplicate()
	highlight.bg_color = _lighten(color, 0.12)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", highlight)
	slider.set_meta("warning_state", state)



func _effect_token(effect_key: String, raw_value: Variant) -> String:
	var labels_map := {
		"population": "人口", "satisfaction": "滿意", "security": "治安", "environment": "環境",
		"traffic": "交通", "education": "教育", "healthcare": "醫療", "commercial_income": "商收",
		"industrial_income": "工收", "monthly_expense": "月支", "maintenance": "維護",
		"score_bonus": "評分", "job_attraction": "就業", "business_bonus": "商業", "industrial_bonus": "工業"
	}
	if not labels_map.has(effect_key):
		return ""
	var value := float(raw_value)
	var is_cost := effect_key in ["monthly_expense", "maintenance"]
	var arrow := "▼" if is_cost or value < 0.0 else "▲"
	var shown := absi(roundi(value * 100.0)) if effect_key in ["business_bonus", "industrial_bonus"] else absi(roundi(value))
	var suffix := "%" if effect_key in ["business_bonus", "industrial_bonus"] else ""
	return "%s %s%d%s" % [arrow, L10n.text(labels_map[effect_key]), shown, suffix]

func _visual_effects(source: Dictionary, limit: int = 3) -> String:
	var tokens: Array[String] = []
	var order := ["population", "satisfaction", "security", "environment", "traffic", "education", "healthcare", "commercial_income", "industrial_income", "business_bonus", "industrial_bonus", "job_attraction", "score_bonus", "monthly_expense", "maintenance"]
	for effect_key: String in order:
		if not source.has(effect_key):
			continue
		var token := _effect_token(effect_key, source[effect_key])
		if not token.is_empty():
			tokens.append(token)
		if tokens.size() >= limit:
			break
	return "  ".join(tokens)

func _building_visual_text(building_name: String, data: Dictionary) -> String:
	var effect_source := data.duplicate()
	effect_source.erase("maintenance")
	effect_source.erase("monthly_expense")
	var effects := _visual_effects(effect_source, 2)
	var desc := L10n.text(str(data.get("description", "")))
	return L10n.text("%s　基礎造價 $%d\n%s\n%s $%d/%s") % [
		L10n.text(building_name), int(data.get("cost", 0)),
		effects if not effects.is_empty() else desc,
		L10n.text("修"), int(data.get("maintenance", 0)), L10n.text("月")
	]


func _building_texture(building_name: String) -> Texture2D:
	var path := BuildingVisuals.asset_path(building_name)
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return _icon_texture("building_civic")


func _select_building(building_name: String) -> void:
	selected_building = building_name
	if vertical_slice_panel:
		vertical_slice_panel.set_selected_building(selected_building)
	if _has_approved_blueprint_for_selected():
		_set_hint("已選擇「%s」；請在藍圖頁確認總價後放置。" % selected_building, false)
	else:
		_set_hint("已選擇「%s」；請在藍圖頁調整規格並送審，核准後即可放置。" % selected_building, false)
	_update_ui()


func _select_building_from_catalog(building_name: String) -> void:
	_select_building(building_name)
	var overlay := _ensure_municipal_overlay()
	if overlay != null:
		overlay.open_page("blueprint")
	_set_hint("已進入「%s」設計；調整規格後，總價、工期與占地會立即更新。" % building_name, false)
	call_deferred("_refresh_onboarding_guide")


func _select_building_group(group_id: String) -> void:
	if not building_group_pages.has(group_id):
		return
	selected_building_group = group_id
	if building_family_tabs != null:
		for family_index in BUILDING_FAMILIES.size():
			if group_id in BUILDING_FAMILIES[family_index]["groups"]:
				building_family_tabs.current_tab = family_index
				break
	for page_id in building_group_pages.keys():
		var page: Control = building_group_pages[page_id]
		page.visible = str(page_id) == group_id
	for button_id in building_group_buttons.keys():
		var button: Button = building_group_buttons[button_id]
		_apply_button_style(button, "primary" if str(button_id) == group_id else "normal")
	call_deferred("_refresh_onboarding_guide")


func _on_building_family_changed(family_index: int) -> void:
	if family_index < 0 or family_index >= BUILDING_FAMILIES.size():
		return
	var group_ids: Array = BUILDING_FAMILIES[family_index]["groups"]
	if selected_building_group in group_ids:
		return
	if not group_ids.is_empty():
		_select_building_group(str(group_ids[0]))
	call_deferred("_refresh_onboarding_guide")


func _building_group_definition(group_id: String) -> Dictionary:
	for group in BUILDING_GROUPS:
		if str(group["id"]) == group_id:
			return group
	return {}

func _on_blueprint_submit_requested(payload: Dictionary) -> void:
	if vertical_slice == null:
		return
	_cancel_building_placement(false)
	var result: Dictionary = vertical_slice.submit_blueprint(payload)
	if bool(result.get("ok", false)):
		var onboarding_recorded := onboarding_action_router.record_blueprint_success(
			payload, result, vertical_slice.game_day()
		)
		var review: Dictionary = result.get("review", {})
		_set_hint("「%s」藍圖已送審，預計 %d 個遊戲日完成審核。" % [payload.get("building_name", selected_building), int(review.get("review_days", 0))], false)
		_add_announcement("「%s」藍圖已收件，預計 %d 個遊戲日完成審核。" % [payload.get("building_name", selected_building), int(review.get("review_days", 0))])
		if onboarding_recorded:
			call_deferred("_refresh_onboarding_guide")
	else:
		_set_hint("藍圖無法送審：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
	_sync_vertical_state()
	_update_ui()
	if bool(result.get("ok", false)):
		_autosave("action:blueprint_submitted")


func _on_blueprint_placement_requested(building_name: String) -> void:
	if building_name in TRANSPORT_SESSION_STATIONS:
		_on_transport_station_requested(building_name)
	else:
		_enter_building_placement(building_name)


func _on_blueprint_worker_count_changed(_count: int) -> void:
	if vertical_slice == null:
		return
	_update_scoped_municipal_pages(vertical_slice.get_view_model(selected_cell_index))


func _on_blueprint_design_changed(payload: Dictionary) -> void:
	if vertical_slice == null:
		return
	onboarding_action_router.note_blueprint_design(payload)
	_update_scoped_municipal_pages(vertical_slice.get_view_model(selected_cell_index))
	call_deferred("_refresh_onboarding_guide")


func _on_blueprint_library_selection_requested(building_name: String, library_id: String) -> void:
	if vertical_slice == null:
		return
	var result: Dictionary = vertical_slice.select_approved_blueprint(building_name, library_id)
	if bool(result.get("ok", false)):
		var entry: Dictionary = result.get("entry", {})
		_set_hint("已載入「%s」；這份藍圖可反覆套用興建。" % str(entry.get("title", "核准藍圖")), false)
		_sync_vertical_state()
		_update_ui()
		_autosave("action:blueprint_library_selected")
	else:
		_set_hint("無法載入藍圖：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)

func _on_tax_changed(value: float, tax_key: String) -> void:
	_set_fiscal_draft_value("tax", tax_key, int(value))

func _on_utility_fee_changed(value: float, fee_key: String) -> void:
	_set_fiscal_draft_value("utility", fee_key, int(value))

func _on_service_fee_changed(value: float, service_key: String) -> void:
	_set_fiscal_draft_value("service", service_key, int(value))

func _on_tax_input_submitted(text: String, tax_key: String) -> void:
	_commit_number_input("tax", tax_key, text)

func _on_tax_input_focus_exited(tax_key: String) -> void:
	_commit_number_input("tax", tax_key, tax_inputs[tax_key].text)

func _on_utility_input_submitted(text: String, fee_key: String) -> void:
	_commit_number_input("utility", fee_key, text)

func _on_utility_input_focus_exited(fee_key: String) -> void:
	_commit_number_input("utility", fee_key, utility_inputs[fee_key].text)

func _on_service_input_submitted(text: String, service_key: String) -> void:
	_commit_number_input("service", service_key, text)

func _on_service_input_focus_exited(service_key: String) -> void:
	_commit_number_input("service", service_key, service_inputs[service_key].text)

func _toggle_policy(enabled: bool, policy_name: String) -> void:
	if lower_council_stage != null:
		lower_council_stage.set_catalog_focus("policy_selected", policy_name)
	active_policies[policy_name] = enabled
	_record_major_event(
		"policy_enabled" if enabled else "policy_disabled",
		policy_name,
		"",
		"policy:%d:%s:%s" % [vertical_slice.game_day() if vertical_slice != null else 0, policy_name, str(enabled)],
		vertical_slice.game_day() if vertical_slice != null else -1
	)
	_set_hint("%s：%s" % [policy_name, "啟用" if enabled else "停用"], false)
	_recalculate_satisfaction()
	_recalculate_score()
	_update_ui()
	_select_governance_status("implemented" if enabled else "unimplemented")
	_autosave("action:policy_toggled")

func _submit_bill(bill_name: String) -> void:
	if lower_council_stage != null:
		lower_council_stage.set_catalog_focus("bill_selected", bill_name)
	var bill_id := _governance_bill_id(bill_name)
	var result: Dictionary = vertical_slice.submit_bill(bill_id, _vertical_city_context())
	if bool(result.get("ok", false)):
		_add_announcement("已送交兩院審查《%s》，下議院將先投票並進行一次辯論。" % bill_name)
		_set_hint("《%s》已送審。" % bill_name, false)
	else:
		_set_hint("法案無法送審：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
	_update_ui()
	if bool(result.get("ok", false)):
		if lower_council_stage != null:
			lower_council_stage.set_catalog_focus("bill_review", bill_name)
		_select_governance_status("review")
		_autosave("action:bill_submitted")
		call_deferred("_refresh_onboarding_guide")


func _on_lower_council_response_selected(response_id: String) -> void:
	if vertical_slice == null or lower_council_stage == null:
		return
	var preview: Dictionary = vertical_slice.preview_lower_house_response(response_id, _vertical_city_context())
	lower_council_stage.set_preview(preview)
	if not bool(preview.get("ok", false)):
		_set_hint("表決預覽無法建立：%s" % _vertical_error_text(str(preview.get("error", "unknown"))), true)
	call_deferred("_refresh_onboarding_guide")


func _on_lower_council_response_confirmed(response_id: String) -> void:
	if vertical_slice == null or lower_council_stage == null:
		return
	var result: Dictionary = vertical_slice.answer_lower_house_hearing(response_id, _vertical_city_context())
	if not bool(result.get("ok", false)):
		_set_hint("答詢無法送出：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		return
	var final_decision: Dictionary = result.get("decision", {})
	_lower_council_final_decision = final_decision.duplicate(true)
	_consume_vertical_events(vertical_slice.drain_ui_events())
	_update_ui()
	_set_hint("答詢已確認，下議院完成正式表決。", false)
	call_deferred("_refresh_onboarding_guide")


func _is_transport_map_action_active() -> bool:
	return map_action_mode in ["transport_infrastructure", "transport_route_stops"]


func _transport_planning_owns_map_input() -> bool:
	return _is_transport_map_action_active() or _is_transport_station_session_placement()


func _transport_session_snapshot() -> Dictionary:
	if vertical_slice == null or not vertical_slice.has_method("transport_planning_session_snapshot"):
		return {"state": "inactive"}
	return Dictionary(vertical_slice.call("transport_planning_session_snapshot")).duplicate(true)


func _transport_session_is_active(snapshot: Dictionary = {}) -> bool:
	var current := snapshot if not snapshot.is_empty() else _transport_session_snapshot()
	return str(current.get("state", "inactive")) not in ["inactive", "closed"]


func _transport_session_guideway(mode: String) -> String:
	return {
		"bus": "road",
		"metro": "metro_track",
		"train": "rail_track",
		"air": "runway",
	}.get(mode, "")


func _transport_session_supports_kind(mode: String, kind: String) -> bool:
	return TransportPlanningSessionScript.network_kind_matches_mode(mode, kind)


func _transport_session_station_count(snapshot: Dictionary) -> int:
	if str(snapshot.get("workflow", "")) == TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1:
		return Array(Dictionary(snapshot.get("route_draft", {})).get("station_placements", [])).size()
	var result := 0
	for ref_value: Variant in snapshot.get("station_refs", []):
		if ref_value is Dictionary and str((ref_value as Dictionary).get("status", "")) != "cancelled":
			result += 1
	return result


func _transport_session_is_route_package(snapshot: Dictionary = {}) -> bool:
	var current := snapshot if not snapshot.is_empty() else _transport_session_snapshot()
	return str(current.get("workflow", "")) == TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1


func _transport_session_has_station_draft(snapshot: Dictionary, anchor_tile_id: int) -> bool:
	for placement_value: Variant in Dictionary(snapshot.get("route_draft", {})).get("station_placements", []):
		if placement_value is Dictionary and int((placement_value as Dictionary).get("anchor_tile_id", -1)) == anchor_tile_id:
			return true
	return false


func _transport_session_has_active_jobs(snapshot: Dictionary) -> bool:
	for field_name: String in ["station_refs", "network_refs"]:
		for ref_value: Variant in snapshot.get(field_name, []):
			if ref_value is Dictionary and str((ref_value as Dictionary).get("status", "")) == "active":
				return true
	return false


func _is_transport_station_session_placement() -> bool:
	if not placement_mode_active:
		return false
	var snapshot := _transport_session_snapshot()
	return (
		str(snapshot.get("state", "")) == "station_placement"
		and str(snapshot.get("station_blueprint_name", "")) == placement_building_name
	)


func _on_transport_infrastructure_requested(kind: String, operation: String) -> void:
	if vertical_slice == null:
		return
	var normalized_kind := "rail_track" if kind == "heavy_rail" else kind
	var session := _transport_session_snapshot()
	if _transport_session_is_active(session):
		if str(session.get("state", "")) != "network_placement":
			_set_hint("目前交通規劃尚未進入路網步驟；請先使用「繼續規劃」。", true)
			return
		if operation not in ["build", "place"]:
			_set_hint("進行中的規劃只會新增同模式設施；要拆除請先結束本次規劃。", true)
			return
		if not _transport_session_supports_kind(str(session.get("mode", "")), normalized_kind):
			_set_hint("此設施與進行中的交通模式不相容。", true)
			return
	_cancel_building_placement(false)
	map_action_mode = "transport_infrastructure"
	transport_plan_kind = normalized_kind
	transport_plan_operation = "build" if operation in ["build", "place"] else "demolish"
	transport_plan_tiles.clear()
	transport_route_mode = ""
	transport_route_station_tiles.clear()
	_pending_terrain_tile = -1
	_close_building_context()
	_hide_npc_dialogue()
	if municipal_overlay != null and municipal_overlay.is_open():
		municipal_overlay.close_overlay()
	_sync_placement_banner()
	_update_transport_runtime()
	_sync_map_interaction_for_ui()
	_set_hint("請依序點選相鄰地格規劃%s；確認前不會扣款。" % _transport_kind_label(transport_plan_kind), false)


func _on_transport_station_requested(building_name: String) -> void:
	if not buildings.has(building_name):
		_set_hint("找不到交通站點「%s」。" % building_name, true)
		return
	_select_building(building_name)
	if _has_approved_blueprint_for_selected():
		var session := _transport_session_snapshot()
		if _transport_session_is_active(session):
			if str(session.get("station_blueprint_name", "")) != building_name:
				_set_hint("已有進行中的「%s」規劃；請先結束規劃再更換站點。" % str(session.get("station_blueprint_name", "交通站點")), true)
				return
			if str(session.get("state", "")) == "paused":
				var resumed: Dictionary = vertical_slice.call("resume_transport_planning_session")
				if not bool(resumed.get("ok", false)):
					_set_hint("無法繼續交通規劃：%s" % _vertical_error_text(str(resumed.get("error", "unknown"))), true)
					return
				session = resumed.get("session", {})
			if str(session.get("state", "")) != "station_placement":
				_set_hint("這個規劃已進入後續步驟，請在交通規劃頁繼續。", true)
				_open_transport_planning()
				return
		else:
			var begun: Dictionary = vertical_slice.call(
				"begin_transport_planning_session", building_name,
				TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1
			)
			if not bool(begun.get("ok", false)):
				_set_hint("無法開始交通規劃：%s" % _vertical_error_text(str(begun.get("error", "unknown"))), true)
				return
		_enter_building_placement(building_name)
		_set_hint("已開始連續放置「%s」；完成一站後可直接選擇下一站。" % building_name, false)
		return
	var overlay := _ensure_municipal_overlay()
	if overlay != null:
		overlay.open_page("blueprint")
	_set_hint("請先送審「%s」藍圖；核准並完成站點施工後才能建立路線。" % building_name, false)


func _on_transport_route_planning_requested(mode: String, fleet_size: int, headway_minutes: int, fare: int) -> void:
	var session := _transport_session_snapshot()
	if _transport_session_is_active(session):
		if str(session.get("state", "")) != "route_edit" or str(session.get("mode", "")) != mode:
			_set_hint("目前規劃尚未進入這個模式的路線步驟。", true)
			return
	_cancel_building_placement(false)
	map_action_mode = "transport_route_stops"
	transport_route_mode = mode
	transport_route_fleet_size = clampi(fleet_size, 1, 40)
	transport_route_headway_minutes = clampi(headway_minutes, 1, 60)
	transport_route_fare = clampi(fare, 0, 500)
	transport_route_station_tiles.clear()
	transport_plan_kind = ""
	transport_plan_operation = ""
	transport_plan_tiles.clear()
	_close_building_context()
	_hide_npc_dialogue()
	if municipal_overlay != null and municipal_overlay.is_open():
		municipal_overlay.close_overlay()
	_sync_placement_banner()
	_update_transport_runtime()
	_sync_map_interaction_for_ui()
	_set_hint("請依營運順序點選%s；確認後才會驗證完整路網與車隊。" % _transport_route_label(mode), false)


func _on_transport_session_continue_requested() -> void:
	if vertical_slice == null:
		return
	var session := _transport_session_snapshot()
	var state := str(session.get("state", "inactive"))
	var resumed_from_pause := state == "paused"
	if state == "paused":
		var resumed: Dictionary = vertical_slice.call("resume_transport_planning_session")
		if not bool(resumed.get("ok", false)):
			_set_hint("無法繼續交通規劃：%s" % _vertical_error_text(str(resumed.get("error", "unknown"))), true)
			return
		session = resumed.get("session", {})
		state = str(session.get("state", "inactive"))
	match state:
		"station_placement":
			_enter_building_placement(str(session.get("station_blueprint_name", "")))
		"network_placement":
			if resumed_from_pause:
				_resume_transport_session_network_map_action(session)
			else:
				_advance_transport_session_to_route()
		"route_edit":
			var settings: Dictionary = transport_planning_panel.debug_snapshot() if transport_planning_panel != null else {}
			if _transport_session_is_route_package(session):
				_confirm_transport_session_package(
					int(settings.get("fleet_size", 2)),
					int(settings.get("headway_minutes", 10)),
					int(settings.get("fare", 30))
				)
				return
			_on_transport_route_planning_requested(
				str(session.get("mode", "")),
				int(settings.get("fleet_size", 2)),
				int(settings.get("headway_minutes", 10)),
				int(settings.get("fare", 30))
			)
			if resumed_from_pause:
				var route_draft: Dictionary = session.get("route_draft", {})
				transport_route_station_tiles.clear()
				for tile_value: Variant in route_draft.get("station_tile_ids", []):
					var tile_id := int(tile_value)
					if tile_id >= 0 and tile_id < city_grid.size() and not transport_route_station_tiles.has(tile_id):
						transport_route_station_tiles.append(tile_id)
				_sync_placement_banner()
				_update_transport_runtime()
		"waiting_construction":
			_set_hint("工程完工後會自動回到同一個規劃步驟。", false)
		"materialized":
			_set_hint("這筆交通規劃已完成；可明確選擇「結束規劃」。", false)
	_refresh_transport_planning_panel()


func _resume_transport_session_network_map_action(session: Dictionary) -> void:
	var draft: Dictionary = session.get("network_draft", {})
	var kind := str(draft.get("kind", _transport_session_guideway(str(session.get("mode", "")))))
	_on_transport_infrastructure_requested(kind, "build")
	for tile_value: Variant in draft.get("tile_ids", []):
		var tile_id := int(tile_value)
		if tile_id >= 0 and tile_id < city_grid.size() and not transport_plan_tiles.has(tile_id):
			transport_plan_tiles.append(tile_id)
	_sync_placement_banner()
	_update_transport_runtime()


func _on_transport_session_close_requested() -> void:
	if vertical_slice == null or not _transport_session_is_active():
		return
	var result: Dictionary = vertical_slice.call("close_transport_planning_session", "player_finished_ui_flow")
	if not bool(result.get("ok", false)):
		_set_hint("無法結束交通規劃：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		return
	_clear_building_placement_ui()
	_clear_transport_map_action()
	_refresh_transport_planning_panel()
	_set_hint("已結束本次交通規劃；已開工的工程仍由施工系統持續處理。", false)
	_autosave("action:transport_planning_session_closed")


func _on_transport_route_toggle_requested(route_id: String, enabled: bool) -> void:
	if vertical_slice == null or not vertical_slice.has_method("set_transport_route_enabled"):
		return
	var result: Dictionary = vertical_slice.call("set_transport_route_enabled", route_id, enabled, city_grid)
	if bool(result.get("ok", false)):
		_set_hint("路線已%s；只有營運狀態才會派出載具。" % ("啟用" if enabled else "停駛"), false)
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_update_ui()
		_autosave("action:transport_route_toggled")
	else:
		_set_hint("無法變更路線：%s" % _vertical_error_text(str(result.get("error", "transport_route_invalid"))), true)
	_refresh_transport_planning_panel()


func _on_transport_route_delete_requested(route_id: String) -> void:
	if vertical_slice == null or not vertical_slice.has_method("delete_transport_route"):
		return
	var result: Dictionary = vertical_slice.call("delete_transport_route", route_id)
	if bool(result.get("ok", false)):
		_set_hint("路線已刪除；其基礎設施仍保留供其他路線使用。", false)
		_update_ui()
		_autosave("action:transport_route_deleted")
	else:
		_set_hint("無法刪除路線：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)


func _handle_transport_tile_pressed(index: int) -> void:
	if not _is_tile_inside_hud_safe_area(index):
		_set_hint("此地格位於頂部資訊列安全區內，請選擇下方地格。", true)
		return
	if map_action_mode == "transport_route_stops":
		_handle_transport_station_tile(index)
		return
	if map_action_mode != "transport_infrastructure":
		return
	if transport_plan_operation == "demolish":
		_handle_transport_demolition_tile(index)
		return
	var is_path_kind := transport_plan_kind in ["road", "metro_track", "rail_track", "runway", "taxiway"]
	if not transport_plan_tiles.is_empty() and index == transport_plan_tiles.back():
		_pending_terrain_tile = -1
		transport_plan_tiles.pop_back()
		_sync_placement_banner()
		_update_transport_runtime()
		return
	if index in transport_plan_tiles:
		_pending_terrain_tile = -1
		_sync_placement_banner()
		_set_hint("同一個地格不能在同一工程中重複選取。", true)
		return
	if is_path_kind and not transport_plan_tiles.is_empty():
		var pair := _transport_direction_pair(transport_plan_tiles.back(), index)
		if pair.is_empty():
			_pending_terrain_tile = -1
			_sync_placement_banner()
			_set_hint("路廊必須逐格相鄰連接，不能跨越空地。", true)
			return
	if not is_path_kind and not transport_plan_tiles.is_empty():
		transport_plan_tiles.clear()
	var candidate := transport_plan_tiles.duplicate()
	candidate.append(index)
	var quote := _transport_project_quote(candidate)
	if not bool(quote.get("ok", false)):
		var error := _transport_quote_error(quote)
		if error == "terrain_not_flat":
			_pending_terrain_tile = index
			selected_cell_index = index
			_sync_placement_banner()
			_set_hint("此地格不是平坦地形；必須先整平才能興建交通設施。", true)
			return
		_pending_terrain_tile = -1
		_sync_placement_banner()
		_set_hint("此路網規劃不可用：%s" % _vertical_error_text(error), true)
		return
	_pending_terrain_tile = -1
	transport_plan_tiles = candidate
	_sync_placement_banner()
	_update_transport_runtime()
	_set_hint("已選 %d 格｜目前工程估價 $%d。" % [
		transport_plan_tiles.size(),
		_transport_visible_plan_cost(quote, transport_plan_tiles.size(), _transport_session_snapshot()),
	], false)
	call_deferred("_refresh_onboarding_guide")


func _handle_transport_demolition_tile(index: int) -> void:
	_pending_terrain_tile = -1
	if index in transport_plan_tiles:
		transport_plan_tiles.clear()
		_sync_placement_banner()
		_update_transport_runtime()
		_set_hint("已取消這一段%s的拆除選取。" % _transport_kind_label(transport_plan_kind), false)
		return
	var quote := _transport_project_quote([index])
	if not bool(quote.get("ok", false)):
		transport_plan_tiles.clear()
		_sync_placement_banner()
		_update_transport_runtime()
		_set_hint("此格沒有可拆除的%s：%s" % [_transport_kind_label(transport_plan_kind), _vertical_error_text(_transport_quote_error(quote))], true)
		return
	var resolved_tiles: Array[int] = []
	for tile_variant: Variant in quote.get("tile_indices", []):
		var tile_id := int(tile_variant)
		if tile_id >= 0 and not resolved_tiles.has(tile_id):
			resolved_tiles.append(tile_id)
	resolved_tiles.sort()
	transport_plan_tiles = resolved_tiles
	_sync_placement_banner()
	_update_transport_runtime()
	_set_hint("已選取完整%s區段，共 %d 格；確認後將整段拆除並重新驗證路線。" % [_transport_kind_label(transport_plan_kind), transport_plan_tiles.size()], false)


func _handle_transport_station_tile(index: int) -> void:
	var expected := _transport_station_for_mode(transport_route_mode)
	if index < 0 or index >= city_grid.size() or city_grid[index] != expected:
		_set_hint("%s只能選擇已完工的「%s」。" % [_transport_route_label(transport_route_mode), expected], true)
		return
	if not transport_route_station_tiles.is_empty() and index == transport_route_station_tiles.back():
		transport_route_station_tiles.pop_back()
	elif index in transport_route_station_tiles:
		_set_hint("同一路線不可重複加入同一站點。", true)
		return
	else:
		transport_route_station_tiles.append(index)
	_sync_placement_banner()
	_update_transport_runtime()
	_set_hint("已依序選擇 %d 個站點。" % transport_route_station_tiles.size(), false)
	call_deferred("_refresh_onboarding_guide")


func _transport_project_quote(tile_ids: Array[int]) -> Dictionary:
	if vertical_slice == null or not vertical_slice.has_method("transport_project_quote"):
		return {"ok": false, "error": "transport_system_unavailable"}
	var workers := int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel != null else 5
	return vertical_slice.call(
		"transport_project_quote",
		transport_plan_kind,
		transport_plan_operation,
		tile_ids,
		workers,
		city_grid
	)


func _transport_quote_error(quote: Dictionary) -> String:
	for issue_variant: Variant in quote.get("issues", []):
		var issue := str(issue_variant)
		if issue.begins_with("terrain_not_flat:"):
			return "terrain_not_flat"
		if issue.begins_with("tile_occupied:"):
			return "tile_occupied"
		if issue.begins_with("tile_under_construction:"):
			return "transport_construction_conflict"
		if issue.begins_with("non_cardinal_segment_path:"):
			return "transport_path_not_contiguous"
		if issue.begins_with("incompatible_segment_overlap:"):
			return "transport_overlap_invalid"
	return str(quote.get("error", "transport_plan_invalid"))


func _confirm_transport_map_plan() -> void:
	if _is_transport_station_session_placement():
		_advance_transport_station_session()
	elif map_action_mode == "transport_infrastructure":
		_confirm_transport_infrastructure_plan()
	elif map_action_mode == "transport_route_stops":
		_confirm_transport_route_plan()


func _confirm_transport_infrastructure_plan() -> void:
	if vertical_slice == null or transport_plan_tiles.is_empty() or not vertical_slice.has_method("start_transport_project"):
		return
	var workers := int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel != null else 5
	var session := _transport_session_snapshot()
	var use_session := (
		str(session.get("state", "")) == "network_placement"
		and transport_plan_operation == "build"
		and _transport_session_supports_kind(str(session.get("mode", "")), transport_plan_kind)
	)
	if use_session and _transport_session_is_route_package(session):
		var drafted: Dictionary = vertical_slice.call(
			"draft_transport_session_network", transport_plan_kind, transport_plan_tiles, workers
		)
		if not bool(drafted.get("ok", false)):
			_set_hint("路線草案無法保存：%s" % _vertical_error_text(str(drafted.get("error", "unknown"))), true)
			return
		var selected_count := transport_plan_tiles.size()
		_clear_transport_map_action()
		_advance_transport_session_to_route()
		_set_hint("已完成 %d 格連續路線草案；請確認總工程費、維護費與營運設定後一次開工。" % selected_count, false)
		return
	var method_name := "start_transport_session_network_project" if use_session else "start_transport_project"
	var result: Dictionary
	if use_session:
		result = vertical_slice.call(method_name, transport_plan_kind, transport_plan_tiles, workers, city_grid)
	else:
		result = vertical_slice.call(method_name, transport_plan_kind, transport_plan_operation, transport_plan_tiles, workers, city_grid)
	if not bool(result.get("ok", false)):
		_set_hint("交通工程無法開工：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		_refresh_transport_planning_panel()
		return
	var selected_count := transport_plan_tiles.size()
	var kind_label := _transport_kind_label(transport_plan_kind)
	_clear_transport_map_action()
	_consume_vertical_events(vertical_slice.drain_ui_events())
	debug_sync_npc_navigation_obstacles()
	if npc_map_controller != null:
		npc_map_controller.repath_all()
	_update_ui()
	if use_session:
		_open_transport_planning()
		_set_hint("%s工程已加入同一規劃，共 %d 格；可繼續選擇同模式設施，或按「下一步：規劃路線」。" % [kind_label, selected_count], false)
	else:
		_set_hint("%s工程已開工，共 %d 格；完工且路網驗證通過前不會生成載具。" % [kind_label, selected_count], false)
	_autosave("action:transport_project_started")


func _confirm_transport_route_plan() -> void:
	if vertical_slice == null or not vertical_slice.has_method("create_transport_route"):
		return
	var required_stops := 1 if transport_route_mode == "air" else 2
	if transport_route_station_tiles.size() < required_stops:
		_set_hint("%s至少需要 %d 個已完工站點。" % [_transport_route_label(transport_route_mode), required_stops], true)
		return
	var session := _transport_session_snapshot()
	var use_session := str(session.get("state", "")) == "route_edit" and str(session.get("mode", "")) == transport_route_mode
	var method_name := "materialize_transport_session_route" if use_session else "create_transport_route"
	var result: Dictionary
	if use_session:
		result = vertical_slice.call(
			method_name,
			transport_route_station_tiles,
			transport_route_fleet_size,
			transport_route_headway_minutes,
			transport_route_fare,
			city_grid
		)
	else:
		result = vertical_slice.call(
			method_name,
			transport_route_mode,
			transport_route_station_tiles,
			transport_route_fleet_size,
			transport_route_headway_minutes,
			transport_route_fare,
			city_grid
		)
	if not bool(result.get("ok", false)) or not bool(result.get("valid", true)):
		_set_hint("路線無法啟用：%s" % _vertical_error_text(str(result.get("error", "transport_route_invalid"))), true)
		_refresh_transport_planning_panel()
		return
	var route: Dictionary = result.get("route", {})
	var route_name := str(route.get("name", _transport_route_label(transport_route_mode)))
	_clear_transport_map_action()
	_consume_vertical_events(vertical_slice.drain_ui_events())
	_update_ui()
	if use_session:
		_open_transport_planning()
		_set_hint("「%s」已在同一規劃中完成；確認摘要後可明確結束規劃。" % route_name, false)
	else:
		_set_hint("「%s」已建立並通過連通驗證；載具只沿這條權威路徑運行。" % route_name, false)
	_autosave("action:transport_route_created")


func _advance_transport_station_session() -> void:
	if vertical_slice == null:
		return
	var session := _transport_session_snapshot()
	var mode := str(session.get("mode", ""))
	var minimum_stops := 1 if mode == "air" else 2
	if str(session.get("state", "")) != "station_placement" or _transport_session_station_count(session) < minimum_stops:
		_set_hint("至少需要放置 %d 座同型站點才能規劃路網。" % minimum_stops, true)
		return
	var guideway_kind := _transport_session_guideway(mode)
	var begun: Dictionary = vertical_slice.call("begin_transport_session_network_placement", guideway_kind, {"kind": guideway_kind})
	if not bool(begun.get("ok", false)):
		_set_hint("無法進入路網規劃：%s" % _vertical_error_text(str(begun.get("error", "unknown"))), true)
		return
	if _transport_session_has_active_jobs(begun.get("session", {})):
		var waiting: Dictionary = vertical_slice.call("wait_for_transport_session_construction", "network_placement")
		if not bool(waiting.get("ok", false)):
			_set_hint("無法等待站點工程：%s" % _vertical_error_text(str(waiting.get("error", "unknown"))), true)
			return
	_clear_building_placement_ui()
	_open_transport_planning()
	_refresh_transport_planning_panel()
	_set_hint("已保留同一規劃；站點完工後會自動進入路網步驟。", false)
	_autosave("action:transport_session_station_phase_completed")


func _advance_transport_session_to_route() -> void:
	if vertical_slice == null:
		return
	var session := _transport_session_snapshot()
	if str(session.get("state", "")) != "network_placement":
		return
	var settings: Dictionary = transport_planning_panel.debug_snapshot() if transport_planning_panel != null else {}
	var route_draft := {
		"fleet_size": int(settings.get("fleet_size", 2)),
		"headway_minutes": int(settings.get("headway_minutes", 10)),
		"fare": int(settings.get("fare", 30)),
	}
	var result: Dictionary = vertical_slice.call("begin_transport_session_route_edit", route_draft)
	if not bool(result.get("ok", false)):
		_set_hint("尚無法進入路線規劃：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		_refresh_transport_planning_panel()
		return
	if _transport_session_is_route_package(result.get("session", {})):
		_set_hint("站點與路線仍是草案；核對總包估價後才會一次扣款並開始施工。", false)
	elif _transport_session_has_active_jobs(result.get("session", {})):
		var waiting: Dictionary = vertical_slice.call("wait_for_transport_session_construction", "route_edit")
		if not bool(waiting.get("ok", false)):
			_set_hint("無法等待路網工程：%s" % _vertical_error_text(str(waiting.get("error", "unknown"))), true)
			return
		_set_hint("已進入路線步驟；路網完工後會自動開放站序規劃。", false)
	else:
		_set_hint("路網階段已完成，現在可依序選擇站點。", false)
	_open_transport_planning()
	_refresh_transport_planning_panel()
	_autosave("action:transport_session_route_phase_started")


func _confirm_transport_session_package(fleet_size: int, headway_minutes: int, fare: int) -> void:
	if vertical_slice == null:
		return
	var settings_result: Dictionary = vertical_slice.call(
		"update_transport_session_route_settings", fleet_size, headway_minutes, fare
	)
	if not bool(settings_result.get("ok", false)):
		_set_hint("無法更新總包營運設定：%s" % _vertical_error_text(str(settings_result.get("error", "unknown"))), true)
		return
	var quote: Dictionary = vertical_slice.call("transport_session_package_quote", city_grid)
	if not bool(quote.get("ok", false)):
		_set_hint("交通總包估價失敗：%s" % _vertical_error_text(str(quote.get("error", "unknown"))), true)
		_refresh_transport_planning_panel()
		return
	var result: Dictionary = vertical_slice.call("start_transport_session_package", city_grid)
	if not bool(result.get("ok", false)):
		_set_hint("交通總包無法開工：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		_refresh_transport_planning_panel()
		return
	var onboarding_recorded := onboarding_action_router.record_route_package_success(
		result, vertical_slice.game_day()
	)
	_consume_vertical_events(vertical_slice.drain_ui_events(), false)
	debug_sync_npc_navigation_obstacles()
	_update_ui()
	_refresh_transport_planning_panel()
	_set_hint("交通總包已一次扣款 $%d；站點與 %d 格路線開始施工，完工後會自動驗證並啟用路線。" % [
		int(result.get("total_cost", 0)), int(quote.get("route_tile_count", 0)),
	], false)
	_autosave("action:transport_route_package_started")
	if onboarding_recorded:
		call_deferred("_refresh_onboarding_guide")


func _cancel_transport_map_action(show_feedback: bool) -> void:
	var was_active := _is_transport_map_action_active()
	var session := _transport_session_snapshot()
	var session_state := str(session.get("state", ""))
	if was_active and session_state in ["network_placement", "route_edit"]:
		var paused: Dictionary = vertical_slice.call("pause_transport_planning_session")
		if not bool(paused.get("ok", false)):
			_set_hint("無法暫停交通規劃：%s" % _vertical_error_text(str(paused.get("error", "unknown"))), true)
			return
	_clear_transport_map_action()
	if show_feedback and was_active:
		_set_hint("已暫停地圖規劃；進度與草案仍保留，可從交通規劃頁繼續。" if session_state in ["network_placement", "route_edit"] else "已取消交通規劃；沒有扣除任何費用，也沒有生成載具。", false)


func _clear_transport_map_action() -> void:
	map_action_mode = "inspect"
	transport_plan_kind = ""
	transport_plan_operation = ""
	transport_plan_tiles.clear()
	transport_route_mode = ""
	transport_route_station_tiles.clear()
	_pending_terrain_tile = -1
	_sync_placement_banner()
	_update_transport_runtime()
	_sync_map_interaction_for_ui()


func _transport_station_for_mode(mode: String) -> String:
	return {"bus": "公車站", "metro": "捷運站", "train": "火車站", "air": "機場"}.get(mode, "")


func _transport_route_label(mode: String) -> String:
	return {"bus": "公車路線", "metro": "捷運路線", "train": "火車路線", "air": "航空路線"}.get(mode, "交通路線")


func _transport_kind_label(kind: String) -> String:
	return {
		"road": "道路", "metro_track": "捷運軌道", "rail_track": "重型鐵路",
		"runway": "跑道", "taxiway": "滑行道", "bus_depot": "公車車庫",
		"metro_depot": "捷運機廠", "rail_depot": "鐵路機廠", "rail_signal": "鐵路號誌",
	}.get(kind, "交通設施")


func _transport_project_kind(project: Dictionary) -> String:
	var plan: Dictionary = project.get("plan", {})
	var segments: Array = plan.get("segments", [])
	if not segments.is_empty() and segments[0] is Dictionary:
		return str(Dictionary(segments[0]).get("kind", ""))
	var facilities: Array = plan.get("facilities", [])
	if not facilities.is_empty() and facilities[0] is Dictionary:
		return str(Dictionary(facilities[0]).get("kind", ""))
	for segment_id_variant: Variant in plan.get("segment_ids", []):
		if vertical_slice != null and vertical_slice.transport != null:
			var segment: Dictionary = vertical_slice.transport.segments.get(str(segment_id_variant), {})
			if not segment.is_empty():
				return str(segment.get("kind", ""))
	for facility_id_variant: Variant in plan.get("facility_ids", []):
		if vertical_slice != null and vertical_slice.transport != null:
			var facility: Dictionary = vertical_slice.transport.facilities.get(str(facility_id_variant), {})
			if not facility.is_empty():
				return str(facility.get("kind", ""))
	return ""


func _refresh_transport_planning_panel() -> void:
	if transport_planning_panel == null:
		return
	var snapshot: Dictionary = {"planning_unlocked": true, "routes": []}
	if vertical_slice != null and vertical_slice.has_method("transport_view_model"):
		snapshot = vertical_slice.call("transport_view_model", city_grid)
	if vertical_slice != null and vertical_slice.has_method("transport_planning_session_snapshot"):
		snapshot["planning_session"] = vertical_slice.call("transport_planning_session_snapshot")
	transport_planning_panel.set_view_model(snapshot)

func _on_grid_pressed(index: int) -> void:
	if _modal_pointer_guard_blocks_grid_intent():
		return
	if index < 0 or index >= city_grid.size():
		return
	if _is_transport_map_action_active():
		_handle_transport_tile_pressed(index)
		return
	if placement_mode_active and not _is_tile_inside_hud_safe_area(index):
		_set_hint("此地格位於頂部資訊列安全區內，請選擇下方空地。", true)
		return
	var active_job: Dictionary = vertical_slice.active_construction_for_tile(index) if vertical_slice != null else {}
	var building_record: Dictionary = vertical_slice.get_building_by_tile(index) if vertical_slice != null else {}
	if (
		placement_mode_active
		and not building_record.is_empty()
		and active_job.is_empty()
		and _is_transport_station_session_placement()
		and _transport_session_is_route_package()
	):
		var station_anchor := int(building_record.get("anchor_tile_id", building_record.get("tile_index", index)))
		var planning_snapshot := _transport_session_snapshot()
		if _transport_session_has_station_draft(planning_snapshot, station_anchor):
			var removed: Dictionary = vertical_slice.call("remove_transport_session_station_draft", station_anchor)
			if bool(removed.get("ok", false)):
				_sync_placement_banner()
				_update_transport_runtime()
				_refresh_transport_planning_panel()
				_set_hint("已取消沿用這座既有站點；既有建築與路網權威不受影響。", false)
			return
		var reused: Dictionary = vertical_slice.call("reuse_transport_session_station", station_anchor)
		if bool(reused.get("ok", false)):
			_sync_placement_banner()
			_update_transport_runtime()
			_refresh_transport_planning_panel()
			_set_hint("已沿用這座完工站點；不重複施工、不重複計費。", false)
		else:
			_set_hint(_vertical_error_text(str(reused.get("error", "transport_station_not_found"))), true)
		return
	if placement_mode_active and (not building_record.is_empty() or not active_job.is_empty()):
		_set_hint("此地格已有建築或工程，請選擇其他空地。", true)
		return
	if not active_job.is_empty():
		var footprint_view: Dictionary = vertical_slice.footprint_cell_view(index) if vertical_slice != null else {}
		selected_cell_index = (
			int(footprint_view.get("owner_anchor_tile_id", index))
			if str(footprint_view.get("kind", "")) == "construction"
			else index
		)
		_hide_npc_dialogue()
		_close_building_context()
		_set_hint(_construction_job_player_text(active_job), false)
		_update_ui()
		return
	if not building_record.is_empty():
		_select_built_cell(index)
		return
	if vertical_slice == null:
		return
	var transport_tile_state := _transport_tile_visual_state(index)
	if not placement_mode_active and _transport_tile_has_player_content(transport_tile_state):
		selected_cell_index = index
		_close_building_context()
		_hide_npc_dialogue()
		_set_hint(_transport_tile_player_text(transport_tile_state), false)
		_update_ui()
		_update_tile_visual(index, city_grid[index])
		return
	if not placement_mode_active:
		selected_cell_index = -1
		_close_building_context()
		_hide_npc_dialogue()
		_update_ui()
		return
	var planning_snapshot := _transport_session_snapshot()
	if (
		_is_transport_station_session_placement()
		and _transport_session_is_route_package(planning_snapshot)
		and _transport_session_has_station_draft(planning_snapshot, index)
	):
		var removed: Dictionary = vertical_slice.call("remove_transport_session_station_draft", index)
		if bool(removed.get("ok", false)):
			_sync_placement_banner()
			_update_transport_runtime()
			_refresh_transport_planning_panel()
			_set_hint("已移除這座站點草案；確認總包前仍未扣款。", false)
		return
	var terrain = _terrain_map()
	if (
		_is_transport_station_session_placement()
		and terrain != null
		and not terrain.is_buildable(index)
	):
		selected_cell_index = index
		_pending_terrain_tile = index
		_pending_construction_tile = -1
		_hide_npc_dialogue()
		_sync_placement_banner()
		_update_tile_visual(index, city_grid[index])
		var terrain_state: Dictionary = terrain.tile_state(index)
		var terrain_label := str(TERRAIN_LABELS.get(str(terrain_state.get("effective_kind", "")), "非平坦地形"))
		var flatten_quote: Dictionary = vertical_slice.terrain_flatten_quote(index)
		_set_hint("%s不可興建；整地工程預估 $%d、%d 個遊戲日。" % [
			terrain_label,
			int(flatten_quote.get("total_cost", flatten_quote.get("cost", 0))),
			int(flatten_quote.get("duration_days", 0)),
		], true)
		return
	_pending_terrain_tile = -1
	var workers: int = int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel else 5
	var quote: Dictionary = vertical_slice.placement_footprint_quote(
		placement_building_name,
		index,
		workers,
		placement_rotation_quarter_turns_ccw
	)
	if not bool(quote.get("ok", false)):
		var placement_error := str(quote.get("error", "unknown"))
		if placement_error in ["blueprint_not_found", "approved_blueprint_required"]:
			_set_hint("目前沒有可放置的核准藍圖。", true)
			_cancel_building_placement(false)
			_update_ui()
			return
		if placement_error == "terrain_not_flat" and str(quote.get("building_terrain_label", "")) == "non_buildable":
			_set_hint("建築占格包含不可興建地格；請更換位置或按「逆時針旋轉 90°」後再試。", true)
			return
		_set_hint("此處無法完整放置「%s」：%s" % [
			placement_building_name,
			_vertical_error_text(placement_error),
		], true)
		return
	if str(quote.get("status", "")) != "approved":
		_set_hint("目前沒有可放置的核准藍圖。", true)
		_cancel_building_placement(false)
		_update_ui()
		return
	if not bool(quote.get("can_afford", false)):
		if not (_is_transport_station_session_placement() and _transport_session_is_route_package()):
			_set_hint("城市公庫不足：本工程需要 $%d。" % int(quote.get("total_cost", 0)), true)
			return
	if _is_transport_station_session_placement() and _transport_session_is_route_package():
		var drafted: Dictionary = vertical_slice.call("draft_transport_session_station", index, workers)
		if not bool(drafted.get("ok", false)):
			_set_hint("站點草案無法保存：%s" % _vertical_error_text(str(drafted.get("error", "unknown"))), true)
			return
		selected_cell_index = index
		_placement_preview_anchor = -1
		_placement_preview.clear()
		_sync_placement_banner()
		_update_transport_runtime()
		_refresh_transport_planning_panel()
		_set_hint("已加入第 %d 座「%s」草案；確認總包前不扣款、不建立工程。" % [
			_transport_session_station_count(drafted.get("session", {})), placement_building_name,
		], false)
		_autosave("action:transport_session_station_drafted")
		call_deferred("_refresh_onboarding_guide")
		return
	_pending_construction_tile = index
	_pending_construction_workers = workers
	_pending_construction_rotation_quarter_turns_ccw = placement_rotation_quarter_turns_ccw
	_hide_npc_dialogue()
	if construction_confirmation != null:
		_set_map_interaction_enabled(false)
		construction_confirmation.open(placement_building_name, index, quote, funds)
		call_deferred("_refresh_onboarding_guide")


func _enter_building_placement(building_name: String) -> void:
	if vertical_slice == null or not buildings.has(building_name):
		return
	_cancel_transport_map_action(false)
	selected_building = building_name
	if vertical_slice_panel != null:
		vertical_slice_panel.set_selected_building(building_name)
	if not _has_approved_blueprint_for_selected():
		_set_hint("「%s」目前沒有核准藍圖。" % building_name, true)
		return
	placement_mode_active = true
	placement_building_name = building_name
	placement_rotation_quarter_turns_ccw = 0
	_placement_preview_anchor = -1
	_placement_preview.clear()
	_pending_construction_tile = -1
	_pending_terrain_tile = -1
	_hide_npc_dialogue()
	_close_building_context()
	if municipal_overlay != null and municipal_overlay.is_open():
		municipal_overlay.close_overlay()
	if settings_overlay != null and settings_overlay.is_open():
		settings_overlay.close()
	_sync_placement_banner()
	_update_ui()
	call_deferred("_refresh_onboarding_guide")


func _cancel_active_map_action(show_feedback: bool = true) -> void:
	if _is_transport_map_action_active():
		_cancel_transport_map_action(show_feedback)
	else:
		_cancel_building_placement(show_feedback)


func _cancel_building_placement(show_feedback: bool) -> void:
	var was_active := placement_mode_active
	var session_state := str(_transport_session_snapshot().get("state", ""))
	var paused_session := was_active and _is_transport_station_session_placement()
	if paused_session:
		var paused: Dictionary = vertical_slice.call("pause_transport_planning_session")
		if not bool(paused.get("ok", false)):
			_set_hint("無法暫停交通規劃：%s" % _vertical_error_text(str(paused.get("error", "unknown"))), true)
			return
	_clear_building_placement_ui()
	if show_feedback and was_active:
		_set_hint("已暫停站點放置；規劃進度仍保留。" if paused_session or session_state == "paused" else "已取消建築放置；沒有扣除任何費用。", false)


func _clear_building_placement_ui() -> void:
	placement_mode_active = false
	placement_building_name = ""
	placement_rotation_quarter_turns_ccw = 0
	_placement_preview_anchor = -1
	_placement_preview.clear()
	_pending_construction_tile = -1
	_pending_construction_rotation_quarter_turns_ccw = 0
	_pending_terrain_tile = -1
	if construction_confirmation != null and construction_confirmation.is_open():
		construction_confirmation.close()
	_sync_placement_banner()
	if is_node_ready() and grid_buttons.size() == CELL_COUNT:
		for index in CELL_COUNT:
			_update_tile_visual(index, city_grid[index])
	_sync_map_interaction_for_ui()


func _refresh_placement_preview(index: int) -> void:
	if not placement_mode_active or vertical_slice == null:
		return
	if index < 0 or index >= city_grid.size():
		return
	var workers: int = int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel else 5
	var preview: Dictionary = vertical_slice.placement_footprint_preview(
		placement_building_name,
		index,
		workers,
		placement_rotation_quarter_turns_ccw
	)
	var all_inside_hud_safe_area := true
	for tile_variant: Variant in preview.get("occupied_tile_ids", []):
		if not _is_tile_inside_hud_safe_area(int(tile_variant)):
			all_inside_hud_safe_area = false
			break
	if not _is_tile_inside_hud_safe_area(index):
		all_inside_hud_safe_area = false
	preview["can_place"] = bool(preview.get("can_place", false)) and all_inside_hud_safe_area
	if not all_inside_hud_safe_area:
		preview["error"] = "hud_safe_area"
	var previous_anchor := _placement_preview_anchor
	_placement_preview_anchor = index
	_placement_preview = preview
	if previous_anchor >= 0 and previous_anchor < grid_buttons.size():
		_update_tile_visual(previous_anchor, city_grid[previous_anchor])
	_update_tile_visual(index, city_grid[index])


func get_placement_preview_snapshot() -> Dictionary:
	return _placement_preview.duplicate(true)


func _sync_placement_banner() -> void:
	if placement_banner == null or placement_label == null:
		return
	var transport_active := _is_transport_map_action_active()
	var compact_transport_layout := transport_active or _is_transport_station_session_placement()
	_set_placement_banner_layout(compact_transport_layout)
	placement_banner.visible = placement_mode_active or transport_active
	if placement_level_button != null:
		placement_level_button.visible = false
	if placement_rotate_button != null:
		placement_rotate_button.visible = placement_mode_active and not compact_transport_layout
		placement_rotate_button.disabled = placement_building_name.is_empty()
	if placement_confirm_button != null:
		placement_confirm_button.visible = false
		placement_confirm_button.disabled = true
	if placement_cancel_button != null:
		var session_map_action := _transport_session_is_active() and (transport_active or _is_transport_station_session_placement())
		placement_cancel_button.text = L10n.text("暫停規劃" if session_map_action else ("取消規劃" if transport_active else "取消放置"))
		placement_cancel_button.tooltip_text = L10n.text("暫停並保留交通規劃（Esc／右鍵）" if session_map_action else ("取消目前的交通規劃（Esc／右鍵）" if transport_active else "取消目前的建築放置（Esc／右鍵）"))
	if not placement_mode_active and not transport_active:
		return
	if _pending_terrain_tile >= 0 and vertical_slice != null:
		var quote: Dictionary = vertical_slice.terrain_flatten_quote(_pending_terrain_tile)
		var terrain: Dictionary = quote.get("terrain", {})
		var terrain_label := L10n.text(str(TERRAIN_LABELS.get(str(terrain.get("effective_kind", "")), "非平坦地形")))
		placement_label.text = L10n.text("%s不可興建｜先整平地形才能施工") % terrain_label
		if placement_level_button != null:
			placement_level_button.text = L10n.text("整地開工 $%d｜%d 日") % [
				int(quote.get("total_cost", quote.get("cost", 0))),
				int(quote.get("duration_days", 0)),
			]
			placement_level_button.disabled = not bool(quote.get("can_start", false))
			placement_level_button.visible = true
		return
	if transport_active:
		var session := _transport_session_snapshot()
		var session_prefix := ""
		if _transport_session_is_active(session):
			session_prefix = "%s｜" % L10n.text(str(session.get("station_blueprint_name", "交通站點")))
		if placement_confirm_button != null:
			placement_confirm_button.visible = true
		if map_action_mode == "transport_infrastructure":
			var quote := _transport_project_quote(transport_plan_tiles) if not transport_plan_tiles.is_empty() else {}
			var valid := not transport_plan_tiles.is_empty() and bool(quote.get("ok", false))
			var can_afford := valid and bool(quote.get("can_afford", true))
			var package_route := _transport_session_is_route_package(session) and transport_plan_operation == "build"
			var cost := _transport_visible_plan_cost(quote, transport_plan_tiles.size(), session)
			var operation_label := "興建" if transport_plan_operation == "build" else "拆除"
			if package_route and cost < 0:
				placement_label.text = L10n.text("此路網規劃不可用：%s") % _vertical_error_text("invalid_transport_kind")
				if placement_confirm_button != null:
					placement_confirm_button.text = L10n.text("下一步：確認總包")
					placement_confirm_button.disabled = true
				return
			placement_label.text = L10n.text("%s步驟 2/3｜%s%s｜已選 %d 格｜預估 $%d") % [
				session_prefix, L10n.text(operation_label), L10n.text(_transport_kind_label(transport_plan_kind)),
				transport_plan_tiles.size(), cost,
			]
			if placement_confirm_button != null:
				placement_confirm_button.text = L10n.text("下一步：確認總包" if package_route else "確認開工")
				placement_confirm_button.disabled = not valid or not can_afford
		else:
			var minimum_stops := 1 if transport_route_mode == "air" else 2
			placement_label.text = L10n.text("%s步驟 3/3｜規劃%s｜已選 %d/%d 站｜車隊 %d｜班距 %d 分｜票價 $%d") % [
				session_prefix, L10n.text(_transport_route_label(transport_route_mode)), transport_route_station_tiles.size(), minimum_stops,
				transport_route_fleet_size, transport_route_headway_minutes, transport_route_fare,
			]
			if placement_confirm_button != null:
				placement_confirm_button.text = L10n.text("建立並驗證路線")
				placement_confirm_button.disabled = transport_route_station_tiles.size() < minimum_stops
		return
	if _is_transport_station_session_placement():
		var session := _transport_session_snapshot()
		var mode := str(session.get("mode", ""))
		var minimum_stops := 1 if mode == "air" else 2
		var station_count := _transport_session_station_count(session)
		placement_label.text = L10n.text("%s｜步驟 1/3 站點選址｜%s｜已放 %d/%d 站｜可繼續放置") % [
			L10n.text(_transport_route_label(mode)), L10n.text(placement_building_name), station_count, minimum_stops,
		]
		if placement_confirm_button != null:
			placement_confirm_button.visible = true
			placement_confirm_button.text = L10n.text("下一步：規劃路網")
			placement_confirm_button.disabled = station_count < minimum_stops
		return
	placement_label.text = L10n.text("放置 %s｜方向 %d°｜點擊空地查看總價｜Esc／右鍵取消") % [
		L10n.text(placement_building_name),
		placement_rotation_quarter_turns_ccw * 90,
	]


func _rotate_building_placement_ccw() -> void:
	if not placement_mode_active or _is_transport_station_session_placement():
		return
	placement_rotation_quarter_turns_ccw = posmod(placement_rotation_quarter_turns_ccw + 1, 4)
	_pending_construction_tile = -1
	_pending_construction_rotation_quarter_turns_ccw = 0
	if construction_confirmation != null and construction_confirmation.is_open():
		construction_confirmation.close()
		_sync_map_interaction_for_ui()
	if _placement_preview_anchor >= 0:
		_refresh_placement_preview(_placement_preview_anchor)
	_sync_placement_banner()


func _transport_visible_plan_cost(quote: Dictionary, tile_count: int, session: Dictionary = {}) -> int:
	if _transport_session_is_route_package(session) and transport_plan_operation == "build":
		var package_quote: Dictionary = TransportModesScript.route_package_price_quote(tile_count, transport_plan_kind)
		if not bool(package_quote.get("ok", false)):
			return -1
		return int(package_quote.get("construction_cost", -1))
	return int(quote.get("total_cost", quote.get("cost", 0)))


func _flatten_pending_terrain() -> void:
	if (not placement_mode_active and not _is_transport_map_action_active()) or vertical_slice == null or _pending_terrain_tile < 0:
		return
	var tile_index := _pending_terrain_tile
	var result: Dictionary = vertical_slice.flatten_terrain(tile_index)
	if not bool(result.get("ok", false)):
		_set_hint("無法整平地形：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		_sync_placement_banner()
		return
	_pending_terrain_tile = -1
	selected_cell_index = tile_index
	_consume_vertical_events(vertical_slice.drain_ui_events())
	_update_tile_visual(tile_index, city_grid[tile_index])
	# Starting earthworks is a prepaid treasury transaction. Terrain and
	# navigation remain blocked until the terrain_flattened completion event.
	_update_ui()
	_sync_placement_banner()
	var job: Dictionary = result.get("job", {})
	_set_hint("整地工程已開工：%d 名工人、預計 %d 日、預付 $%d；完工後請再安排建築或交通。" % [
		int(job.get("worker_count", 0)),
		int(job.get("projected_total_days", 0)),
		int(result.get("total_cost", result.get("cost", 0))),
	], false)
	_autosave("action:terrain_flatten_started")


func _confirm_pending_construction(tile_index: int) -> void:
	if not placement_mode_active or tile_index != _pending_construction_tile or vertical_slice == null:
		return
	var building_name := placement_building_name
	var session_placement := _is_transport_station_session_placement()
	var result: Dictionary = (
		vertical_slice.call("place_transport_session_station", tile_index, _pending_construction_workers)
		if session_placement
		else vertical_slice.start_approved_building(
			building_name,
			tile_index,
			_pending_construction_workers,
			_pending_construction_rotation_quarter_turns_ccw
		)
	)
	if not bool(result.get("ok", false)):
		_set_hint("無法開工「%s」：%s" % [building_name, _vertical_error_text(str(result.get("error", "unknown")))], true)
		_pending_construction_tile = -1
		_update_ui()
		return
	selected_cell_index = tile_index
	_placement_preview_anchor = -1
	_placement_preview.clear()
	_pending_construction_tile = -1
	_pending_construction_rotation_quarter_turns_ccw = 0
	if not session_placement:
		placement_mode_active = false
		placement_building_name = ""
		placement_rotation_quarter_turns_ccw = 0
	_sync_placement_banner()
	if session_placement:
		var station_count := _transport_session_station_count(result.get("session", {}))
		_set_hint("「%s」第 %d 站已開工；規劃未結束，可直接選擇下一個站點。" % [building_name, station_count], false)
	else:
		_set_hint("「%s」已開工，分配 %d 名工程人員，預付總造價 $%d。" % [building_name, _pending_construction_workers, int(result.get("total_cost", 0))], false)
	var onboarding_recorded := onboarding_action_router.record_build_success(
		building_name,
		session_placement or building_name in TRANSPORT_SESSION_STATIONS,
		result,
		vertical_slice.game_day()
	)
	# start_approved_building() queues construction_started immediately, while
	# process_frame() only drains UI events on the next 120-second game-day tick.
	# Consume it now so the worksite footprint and every resident path are updated
	# in the same frame as the confirmed placement.
	_consume_vertical_events(vertical_slice.drain_ui_events(), false)
	_sync_vertical_state()
	_update_ui()
	_autosave("action:transport_session_station_started" if session_placement else "action:construction_started")
	if onboarding_recorded:
		call_deferred("_refresh_onboarding_guide")


func _on_construction_confirmation_cancelled() -> void:
	_pending_construction_tile = -1
	_set_hint("已返回選地；尚未扣除任何費用。", false)

func _select_built_cell(index: int) -> void:
	var record: Dictionary = vertical_slice.get_building_by_tile(index) if vertical_slice != null else {}
	var anchor_tile_id := int(record.get("anchor_tile_id", record.get("tile_index", index)))
	if anchor_tile_id < 0 or anchor_tile_id >= city_grid.size():
		return
	selected_cell_index = anchor_tile_id
	var building_name := str(record.get("building_name", city_grid[anchor_tile_id]))
	if _is_customizable_building(building_name) and not building_customizations.has(anchor_tile_id):
		building_customizations[anchor_tile_id] = {"variant": 0, "roof": 0, "wall": 0}
	_set_hint("已選取「%s」。建築功能已顯示在地塊旁。" % building_name, false)
	_update_scoped_municipal_pages(vertical_slice.get_view_model(selected_cell_index))
	if judicial_panel:
		judicial_panel.refresh(vertical_slice.governance.justice_system)
	if oversight_panel:
		oversight_panel.refresh(vertical_slice.governance.justice_system)
	_update_building_info_panel()
	L10n.localize_tree(self)
	_sync_map_interaction_for_ui()
	_sync_placement_banner()
	_refresh_building_context()
	_open_building_context(anchor_tile_id)

func _is_customizable_building(building_name: String) -> bool:
	return CUSTOMIZABLE_BUILDINGS.has(building_name)

func _cycle_selected_building_variant() -> void:
	if not _can_customize_selected_cell():
		return
	var customization: Dictionary = building_customizations[selected_cell_index]
	customization["variant"] = (int(customization.get("variant", 0)) + 1) % CUSTOM_VARIANTS.size()
	building_customizations[selected_cell_index] = customization
	_update_ui()
	_update_building_info_panel()
	_refresh_building_context()
	_autosave("action:building_style_changed")

func _cycle_selected_building_roof() -> void:
	if not _can_customize_selected_cell():
		return
	var customization: Dictionary = building_customizations[selected_cell_index]
	customization["roof"] = (int(customization.get("roof", 0)) + 1) % CUSTOM_ROOF_COLORS.size()
	building_customizations[selected_cell_index] = customization
	_update_ui()
	_update_building_info_panel()
	_refresh_building_context()
	_autosave("action:building_roof_changed")

func _cycle_selected_building_wall() -> void:
	if not _can_customize_selected_cell():
		return
	var customization: Dictionary = building_customizations[selected_cell_index]
	customization["wall"] = (int(customization.get("wall", 0)) + 1) % CUSTOM_WALL_COLORS.size()
	building_customizations[selected_cell_index] = customization
	_update_ui()
	_update_building_info_panel()
	_refresh_building_context()
	_autosave("action:building_exterior_changed")

func _can_customize_selected_cell() -> bool:
	if selected_cell_index < 0 or selected_cell_index >= city_grid.size():
		return false
	return _is_customizable_building(city_grid[selected_cell_index])

func _update_building_info_panel() -> void:
	if building_info_label == null or customization_label == null:
		return
	if selected_cell_index < 0 or selected_cell_index >= city_grid.size() or city_grid[selected_cell_index] == "":
		building_info_label.text = L10n.text("點選已建築地塊可查看資訊與調整外觀。")
		customization_label.text = L10n.text("外觀：未選取")
		return

	var building_name := city_grid[selected_cell_index]
	var data: Dictionary = buildings[building_name]
	var visual: Dictionary = BUILDING_VISUALS.get(building_name, {"shape": building_name, "detail": "城鎮建物"})
	var durability_value := 100
	var building_record: Dictionary = vertical_slice.get_building_by_tile(selected_cell_index) if vertical_slice != null else {}
	if not building_record.is_empty():
		var durability_record: Dictionary = vertical_slice.durability.get_building(str(building_record.get("building_id", "")))
		durability_value = int(durability_record.get("durability", building_record.get("durability", 100)))
	var cat = L10n.text(data.get("category", "未分類"))
	building_info_label.text = L10n.text("%s｜%s｜%s｜耐久 %d｜維護 $%d") % [L10n.text(building_name), L10n.text(visual["shape"]), cat, durability_value, int(data.get("maintenance", 0))]
	var can_customize := _is_customizable_building(building_name)
	if can_customize and not building_customizations.has(selected_cell_index):
		building_customizations[selected_cell_index] = {"variant": 0, "roof": 0, "wall": 0}
	var description := L10n.text("不可客製")
	if can_customize:
		var customization: Dictionary = building_customizations[selected_cell_index]
		description = "%s / %s / %s" % [
			L10n.text(CUSTOM_VARIANTS[int(customization.get("variant", 0))]),
			L10n.text(CUSTOM_ROOF_COLORS[int(customization.get("roof", 0))]),
			L10n.text(CUSTOM_WALL_COLORS[int(customization.get("wall", 0))])
		]
	customization_label.text = L10n.text("外觀：%s") % description


func _open_building_context(index: int) -> void:
	if building_context_panel == null or index < 0 or index >= grid_buttons.size():
		return
	var anchor := (grid_buttons[index] as Control).get_global_rect().get_center()
	building_context_panel.open_for(_building_context_state(), anchor, get_viewport_rect().size)


func _refresh_building_context() -> void:
	if building_context_panel == null or not building_context_panel.visible or selected_cell_index < 0:
		return
	_open_building_context(selected_cell_index)


func _close_building_context() -> void:
	if building_context_panel != null:
		building_context_panel.close_panel()


func _building_context_state() -> Dictionary:
	if selected_cell_index < 0 or selected_cell_index >= city_grid.size() or city_grid[selected_cell_index] == "":
		return {}
	var building_name := city_grid[selected_cell_index]
	var customization: Dictionary = building_customizations.get(selected_cell_index, {})
	var appearance := "不可客製"
	if _is_customizable_building(building_name):
		appearance = "%s／%s／%s" % [
			CUSTOM_VARIANTS[int(customization.get("variant", 0))],
			CUSTOM_ROOF_COLORS[int(customization.get("roof", 0))],
			CUSTOM_WALL_COLORS[int(customization.get("wall", 0))],
		]
	var view_model: Dictionary = vertical_slice.get_view_model(selected_cell_index)
	return {
		"building_name": building_name,
		"durability": int(view_model.get("selected_durability", 100)),
		"appearance": appearance,
		"can_customize": _is_customizable_building(building_name),
		"can_repair": bool(view_model.get("can_repair", false)),
		"can_demolish": bool(view_model.get("can_demolish", false)),
	}


func _on_building_context_action(action_id: String) -> void:
	match action_id:
		"style": _cycle_selected_building_variant()
		"roof": _cycle_selected_building_roof()
		"exterior": _cycle_selected_building_wall()
		"maintenance": _repair_selected_building()
		"demolish":
			_start_selected_demolition()
			_close_building_context()

func _animate_building_placement(index: int) -> void:
	if index < 0 or index >= grid_buttons.size():
		return
	var button := grid_buttons[index]
	button.pivot_offset = button.size * 0.5
	button.scale = Vector2(0.82, 0.82)
	button.modulate.a = 0.25
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate:a", 1.0, 0.18)

func _animate_label_flash(label: Label) -> void:
	if label == null:
		return
	label.pivot_offset = label.size * 0.5
	label.modulate.a = 0.35
	label.scale = Vector2(0.98, 0.98)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.22)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _apply_building_effect(data: Dictionary) -> void:
	_apply_city_metric_patch(
		CitySimulationServiceScript.metric_effect_patch(
			_city_metrics_snapshot(), _direct_building_effects(data), 1
		)
	)

func _remove_building_effect(data: Dictionary) -> void:
	_apply_city_metric_patch(
		CitySimulationServiceScript.metric_effect_patch(
			_city_metrics_snapshot(), _direct_building_effects(data), -1
		)
	)


func _direct_building_effects(data: Dictionary) -> Dictionary:
	var direct_effects := data.duplicate(true)
	var service_value: Variant = direct_effects.get("public_service", {})
	if service_value is Dictionary and str((service_value as Dictionary).get("id", "")) == "healthcare":
		direct_effects.erase("healthcare")
		direct_effects.erase("satisfaction")
	return direct_effects


func _healthcare_service_result() -> Dictionary:
	if vertical_slice != null and vertical_slice.has_method("healthcare_service_result"):
		return Dictionary(vertical_slice.call("healthcare_service_result", city_grid)).duplicate(true)
	return CitySimulationServiceScript.healthcare_service_result({
		"population": population,
		"building_records": {},
		"road_access_components": [],
		"durability_records": {},
		"maintenance_enabled": false,
		"unpaid_maintenance_months": 0,
		"capacity_per_facility": 0,
		"max_metric_bonus": 0,
	})


func _healthcare_max_metric_bonus() -> int:
	var hospital_data: Dictionary = buildings.get("醫院", {})
	var service_value: Variant = hospital_data.get("public_service", {})
	if not service_value is Dictionary:
		return 0
	return maxi(0, int((service_value as Dictionary).get("max_metric_bonus", 0)))


func _reconcile_healthcare_service() -> Dictionary:
	var result := _healthcare_service_result()
	if vertical_slice == null or vertical_slice.session == null:
		return result
	var target_bonus := maxi(0, int(result.get("metric_bonus", 0)))
	var base_healthcare := clampi(healthcare - healthcare_applied_bonus, 0, 100)
	var next_healthcare := clampi(base_healthcare + target_bonus, 0, 100)
	var effective_bonus := next_healthcare - base_healthcare
	if next_healthcare == healthcare and effective_bonus == healthcare_applied_bonus:
		return result
	healthcare = next_healthcare
	healthcare_applied_bonus = effective_bonus
	_recalculate_satisfaction()
	_recalculate_score()
	return result


func _migrate_legacy_hospital_direct_effects() -> void:
	if vertical_slice == null or vertical_slice.session == null:
		return
	var active_legacy_count := 0
	for building_variant: Variant in vertical_slice.session.state.buildings.values():
		if not building_variant is Dictionary:
			continue
		var record: Dictionary = building_variant
		if str(record.get("definition_id", "")) != "hospital" and str(record.get("building_name", "")) != "醫院":
			continue
		if str(record.get("status", "active")) == "scrapped":
			continue
		var tile_index := int(record.get("tile_index", -1))
		var customization: Dictionary = building_customizations.get(tile_index, {})
		if bool(customization.get("effects_inactive", false)):
			continue
		active_legacy_count += 1
	if active_legacy_count <= 0:
		return
	var hospital_data: Dictionary = buildings.get("醫院", {})
	_apply_city_metric_patch({
		"healthcare": healthcare - int(hospital_data.get("healthcare", 0)) * active_legacy_count,
		"satisfaction": total_satisfaction - int(hospital_data.get("satisfaction", 0)) * active_legacy_count,
	})
	_recalculate_satisfaction()
	_recalculate_score()


func _healthcare_service_visible_text(result: Dictionary) -> String:
	return L10n.text("%s｜%s｜服務 %d/%d｜覆蓋 %d%%") % [
		_healthcare_service_status_text(str(result.get("status", "unavailable"))),
		_healthcare_service_reason_text(str(result.get("reason_code", "facility_missing"))),
		maxi(0, int(result.get("served", 0))),
		maxi(0, int(result.get("capacity", 0))),
		clampi(int(round(float(result.get("coverage", 0.0)) * 100.0)), 0, 100),
	]


func _healthcare_service_status_text(status_code: String) -> String:
	var source_text := str({
		"operational": "正常",
		"degraded": "容量不足",
		"unavailable": "無法服務",
	}.get(status_code, "無法服務"))
	return L10n.text(source_text)


func _healthcare_service_reason_text(reason_code: String) -> String:
	var source_text := str({
		"operational": "運作正常",
		"capacity_shortfall": "容量低於需求",
		"facility_missing": "缺少醫院",
		"road_missing": "缺少道路連接",
		"maintenance_unfunded": "維護未撥款",
	}.get(reason_code, "服務條件未滿足"))
	return L10n.text(source_text)


func _healthcare_service_action_text(result: Dictionary) -> String:
	match str(result.get("reason_code", "facility_missing")):
		"facility_missing":
			return L10n.text("優先建造：醫院")
		"road_missing":
			return L10n.text("請以道路連接醫院與城市建築。")
		"maintenance_unfunded":
			return L10n.text("恢復維護預算後才會提供醫療。")
		"capacity_shortfall":
			return L10n.text("醫療容量不足，請維修或增建醫院。")
	return L10n.text("醫療服務運作正常。")

func _next_day() -> void:
	if vertical_slice == null:
		return
	var events: Array[Dictionary] = vertical_slice.advance_days(1, _vertical_city_context(), false)
	_consume_vertical_events(events)
	_sync_vertical_state()
	_update_ui()
	if events.is_empty():
		_autosave("event:day_advanced")

func _next_month() -> void:
	var target_month := month
	while month == target_month:
		_next_day()

func _settle_month(autosave_after: bool = true) -> void:
	var previous_satisfaction := total_satisfaction
	var previous_security := security
	var previous_environment := environment
	var previous_traffic := traffic
	var previous_education := education
	var previous_healthcare := healthcare
	var month_plan := CitySimulationServiceScript.compose_month_settlement(
		_tax_revenues(),
		_business_income(),
		_industrial_income(),
		_utility_income(),
		_service_income(),
		_maintenance_cost(),
		_policy_expense(),
		_active_law_expense()
	)
	var tax_income := int(month_plan["tax_income"])
	var business_income := int(month_plan["business_income"])
	var industrial_income := int(month_plan["industrial_income"])
	var utility_income := int(month_plan["utility_income"])
	var service_income := int(month_plan["service_income"])
	var maintenance := int(month_plan["maintenance"])
	var policy_expense := int(month_plan["policy_expense"])
	var law_expense := int(month_plan["law_expense"])
	var income := int(month_plan["income"])
	var expense := int(month_plan["expense"])
	_apply_active_law_population_effect()
	_match_available_jobs()

	var settlement: Dictionary = vertical_slice.settle_month(
		month_plan["income_entries"],
		month_plan["expense_entries"],
		maintenance,
		_vertical_city_context(),
		false
	)
	_reconcile_healthcare_service()
	expense = int(settlement.get("expense", expense))
	_apply_monthly_policy_effects()
	_apply_active_law_effects()
	_sync_vertical_state()
	_apply_city_pressure()
	_recalculate_satisfaction()
	_recalculate_score()

	var population_change := population - month_start_population
	var population_rate := float(population_change) / float(maxi(1, month_start_population)) * 100.0
	var satisfaction_change := total_satisfaction - previous_satisfaction
	city_report_history_service.record_month({
		"available": true,
		"income": income,
		"expense": expense,
		"net": income - expense,
		"population_change": population_change,
		"satisfaction_change": satisfaction_change,
		"security_change": security - previous_security,
		"environment_change": environment - previous_environment,
		"traffic_change": traffic - previous_traffic,
		"education_change": education - previous_education,
		"healthcare_change": healthcare - previous_healthcare,
	}, income, expense, population_rate, _city_report_metric_snapshot())
	month_start_population = population
	var prioritized_metrics := _prioritized_city_metric_specs()
	var priority_spec: Dictionary = prioritized_metrics[0] if not prioritized_metrics.is_empty() else {"id": "security", "label": "治安", "building": "警局"}
	var priority_value := _city_metric_value(str(priority_spec["id"]))
	var settlement_coverage := 100.0 if expense <= 0 and income > 0 else 0.0
	if expense > 0:
		settlement_coverage = float(income) / float(expense) * 100.0
	last_report = "收支覆蓋率 %.0f%%・%s｜人口 %s（%+d）\n居民滿意：%s｜優先改善：%s %s" % [
		settlement_coverage,
		_benchmark_gap_text(settlement_coverage, 100.0, "收支安全線", 0),
		_format_grouped_int(population),
		population_change,
		_benchmark_gap_text(float(total_satisfaction), 60.0),
		L10n.text(str(priority_spec["label"])),
		_benchmark_gap_text(float(priority_value), 60.0),
	]
	last_report_details = "收入 $%d｜稅收 $%d・商業 $%d・工業 $%d・公共事業 $%d・服務 $%d\n支出 $%d｜維護 $%d・政策 $%d・法案 $%d｜結算資金 $%d\n人口動態：%s｜市民意見：%s｜城市評級：%s" % [
		income,
		tax_income,
		business_income,
		industrial_income,
		utility_income,
		service_income,
		expense,
		maintenance,
		policy_expense,
		law_expense,
		funds,
		last_population_reason,
		_citizen_comment(),
		city_rating
	]
	if funds < 0:
		_add_announcement("城市財政陷入赤字，請調整稅率、費用或支出。")
	if _migration_pressure() > 0:
		_add_announcement(_migration_reason())
	for warning in _infrastructure_warnings():
		_add_announcement(warning)
	_set_hint("月份推進到第 %d 月。" % month, false)
	_animate_label_flash(report_label)
	_sync_vertical_state()
	_update_ui()
	if autosave_after:
		_autosave("event:month_started")

func _vertical_city_context() -> Dictionary:
	var fee_total := 0
	for fee_value in utility_fees.values():
		fee_total += int(fee_value)
	var healthcare_result := _healthcare_service_result()
	return {
		"park_count": _building_count("公園"),
		"hospital_count": _building_count("醫院"),
		"operational_hospital_count": maxi(0, int(healthcare_result.get("operational_facility_count", 0))),
		"operational_hospital_capacity": maxi(0, int(healthcare_result.get("capacity", 0))),
		"school_count": _building_count("學校"),
		"utility_fee": int(round(float(fee_total) / maxf(1.0, float(utility_fees.size())))),
		"economic_health": clampf(50.0 + float(funds) / 20_000.0, 0.0, 100.0),
		"public_support": clampf(float(total_satisfaction), 0.0, 100.0),
		"security": security,
		"environment": environment,
		"traffic": traffic,
		"housing_pressure": clampf(float(population - _building_count("住宅") * 28 - _building_count("社會住宅") * 48), 0.0, 100.0),
		"mayor_argument_bonus": 2.0,
		"regional_support": {},
		"policy_effectiveness": {}
	}

func _sync_vertical_state() -> void:
	if vertical_slice == null:
		return
	var date: Dictionary = vertical_slice.current_date()
	month = int(date.get("month", 1))
	day = int(date.get("day", 1))
	_record_governance_failure_if_needed()
	_update_scoped_municipal_pages(vertical_slice.get_view_model(selected_cell_index))


func _sync_city_metrics_to_core() -> void:
	# Compatibility seam retained for older callers. CityState now owns every
	# metric write; the main shell only exposes property wrappers and view data.
	return


func _update_scoped_municipal_pages(view_model: Dictionary) -> void:
	if vertical_slice_panel:
		var blueprint_view_model := view_model.duplicate(false)
		blueprint_view_model["transport_station_mode"] = selected_building in TRANSPORT_SESSION_STATIONS
		blueprint_view_model["blueprint_review"] = vertical_slice.blueprint_review_status(selected_building)
		blueprint_view_model["blueprint_library"] = vertical_slice.approved_blueprints(selected_building)
		blueprint_view_model["active_blueprint_id"] = str(vertical_slice.active_blueprint_status(selected_building).get("library_id", ""))
		# Let an incoming approved/library selection bind the UI draft first.  The
		# second lightweight view update below then quotes those exact controls,
		# instead of accidentally pricing the controls from the previously selected
		# building for one frame.
		vertical_slice_panel.set_view_model(blueprint_view_model)
		var design_state: Dictionary = vertical_slice_panel.active_design_state()
		var placement_quote: Dictionary = (
			vertical_slice.placement_quote(selected_building, vertical_slice_panel.selected_worker_count())
			if bool(design_state.get("matches_active_approved", false))
			else vertical_slice.draft_placement_quote(selected_building, vertical_slice_panel.current_design_payload())
		)
		blueprint_view_model["placement_quote"] = placement_quote if bool(placement_quote.get("ok", false)) else {}
		vertical_slice_panel.set_view_model(blueprint_view_model)
	if public_affairs_panel:
		public_affairs_panel.set_view_model(view_model)
	if governance_force_label:
		governance_force_label.text = str(view_model.get("governance_text", "目前沒有遭否決的法案。"))
	if governance_force_button:
		governance_force_button.disabled = not bool(view_model.get("can_force_enact", false))

func _consume_vertical_events(events: Array[Dictionary], autosave_events: bool = true) -> void:
	var event_types := PackedStringArray()
	var navigation_changed := false
	var request_context_changed := false
	var save_loaded := false
	for event in events:
		var event_type := str(event.get("type", ""))
		var event_game_time := int(event.get("game_day", vertical_slice.game_day() if vertical_slice != null else 0))
		if not event_type.is_empty() and event_type != "save_loaded" and not event_types.has(event_type):
			event_types.append(event_type)
		var payload: Dictionary = event.get("payload", {})
		match event_type:
			"blueprint_approved":
				var review: Dictionary = payload.get("payload", payload)
				var approved_building_name := _building_name_from_id(str(review.get("blueprint", {}).get("building_id", "")))
				_add_announcement("「%s」藍圖審核通過，已永久存入藍圖庫；可反覆套用興建。" % approved_building_name)
				_record_major_event("blueprint_approved", approved_building_name, "", "blueprint:%s" % str(review.get("id", "")), event_game_time)
				if audio_director != null:
					audio_director.play_success()
			"blueprint_rejected":
				_add_announcement("藍圖遭駁回：%s。可修改後重新送審。" % _vertical_error_text(str(payload.get("reason_tag", "review_rejected"))))
			"construction_started":
				navigation_changed = true
				_add_announcement("工程已排入全城 20 人工程隊。")
			"terrain_flatten_started":
				_add_announcement("整地工程已開工；完工前仍不可建造、通行或鋪設交通。")
			"transport_project_started":
				navigation_changed = true
				var started_project: Dictionary = payload.get("project", {})
				_add_announcement("%s工程已開工；完工前不會生成行駛中的載具。" % _transport_kind_label(_transport_project_kind(started_project)))
			"transport_project_completed":
				navigation_changed = true
				var completed_project: Dictionary = payload.get("project", {})
				_add_announcement("%s工程已完工，所有路線已重新檢查連通狀態。" % _transport_kind_label(_transport_project_kind(completed_project)))
			"transport_project_completion_failed":
				navigation_changed = true
				_add_announcement("交通工程完工登錄失敗：%s。" % _vertical_error_text(str(payload.get("error", "transport_project_completion_failed"))))
			"transport_route_created":
				_add_announcement("「%s」已建立；只有連通且啟用的路線會派出載具。" % str(payload.get("name", "交通路線")))
			"transport_route_enabled":
				_add_announcement("「%s」已啟用並重新驗證路網。" % str(payload.get("name", "交通路線")))
			"transport_route_disabled":
				_add_announcement("「%s」已停駛，所屬載具已撤回。" % str(payload.get("name", "交通路線")))
			"transport_route_deleted":
				_add_announcement("交通路線已刪除，共用基礎設施仍保留。")
			"building_completed":
				navigation_changed = true
				request_context_changed = true
				if audio_director != null:
					audio_director.play_construction_complete()
				var tile_index := int(payload.get("tile_index", -1))
				var building_name := str(payload.get("building_name", ""))
				_record_major_event("building_completed", building_name, "", "building_completed:%s" % str(payload.get("building_id", tile_index)), event_game_time)
				if tile_index >= 0 and tile_index < city_grid.size() and city_grid[tile_index] == "" and buildings.has(building_name):
					city_grid[tile_index] = building_name
					var blueprint: Dictionary = payload.get("blueprint", {})
					building_customizations[tile_index] = _customization_from_blueprint(blueprint)
					_apply_building_effect(buildings[building_name])
					_recalculate_satisfaction()
					_recalculate_score()
					_animate_building_placement(tile_index)
					_add_announcement("「%s」施工完成。" % building_name)
			"terrain_flattened":
				navigation_changed = true
				_add_announcement("地形已整平，該地格現在可供興建。")
			"terrain_flatten_completion_failed":
				_add_announcement("整地完工登錄失敗：%s。" % _vertical_error_text(str(payload.get("error", "terrain_flatten_completion_failed"))))
			"demolition_started":
				_add_announcement("拆除工程已開始；完成前建築仍占用原地格。")
			"demolition_completed":
				navigation_changed = true
				var tile_index := int(payload.get("tile_index", -1))
				var building_name := str(payload.get("building_name", ""))
				_record_major_event("building_demolished", building_name, "", "building_demolished:%s" % str(payload.get("building_id", tile_index)), event_game_time)
				if tile_index >= 0 and tile_index < city_grid.size() and city_grid[tile_index] == building_name:
					var customization: Dictionary = building_customizations.get(tile_index, {})
					if buildings.has(building_name) and not bool(customization.get("effects_inactive", false)):
						_remove_building_effect(buildings[building_name])
					city_grid[tile_index] = ""
					building_customizations.erase(tile_index)
					if selected_cell_index == tile_index:
						selected_cell_index = -1
						_close_building_context()
					_recalculate_satisfaction()
					_recalculate_score()
					_add_announcement("「%s」已拆除，地格恢復可建造狀態。" % building_name)
			"building_repaired":
				_add_announcement("選取建築已維修至 100 耐久。")
			"building_scrapped":
				var scrapped_tile := int(payload.get("tile_index", -1))
				if scrapped_tile >= 0 and scrapped_tile < city_grid.size() and city_grid[scrapped_tile] != "":
					var customization: Dictionary = building_customizations.get(scrapped_tile, {})
					if not bool(customization.get("effects_inactive", false)):
						_remove_building_effect(buildings[city_grid[scrapped_tile]])
						customization["effects_inactive"] = true
						building_customizations[scrapped_tile] = customization
				_add_announcement("%s 耐久低於 40，已報廢；請安排拆除。" % payload.get("building_name", "建築"))
			"month_started":
				_settle_month(false)
			"lower_house_hearing_ready":
				_add_announcement("下議院完成初步意向，正在等待市長進入治理頁答詢。")
				call_deferred("_refresh_onboarding_guide")
			"bill_enacted":
				_add_announcement("法案通過兩院並正式生效。")
				_record_major_event("bill_enacted", str(payload.get("name", payload.get("bill_id", "法案"))), "", "bill_enacted:%s" % str(payload.get("bill_id", "")), event_game_time)
			"bill_rejected":
				_add_announcement("法案遭上議院或下議院否決；可選擇修改或強制執行。")
			"bill_force_enacted":
				_add_announcement("法案已強制執行，司法委員會開始審理，監察委員會同步調查行政責任。")
				var forced_law: Dictionary = payload.get("law", {})
				_record_major_event("bill_force_enacted", str(forced_law.get("name", forced_law.get("bill_id", "法案"))), "", "bill_force_enacted:%s" % str(forced_law.get("bill_id", "")), event_game_time)
			"judiciary_fine":
				_add_announcement("司法院裁定罰款，城市仍可繼續經營。")
				_record_major_event("judicial_ruling", "", "司法院裁定罰款，城市仍可繼續經營。", "judicial_fine:%s" % str(payload.get("case_id", event_game_time)), event_game_time)
			"judiciary_stop_order":
				_add_announcement("司法院裁定停止施行。")
				_record_major_event("judicial_ruling", "", "司法院裁定停止施行。", "judicial_stop:%s" % str(payload.get("case_id", event_game_time)), event_game_time)
			"judiciary_prison":
				_add_announcement("司法院判處監禁，遊戲失敗。")
				_record_major_event("judicial_ruling", "", "司法院判處監禁，遊戲失敗。", "judicial_prison:%s" % str(payload.get("case_id", event_game_time)), event_game_time)
			"oversight_impeachment":
				_add_announcement("監察委員會通過彈劾行政官員。")
				_record_major_event("impeachment", "", "監察委員會通過彈劾行政官員。", "impeachment:%s" % str(payload.get("case_id", event_game_time)), event_game_time)
			"oversight_cleared":
				_add_announcement("監察委員會完成調查，決議不提出彈劾。")
			"committee_term_expired":
				_add_announcement("委員任期屆滿，已進入續任或改任程序。")
			"committee_member_reappointed":
				_add_announcement("委員完成續任，新任期開始。")
			"npc_request_accepted":
				_add_announcement("已接受居民請求；完成條件後會寫入重大人物事件簿。")
				var accepted_request := _request_major_event_data(str(payload.get("request_id", "")))
				_record_major_event(
					"petition_accepted",
					str(accepted_request.get("title", "居民陳情")),
					str(accepted_request.get("description", "")),
					"petition_accepted:%s" % str(payload.get("request_id", "")),
					event_game_time,
					str(accepted_request.get("npc_id", ""))
				)
			"npc_request_rejected":
				_add_announcement("居民陳情已拒絕；民情中心會保留此決策紀錄。")
			"npc_request_completed":
				_add_announcement("居民請求已完成並記入人物事件簿。")
				var completed_request := _request_major_event_data(str(payload.get("request_id", "")))
				_record_major_event(
					"petition_completed",
					str(completed_request.get("title", "居民陳情")),
					str(completed_request.get("description", "")),
					"petition_completed:%s" % str(payload.get("request_id", "")),
					event_game_time,
					str(completed_request.get("npc_id", ""))
				)
			"save_loaded":
				save_loaded = true
				_rebuild_city_from_core()
				_add_announcement("存檔讀取完成。")
	if not save_loaded:
		_reconcile_healthcare_service()
	if request_context_changed:
		_reconcile_resident_request_completion()
	if navigation_changed:
		debug_sync_npc_navigation_obstacles()
		if npc_map_controller != null:
			npc_map_controller.repath_all()
	_sync_vertical_state()
	refresh_visible_npc_proxies()
	if autosave_events and not event_types.is_empty():
		_autosave("event:%s" % ",".join(event_types))

func _start_selected_demolition() -> void:
	if vertical_slice == null or selected_cell_index < 0 or selected_cell_index >= city_grid.size() or city_grid[selected_cell_index] == "":
		_set_hint("請先在地圖上選取要拆除的建築。", true)
		return
	var workers: int = int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel else 5
	var result: Dictionary = vertical_slice.start_demolition(selected_cell_index, workers)
	if bool(result.get("ok", false)):
		_consume_vertical_events(vertical_slice.drain_ui_events())
		var job: Dictionary = result.get("job", {})
		_set_hint("拆除工程已排程：%d 名工人，預計 %d 天，費用 $%d。" % [workers, int(job.get("projected_total_days", 0)), int(result.get("total_cost", 0))], false)
	else:
		_set_hint("無法拆除：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
	_sync_vertical_state()
	_update_ui()
	if bool(result.get("ok", false)):
		_autosave("action:demolition_started")

func _repair_selected_building() -> void:
	if vertical_slice == null or selected_cell_index < 0:
		_set_hint("請先選取需要維修的建築。", true)
		return
	var result: Dictionary = vertical_slice.repair_building(selected_cell_index)
	if bool(result.get("ok", false)):
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_set_hint("建築已維修至 100 耐久。", false)
		_autosave("action:building_repaired")
	else:
		_set_hint("無法維修：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
	_update_ui()
	_refresh_building_context()



func _force_latest_rejected_bill() -> void:
	var result: Dictionary = vertical_slice.force_latest_rejected(false)
	if bool(result.get("ok", false)):
		var onboarding_recorded := onboarding_action_router.record_governance_force_success(
			result,
			vertical_slice.governance,
			vertical_slice.session.state.event_book,
			vertical_slice.governance.checks_and_balances_history,
			vertical_slice.game_day()
		)
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_set_hint("已進入司法與彈劾程序；請到市政中心的「法院審判」與「監察質詢」自行提出辯護。", true)
		if onboarding_recorded:
			call_deferred("_refresh_onboarding_guide")
	else:
		_set_hint("目前沒有可強制執行的遭否決法案。", true)
	_update_ui()

func _accept_request_by_id(request_id: String) -> void:
	var before := _resident_request_snapshot(request_id)
	if vertical_slice.accept_request_by_id(request_id, false):
		var after := _resident_request_snapshot(request_id)
		var onboarding_recorded := onboarding_action_router.record_public_request_accept_success(
			before, after, vertical_slice.game_day()
		)
		_reconcile_resident_request_completion(false)
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_set_hint("居民陳情已列入處理。", false)
		if onboarding_recorded:
			call_deferred("_refresh_onboarding_guide")
	else:
		_set_hint("這筆陳情已處理或不存在。", true)
	_update_ui()


func _reconcile_resident_request_completion(consume_events: bool = true) -> bool:
	if vertical_slice == null:
		return false
	var completed: Array[String] = vertical_slice.complete_requests(_vertical_city_context())
	if completed.is_empty():
		return false
	if not consume_events:
		return true
	var completion_events: Array[Dictionary] = vertical_slice.drain_ui_events()
	if not completion_events.is_empty():
		_consume_vertical_events(completion_events)
	return true


func _resident_request_snapshot(request_id: String) -> Dictionary:
	if vertical_slice == null or request_id.is_empty():
		return {}
	var view_model: Dictionary = vertical_slice.get_view_model(selected_cell_index)
	for request_variant: Variant in view_model.get("citizen_requests", []):
		if request_variant is Dictionary:
			var request := request_variant as Dictionary
			if str(request.get("request_id", "")) == request_id:
				return request.duplicate(true)
	return {}


func _reject_request_by_id(request_id: String) -> void:
	if vertical_slice.reject_request_by_id(request_id, false):
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_set_hint("居民陳情已拒絕。", false)
	else:
		_set_hint("這筆陳情已處理或不存在。", true)
	_update_ui()


func _on_defense_submitted(mode: String, case_id: String, defense_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	if mode not in ["judicial", "oversight"]:
		return
	vertical_slice.sync_governance_state("governance.%s_defense_submitted" % mode)
	var onboarding_recorded := false
	if mode == "judicial":
		onboarding_recorded = onboarding_action_router.record_judicial_defense_success(
			case_id,
			defense_id,
			result,
			vertical_slice.governance,
			vertical_slice.session.state.event_book,
			vertical_slice.game_day()
		)
	else:
		onboarding_recorded = onboarding_action_router.record_oversight_defense_success(
			case_id,
			defense_id,
			result,
			vertical_slice.governance,
			vertical_slice.session.state.event_book,
			vertical_slice.game_day()
		)
	if onboarding_recorded and onboarding_progress.is_completed():
		tutorial_completed = true
	_set_hint("%s辯護資料已提交。" % ("法院" if mode == "judicial" else "監察質詢"), false)
	_autosave("action:%s_defense_submitted" % mode)
	_update_ui()
	if onboarding_recorded:
		call_deferred("_refresh_onboarding_guide")

func _rebuild_city_from_core() -> void:
	city_grid.clear()
	for _index in CELL_COUNT:
		city_grid.append("")
	building_customizations.clear()
	healthcare_applied_bonus = 0
	_healthcare_legacy_migration_applied = false
	# SaveService restores CityState before emitting save_loaded. Rebuilding the
	# visual grid must not re-derive or reset those already-authoritative metrics;
	# legacy shell metrics are migrated by _restore_player_shell_state afterward.
	for building in vertical_slice.session.state.buildings.values():
		var record: Dictionary = building
		var tile_index := int(record.get("tile_index", -1))
		var building_name := str(record.get("building_name", ""))
		if tile_index < 0 or tile_index >= CELL_COUNT or not buildings.has(building_name):
			continue
		city_grid[tile_index] = building_name
		var blueprint: Dictionary = record.get("blueprint", {})
		var customization := _customization_from_blueprint(blueprint)
		if str(record.get("status", "active")) == "scrapped":
			customization["effects_inactive"] = true
		building_customizations[tile_index] = customization
	debug_sync_npc_navigation_obstacles()
	if npc_map_controller != null:
		npc_map_controller.repath_all()

func _customization_from_blueprint(blueprint: Dictionary) -> Dictionary:
	if blueprint.has("customization"):
		var saved_customization := Dictionary(blueprint["customization"]).duplicate(true)
		saved_customization["material"] = str(blueprint.get("material_id", saved_customization.get("material", "wood")))
		return saved_customization
	var decor_indices := {"flowers": 0, "flags": 1, "window_trim": 2}
	var roof_indices := {"blue": 0, "red": 1, "green": 2, "purple": 3, "pink": 4}
	var wall_indices := {"cream": 0, "yellow": 1, "blue": 2, "pink": 3, "mint": 4}
	return {
		"variant": int(decor_indices.get(str(blueprint.get("decoration_id", "flowers")), 0)),
		"roof": int(roof_indices.get(str(blueprint.get("roof_color", "blue")), 0)),
		"wall": int(wall_indices.get(str(blueprint.get("wall_color", "cream")), 0)),
		"material": str(blueprint.get("material_id", "wood"))
	}

func _building_name_from_id(building_id: String) -> String:
	for building_name in buildings.keys():
		var definition = vertical_slice._definition_for_name(str(building_name)) if vertical_slice != null else null
		if definition != null and String(definition.id) == building_id:
			return str(building_name)
	return building_id

func _vertical_error_text(error_code: String) -> String:
	var messages := {
		"approved_blueprint_required": "尚無核准藍圖，請先到「市政中心 → 建設與藍圖」選擇建築圖卡送審並等待 2–7 天",
		"insufficient_treasury": "城市公庫不足",
		"insufficient_workers": "工程隊人力不足，最多共用 20 人",
		"tile_occupied": "該地格已有建築",
		"footprint_out_of_bounds": "建築占地超出地圖東側邊界",
		"unsupported_building_size": "建築規模沒有對應占地規則",
		"unsupported_footprint": "建築占地格式不受支援",
		"invalid_tile_id": "地格編號無效",
		"terrain_not_flat": "地形尚未整平",
		"terrain_not_flattenable": "該地形不可整平",
		"terrain_in_use": "該地格有建物或工程，不能整平",
		"terrain_flatten_already_active": "該地格的整地工程已在進行中",
		"terrain_flatten_completion_failed": "整地完工狀態無法登錄",
		"building_not_found": "找不到建築",
		"demolition_already_active": "這棟建築已在拆除中",
		"blueprint_not_approved": "藍圖尚未核准",
		"blueprint_already_under_review": "這項建築藍圖已在審核中",
		"approved_blueprint_available": "這項建築已有核准藍圖，請先到地圖選擇空地開工",
		"blueprint_in_construction": "這項建築已在施工中，完工後才能送審新版",
		"bill_pending": "已有法案正在審核",
		"another_bill_is_in_review": "已有另一項法案正在審核",
		"bill_already_active": "法案已經生效",
		"duplicate_bill": "相同法案已存在",
		"transport_system_unavailable": "交通系統尚未就緒",
		"invalid_project_operation": "交通工程操作無效",
		"invalid_worker_count": "工程人數必須介於 1 至 20 人",
		"invalid_transport_kind": "交通設施類型無效",
		"invalid_transport_plan": "交通規劃不符合地形、占用或連通規則",
		"transport_targets_required": "尚未選取交通工程地格",
		"transport_target_not_found": "所選地格沒有這類可拆除設施",
		"transport_construction_conflict": "所選地格已有工程進行中",
		"transport_path_not_contiguous": "道路或軌道必須逐格相鄰連接",
		"transport_overlap_invalid": "這些交通設施不能重疊興建",
		"transport_route_invalid": "站點、路網、機廠、號誌或跑道條件尚未完整",
		"transport_station_not_found": "找不到相容且已完工的交通站點",
		"transport_station_incompatible": "該站點與目前規劃的運具不相容",
		"transport_station_not_completed": "該站點尚未完工，不能沿用",
		"transport_station_authority_mismatch": "站點的建築與交通權威資料不一致",
		"station_under_construction": "該站點仍有工程進行中",
		"station_draft_already_recorded": "這個站點已加入目前的路線規劃",
		"duplicate_station_tile": "同一路線不能重複加入同一站點",
		"route_not_found": "找不到指定交通路線",
		"review_rules_satisfied": "審核通過",
		"insufficient_budget": "審核認定預算不足",
		"insufficient_public_support": "民意支持不足"
	}
	return str(messages.get(error_code, error_code.replace("_", " ")))

func _apply_monthly_policy_effects() -> void:
	_apply_city_metric_patch(
		CitySimulationServiceScript.monthly_policy_metric_patch(
			_city_metrics_snapshot(),
			policies,
			active_policies
		)
	)

func _apply_active_law_effects() -> void:
	var effects: Dictionary = {}
	for metric_name: String in CitySimulationServiceScript.METRIC_EFFECT_KEYS:
		effects[metric_name] = _active_law_value(metric_name)
	_apply_city_metric_patch(
		CitySimulationServiceScript.metric_effect_patch(_city_metrics_snapshot(), effects, 1)
	)


func _apply_active_law_population_effect() -> void:
	if vertical_slice == null:
		return
	var requested_delta := int(_active_law_value("population"))
	if requested_delta == 0:
		return
	var result: Dictionary = vertical_slice.adjust_population(
		requested_delta,
		"population.active_law_monthly"
	)
	var actual_delta := int(result.get("actual_delta", 0))
	if actual_delta > 0:
		last_population_reason = "人口增加，居民滿意度上升。"
	elif actual_delta == 0:
		last_population_reason = "人口維持穩定。"

func _add_announcement(message: String) -> void:
	announcements.push_front("第 %d 月第 %d 天：%s" % [month, day, message])
	while announcements.size() > 5:
		announcements.pop_back()


func _apply_city_pressure() -> void:
	_apply_city_metric_patch(
		CitySimulationServiceScript.city_pressure_metric_patch(
			_city_metrics_snapshot(),
			population,
			city_grid
		)
	)

func _recalculate_satisfaction() -> void:
	var result: Dictionary = CitySimulationServiceScript.satisfaction_result(
		_city_metrics_snapshot(),
		tax_rates,
		TAX_DEFS,
		utility_fees,
		UTILITY_DEFS,
		service_fees,
		SERVICE_DEFS,
		city_grid,
		policies,
		active_policies,
		_active_law_value("utility_relief")
	)
	group_satisfaction = (result.get("group_satisfaction", {}) as Dictionary).duplicate(true)
	_set_authoritative_metric_value("satisfaction", int(result.get("satisfaction", total_satisfaction)))

func _recalculate_score() -> void:
	var result: Dictionary = CitySimulationServiceScript.score_result(
		_city_metrics_snapshot(),
		funds,
		population,
		_building_score_bonus(),
		_tax_pressure_score(),
		best_score
	)
	ranking_score = int(result.get("ranking_score", ranking_score))
	best_score = int(result.get("best_score", best_score))
	city_rating = str(result.get("city_rating", city_rating))


func _total_tax_income() -> int:
	return _total_tax_income_for(tax_rates)

func _total_tax_income_for(projection_tax: Dictionary) -> int:
	return CitySimulationServiceScript.sum_int_values(_tax_revenues_for(projection_tax))

func _tax_revenues() -> Dictionary:
	return _tax_revenues_for(tax_rates)

func _tax_revenues_for(projection_tax: Dictionary) -> Dictionary:
	return CitySimulationServiceScript.tax_revenues(
		_resident_income_tax_base(),
		population,
		_commercial_base_income(),
		_industrial_base_income(),
		projection_tax
	)


func _resident_income_tax_base() -> float:
	if vertical_slice == null or vertical_slice.population == null:
		return 0.0
	return MunicipalEconomyServiceScript.resident_income_tax_base(
		vertical_slice.population.resident_income_total(),
		RESIDENT_INCOME_TREASURY_SCALE
	)


func _match_available_jobs() -> Array[Dictionary]:
	if vertical_slice == null or vertical_slice.population == null:
		return []
	var open_jobs: Array[Dictionary] = MunicipalEconomyServiceScript.build_open_jobs(
		city_grid,
		buildings,
		CELL_COUNT,
		_active_law_value("job_attraction")
	)
	return vertical_slice.match_population_jobs(open_jobs)


func _job_sector_for_building(building_name: String) -> String:
	return MunicipalEconomyServiceScript.job_sector_for_building(building_name, buildings)

func _commercial_base_income() -> int:
	return CitySimulationServiceScript.base_income(city_grid, buildings, "commercial_income")

func _industrial_base_income() -> int:
	return CitySimulationServiceScript.base_income(city_grid, buildings, "industrial_income")

func _business_income() -> int:
	return _business_income_for(tax_rates)

func _business_income_for(projection_tax: Dictionary) -> int:
	return CitySimulationServiceScript.business_income(
		_commercial_base_income(),
		bool(active_policies.get("商業振興", false)),
		_active_law_value("business_bonus"),
		_tax_activity_factor_for("business", projection_tax),
		_tax_activity_factor_for("consumption", projection_tax)
	)

func _industrial_income() -> int:
	return _industrial_income_for(tax_rates)

func _industrial_income_for(projection_tax: Dictionary) -> int:
	return CitySimulationServiceScript.industrial_income(
		_industrial_base_income(),
		_tax_activity_factor_for("industry", projection_tax),
		_active_law_value("industrial_bonus")
	)

func _tax_activity_factor(tax_key: String) -> float:
	return _tax_activity_factor_for(tax_key, tax_rates)

func _tax_activity_factor_for(tax_key: String, projection_tax: Dictionary) -> float:
	return CitySimulationServiceScript.tax_activity_factor(
		int(projection_tax[tax_key]),
		int(TAX_DEFS[tax_key]["reasonable"])
	)

func _utility_income() -> int:
	return _utility_income_for(utility_fees)

func _utility_income_for(projection_utility: Dictionary) -> int:
	var raw_total := 0.0
	for revenue: Variant in CitySimulationServiceScript.utility_revenues(
		population, city_grid, buildings, projection_utility, UTILITY_DEFS
	).values():
		raw_total += float(revenue)
	return int(round(raw_total))

func _utility_base_units(fee_key: String) -> float:
	return CitySimulationServiceScript.utility_base_units(fee_key, population, city_grid)

func _service_income() -> int:
	return _service_income_for(service_fees)

func _service_income_for(projection_service: Dictionary) -> int:
	return CitySimulationServiceScript.sum_int_values(_service_revenues_for(projection_service))

func _service_revenues() -> Dictionary:
	return _service_revenues_for(service_fees)

func _service_revenues_for(projection_service: Dictionary) -> Dictionary:
	var revenues := CitySimulationServiceScript.service_revenues(
		population,
		city_grid,
		projection_service,
		SERVICE_DEFS
	)
	for mode: String in ["bus", "metro", "train", "air"]:
		revenues[mode] = 0
		if vertical_slice != null and vertical_slice.has_method("transport_service_revenue"):
			revenues[mode] = int(vertical_slice.call(
				"transport_service_revenue",
				mode,
				population,
				Dictionary(SERVICE_DEFS.get(mode, {})).duplicate(true)
			))
	var road_access_operational := false
	if vertical_slice != null and vertical_slice.has_method("transport_has_private_road_traffic"):
		road_access_operational = bool(vertical_slice.call("transport_has_private_road_traffic", city_grid))
	if not road_access_operational:
		revenues["parking"] = 0
	revenues["medical"] = CitySimulationServiceScript.medical_service_revenue(
		population,
		int(projection_service.get("medical", 0)),
		Dictionary(SERVICE_DEFS.get("medical", {})).duplicate(true),
		_healthcare_service_result()
	)
	return revenues

func _service_fee_income(service_key: String, projection_service: Dictionary = {}) -> int:
	var values := service_fees if projection_service.is_empty() else projection_service
	return int(_service_revenues_for(values).get(service_key, 0))

func _utility_fee_income(fee_key: String, base_units: float, projection_utility: Dictionary = {}) -> float:
	var values := utility_fees if projection_utility.is_empty() else projection_utility
	return CitySimulationServiceScript.utility_fee_income(
		fee_key,
		base_units,
		city_grid,
		buildings,
		values,
		UTILITY_DEFS
	)

func _utility_efficiency_bonus(fee_key: String) -> float:
	return CitySimulationServiceScript.utility_efficiency_bonus(fee_key, city_grid, buildings)

func _maintenance_cost() -> int:
	var total := CitySimulationServiceScript.maintenance_cost(city_grid, buildings)
	if vertical_slice != null and vertical_slice.has_method("transport_incremental_monthly_maintenance"):
		total += int(vertical_slice.call("transport_incremental_monthly_maintenance"))
	elif vertical_slice != null and vertical_slice.has_method("transport_monthly_maintenance"):
		total += int(vertical_slice.call("transport_monthly_maintenance"))
	return total

func _policy_expense() -> int:
	return CitySimulationServiceScript.policy_expense(policies, active_policies)

func _active_law_expense() -> int:
	return int(_active_law_value("monthly_expense"))

func _building_count(building_name: String) -> int:
	return CitySimulationServiceScript.building_count(city_grid, building_name)

func _building_score_bonus() -> int:
	return CitySimulationServiceScript.building_score_bonus(city_grid, buildings)



func _migration_pressure() -> int:
	return CitySimulationServiceScript.migration_pressure(
		_tax_pressure_score(),
		_city_metrics_snapshot(),
		utility_fees,
		UTILITY_DEFS,
		service_fees,
		SERVICE_DEFS
	)

func _migration_reason() -> String:
	return CitySimulationServiceScript.migration_reason(
		tax_rates,
		TAX_DEFS,
		utility_fees,
		UTILITY_DEFS,
		service_fees,
		SERVICE_DEFS,
		_city_metrics_snapshot()
	)

func _utility_satisfaction_penalty() -> int:
	return CitySimulationServiceScript.utility_satisfaction_penalty(
		utility_fees,
		UTILITY_DEFS,
		city_grid
	)

func _service_satisfaction_penalty() -> int:
	return CitySimulationServiceScript.service_satisfaction_penalty(service_fees, SERVICE_DEFS)

func _tax_pressure_score() -> int:
	return CitySimulationServiceScript.tax_pressure_score(tax_rates, TAX_DEFS)

func _average_utility_fee_ratio() -> float:
	return CitySimulationServiceScript.average_utility_fee_ratio(utility_fees, UTILITY_DEFS)

func _infrastructure_warnings() -> Array[String]:
	return CitySimulationServiceScript.infrastructure_warnings(
		utility_fees,
		UTILITY_DEFS,
		city_grid
	)

func _active_law_value(effect_key: String) -> float:
	var total := 0.0
	if vertical_slice == null or vertical_slice.governance == null:
		return total
	for law in vertical_slice.governance.active_laws.values():
		if str(law.get("status", "active")) != "active":
			continue
		var effects: Dictionary = law.get("effects", {})
		total += float(effects.get(effect_key, 0.0))
	return total

func _citizen_comment() -> String:
	if _average_utility_fee_ratio() > 1.75:
		return "公共事業費用過高，居民負擔明顯增加。"
	if int(tax_rates["income"]) > 24:
		return "所得稅偏高，一般居民對負擔表達不滿。"
	if int(tax_rates["business"]) > 20:
		return "商業營業稅過高，商人族群開始抱怨。"
	if int(tax_rates["industry"]) > 20:
		return "工業營業稅過高，工廠收益下降。"
	if environment < 40:
		return "市民抱怨城市污染嚴重。"
	if security < 40:
		return "市民擔心夜間安全問題。"
	if total_satisfaction > 80:
		return "市民普遍支持目前市政方向。"
	if total_satisfaction >= 60:
		return "市民對城市發展大致滿意。"
	if total_satisfaction >= 40:
		return "市民開始對部分政策感到不安。"
	return "市民抗議聲浪逐漸升高。"

func _rating_for_score(score: int) -> String:
	return CitySimulationServiceScript.rating_for_score(score)

func _bill_status_text() -> String:
	return str(vertical_slice.get_view_model(selected_cell_index).get("governance_text", ""))

func _tax_detail_text(tax_key: String, revenue: int) -> String:
	var def: Dictionary = TAX_DEFS[tax_key]
	var forecast := _fiscal_item_forecast("tax", tax_key)
	return L10n.text("收入 $%d｜%s") % [revenue, forecast["summary"]]

func _utility_detail_text(fee_key: String, projection_utility: Dictionary = {}) -> String:
	var def: Dictionary = UTILITY_DEFS[fee_key]
	var has_building := _building_count(def["building"]) > 0
	var building_name := L10n.text(str(def["building"]))
	var note := (L10n.text("有%s") % building_name) if has_building else (L10n.text("缺%s") % building_name)
	var forecast := _fiscal_item_forecast("utility", fee_key)
	return L10n.text("收入 $%d｜%s｜%s") % [int(round(_utility_fee_income(fee_key, _utility_base_units(fee_key), projection_utility))), note, forecast["summary"]]

func _service_detail_text(service_key: String, projection_service: Dictionary = {}) -> String:
	var def: Dictionary = SERVICE_DEFS[service_key]
	if service_key == "medical":
		var healthcare_result := _healthcare_service_result()
		var medical_forecast := _fiscal_item_forecast("service", service_key)
		return L10n.text("收入 $%d｜%s｜%s") % [
			_service_fee_income(service_key, projection_service),
			_healthcare_service_visible_text(healthcare_result),
			str(medical_forecast["summary"]),
		]
	var has_building := _building_count(def["building"]) > 0
	var building_name := L10n.text(str(def["building"]))
	var note := (L10n.text("有%s") % building_name) if has_building else (L10n.text("缺%s") % building_name)
	var forecast := _fiscal_item_forecast("service", service_key)
	return L10n.text("收入 $%d｜%s｜%s") % [_service_fee_income(service_key, projection_service), note, forecast["summary"]]

func _update_ui() -> void:
	_sync_vertical_state()
	# Finance renders through explicit projection dictionaries. Draft values never
	# replace the authoritative simulation/save dictionaries, even temporarily.
	var fiscal_tax_values: Dictionary = _fiscal_draft_tax_rates if _fiscal_draft_active else tax_rates
	var fiscal_utility_values: Dictionary = _fiscal_draft_utility_fees if _fiscal_draft_active else utility_fees
	var fiscal_service_values: Dictionary = _fiscal_draft_service_fees if _fiscal_draft_active else service_fees
	var terrain = _terrain_map()
	if city_backdrop != null and terrain != null:
		city_backdrop.call("set_terrain_snapshot", terrain.to_dict())
	_refresh_time_hud()
	labels["funds"].text = _format_currency(funds)
	labels["funds"].tooltip_text = L10n.text("城市公庫：$%d") % funds
	labels["population"].text = "%s %d" % [L10n.text("人口"), population]
	labels["population"].tooltip_text = L10n.text("城市人口：%d 人") % population
	labels["satisfaction"].text = "%s %d" % [L10n.text("滿意"), total_satisfaction]
	labels["satisfaction"].tooltip_text = L10n.text("整體居民滿意度：%d") % total_satisfaction
	var grievance := int(vertical_slice.governance.grievance) if vertical_slice != null else 0
	var trust := int(vertical_slice.governance.municipal_trust) if vertical_slice != null else 75
	labels["grievance"].text = "%s %d↓" % [L10n.text("民怨"), grievance]
	labels["trust"].text = "%s %d" % [L10n.text("信任"), trust]
	labels["grievance"].tooltip_text = L10n.text("居民民怨：%d；越低越好。") % grievance
	labels["trust"].tooltip_text = L10n.text("市政信任：%d；越高越好。") % trust
	var header_text_color := Color("fff4d7") if is_dark_mode else Color("35291f")
	labels["grievance"].add_theme_color_override(
		"font_color",
		(Color("ff806c") if is_dark_mode else Color("a72f26")) if grievance >= 70 else header_text_color
	)
	labels["trust"].add_theme_color_override(
		"font_color",
		(Color("ffd36a") if is_dark_mode else Color("8a5d00")) if trust <= 50 else header_text_color
	)
	labels["score"].text = "%s %d" % [L10n.text("評分"), ranking_score]
	labels["score"].tooltip_text = L10n.text("本局最高評分：%d") % best_score
	labels["rating"].text = "%s" % L10n.text(city_rating)
	labels["rating"].tooltip_text = L10n.text("目前城市評級：%s") % L10n.text(city_rating)
	_set_bar_visual(header_bars["funds"], minf(100.0, maxf(0.0, float(funds) / 500000.0 * 100.0)), COLOR_SUCCESS if funds >= 0 else COLOR_WARNING)
	_set_bar_visual(header_bars["population"], minf(100.0, float(population) / 1000.0 * 100.0), COLOR_INFO)
	_set_bar_visual(header_bars["satisfaction"], float(total_satisfaction), _score_color(total_satisfaction))
	# The bar and number now encode the same raw grievance direction. Color still
	# communicates that a short/low bar is healthy, and the down-arrow plus
	# tooltip explicitly state that lower is better.
	_set_bar_visual(header_bars["grievance"], float(grievance), _score_color(grievance, true))
	_set_bar_visual(header_bars["trust"], float(trust), _score_color(trust))
	_set_bar_visual(header_bars["score"], float(ranking_score), COLOR_GOLD)
	_set_bar_visual(header_bars["rating"], float(ranking_score), COLOR_GOLD)
	if municipal_overlay != null:
		for tax_key in tax_rates.keys():
			var tax_forecast := _fiscal_item_forecast("tax", tax_key)
			var tax_value_label := _cached_fiscal_label("tax_value_%s" % tax_key)
			if tax_value_label != null:
				tax_value_label.text = "%s  ● %s" % [_fiscal_display_value("tax", tax_key, "%"), tax_forecast["state_text"]]
				tax_value_label.add_theme_color_override("font_color", tax_forecast["color"])
			var tax_slider := _cached_fiscal_slider(tax_sliders, tax_key)
			if tax_slider != null:
				_apply_fee_slider_visual(tax_slider, str(tax_forecast["state"]))
				tax_slider.tooltip_text = str(tax_forecast["summary"])
		for fee_key in utility_fees.keys():
			var utility_forecast := _fiscal_item_forecast("utility", fee_key)
			var utility_value_label := _cached_fiscal_label("utility_%s" % fee_key)
			if utility_value_label != null:
				utility_value_label.text = "%s  ● %s" % [_fiscal_display_value("utility", fee_key, " / %s" % UTILITY_DEFS[fee_key]["unit"]), utility_forecast["state_text"]]
				utility_value_label.add_theme_color_override("font_color", utility_forecast["color"])
			var utility_slider := _cached_fiscal_slider(utility_sliders, fee_key)
			if utility_slider != null:
				_apply_fee_slider_visual(utility_slider, str(utility_forecast["state"]))
				utility_slider.tooltip_text = str(utility_forecast["summary"])
		for service_key in service_fees.keys():
			var service_forecast := _fiscal_item_forecast("service", service_key)
			var service_value_label := _cached_fiscal_label("service_%s" % service_key)
			if service_value_label != null:
				service_value_label.text = "%s  ● %s" % [_fiscal_display_value("service", service_key, " / %s" % SERVICE_DEFS[service_key]["unit"]), service_forecast["state_text"]]
				service_value_label.add_theme_color_override("font_color", service_forecast["color"])
			var service_slider := _cached_fiscal_slider(service_sliders, service_key)
			if service_slider != null:
				_apply_fee_slider_visual(service_slider, str(service_forecast["state"]))
				service_slider.tooltip_text = str(service_forecast["summary"])
	if selected_label != null:
		selected_label.text = L10n.text("%s　基礎造價 $%d\n%s") % [
			L10n.text(selected_building),
			buildings[selected_building]["cost"],
			_visual_effects(buildings[selected_building], 3)
		]
	if report_label != null:
		report_label.text = _current_month_major_event_summary()
	if report_details_label != null:
		report_details_label.text = last_report_details
	_update_metric_visual("治安", security)
	_update_metric_visual("環境", environment)
	_update_metric_visual("交通", traffic)
	_update_metric_visual("教育", education)
	_update_metric_visual("醫療", healthcare)
	_update_city_metric_cards()

	var tax_revenues := _tax_revenues_for(fiscal_tax_values)
	if municipal_overlay != null:
		for tax_key in tax_rates.keys():
			var tax_detail_label := _cached_fiscal_label("tax_detail_%s" % tax_key)
			if tax_detail_label != null:
				tax_detail_label.text = _tax_detail_text(tax_key, tax_revenues[tax_key])
		for fee_key in utility_fees.keys():
			var utility_detail_label := _cached_fiscal_label("utility_detail_%s" % fee_key)
			if utility_detail_label != null:
				utility_detail_label.text = _utility_detail_text(fee_key, fiscal_utility_values)
		for service_key in service_fees.keys():
			var service_detail_label := _cached_fiscal_label("service_detail_%s" % service_key)
			if service_detail_label != null:
				service_detail_label.text = _service_detail_text(service_key, fiscal_service_values)
	var maintenance := _maintenance_cost()
	var policy_expense := _policy_expense()
	var law_expense := _active_law_expense()
	var city_data_finance := _city_data_finance_snapshot_for(
		fiscal_tax_values,
		fiscal_utility_values,
		fiscal_service_values,
		maintenance,
		policy_expense,
		law_expense
	)
	var tax_income := int(city_data_finance["tax_income"])
	var business_income := int(city_data_finance["business_income"])
	var industrial_income := int(city_data_finance["industrial_income"])
	var utility_income := int(city_data_finance["utility_income"])
	var service_income := int(city_data_finance["service_income"])
	var total_income := int(city_data_finance["total_income"])
	var total_expense := int(city_data_finance["total_expense"])
	var net_income := int(city_data_finance["net_income"])
	if labels.has("income_tax"):
		labels["income_tax"].text = _tax_detail_text("income", tax_revenues["income"])
	if labels.has("consumption_tax"):
		labels["consumption_tax"].text = _tax_detail_text("consumption", tax_revenues["consumption"])
	if labels.has("business_tax"):
		labels["business_tax"].text = _tax_detail_text("business", tax_revenues["business"])
	if labels.has("industry_tax"):
		labels["industry_tax"].text = _tax_detail_text("industry", tax_revenues["industry"])
	_refresh_city_data_dashboard(city_data_finance)
	var income_scale := maxi(1, total_income)
	var expense_scale := maxi(1, maxi(total_income, total_expense))
	var safety_buffer := _fiscal_safety_buffer()
	var fiscal_color := COLOR_SUCCESS if net_income >= safety_buffer else (COLOR_CAUTION if net_income >= 0 else COLOR_WARNING)
	_update_finance_visual("fiscal_total_income", total_income, income_scale, COLOR_SUCCESS)
	_update_finance_visual("fiscal_total_expense", total_expense, expense_scale, COLOR_WARNING)
	_update_finance_visual("fiscal_net_income", net_income, maxi(1, maxi(total_income, total_expense)), fiscal_color, true)
	_update_finance_visual("fiscal_safety_buffer", safety_buffer, maxi(1, total_expense), COLOR_CAUTION)
	if labels.has("fiscal_operating_status"):
		var operating_status: Label = labels["fiscal_operating_status"]
		if net_income < 0:
			operating_status.text = "● 赤字預警\n目前收費不足以支應每月市政運作。"
		elif net_income < safety_buffer:
			operating_status.text = "● 緩衝不足\n可運作，但無法承受收入波動。"
		else:
			operating_status.text = "● 財政安全\n預估淨額已覆蓋市政支出與安全緩衝。"
		operating_status.add_theme_color_override("font_color", fiscal_color)
	_update_finance_visual("tax_income", tax_income, income_scale, COLOR_SUCCESS)
	_update_finance_visual("business_income", business_income, income_scale, Color(0.10, 0.55, 0.72))
	_update_finance_visual("industrial_income", industrial_income, income_scale, Color(0.45, 0.42, 0.72))
	_update_finance_visual("utility_income", utility_income, income_scale, Color(0.14, 0.60, 0.52))
	_update_finance_visual("service_income", service_income, income_scale, Color(0.25, 0.60, 0.76))
	_update_finance_visual("maintenance", maintenance, expense_scale, COLOR_WARNING)
	_update_finance_visual("policy_expense", policy_expense, expense_scale, Color(0.88, 0.38, 0.12))
	_update_finance_visual("law_expense", law_expense, expense_scale, Color(0.70, 0.25, 0.18))
	_update_finance_visual("net_income", net_income, income_scale, COLOR_SUCCESS if net_income >= 0 else COLOR_WARNING, true)
	for i in CELL_COUNT:
		var item := city_grid[i]
		_update_tile_visual(i, item)
	_update_transport_runtime(false)
	_refresh_transport_planning_panel()

	for building_name in building_buttons.keys():
		var button: Button = building_buttons[building_name]
		var data: Dictionary = buildings[building_name]
		button.text = _building_visual_text(building_name, data)
		button.tooltip_text = "%s\n%s\n%s" % [L10n.text(building_name), L10n.text(str(data.get("description", ""))), _visual_effects(data, 8)]
		button.disabled = false
		_apply_building_button_style(button, building_name, building_name == selected_building)

	_refresh_governance_catalog()
	_refresh_lower_council_stage()
	for policy_name in policy_checks.keys():
		_apply_policy_style(policy_checks[policy_name], active_policies[policy_name])

	for bill_name in bill_buttons.keys():
		var bill_status := _governance_bill_status(bill_name)
		bill_buttons[bill_name].disabled = bill_status != "unimplemented" or not vertical_slice.governance.pending_bill.is_empty()

	if bill_status_label:
		bill_status_label.text = _bill_status_text()
	if announcement_label:
		announcement_label.text = _version_update_announcement_text()
	_update_scoped_municipal_pages(vertical_slice.get_view_model(selected_cell_index))
	if judicial_panel:
		judicial_panel.refresh(vertical_slice.governance.justice_system)
	if oversight_panel:
		oversight_panel.refresh(vertical_slice.governance.justice_system)
	_update_building_info_panel()
	_refresh_fiscal_draft_actions()
	_localize_ui_without_hidden_municipal_pages()
	_sync_placement_banner()
	# Tile/NPC refreshes above restore their normal tooltip text. Re-apply the
	# current UI blocking state last so a start screen or modal remains authoritative.
	_sync_map_interaction_for_ui()


func _localize_ui_without_hidden_municipal_pages() -> void:
	# The municipal overlay is allocated lazily, but once allocated it owns all
	# page trees. Rewalking those hidden siblings on every general UI refresh
	# turns a single page transition into a long synchronous frame. Localize the
	# ordinary top-level UI as before, then ask the overlay to localize only its
	# shell and currently visible surface.
	for child in get_children():
		if child == municipal_overlay:
			municipal_overlay.localize_current_surface()
		else:
			L10n.localize_tree(child)

func _set_hint(message: String, warning: bool) -> void:
	if hint_label == null or feedback_toast == null:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	hint_label.text = L10n.text(message)
	if warning and _game_started and audio_director != null:
		audio_director.play_warning()
	hint_label.add_theme_color_override("font_color", TOAST_WARNING_TEXT if warning else TOAST_SUCCESS_TEXT)
	feedback_toast.modulate.a = 1.0
	feedback_toast.show()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(2.8)
	_hint_tween.tween_property(feedback_toast, "modulate:a", 0.0, 0.28)
	_hint_tween.tween_callback(feedback_toast.hide)

func _toggle_theme() -> void:
	_set_theme(not is_dark_mode, false)


func _set_theme(dark_mode: bool, reopen_settings: bool) -> void:
	if is_dark_mode == dark_mode:
		if reopen_settings and settings_overlay != null:
			settings_overlay.open()
		return
	is_dark_mode = dark_mode
	_rebuild_ui()
	if reopen_settings and settings_overlay != null:
		settings_overlay.open()
	_autosave("action:theme_toggled")


func _on_music_selected(enabled: bool) -> void:
	music_enabled = enabled
	if audio_director != null:
		audio_director.set_music_enabled(enabled)
	_save_audio_preferences()
	_autosave("action:music_toggled")


func _on_sfx_selected(enabled: bool) -> void:
	sfx_enabled = enabled
	if audio_director != null:
		audio_director.set_sfx_enabled(enabled)
	_save_audio_preferences()
	_autosave("action:sfx_toggled")


func _on_music_volume_selected(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if audio_director != null:
		audio_director.set_music_volume(music_volume)
	_save_audio_preferences()
	_autosave("action:music_volume_changed")


func _on_sfx_volume_selected(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if audio_director != null:
		audio_director.set_sfx_volume(sfx_volume)
	_save_audio_preferences()
	_autosave("action:sfx_volume_changed")


func _save_audio_preferences() -> Error:
	_audio_preferences_found = true
	return UserSettingsServiceScript.save_audio_preferences({
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
	})


func _replay_tutorial() -> void:
	if tutorial_overlay == null:
		return
	_tutorial_replay_active = true
	_set_map_interaction_enabled(false)
	tutorial_overlay.open(true)
	_sync_time_pause_for_ui()


func _on_tutorial_audio_cue(cue: String) -> void:
	if audio_director != null:
		audio_director.play_cue(cue)


func _on_tutorial_completed(skipped: bool) -> void:
	var replay_only := _tutorial_replay_active
	_tutorial_replay_active = false
	if not replay_only and onboarding_progress.is_story_pending():
		onboarding_progress.begin_guide()
	tutorial_completed = not onboarding_progress.is_story_pending()
	_refresh_onboarding_guide()
	_sync_time_pause_for_ui()
	_set_hint("故事教學已略過；實作導覽將從興建開始。" if skipped else "故事教學完成；實作導覽將從興建開始。", false)
	if not replay_only:
		_autosave("onboarding:story_skipped" if skipped else "onboarding:story_completed")


func _on_onboarding_advanced(_target_id: String, _receipt: Dictionary) -> void:
	tutorial_completed = not onboarding_progress.is_story_pending()
	_sync_time_pause_for_ui()
	_sync_map_interaction_for_ui()
	_autosave("onboarding:step_completed")


func _on_onboarding_defer_requested() -> void:
	if vertical_slice == null:
		return
	if not onboarding_progress.defer_current_target(vertical_slice.game_day()):
		return
	_refresh_onboarding_guide()
	_autosave("onboarding:deferred")


func _on_onboarding_result_review_confirmed() -> void:
	if vertical_slice == null or not onboarding_progress.is_active():
		return
	var mode := onboarding_progress.current_target()
	if mode not in ["judicial", "oversight"] or onboarding_progress.is_waiting(vertical_slice.game_day()):
		return
	var event_book: Array = vertical_slice.session.state.event_book
	var case_id := onboarding_action_router.linked_case_id(mode, event_book)
	var cases: Dictionary = (
		vertical_slice.governance.judiciary_cases
		if mode == "judicial"
		else vertical_slice.governance.oversight_cases
	)
	if case_id.is_empty() or not cases.has(case_id) or not (cases[case_id] is Dictionary):
		return
	if not onboarding_action_router.record_case_result_review_success(
		mode,
		Dictionary(cases[case_id]).duplicate(true),
		vertical_slice.governance,
		event_book,
		vertical_slice.game_day()
	):
		return
	if onboarding_progress.is_completed():
		tutorial_completed = true
	_set_hint("已閱讀%s結案結果。" % ("司法案件" if mode == "judicial" else "監察案件"), false)
	_autosave("onboarding:%s_result_reviewed" % mode)
	_refresh_onboarding_guide()


func _wire_ui_sounds() -> void:
	if audio_director == null:
		return
	var click_callable := Callable(audio_director, "play_ui_click")
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		if tutorial_overlay != null and tutorial_overlay.is_ancestor_of(button):
			continue
		if not button.pressed.is_connected(click_callable):
			button.pressed.connect(click_callable)

func _rebuild_ui() -> void:
	if npc_map_controller != null:
		npc_map_controller.unmount()
	onboarding_action_router.reset_transient_evidence()
	if onboarding_guide != null:
		onboarding_guide.invalidate_target()
	for child in get_children():
		if child == audio_director:
			continue
		remove_child(child)
		child.queue_free()
	grid_buttons.clear()
	building_buttons.clear()
	building_group_buttons.clear()
	building_group_pages.clear()
	building_card_pagers.clear()
	city_metric_cards.clear()
	city_metric_primary_grid = null
	city_metric_secondary_grid = null
	city_metric_priority_label = null
	city_metric_details_button = null
	_city_metric_layout_signature = ""
	report_details_label = null
	report_details_panel = null
	report_details_button = null
	building_family_tabs = null
	policy_checks.clear()
	labels.clear()
	bars.clear()
	tax_sliders.clear()
	utility_sliders.clear()
	service_sliders.clear()
	tax_inputs.clear()
	utility_inputs.clear()
	service_inputs.clear()
	fiscal_apply_button = null
	fiscal_discard_button = null
	fiscal_preview_button = null
	fiscal_back_to_edit_button = null
	fiscal_draft_status_label = null
	fiscal_category_surface = null
	fiscal_category_grid = null
	fiscal_plan_surface = null
	fiscal_plan_title = null
	fiscal_plan_hint = null
	fiscal_custom_editor = null
	fiscal_custom_pages.clear()
	fiscal_draft_preview = null
	fiscal_draft_change_list = null
	fiscal_draft_risk_label = null
	fiscal_responsive_layout = null
	fiscal_page_scroll = null
	_selected_fiscal_category = ""
	_selected_fiscal_plan = ""
	_fiscal_draft_active = false
	_fiscal_flow_step = "edit"
	_fiscal_draft_revision = 0
	_fiscal_preview_revision = -1
	bill_buttons.clear()
	governance_status_tabs = null
	governance_status_grids.clear()
	governance_status_pagers.clear()
	governance_status_sections.clear()
	governance_status_empty_labels.clear()
	governance_bill_cards.clear()
	governance_policy_cards.clear()
	governance_catalog_title = null
	governance_catalog_legend = null
	governance_force_panel = null
	lower_council_stage = null
	map_stage = null
	city_backdrop = null
	tile_layer = null
	npc_layer = null
	npc_map_controller = null
	weather_visual_layer = null
	npc_dialogue_card = null
	npc_dialogue_label = null
	_active_npc_dialogue_index = -1
	_npc_dialogue_remaining_seconds = 0.0
	_npc_proxy_refresh_pending = false
	municipal_button = null
	settings_button = null
	exit_button = null
	language_selector = null
	municipal_overlay = null
	settings_overlay = null
	tutorial_overlay = null
	onboarding_guide = null
	construction_confirmation = null
	exit_confirmation = null
	start_screen = null
	action_dock = null
	status_hud = null
	feedback_toast = null
	placement_banner = null
	placement_label = null
	placement_cancel_button = null
	_hint_tween = null
	hint_label = null
	building_info_label = null
	customization_label = null
	vertical_slice_panel = null
	judicial_panel = null
	oversight_panel = null
	public_affairs_panel = null
	building_context_panel = null
	city_data_dashboard = null
	governance_force_label = null
	governance_force_button = null
	_pending_construction_tile = -1
	_build_ui()
	_update_ui()
	call_deferred("_refresh_onboarding_guide")

func _number_input(text: String) -> LineEdit:
	var input := LineEdit.new()
	input.text = text
	input.custom_minimum_size = Vector2(68, 44)
	input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	input.add_theme_font_size_override("font_size", 18)
	input.add_theme_color_override("font_color", _theme_text())
	input.add_theme_color_override("font_placeholder_color", _theme_muted())
	return input

func _commit_number_input(kind: String, key: String, raw_text: String) -> void:
	var cleaned := raw_text.strip_edges()
	if cleaned == "" or not cleaned.is_valid_int():
		_restore_number_input(kind, key)
		return

	var value := int(cleaned)
	_set_fiscal_draft_value(kind, key, value)

func _restore_number_input(kind: String, key: String) -> void:
	var value: int = int(_fiscal_draft_dictionary(kind).get(key, _fiscal_value(kind, key))) if _fiscal_draft_active else _fiscal_value(kind, key)
	if kind == "tax":
		_sync_number_input(tax_inputs, key, int(value), true)
	elif kind == "utility":
		_sync_number_input(utility_inputs, key, int(value), true)
	elif kind == "service":
		_sync_number_input(service_inputs, key, int(value), true)

func _sync_number_input(inputs: Dictionary, key: String, value: int, force: bool = false) -> void:
	if not inputs.has(key):
		return
	var input_variant: Variant = inputs[key]
	if not input_variant is LineEdit:
		return
	var input := input_variant as LineEdit
	if force or not input.has_focus():
		input.text = str(value)


func _cached_fiscal_slider(sliders: Dictionary, key: String) -> HSlider:
	if not sliders.has(key):
		return null
	var slider_variant: Variant = sliders[key]
	return slider_variant as HSlider if slider_variant is HSlider else null


func _cached_fiscal_label(key: String) -> Label:
	if not labels.has(key):
		return null
	var label_variant: Variant = labels[key]
	return label_variant as Label if label_variant is Label else null


func _panel(color: Color, radius: int, padding: int = 14) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(2)
	style.border_color = _theme_border()
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_constant_override("margin_left", padding)
	panel.add_theme_constant_override("margin_top", padding)
	panel.add_theme_constant_override("margin_right", padding)
	panel.add_theme_constant_override("margin_bottom", padding)
	return panel

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _readable_font_size(size))
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _format_grouped_int(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		var split_at := digits.length() - 3
		grouped = ",%s%s" % [digits.substr(split_at, 3), grouped]
		digits = digits.substr(0, split_at)
	return "%s%s%s" % ["-" if value < 0 else "", digits, grouped]


func _format_currency(value: int) -> String:
	return "$%s" % _format_grouped_int(value)


func _format_signed_currency(value: int) -> String:
	return "%s$%s" % ["+" if value >= 0 else "-", _format_grouped_int(absi(value))]


func _refresh_time_hud() -> void:
	if vertical_slice == null or not labels.has("month"):
		return
	var paused: bool = bool(vertical_slice.is_time_paused())
	var status_text := L10n.text("暫停") if paused else L10n.text("自動")
	labels["month"].text = "%d/%d · %s" % [month, day, status_text]
	labels["month"].tooltip_text = L10n.text(
		"管理或教學畫面開啟時會自動暫停，日期區不需點擊。"
		if paused
		else "遊戲時間每 120 秒自動推進一天，日期區不需點擊。"
	)
	if header_bars.has("month"):
		_set_bar_visual(header_bars["month"], (float((month - 1) * 30 + day) / 360.0) * 100.0, COLOR_CAUTION if paused else COLOR_INFO)

func _section_title(text: String) -> Label:
	var title := _label(text, 21, _theme_text())
	title.custom_minimum_size = Vector2(0, 38)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	return title

func _category_title(text: String) -> Label:
	var title := _label(text, 16, _theme_muted())
	title.custom_minimum_size = Vector2(0, 28)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	return title

func _button(text: String, variant: String = "normal") -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", UI_CONTROL_FONT_SIZE)
	_apply_button_style(button, variant)
	return button

func _apply_button_style(button: Button, variant: String = "normal") -> void:
	var is_primary := variant == "primary"
	var is_danger := variant == "danger"
	var normal := StyleBoxFlat.new()
	normal.bg_color = SemanticPalette.color_for(is_dark_mode, "danger") if is_danger else (SemanticPalette.color_for(is_dark_mode, "action_primary") if is_primary else SemanticPalette.color_for(is_dark_mode, "surface_raised"))
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	normal.border_color = SemanticPalette.color_for(is_dark_mode, "danger") if is_danger else (SemanticPalette.color_for(is_dark_mode, "border_focus") if is_primary else _theme_border())
	var hover := normal.duplicate()
	hover.bg_color = SemanticPalette.color_for(is_dark_mode, "danger") if is_danger else (SemanticPalette.color_for(is_dark_mode, "action_primary_hover") if is_primary else SemanticPalette.color_for(is_dark_mode, "surface_muted"))
	hover.border_color = SemanticPalette.color_for(is_dark_mode, "border_focus")
	var pressed := normal.duplicate()
	pressed.bg_color = SemanticPalette.color_for(is_dark_mode, "danger") if is_danger else (SemanticPalette.color_for(is_dark_mode, "action_primary_hover") if is_primary else SemanticPalette.color_for(is_dark_mode, "surface_base"))
	var disabled := normal.duplicate()
	disabled.bg_color = SemanticPalette.color_for(is_dark_mode, "action_primary_disabled")
	disabled.border_color = SemanticPalette.color_for(is_dark_mode, "border_disabled")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	var action_text := SemanticPalette.color_for(is_dark_mode, "text_on_accent")
	button.add_theme_color_override("font_color", action_text if is_primary or is_danger else _theme_text())
	button.add_theme_color_override("font_hover_color", action_text if is_primary or is_danger else _theme_text())
	button.add_theme_color_override("font_pressed_color", action_text if is_primary or is_danger else _theme_text())
	button.add_theme_color_override("font_focus_color", action_text if is_primary or is_danger else _theme_text())
	button.add_theme_color_override("font_disabled_color", SemanticPalette.color_for(is_dark_mode, "text_disabled"))

func _apply_cell_style(button: Button, item: String) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	if item == "":
		style.bg_color = Color(0.78, 0.91, 0.62) if not is_dark_mode else Color(0.18, 0.30, 0.18)
		style.border_color = Color(0.48, 0.66, 0.38) if not is_dark_mode else Color(0.35, 0.48, 0.31)
		button.add_theme_color_override("font_color", Color(0.12, 0.28, 0.14) if not is_dark_mode else Color(0.78, 0.93, 0.72))
		button.add_theme_color_override("font_hover_color", Color(0.08, 0.22, 0.10) if not is_dark_mode else Color(0.88, 1.0, 0.78))
	else:
		var base := _building_color(item)
		style.bg_color = _lighten(base, 0.22) if not is_dark_mode else _darken(base, 0.28)
		style.border_color = _darken(base, 0.30)
		button.add_theme_color_override("font_color", _readable_text_color(style.bg_color))
		button.add_theme_color_override("font_hover_color", _readable_text_color(_lighten(style.bg_color, 0.08)))
	var hover := style.duplicate()
	hover.bg_color = Color(0.88, 0.97, 0.70) if item == "" else _lighten(style.bg_color, 0.12)
	var pressed := style.duplicate()
	pressed.bg_color = Color(0.70, 0.86, 0.56) if item == "" else _darken(style.bg_color, 0.08)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

func _apply_building_button_style(button: Button, building_name: String, selected: bool) -> void:
	var base_color := _building_color(building_name)
	var text_color := _building_text_color(building_name)
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	if selected:
		normal.bg_color = _lighten(base_color, 0.12)
		normal.border_color = Color(0.02, 0.10, 0.16)
	else:
		normal.bg_color = _lighten(base_color, 0.28)
		normal.border_color = _darken(base_color, 0.18)
	var hover := normal.duplicate()
	hover.bg_color = _lighten(base_color, 0.18)
	var pressed := normal.duplicate()
	pressed.bg_color = base_color
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.78, 0.82, 0.85)
	disabled.border_color = Color(0.56, 0.61, 0.66)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", text_color if selected else _readable_text_color(normal.bg_color))
	button.add_theme_color_override("font_hover_color", _readable_text_color(hover.bg_color))
	button.add_theme_color_override("font_pressed_color", _building_text_color(building_name))
	button.add_theme_color_override("font_disabled_color", Color(0.31, 0.36, 0.40))

func _apply_policy_style(check: CheckBox, enabled: bool) -> void:
	var color := COLOR_SUCCESS if enabled else _theme_text()
	check.add_theme_color_override("font_color", color)
	check.add_theme_color_override("font_hover_color", _theme_accent_text())
	check.add_theme_color_override("font_pressed_color", color)
	check.add_theme_color_override("font_hover_pressed_color", color)
	check.add_theme_color_override("font_focus_color", color)

func _style_progress_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.79, 0.86, 0.90)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_ACCENT
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)

func _style_tabs(tabs: TabContainer) -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _theme_panel()
	panel_style.border_color = _theme_border()
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	tabs.add_theme_stylebox_override("panel", panel_style)

	var unselected_style := StyleBoxFlat.new()
	unselected_style.bg_color = _theme_panel_alt()
	unselected_style.border_color = _theme_border()
	unselected_style.set_border_width_all(2)
	unselected_style.set_corner_radius_all(8)
	# Tab labels previously touched adjacent borders in long locales. Explicit
	# content padding keeps every visible tab distinct; clipped tabs remain
	# reachable through TabBar's scrolling arrows.
	unselected_style.content_margin_left = 12
	unselected_style.content_margin_right = 12
	unselected_style.content_margin_top = 6
	unselected_style.content_margin_bottom = 6
	var selected_style := unselected_style.duplicate() as StyleBoxFlat
	selected_style.bg_color = SemanticPalette.color_for(is_dark_mode, "surface_muted")
	selected_style.border_color = SemanticPalette.color_for(is_dark_mode, "border_focus")
	selected_style.shadow_color = Color(0, 0, 0, 0.16)
	selected_style.shadow_size = 2
	var hovered_style := unselected_style.duplicate() as StyleBoxFlat
	hovered_style.bg_color = SemanticPalette.color_for(is_dark_mode, "surface_raised")
	hovered_style.border_color = SemanticPalette.color_for(is_dark_mode, "border_focus")
	tabs.add_theme_stylebox_override("tab_selected", selected_style)
	tabs.add_theme_stylebox_override("tab_unselected", unselected_style)
	tabs.add_theme_stylebox_override("tab_hovered", hovered_style)
	tabs.add_theme_stylebox_override("tab_focus", selected_style)
	tabs.add_theme_color_override("font_selected_color", _theme_text())
	tabs.add_theme_color_override("font_unselected_color", _theme_muted())
	tabs.add_theme_color_override("font_hovered_color", _theme_text())
	tabs.add_theme_color_override("font_focus_color", _theme_text())
	tabs.add_theme_font_size_override("font_size", UI_CONTROL_FONT_SIZE)
	tabs.add_theme_constant_override("side_margin", 8)

func _readable_font_size(requested_size: int) -> int:
	if requested_size >= 24:
		return requested_size + 1
	return maxi(UI_MIN_FONT_SIZE, requested_size + 3)

func _buildings_in_category(category: String) -> Array[String]:
	var names: Array[String] = []
	for building_name in buildings.keys():
		if str(buildings[building_name].get("category", "")) == category:
			names.append(building_name)
	return names

func _update_tile_visual(index: int, building_name: String) -> void:
	if index < 0 or index >= grid_buttons.size():
		return
	var cell: Button = grid_buttons[index]
	cell.position = _iso_tile_position(index)
	cell.z_index = int(_iso_tile_center(index).y)
	if cell.has_method("set_tile"):
		var active_construction: Dictionary = vertical_slice.active_construction_for_tile(index) if vertical_slice != null else {}
		var footprint_view: Dictionary = vertical_slice.footprint_cell_view(index) if vertical_slice != null else {}
		var visual_building_name := building_name
		var owner_anchor_tile_id := index
		var footprint_role := "none"
		var footprint_index := 0
		var footprint_count := 1
		var footprint_id := ""
		if not footprint_view.is_empty():
			owner_anchor_tile_id = int(footprint_view.get("owner_anchor_tile_id", index))
			footprint_role = str(footprint_view.get("role", "none"))
			footprint_index = int(footprint_view.get("footprint_index", 0))
			footprint_count = int(footprint_view.get("footprint_count", 1))
			footprint_id = str(footprint_view.get("footprint_id", ""))
			if str(footprint_view.get("kind", "")) == "building":
				visual_building_name = str(footprint_view.get("building_name", building_name))
		elif not active_construction.is_empty():
			footprint_role = "anchor"
		var terrain_state: Dictionary = vertical_slice.terrain_state_for_tile(index) if vertical_slice != null else {}
		var terrain_buildable := bool(terrain_state.get("buildable", true))
		var building_placement_buildable := terrain_buildable
		if placement_mode_active and not _is_transport_station_session_placement() and vertical_slice != null:
			building_placement_buildable = vertical_slice.is_building_tile_buildable(index)
		var preview := {}
		if placement_mode_active and index == _placement_preview_anchor:
			preview = _placement_preview.duplicate(true)
		cell.call("set_tile", {
			"index": index,
			"building_name": visual_building_name,
			"building_color": _building_color(visual_building_name),
			"terrain_kind": _terrain_kind_for_cell(index, visual_building_name),
			"terrain_type": str(terrain_state.get("effective_kind", "flat_grass")),
			"terrain_buildable": terrain_buildable,
			"terrain_flattenable": bool(terrain_state.get("flattenable", false)),
			"terrain_flattened": bool(terrain_state.get("flattened", false)),
			"visual": BUILDING_VISUALS.get(visual_building_name, {}),
			"customization": building_customizations.get(owner_anchor_tile_id, {}),
			"dark_mode": is_dark_mode,
			"selected": selected_cell_index == owner_anchor_tile_id,
			"is_building_mode": placement_mode_active,
			"placement_allowed": _is_tile_inside_hud_safe_area(index) and building_placement_buildable,
			"construction": active_construction,
			"footprint_role": footprint_role,
			"footprint_index": footprint_index,
			"footprint_count": footprint_count,
			"footprint_id": footprint_id,
			"owner_anchor_tile_id": owner_anchor_tile_id,
			"placement_preview": preview,
			"transport_planning_overlay": _transport_planning_overlay_for_tile(index),
		})
		if not active_construction.is_empty():
			cell.tooltip_text = _construction_job_player_text(active_construction)
		elif visual_building_name.is_empty():
			var transport_state := _transport_tile_visual_state(index)
			if _transport_tile_has_player_content(transport_state):
				cell.tooltip_text = _transport_tile_player_text(transport_state)
	else:
		cell.text = _tile_text(building_name, index)
		_apply_cell_style(cell, building_name)


func _transport_tile_visual_state(tile_index: int) -> Dictionary:
	if vertical_slice == null or vertical_slice.transport == null:
		return {}
	return vertical_slice.transport.tile_visual_state(tile_index, _terrain_map())


func _transport_tile_has_player_content(state: Dictionary) -> bool:
	return not Array(state.get("facilities", [])).is_empty() or not Array(state.get("segments", [])).is_empty() or not str(state.get("crossing", "")).is_empty()


func _construction_job_player_text(job: Dictionary) -> String:
	var metadata: Dictionary = job.get("metadata", {})
	var transport_kind := str(metadata.get("transport_kind", ""))
	var work_name := (
		_transport_kind_label(transport_kind)
		if not transport_kind.is_empty()
		else str(metadata.get("building_name", "工程"))
	)
	return L10n.text("%s｜施工中｜約 %d 天") % [
		L10n.text(work_name),
		int(job.get("projected_remaining_days", 0)),
	]


func _transport_tile_player_text(state: Dictionary) -> String:
	var labels_for_tile: Array[String] = []
	for facility_value: Variant in state.get("facilities", []):
		var facility_label := L10n.text(_transport_kind_label(str(facility_value)))
		if not labels_for_tile.has(facility_label):
			labels_for_tile.append(facility_label)
	for segment_value: Variant in state.get("segments", []):
		var segment_label := L10n.text(_transport_kind_label(str(segment_value)))
		if not labels_for_tile.has(segment_label):
			labels_for_tile.append(segment_label)
	if not str(state.get("crossing", "")).is_empty():
		labels_for_tile.append(L10n.text("平交道"))
	var status := str(state.get("project_status", ""))
	var status_label := L10n.text({
		"planned": "已規劃",
		"under_construction": "施工中",
		"demolishing": "拆除中",
	}.get(status, "已完工"))
	return "%s｜%s" % ["、".join(PackedStringArray(labels_for_tile)), status_label]

func _has_approved_blueprint_for_selected() -> bool:
	if vertical_slice == null:
		return false
	return vertical_slice.has_approved_blueprint(selected_building)

func _terrain_kind_for_cell(index: int, building_name: String) -> int:
	if building_name == "" and index in [5, 6, 13, 14]:
		return 5
	if building_name in ["停車場", "公車站", "捷運站", "機場", "加油站"]:
		return 1
	if building_name in ["市政府", "法院", "監察所", "大型商場"]:
		return 4
	if building_name in ["工廠", "發電廠", "核能發電廠", "瓦斯場", "垃圾處理場"]:
		return 4
	if building_name in ["公園", "游泳池"]:
		return 3
	return index % 5

func _tile_text(building_name: String, index: int) -> String:
	if building_name == "":
		var ground: String = ["花草草地", "石磚空地", "泥土花圃", "小路地塊"][index % 4]
		return "%s\n可建造" % ground
	var visual: Dictionary = BUILDING_VISUALS.get(building_name, {"shape": building_name, "detail": "城鎮建物"})
	var line := str(visual["detail"])
	if building_customizations.has(index):
		var customization: Dictionary = building_customizations[index]
		line = "%s %s" % [
			CUSTOM_ROOF_COLORS[int(customization.get("roof", 0))],
			CUSTOM_VARIANTS[int(customization.get("variant", 0))]
		]
	return "%s\n%s\n%s" % [visual["shape"], building_name, line]

func _building_color(building_name: String) -> Color:
	if building_name == "" or not buildings.has(building_name):
		return Color(0.90, 0.97, 0.90)
	return buildings[building_name].get("color", Color(0.78, 0.89, 0.97))

func _building_text_color(building_name: String) -> Color:
	if building_name == "" or not buildings.has(building_name):
		return COLOR_TEXT
	return buildings[building_name].get("text_color", COLOR_TEXT)

func _lighten(color: Color, amount: float) -> Color:
	return Color(
		lerpf(color.r, 1.0, amount),
		lerpf(color.g, 1.0, amount),
		lerpf(color.b, 1.0, amount),
		color.a
	)

func _darken(color: Color, amount: float) -> Color:
	return Color(
		lerpf(color.r, 0.0, amount),
		lerpf(color.g, 0.0, amount),
		lerpf(color.b, 0.0, amount),
		color.a
	)


func _readable_text_color(background: Color) -> Color:
	var luminance := background.r * 0.299 + background.g * 0.587 + background.b * 0.114
	return Color.WHITE if luminance < 0.48 else COLOR_TEXT

func _theme_bg() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "surface_base")

func _theme_panel() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "surface_raised")

func _theme_panel_alt() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "surface_muted")


func _theme_report_bg() -> Color:
	return Color(0.06, 0.09, 0.13) if is_dark_mode else Color(0.08, 0.14, 0.20)

func _theme_text() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "text_primary")

func _theme_muted() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "text_secondary")

func _theme_border() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "border_default")

func _theme_accent_text() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "border_focus")


func _theme_success_text() -> Color:
	return SemanticPalette.color_for(is_dark_mode, "success")

func _avg(values: Array) -> int:
	if values.is_empty():
		return 0
	var total := 0.0
	for value in values:
		total += float(value)
	return int(round(total / values.size()))

func _clamp_score(value: int) -> int:
	return clampi(value, 0, 100)
