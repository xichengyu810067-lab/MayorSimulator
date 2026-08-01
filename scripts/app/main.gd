extends Control

signal application_quit_requested

const Buildings = preload("res://data/catalogs/buildings.gd")
const BuildingVisuals = preload("res://data/catalogs/building_visuals.gd")
const Policies = preload("res://data/catalogs/policies.gd")
const CityBackdrop = preload("res://scripts/world/city_backdrop.gd")
const CityTileButton = preload("res://scripts/world/city_tile_button.gd")
const NpcMapControllerScript = preload("res://scripts/app/npc_map_controller.gd")
const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CitySimulationServiceScript = preload("res://scripts/app/city_simulation_service.gd")
const CityReportHistoryServiceScript = preload("res://scripts/app/city_report_history_service.gd")
const MunicipalEconomyServiceScript = preload("res://scripts/app/municipal_economy_service.gd")
const VerticalSlicePanelScript = preload("res://ui/shell/vertical_slice_panel.gd")
const MunicipalOverlayScript = preload("res://ui/shell/municipal_overlay.gd")
const JusticeOversightPanelScript = preload("res://ui/governance/justice_oversight_panel.gd")
const PublicAffairsPanelScript = preload("res://ui/shell/public_affairs_panel.gd")
const BuildingContextPanelScript = preload("res://ui/shell/building_context_panel.gd")
const ExitConfirmOverlayScript = preload("res://ui/shell/exit_confirm_overlay.gd")
const ConstructionConfirmOverlayScript = preload("res://ui/shell/construction_confirm_overlay.gd")
const StartScreenScript = preload("res://ui/shell/start_screen.gd")
const WeatherVisualLayerScript = preload("res://ui/effects/weather_visual_layer.gd")
const SettingsOverlayScript = preload("res://ui/shell/settings_overlay.gd")
const TutorialStoryOverlayScript = preload("res://ui/tutorial/tutorial_story_overlay.gd")
const AudioDirectorScript = preload("res://scripts/audio/audio_director.gd")
const UserSettingsServiceScript = preload("res://scripts/app/user_settings_service.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const CityDataDashboardScript = preload("res://ui/shell/city_data_dashboard.gd")
const TransportPlanningPanelScript = preload("res://ui/shell/transport_planning_panel.gd")
const TransportNetworkLayerScript = preload("res://scripts/world/transport_network_layer.gd")
const TransportVehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")
const ProgressiveChoicePagerScript = preload("res://ui/components/progressive_choice_pager.gd")
const NpcDialogueCardScript = preload("res://ui/components/npc_dialogue_card.gd")
const CityMetricCardScript = preload("res://ui/components/city_metric_card.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")
const VERSION_UPDATES_PATH := "res://data/version_updates.json"
const QA_RELEASE_SMOKE_ARG_PREFIX := "--qa-release-smoke-frames="
# Resident records store personal currency units. City treasury calculations
# use a documented scale so tax revenue follows real resident income without
# destabilizing the existing municipal-budget balance.
const RESIDENT_INCOME_TREASURY_SCALE := 0.0005

const GRID_SIZE := CityTerrainMapScript.GRID_COLUMNS
const CELL_COUNT := CityTerrainMapScript.CELL_COUNT
const ISO_TILE_SIZE := Vector2(104, 104)
const ISO_TILE_STEP := Vector2(56, 32)
const ISO_MAP_ORIGIN := Vector2(560, 104)
const MAP_STAGE_SIZE := Vector2(1120, 820)
const MAP_ZOOM_MIN := 0.65
const MAP_ZOOM_MAX := 1.75
const MAP_ZOOM_STEP := 0.10
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
const UI_HUD_BUTTON_SIZE := 88
const UI_STATUS_HEIGHT := 58
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
var blueprint_shortcut_button: Button
var transport_shortcut_button: Button
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
var bill_buttons: Dictionary = {}
var governance_status_tabs: TabContainer
var governance_status_grids: Dictionary = {}
var governance_status_pagers: Dictionary = {}
var governance_status_sections: Dictionary = {}
var governance_status_empty_labels: Dictionary = {}
var governance_bill_cards: Dictionary = {}
var governance_policy_cards: Dictionary = {}
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
var _hint_tween: Tween
var quit_application_on_confirm := true
var _quit_shutdown_in_progress := false
var _qa_release_smoke_active := false
var _qa_release_smoke_frames_remaining := -1
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
var _pending_construction_tile := -1
var _pending_construction_workers := 5
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
var service_fees := {"bus": 15, "metro": 30, "train": 45, "air": 120, "parking": 20, "medical": 50, "tuition": 100, "stadium": 80}
var announcements: Array[String] = []
var last_population_reason := "人口維持穩定。"
var selected_cell_index := -1
var building_customizations: Dictionary = {}
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

	municipal_overlay = _build_management_overlay()
	municipal_overlay.page_opened.connect(Callable(self, "_on_municipal_page_opened"))
	municipal_overlay.overlay_closed.connect(Callable(self, "_sync_map_interaction_for_ui"))
	add_child(municipal_overlay)
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
	tutorial_overlay = TutorialStoryOverlayScript.new()
	tutorial_overlay.completed.connect(Callable(self, "_on_tutorial_completed"))
	tutorial_overlay.audio_cue.connect(Callable(self, "_on_tutorial_audio_cue"))
	add_child(tutorial_overlay)
	for blocking_surface in [municipal_overlay, settings_overlay, construction_confirmation, exit_confirmation, tutorial_overlay]:
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
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and vertical_slice != null:
		vertical_slice.set_time_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and vertical_slice != null:
		_sync_time_pause_for_ui()


func _sync_time_pause_for_ui() -> void:
	if vertical_slice == null:
		return
	var should_pause := not _game_started
	should_pause = should_pause or (municipal_overlay != null and municipal_overlay.is_open())
	should_pause = should_pause or (settings_overlay != null and settings_overlay.is_open())
	should_pause = should_pause or (construction_confirmation != null and construction_confirmation.is_open())
	should_pause = should_pause or (exit_confirmation != null and exit_confirmation.visible)
	should_pause = should_pause or (tutorial_overlay != null and tutorial_overlay.is_open())
	vertical_slice.set_time_paused(should_pause)
	_refresh_time_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var zoom_event := event as InputEventMouseButton
		if zoom_event.button_index == MOUSE_BUTTON_MIDDLE:
			if zoom_event.pressed and _can_zoom_map_at(zoom_event.position):
				_map_pan_drag_active = true
				_map_pan_drag_last_position = zoom_event.position
				get_viewport().set_input_as_handled()
				return
			if not zoom_event.pressed and _map_pan_drag_active:
				_map_pan_drag_active = false
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
	if event is InputEventMouseMotion and _map_pan_drag_active:
		var pan_event := event as InputEventMouseMotion
		if not _can_zoom_map_at(pan_event.position):
			_map_pan_drag_active = false
			return
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
	return true


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
				_restore_player_shell_state(vertical_slice.get_player_shell_state())
				_sync_vertical_state()
				_update_ui()
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
	if not tutorial_completed and tutorial_overlay != null:
		tutorial_overlay.open(true)
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
	selected_cell_index = -1
	selected_building = "住宅"
	selected_building_group = "housing"
	placement_mode_active = false
	placement_building_name = ""
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
	service_fees = {"bus": 15, "metro": 30, "train": 45, "air": 120, "parking": 20, "medical": 50, "tuition": 100, "stadium": 80}
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
	tutorial_completed = false
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
	_sync_city_metrics_to_core()
	var serialized_customizations: Dictionary = {}
	for tile_variant in building_customizations.keys():
		serialized_customizations[str(tile_variant)] = Dictionary(building_customizations[tile_variant]).duplicate(true)
	var report_history_snapshot := city_report_history_service.snapshot()
	return {
		"schema_version": 7,
		"tax_rates": tax_rates.duplicate(true),
		"utility_fees": utility_fees.duplicate(true),
		"service_fees": service_fees.duplicate(true),
		"active_policies": active_policies.duplicate(true),
		"is_dark_mode": is_dark_mode,
		"tutorial_completed": tutorial_completed,
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"map_zoom": map_zoom,
		"selected_building": selected_building,
		"selected_building_group": selected_building_group,
		"selected_cell_index": selected_cell_index,
		"building_customizations": serialized_customizations,
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


func _restore_player_shell_state(state: Dictionary) -> void:
	if state.is_empty():
		return
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
	tutorial_completed = bool(state.get("tutorial_completed", false))
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
	panel.offset_left = 10.0
	panel.offset_top = 10.0
	panel.offset_right = -10.0
	panel.offset_bottom = 10.0 + UI_STATUS_HEIGHT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	panel.add_child(row)

	var title := _label("Mayor Simulator", 20, Color("fff4d7") if is_dark_mode else Color("35291f"))
	title.custom_minimum_size = Vector2(164, 0)
	title.tooltip_text = L10n.text("療癒城市治理模擬")
	row.add_child(title)

	for key in ["month", "funds", "population", "satisfaction", "grievance", "trust", "score", "rating"]:
		row.add_child(_header_metric_card(key))
	return panel

func _on_locale_changed(_locale: String) -> void:
	if not is_node_ready():
		return
	var reopen_settings: bool = settings_overlay != null and settings_overlay.is_open()
	_rebuild_ui()
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

func _build_action_dock() -> PanelContainer:
	var panel := _panel(Color(0.04, 0.12, 0.19, 0.94), 12, 7)
	panel.name = "ActionDock"
	panel.z_index = 3100
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -310.0
	panel.offset_top = -112.0
	panel.offset_right = -10.0
	panel.offset_bottom = -10.0

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)

	municipal_button = _hud_picture_button("municipal", "市政", "開啟市政中心：建築、政策法案、藍圖與財政", "primary")
	municipal_button.pressed.connect(Callable(self, "_open_municipal_center"))
	grid.add_child(municipal_button)
	settings_button = _hud_picture_button("settings", "設定", "調整語言與顯示模式")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(Callable(self, "_open_settings"))
	grid.add_child(settings_button)
	exit_button = _hud_picture_button("exit", "離開", "離開 Mayor Simulator", "danger")
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
	stack.offset_left = 3
	stack.offset_top = 2
	stack.offset_right = -3
	stack.offset_bottom = -2
	stack.add_theme_constant_override("separation", -2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	var picture := _icon_texture_rect(icon_key, Vector2(0, 32))
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(picture)
	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.max_lines_visible = 2
	caption.custom_minimum_size = Vector2(0, 34)
	caption.clip_text = true
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
		audio_director.stop_all()
	await get_tree().process_frame
	if is_instance_valid(audio_director):
		audio_director.detach_streams()
	await get_tree().process_frame
	if _qa_release_smoke_active:
		print("QA_RELEASE_SMOKE_COMPLETED")
	get_tree().quit()


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


func _build_judicial_tab() -> ScrollContainer:
	judicial_panel = JusticeOversightPanelScript.new("judicial")
	judicial_panel.set_dark_mode(is_dark_mode)
	judicial_panel.defense_submitted.connect(Callable(self, "_on_defense_submitted"))
	if vertical_slice != null:
		judicial_panel.refresh(vertical_slice.governance.justice_system)
	return judicial_panel


func _build_oversight_tab() -> ScrollContainer:
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
	transport_planning_panel.station_requested.connect(Callable(self, "_on_transport_station_requested"))
	transport_planning_panel.route_planning_requested.connect(Callable(self, "_on_transport_route_planning_requested"))
	transport_planning_panel.route_toggle_requested.connect(Callable(self, "_on_transport_route_toggle_requested"))
	transport_planning_panel.route_delete_requested.connect(Callable(self, "_on_transport_route_delete_requested"))
	_refresh_transport_planning_panel()
	return transport_planning_panel

func _open_municipal_center() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	if municipal_overlay != null:
		_set_map_interaction_enabled(false)
		municipal_overlay.open_hub()


func _open_transport_planning() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	if municipal_overlay == null:
		return
	_refresh_transport_planning_panel()
	_set_map_interaction_enabled(false)
	municipal_overlay.open_page("transport_planning")


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


func _set_map_interaction_enabled(enabled: bool) -> void:
	if not enabled:
		_map_pan_drag_active = false
	_set_map_npc_tooltips_enabled(enabled)
	_set_map_tile_tooltips_enabled(enabled)


func _sync_map_interaction_for_ui() -> void:
	var blocked := not _game_started
	blocked = blocked or (municipal_overlay != null and municipal_overlay.is_open())
	blocked = blocked or (settings_overlay != null and settings_overlay.is_open())
	blocked = blocked or (construction_confirmation != null and construction_confirmation.is_open())
	blocked = blocked or (exit_confirmation != null and exit_confirmation.visible)
	blocked = blocked or (tutorial_overlay != null and tutorial_overlay.is_open())
	_set_map_interaction_enabled(not blocked)


func _on_municipal_page_opened(page_id: String) -> void:
	_set_map_npc_tooltips_enabled(false)
	if page_id == "transport_planning":
		_refresh_transport_planning_panel()
		return
	if page_id != "governance":
		return
	_refresh_governance_catalog()
	_select_governance_status(_preferred_governance_status())


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
	if municipal_overlay != null:
		_set_map_interaction_enabled(false)
		municipal_overlay.open_page("city_data")
		if city_data_dashboard != null:
			city_data_dashboard.restart_animations()

func _open_monthly_report() -> void:
	_close_building_context()
	_hide_npc_dialogue()
	if municipal_overlay != null:
		_set_map_interaction_enabled(false)
		municipal_overlay.open_page("report")


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
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if key == "rating":
		card.custom_minimum_size = Vector2(145, 0)
		card.size_flags_stretch_ratio = 1.25
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
	visual_row.add_child(_icon_texture_rect(key, Vector2(27, 27)))
	var item := _label("", 14, Color("fff4d7") if is_dark_mode else Color("35291f"))
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	blueprint_shortcut_button = _button("設計藍圖", "primary")
	blueprint_shortcut_button.name = "OpenBlueprintButton"
	blueprint_shortcut_button.icon = _icon_texture("blueprint")
	blueprint_shortcut_button.add_theme_constant_override("icon_max_width", 48)
	blueprint_shortcut_button.expand_icon = true
	blueprint_shortcut_button.custom_minimum_size = Vector2(190, 58)
	blueprint_shortcut_button.add_theme_font_size_override("font_size", 18)
	blueprint_shortcut_button.tooltip_text = L10n.text("用目前選取的建築直接開啟藍圖設計。")
	blueprint_shortcut_button.pressed.connect(_open_selected_blueprint)
	selected_row.add_child(blueprint_shortcut_button)
	transport_shortcut_button = _button("交通路網", "primary")
	transport_shortcut_button.name = "OpenTransportPlanningButton"
	transport_shortcut_button.icon = _icon_texture("traffic")
	transport_shortcut_button.add_theme_constant_override("icon_max_width", 42)
	transport_shortcut_button.expand_icon = true
	transport_shortcut_button.custom_minimum_size = Vector2(190, 58)
	transport_shortcut_button.add_theme_font_size_override("font_size", 18)
	transport_shortcut_button.tooltip_text = "規劃站點、道路、軌道、車庫、號誌、班距與車隊"
	transport_shortcut_button.pressed.connect(Callable(self, "_open_transport_planning"))
	selected_row.add_child(transport_shortcut_button)
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
		var category_grid = ProgressiveChoicePagerScript.new(3, 3)
		category_grid.name = "BuildingChoices_%s" % group_id
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
				button.pressed.connect(Callable(self, "_select_building").bind(building_name))
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
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The fiscal controls need more vertical room than a 1280x720 municipal
	# window provides.  Let the outer page scroll instead of allowing its minimum
	# height to escape the PageHost and clip below the viewport.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(0, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	content.add_child(_illustrated_section_title("funds", "稅率與公共收費"))
	var legend := HFlowContainer.new()
	legend.name = "FiscalWarningLegend"
	legend.add_theme_constant_override("separation", 18)
	legend.add_child(_label("● 綠色　正常／可負擔", 15, COLOR_SUCCESS))
	legend.add_child(_label("● 黃色　收入不足", 15, COLOR_CAUTION))
	legend.add_child(_label("● 紅色　負擔過高", 15, COLOR_WARNING))
	content.add_child(legend)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	content.add_child(body)

	var categories := TabContainer.new()
	categories.name = "FiscalCategoryTabs"
	categories.set_meta("progressive_choice_group", true)
	categories.custom_minimum_size = Vector2(560, 500)
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories.size_flags_stretch_ratio = 1.25
	categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tabs(categories)
	categories.add_theme_font_size_override("font_size", 18)
	categories.add_theme_constant_override("side_margin", 5)
	body.add_child(categories)

	var category_families: Array[Dictionary] = [
		{"title": "稅收", "specs": [
			{"title": "居民稅", "kind": "tax", "keys": ["income", "consumption"]},
			{"title": "產業稅", "kind": "tax", "keys": ["business", "industry"]},
		]},
		{"title": "公共事業", "specs": [
			{"title": "水電", "kind": "utility", "keys": ["water", "electricity"]},
			{"title": "環境能源", "kind": "utility", "keys": ["gas", "garbage"]},
		]},
		{"title": "服務收費", "specs": [
			{"title": "交通收費", "kind": "service", "keys": ["bus", "metro", "parking"]},
			{"title": "社會服務", "kind": "service", "keys": ["medical", "tuition", "stadium"]},
		]},
	]
	for family: Dictionary in category_families:
		var subcategories := TabContainer.new()
		subcategories.name = str(family["title"])
		subcategories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subcategories.size_flags_vertical = Control.SIZE_EXPAND_FILL
		subcategories.add_theme_font_size_override("font_size", 17)
		subcategories.set_meta("progressive_choice_group", true)
		_style_tabs(subcategories)
		for spec: Dictionary in family["specs"]:
			var page := VBoxContainer.new()
			page.name = str(spec["title"])
			page.add_theme_constant_override("separation", 10)
			var intro := _label(_fiscal_category_hint(str(spec["title"])), 15, _theme_muted())
			intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			page.add_child(intro)
			var page_panel := _panel(_theme_panel_alt(), 9, 14)
			page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			page_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var rows := VBoxContainer.new()
			rows.add_theme_constant_override("separation", 10)
			rows.set_meta("progressive_choice_group", true)
			page_panel.add_child(rows)
			for key: String in spec["keys"]:
				match str(spec["kind"]):
					"tax":
						rows.add_child(_build_tax_row(key))
					"utility":
						rows.add_child(_build_utility_fee_row(key))
					"service":
						rows.add_child(_build_service_fee_row(key))
			page.add_child(page_panel)
			subcategories.add_child(page)
		categories.add_child(subcategories)
	categories.get_tab_bar().clip_tabs = true

	var summary_panel := _panel(_theme_panel_alt(), 9, 14)
	summary_panel.name = "FiscalForecastPanel"
	summary_panel.custom_minimum_size = Vector2(330, 0)
	summary_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_panel.size_flags_stretch_ratio = 0.65
	summary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 9)
	summary_panel.add_child(summary_box)
	var forecast_title := _section_title("即時財政預估")
	forecast_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_title.max_lines_visible = 2
	summary_box.add_child(forecast_title)
	var forecast_help := _label("算法：每次只變動目前選項，其他條件維持不變。", 15, _theme_muted())
	forecast_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_box.add_child(forecast_help)
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
	body.add_child(summary_panel)

	return scroll

func _build_bill_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "政策與法案"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(0, 0)
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	content.add_child(_illustrated_section_title("governance", "政策與法案"))
	var legend := HFlowContainer.new()
	legend.name = "GovernanceTagLegend"
	legend.add_theme_constant_override("separation", 8)
	legend.add_child(_governance_tag_chip("政策", Color(0.05, 0.43, 0.70), "LegendPolicyTag"))
	legend.add_child(_governance_tag_chip("法案", Color(0.78, 0.49, 0.08), "LegendBillTag"))
	var legend_note := _label("先查看已實施項目，再選擇尚未實施的政策與法案。", 15, _theme_muted())
	legend_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	legend.add_child(legend_note)
	content.add_child(legend)

	bill_status_label = _label("", 16, _theme_text())
	bill_status_label.name = "GovernanceStatusSummary"
	bill_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bill_status_label.custom_minimum_size = Vector2(0, 34)
	content.add_child(bill_status_label)

	governance_status_tabs = TabContainer.new()
	governance_status_tabs.name = "GovernanceStatusTabs"
	governance_status_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	governance_status_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	governance_status_tabs.custom_minimum_size = Vector2(0, 380)
	governance_status_tabs.add_theme_font_size_override("font_size", 19)
	_style_tabs(governance_status_tabs)
	content.add_child(governance_status_tabs)
	for status_id: String in GOVERNANCE_STATUS_ORDER:
		var page_scroll := ScrollContainer.new()
		page_scroll.name = str(GOVERNANCE_STATUS_TITLES[status_id])
		page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page_scroll.set_meta("status_id", status_id)
		var page_content := VBoxContainer.new()
		page_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_content.add_theme_constant_override("separation", 12)
		page_scroll.add_child(page_content)
		var empty_label := _label("此分類目前沒有項目。", 17, _theme_muted())
		empty_label.name = "GovernanceEmpty_%s" % status_id
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, 86)
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
			var grid := pager.call("choice_grid") as GridContainer
			grid.name = "%s_%s_Grid" % [status_id, kind_id]
			section.add_child(pager)
			kind_tabs.add_child(section)
			var key := "%s:%s" % [status_id, kind_id]
			governance_status_grids[key] = grid
			governance_status_pagers[key] = pager
			governance_status_sections[key] = section
		governance_status_tabs.add_child(page_scroll)

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
	content.add_child(force_panel)
	_refresh_governance_catalog()

	return scroll


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
	var terrain = _terrain_map()
	for layer in range(GRID_SIZE * 2 - 1):
		for row in range(GRID_SIZE):
			var col := layer - row
			if col < 0 or col >= GRID_SIZE:
				continue
			var index: int = int(terrain.tile_id_for_coordinate(Vector2i(col, row))) if terrain != null else row * GRID_SIZE + col
			var cell: Button = CityTileButton.new()
			cell.custom_minimum_size = ISO_TILE_SIZE
			cell.size = ISO_TILE_SIZE
			cell.position = _iso_tile_position(index)
			# Buildings and residents share a feet/ground depth axis.  A resident
			# naturally disappears behind a building whose base is farther south.
			cell.z_index = int(_iso_tile_center(index).y)
			cell.pressed.connect(Callable(self, "_on_grid_pressed").bind(index))
			grid_buttons[index] = cell
		tile_layer.add_child(cell)

	transport_vehicle_controller = TransportVehicleControllerScript.new()
	transport_vehicle_controller.custom_minimum_size = MAP_STAGE_SIZE
	transport_vehicle_controller.size = MAP_STAGE_SIZE
	transport_vehicle_controller.crossing_states_changed.connect(
		func(states: Dictionary) -> void:
			if transport_network_layer != null:
				transport_network_layer.set_crossing_states(states)
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
	var coordinate := _terrain_coordinate(index)
	var row := coordinate.y
	var col := coordinate.x
	return Vector2(
		ISO_MAP_ORIGIN.x + float(col - row) * ISO_TILE_STEP.x - ISO_TILE_SIZE.x * 0.5,
		ISO_MAP_ORIGIN.y + float(col + row) * ISO_TILE_STEP.y - 36.0
	)

func _iso_tile_center(index: int) -> Vector2:
	return _iso_tile_position(index) + Vector2(ISO_TILE_SIZE.x * 0.5, 70.0)


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


func _update_transport_runtime() -> void:
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
	var centers := _transport_tile_centers()
	if transport_network_layer != null:
		transport_network_layer.set_network_snapshot(preview_runtime, centers)
	if transport_vehicle_controller != null:
		transport_vehicle_controller.set_runtime_snapshot(runtime, centers)


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
	var building_centers := {}
	var construction_centers := {}
	var blocked_tiles := {}
	var terrain_blockers := {}
	var terrain = _terrain_map()
	var transport_blocked_tiles := PackedInt32Array()
	if vertical_slice != null and vertical_slice.has_method("transport_navigation_blocked_tile_ids"):
		transport_blocked_tiles = vertical_slice.call("transport_navigation_blocked_tile_ids")
	for tile_index in mini(CELL_COUNT, city_grid.size()):
		var center := _iso_tile_center(tile_index)
		tile_centers.append(center)
		if terrain != null and not terrain.is_walkable(tile_index):
			terrain_blockers[tile_index] = {
				"center": center,
				"kind": terrain.effective_kind(tile_index),
			}
			blocked_tiles[tile_index] = true
		if transport_blocked_tiles.has(tile_index):
			terrain_blockers[tile_index] = {
				"center": center,
				"kind": "transport_network",
			}
			blocked_tiles[tile_index] = true
		if city_grid[tile_index] != "":
			building_centers[tile_index] = center
			blocked_tiles[tile_index] = true
		if vertical_slice != null and not vertical_slice.active_construction_for_tile(tile_index).is_empty():
			construction_centers[tile_index] = center
			blocked_tiles[tile_index] = true
	return {
		"tile_centers": tile_centers,
		"building_centers": building_centers,
		"construction_centers": construction_centers,
		"terrain_blockers": terrain_blockers,
		"blocked_tiles": blocked_tiles,
		"iso_tile_size": ISO_TILE_SIZE,
		"iso_tile_step": ISO_TILE_STEP,
		"terrain_blocker_half_extents": Vector2(ISO_TILE_SIZE.x * 0.48, ISO_TILE_STEP.y),
		"structure_blocker_half_extents": Vector2(ISO_TILE_SIZE.x * 0.48, ISO_TILE_STEP.y),
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
	npc_dialogue_card.dismiss_requested.connect(Callable(self, "_hide_npc_dialogue"))
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


func _update_ambient(delta: float) -> void:
	ambient_time += delta
	if weather_visual_layer != null and vertical_slice != null:
		weather_visual_layer.set_game_day(vertical_slice.game_day())
	if _npc_dialogue_remaining_seconds > 0.0:
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


func _open_selected_npc_request() -> void:
	_hide_npc_dialogue()
	_close_building_context()
	if municipal_overlay != null:
		municipal_overlay.open_page("public_affairs")

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
	var unit_label := _label(L10n.text("%% / %s") % L10n.text(str(def["unit"]).replace(" %", "")), 14, _theme_muted())
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
	city_data_dashboard.refresh({
		"has_previous_month": not monthly_report_history.is_empty(),
		"previous_month": city_report_history_service.latest_monthly_report_snapshot(),
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
		var config := {
			"id": metric_id,
			"icon_key": str(spec["icon_key"]),
			"label": L10n.text(str(spec["label"])),
			"unit": "%",
			"status": str(status["key"]),
			"status_label": localized_status,
			"period_label": L10n.text("本月摘要"),
			"delta_unavailable_text": L10n.text("新城市，尚無上月資料。"),
			"interpretation_text": "%s：%s × %d  ·  %s" % [L10n.text("主要服務"), L10n.text(building_name), relevant_count, localized_status],
			"action_text": _city_metric_action_text(building_name, relevant_count, value),
			"baseline": 60.0,
			"baseline_text": L10n.text("安全線 60%"),
			"chart_current_text": "%s %d%%" % [L10n.text(str(spec["label"])), value],
			"comparison_text": comparison_text,
			"chart_minimum_text": "0%",
			"chart_maximum_text": "100%",
			"chart_tooltip": comparison_text,
		}
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
		"交通收費":
			return "公車、捷運與停車收費；只在對應設施存在時產生收入。"
		"社會服務":
			return "醫療、學費與場館票價；過高會降低服務使用與居民滿意。"
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

func _set_fiscal_value_for_forecast(kind: String, key: String, value: int) -> void:
	match kind:
		"tax":
			tax_rates[key] = value
		"utility":
			utility_fees[key] = value
		"service":
			service_fees[key] = value

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
	var current_value := _fiscal_value(kind, key)
	var current_net := _projected_net_income()
	_set_fiscal_value_for_forecast(kind, key, reasonable)
	var reference_net := _projected_net_income()
	_set_fiscal_value_for_forecast(kind, key, current_value)

	var ratio := float(current_value) / maxf(1.0, float(reasonable))
	var net_delta := current_net - reference_net
	var public_pressure := _fiscal_item_public_pressure(kind, current_value, reasonable)
	var safety_buffer := _fiscal_safety_buffer()
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
		_set_hint("已選擇「%s」；請開啟設計藍圖確認總價，再回到地圖放置。" % selected_building, false)
	else:
		_set_hint("已選擇「%s」；按「設計藍圖」送審，核准後即可放置。" % selected_building, false)
	_update_ui()

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


func _on_building_family_changed(family_index: int) -> void:
	if family_index < 0 or family_index >= BUILDING_FAMILIES.size():
		return
	var group_ids: Array = BUILDING_FAMILIES[family_index]["groups"]
	if selected_building_group in group_ids:
		return
	if not group_ids.is_empty():
		_select_building_group(str(group_ids[0]))


func _building_group_definition(group_id: String) -> Dictionary:
	for group in BUILDING_GROUPS:
		if str(group["id"]) == group_id:
			return group
	return {}

func _open_selected_blueprint() -> void:
	if municipal_overlay != null:
		municipal_overlay.open_page("blueprint")

func _on_blueprint_submit_requested(payload: Dictionary) -> void:
	if vertical_slice == null:
		return
	_cancel_building_placement(false)
	var result: Dictionary = vertical_slice.submit_blueprint(payload)
	if bool(result.get("ok", false)):
		var review: Dictionary = result.get("review", {})
		_set_hint("「%s」藍圖已送審，預計 %d 個遊戲日完成審核。" % [payload.get("building_name", selected_building), int(review.get("review_days", 0))], false)
		_add_announcement("「%s」藍圖已收件，預計 %d 個遊戲日完成審核。" % [payload.get("building_name", selected_building), int(review.get("review_days", 0))])
	else:
		_set_hint("藍圖無法送審：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
	_sync_vertical_state()
	_update_ui()
	if bool(result.get("ok", false)):
		_autosave("action:blueprint_submitted")


func _on_blueprint_placement_requested(building_name: String) -> void:
	_enter_building_placement(building_name)


func _on_blueprint_worker_count_changed(_count: int) -> void:
	if vertical_slice == null:
		return
	_update_scoped_municipal_pages(vertical_slice.get_view_model(selected_cell_index))


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
	tax_rates[tax_key] = int(value)
	tax_rate = int(tax_rates["income"])
	_sync_number_input(tax_inputs, tax_key, tax_rates[tax_key])
	_recalculate_satisfaction()
	_recalculate_score()
	_update_ui()
	_autosave("action:tax_changed")

func _on_utility_fee_changed(value: float, fee_key: String) -> void:
	utility_fees[fee_key] = int(value)
	_sync_number_input(utility_inputs, fee_key, utility_fees[fee_key])
	_recalculate_satisfaction()
	_recalculate_score()
	_set_hint("%s調整為 %d。" % [UTILITY_DEFS[fee_key]["name"], utility_fees[fee_key]], false)
	_reconcile_resident_request_completion()
	_update_ui()
	_autosave("action:utility_fee_changed")

func _on_service_fee_changed(value: float, service_key: String) -> void:
	service_fees[service_key] = int(value)
	_sync_number_input(service_inputs, service_key, service_fees[service_key])
	_recalculate_satisfaction()
	_recalculate_score()
	_set_hint("%s調整為 %d / %s。" % [SERVICE_DEFS[service_key]["name"], service_fees[service_key], SERVICE_DEFS[service_key]["unit"]], false)
	_update_ui()
	_autosave("action:service_fee_changed")

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
	var bill_id := _governance_bill_id(bill_name)
	var result: Dictionary = vertical_slice.submit_bill(bill_id, _vertical_city_context())
	if bool(result.get("ok", false)):
		_add_announcement("已送交兩院審查《%s》，下議院將先投票並進行一次辯論。" % bill_name)
		_set_hint("《%s》已送審。" % bill_name, false)
	else:
		_set_hint("法案無法送審：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
	_update_ui()
	if bool(result.get("ok", false)):
		_select_governance_status("review")
		_autosave("action:bill_submitted")


func _is_transport_map_action_active() -> bool:
	return map_action_mode in ["transport_infrastructure", "transport_route_stops"]


func _on_transport_infrastructure_requested(kind: String, operation: String) -> void:
	if vertical_slice == null:
		return
	_cancel_building_placement(false)
	map_action_mode = "transport_infrastructure"
	transport_plan_kind = "rail_track" if kind == "heavy_rail" else kind
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
	_set_hint("請依序點選相鄰地格規劃%s；確認前不會扣款。" % _transport_kind_label(transport_plan_kind), false)


func _on_transport_station_requested(building_name: String) -> void:
	if not buildings.has(building_name):
		_set_hint("找不到交通站點「%s」。" % building_name, true)
		return
	_select_building(building_name)
	if _has_approved_blueprint_for_selected():
		_enter_building_placement(building_name)
		return
	if municipal_overlay != null:
		municipal_overlay.open_page("blueprint")
	_set_hint("請先送審「%s」藍圖；核准並完成站點施工後才能建立路線。" % building_name, false)


func _on_transport_route_planning_requested(mode: String, fleet_size: int, headway_minutes: int, fare: int) -> void:
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
	_set_hint("請依營運順序點選%s；確認後才會驗證完整路網與車隊。" % _transport_route_label(mode), false)


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
	var is_path_kind := transport_plan_kind in ["road", "metro_track", "rail_track", "runway", "taxiway"]
	if not transport_plan_tiles.is_empty() and index == transport_plan_tiles.back():
		transport_plan_tiles.pop_back()
		_sync_placement_banner()
		_update_transport_runtime()
		return
	if index in transport_plan_tiles:
		_set_hint("同一個地格不能在同一工程中重複選取。", true)
		return
	if is_path_kind and not transport_plan_tiles.is_empty():
		var pair := _transport_direction_pair(transport_plan_tiles.back(), index)
		if pair.is_empty():
			_set_hint("路廊必須逐格相鄰連接，不能跨越空地。", true)
			return
	if not is_path_kind and not transport_plan_tiles.is_empty():
		transport_plan_tiles.clear()
	var candidate := transport_plan_tiles.duplicate()
	candidate.append(index)
	var quote := _transport_project_quote(candidate)
	if not bool(quote.get("ok", false)):
		var error := str(quote.get("error", "transport_plan_invalid"))
		if error in ["terrain_not_flat", "terrain_not_flattened"]:
			_pending_terrain_tile = index
			selected_cell_index = index
			_sync_placement_banner()
			_set_hint("此地格不是平坦地形；必須先整平才能興建交通設施。", true)
			return
		_set_hint("此路網規劃不可用：%s" % _vertical_error_text(error), true)
		return
	_pending_terrain_tile = -1
	transport_plan_tiles = candidate
	_sync_placement_banner()
	_update_transport_runtime()
	_set_hint("已選 %d 格｜目前工程估價 $%d。" % [transport_plan_tiles.size(), int(quote.get("total_cost", quote.get("cost", 0)))], false)


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
	_set_hint("已依序選擇 %d 個站點。" % transport_route_station_tiles.size(), false)


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


func _confirm_transport_map_plan() -> void:
	if map_action_mode == "transport_infrastructure":
		_confirm_transport_infrastructure_plan()
	elif map_action_mode == "transport_route_stops":
		_confirm_transport_route_plan()


func _confirm_transport_infrastructure_plan() -> void:
	if vertical_slice == null or transport_plan_tiles.is_empty() or not vertical_slice.has_method("start_transport_project"):
		return
	var workers := int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel != null else 5
	var result: Dictionary = vertical_slice.call(
		"start_transport_project",
		transport_plan_kind,
		transport_plan_operation,
		transport_plan_tiles,
		workers,
		city_grid
	)
	if not bool(result.get("ok", false)):
		_set_hint("交通工程無法開工：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		return
	var selected_count := transport_plan_tiles.size()
	var kind_label := _transport_kind_label(transport_plan_kind)
	_cancel_transport_map_action(false)
	_consume_vertical_events(vertical_slice.drain_ui_events())
	debug_sync_npc_navigation_obstacles()
	if npc_map_controller != null:
		npc_map_controller.repath_all()
	_update_ui()
	_set_hint("%s工程已開工，共 %d 格；完工且路網驗證通過前不會生成載具。" % [kind_label, selected_count], false)
	_autosave("action:transport_project_started")


func _confirm_transport_route_plan() -> void:
	if vertical_slice == null or not vertical_slice.has_method("create_transport_route"):
		return
	var required_stops := 1 if transport_route_mode == "air" else 2
	if transport_route_station_tiles.size() < required_stops:
		_set_hint("%s至少需要 %d 個已完工站點。" % [_transport_route_label(transport_route_mode), required_stops], true)
		return
	var result: Dictionary = vertical_slice.call(
		"create_transport_route",
		transport_route_mode,
		transport_route_station_tiles,
		transport_route_fleet_size,
		transport_route_headway_minutes,
		transport_route_fare,
		city_grid
	)
	if not bool(result.get("ok", false)):
		_set_hint("路線無法啟用：%s" % _vertical_error_text(str(result.get("error", "transport_route_invalid"))), true)
		return
	var route: Dictionary = result.get("route", {})
	var route_name := str(route.get("name", _transport_route_label(transport_route_mode)))
	_cancel_transport_map_action(false)
	_consume_vertical_events(vertical_slice.drain_ui_events())
	_update_ui()
	_set_hint("「%s」已建立並通過連通驗證；載具只沿這條權威路徑運行。" % route_name, false)
	_autosave("action:transport_route_created")


func _cancel_transport_map_action(show_feedback: bool) -> void:
	var was_active := _is_transport_map_action_active()
	map_action_mode = "inspect"
	transport_plan_kind = ""
	transport_plan_operation = ""
	transport_plan_tiles.clear()
	transport_route_mode = ""
	transport_route_station_tiles.clear()
	_pending_terrain_tile = -1
	_sync_placement_banner()
	_update_transport_runtime()
	if show_feedback and was_active:
		_set_hint("已取消交通規劃；沒有扣除任何費用，也沒有生成載具。", false)


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


func _refresh_transport_planning_panel() -> void:
	if transport_planning_panel == null:
		return
	var snapshot: Dictionary = {"planning_unlocked": true, "routes": []}
	if vertical_slice != null and vertical_slice.has_method("transport_view_model"):
		snapshot = vertical_slice.call("transport_view_model", city_grid)
	transport_planning_panel.set_view_model(snapshot)

func _on_grid_pressed(index: int) -> void:
	if index < 0 or index >= city_grid.size():
		return
	if _is_transport_map_action_active():
		_handle_transport_tile_pressed(index)
		return
	if placement_mode_active and not _is_tile_inside_hud_safe_area(index):
		_set_hint("此地格位於頂部資訊列安全區內，請選擇下方空地。", true)
		return
	var active_job: Dictionary = vertical_slice.active_construction_for_tile(index) if vertical_slice != null else {}
	if placement_mode_active and (city_grid[index] != "" or not active_job.is_empty()):
		_set_hint("此地格已有建築或工程，請選擇其他空地。", true)
		return
	if city_grid[index] != "":
		_select_built_cell(index)
		return
	if not active_job.is_empty():
		selected_cell_index = index
		_hide_npc_dialogue()
		_set_hint("%s施工中，預計尚需 %d 個遊戲日。" % [
			str(active_job.get("metadata", {}).get("building_name", "工程")),
			int(active_job.get("projected_remaining_days", 0))
		], false)
		_update_ui()
		return
	if vertical_slice == null:
		return
	if not placement_mode_active:
		selected_cell_index = -1
		_close_building_context()
		_hide_npc_dialogue()
		_update_ui()
		return
	var terrain = _terrain_map()
	if terrain != null and not terrain.is_buildable(index):
		selected_cell_index = index
		_pending_terrain_tile = index
		_pending_construction_tile = -1
		_hide_npc_dialogue()
		_sync_placement_banner()
		_update_tile_visual(index, city_grid[index])
		var terrain_state: Dictionary = terrain.tile_state(index)
		var terrain_label := str(TERRAIN_LABELS.get(str(terrain_state.get("effective_kind", "")), "非平坦地形"))
		var flatten_quote: Dictionary = vertical_slice.terrain_flatten_quote(index)
		_set_hint("%s不可興建；請先整平（費用 $%d）。" % [terrain_label, int(flatten_quote.get("cost", 0))], true)
		return
	_pending_terrain_tile = -1
	var workers: int = int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel else 5
	var quote: Dictionary = vertical_slice.placement_quote(placement_building_name, workers)
	if not bool(quote.get("ok", false)) or str(quote.get("status", "")) != "approved":
		_set_hint("目前沒有可放置的核准藍圖。", true)
		_cancel_building_placement(false)
		_update_ui()
		return
	if not bool(quote.get("can_afford", false)):
		_set_hint("城市公庫不足：本工程需要 $%d。" % int(quote.get("total_cost", 0)), true)
		return
	_pending_construction_tile = index
	_pending_construction_workers = workers
	_hide_npc_dialogue()
	if construction_confirmation != null:
		_set_map_interaction_enabled(false)
		construction_confirmation.open(placement_building_name, index, quote, funds)


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


func _cancel_active_map_action(show_feedback: bool = true) -> void:
	if _is_transport_map_action_active():
		_cancel_transport_map_action(show_feedback)
	else:
		_cancel_building_placement(show_feedback)


func _cancel_building_placement(show_feedback: bool) -> void:
	var was_active := placement_mode_active
	placement_mode_active = false
	placement_building_name = ""
	_pending_construction_tile = -1
	_pending_terrain_tile = -1
	if construction_confirmation != null and construction_confirmation.is_open():
		construction_confirmation.close()
	_sync_placement_banner()
	if is_node_ready() and grid_buttons.size() == CELL_COUNT:
		for index in CELL_COUNT:
			_update_tile_visual(index, city_grid[index])
	if show_feedback and was_active:
		_set_hint("已取消建築放置；沒有扣除任何費用。", false)


func _sync_placement_banner() -> void:
	if placement_banner == null or placement_label == null:
		return
	var transport_active := _is_transport_map_action_active()
	placement_banner.visible = placement_mode_active or transport_active
	if placement_level_button != null:
		placement_level_button.visible = false
	if placement_confirm_button != null:
		placement_confirm_button.visible = false
		placement_confirm_button.disabled = true
	if placement_cancel_button != null:
		placement_cancel_button.text = L10n.text("取消規劃" if transport_active else "取消放置")
		placement_cancel_button.tooltip_text = L10n.text("取消目前的交通規劃（Esc／右鍵）" if transport_active else "取消目前的建築放置（Esc／右鍵）")
	if not placement_mode_active and not transport_active:
		return
	if _pending_terrain_tile >= 0 and vertical_slice != null:
		var quote: Dictionary = vertical_slice.terrain_flatten_quote(_pending_terrain_tile)
		var terrain: Dictionary = quote.get("terrain", {})
		var terrain_label := L10n.text(str(TERRAIN_LABELS.get(str(terrain.get("effective_kind", "")), "非平坦地形")))
		placement_label.text = L10n.text("%s不可興建｜先整平地形才能施工") % terrain_label
		if placement_level_button != null:
			placement_level_button.text = L10n.text("整平地形 $%d") % int(quote.get("cost", 0))
			placement_level_button.disabled = not bool(quote.get("can_afford", false))
			placement_level_button.visible = true
		return
	if transport_active:
		if placement_confirm_button != null:
			placement_confirm_button.visible = true
		if map_action_mode == "transport_infrastructure":
			var quote := _transport_project_quote(transport_plan_tiles) if not transport_plan_tiles.is_empty() else {}
			var valid := not transport_plan_tiles.is_empty() and bool(quote.get("ok", false))
			var can_afford := valid and bool(quote.get("can_afford", true))
			var cost := int(quote.get("total_cost", 0))
			var operation_label := "興建" if transport_plan_operation == "build" else "拆除"
			placement_label.text = L10n.text("%s%s｜已選 %d 格｜預估 $%d｜逐格相鄰選取") % [
				L10n.text(operation_label), L10n.text(_transport_kind_label(transport_plan_kind)),
				transport_plan_tiles.size(), cost,
			]
			if placement_confirm_button != null:
				placement_confirm_button.text = L10n.text("確認開工")
				placement_confirm_button.disabled = not valid or not can_afford
		else:
			var minimum_stops := 1 if transport_route_mode == "air" else 2
			placement_label.text = L10n.text("規劃%s｜已選 %d/%d 站｜車隊 %d｜班距 %d 分｜票價 $%d") % [
				L10n.text(_transport_route_label(transport_route_mode)), transport_route_station_tiles.size(), minimum_stops,
				transport_route_fleet_size, transport_route_headway_minutes, transport_route_fare,
			]
			if placement_confirm_button != null:
				placement_confirm_button.text = L10n.text("建立並驗證路線")
				placement_confirm_button.disabled = transport_route_station_tiles.size() < minimum_stops
		return
	placement_label.text = L10n.text("放置 %s｜點擊空地查看總價｜Esc／右鍵取消") % L10n.text(placement_building_name)


func _flatten_pending_terrain() -> void:
	if (not placement_mode_active and not _is_transport_map_action_active()) or vertical_slice == null or _pending_terrain_tile < 0:
		return
	var tile_index := _pending_terrain_tile
	var was_transport_plan := _is_transport_map_action_active()
	var result: Dictionary = vertical_slice.flatten_terrain(tile_index)
	if not bool(result.get("ok", false)):
		_set_hint("無法整平地形：%s" % _vertical_error_text(str(result.get("error", "unknown"))), true)
		_sync_placement_banner()
		return
	_pending_terrain_tile = -1
	selected_cell_index = tile_index
	_consume_vertical_events(vertical_slice.drain_ui_events())
	debug_sync_npc_navigation_obstacles()
	if npc_map_controller != null:
		npc_map_controller.repath_all()
	_update_tile_visual(tile_index, city_grid[tile_index])
	# Flattening is a treasury transaction, so refresh the HUD in the same frame.
	# Otherwise the authoritative funds value changes immediately but the header
	# keeps showing the pre-flatten balance until another unrelated UI action.
	_update_ui()
	_sync_placement_banner()
	if was_transport_plan:
		_handle_transport_tile_pressed(tile_index)
		_set_hint("地形已整平，費用 $%d；此格已加入目前交通規劃。" % int(result.get("cost", 0)), false)
	else:
		_set_hint("地形已整平，費用 $%d；現在可在此地格施工。" % int(result.get("cost", 0)), false)
	_autosave("action:terrain_flattened")


func _confirm_pending_construction(tile_index: int) -> void:
	if not placement_mode_active or tile_index != _pending_construction_tile or vertical_slice == null:
		return
	var building_name := placement_building_name
	var result: Dictionary = vertical_slice.start_approved_building(building_name, tile_index, _pending_construction_workers)
	if not bool(result.get("ok", false)):
		_set_hint("無法開工「%s」：%s" % [building_name, _vertical_error_text(str(result.get("error", "unknown")))], true)
		_pending_construction_tile = -1
		_update_ui()
		return
	selected_cell_index = tile_index
	placement_mode_active = false
	placement_building_name = ""
	_pending_construction_tile = -1
	_sync_placement_banner()
	_set_hint("「%s」已開工，分配 %d 名工程人員，預付總造價 $%d。" % [building_name, _pending_construction_workers, int(result.get("total_cost", 0))], false)
	# start_approved_building() queues construction_started immediately, while
	# process_frame() only drains UI events on the next 120-second game-day tick.
	# Consume it now so the worksite footprint and every resident path are updated
	# in the same frame as the confirmed placement.
	_consume_vertical_events(vertical_slice.drain_ui_events())
	_sync_vertical_state()
	_update_ui()
	_autosave("action:construction_started")


func _on_construction_confirmation_cancelled() -> void:
	_pending_construction_tile = -1
	_set_hint("已返回選地；尚未扣除任何費用。", false)

func _select_built_cell(index: int) -> void:
	selected_cell_index = index
	var building_name := city_grid[index]
	if _is_customizable_building(building_name) and not building_customizations.has(index):
		building_customizations[index] = {"variant": 0, "roof": 0, "wall": 0}
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
	_open_building_context(index)

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
		CitySimulationServiceScript.metric_effect_patch(_city_metrics_snapshot(), data, 1)
	)

func _remove_building_effect(data: Dictionary) -> void:
	_apply_city_metric_patch(
		CitySimulationServiceScript.metric_effect_patch(_city_metrics_snapshot(), data, -1)
	)

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
	return {
		"park_count": _building_count("公園"),
		"hospital_count": _building_count("醫院"),
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
		blueprint_view_model["blueprint_review"] = vertical_slice.blueprint_review_status(selected_building)
		blueprint_view_model["blueprint_library"] = vertical_slice.approved_blueprints(selected_building)
		blueprint_view_model["active_blueprint_id"] = str(vertical_slice.active_blueprint_status(selected_building).get("library_id", ""))
		var placement_quote: Dictionary = vertical_slice.placement_quote(
			selected_building,
			vertical_slice_panel.selected_worker_count()
		)
		blueprint_view_model["placement_quote"] = placement_quote if bool(placement_quote.get("ok", false)) else {}
		vertical_slice_panel.set_view_model(blueprint_view_model)
	if public_affairs_panel:
		public_affairs_panel.set_view_model(view_model)
	if governance_force_label:
		governance_force_label.text = str(view_model.get("governance_text", "目前沒有遭否決的法案。"))
	if governance_force_button:
		governance_force_button.disabled = not bool(view_model.get("can_force_enact", false))

func _consume_vertical_events(events: Array[Dictionary]) -> void:
	var event_types := PackedStringArray()
	var navigation_changed := false
	var request_context_changed := false
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
				_rebuild_city_from_core()
				_add_announcement("存檔讀取完成。")
	if request_context_changed:
		_reconcile_resident_request_completion()
	if navigation_changed:
		debug_sync_npc_navigation_obstacles()
		if npc_map_controller != null:
			npc_map_controller.repath_all()
	_sync_vertical_state()
	refresh_visible_npc_proxies()
	if not event_types.is_empty():
		_autosave("event:%s" % ",".join(event_types))

func _start_selected_demolition() -> void:
	if vertical_slice == null or selected_cell_index < 0 or selected_cell_index >= city_grid.size() or city_grid[selected_cell_index] == "":
		_set_hint("請先在地圖上選取要拆除的建築。", true)
		return
	var workers: int = int(vertical_slice_panel.selected_worker_count()) if vertical_slice_panel else 5
	var result: Dictionary = vertical_slice.start_demolition(selected_cell_index, workers)
	if bool(result.get("ok", false)):
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
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_set_hint("已進入司法與彈劾程序；請到市政中心的「法院審判」與「監察質詢」自行提出辯護。", true)
	else:
		_set_hint("目前沒有可強制執行的遭否決法案。", true)
	_update_ui()

func _accept_request_by_id(request_id: String) -> void:
	if vertical_slice.accept_request_by_id(request_id, false):
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_reconcile_resident_request_completion()
		_set_hint("居民陳情已列入處理。", false)
	else:
		_set_hint("這筆陳情已處理或不存在。", true)
	_update_ui()


func _reconcile_resident_request_completion() -> bool:
	if vertical_slice == null:
		return false
	var completed: Array[String] = vertical_slice.complete_requests(_vertical_city_context())
	if completed.is_empty():
		return false
	var completion_events: Array[Dictionary] = vertical_slice.drain_ui_events()
	if not completion_events.is_empty():
		_consume_vertical_events(completion_events)
	return true


func _reject_request_by_id(request_id: String) -> void:
	if vertical_slice.reject_request_by_id(request_id, false):
		_consume_vertical_events(vertical_slice.drain_ui_events())
		_set_hint("居民陳情已拒絕。", false)
	else:
		_set_hint("這筆陳情已處理或不存在。", true)
	_update_ui()


func _on_defense_submitted(mode: String, _case_id: String, _defense_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	vertical_slice.sync_governance_state("governance.%s_defense_submitted" % mode)
	_set_hint("%s辯護資料已提交。" % ("法院" if mode == "judicial" else "監察質詢"), false)
	_autosave("action:%s_defense_submitted" % mode)
	_update_ui()

func _rebuild_city_from_core() -> void:
	city_grid.clear()
	for _index in CELL_COUNT:
		city_grid.append("")
	building_customizations.clear()
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
		"approved_blueprint_required": "尚無核准藍圖，請先到「市政中心 → 設計藍圖」送審並等待 2–7 天",
		"insufficient_treasury": "城市公庫不足",
		"insufficient_workers": "工程隊人力不足，最多共用 20 人",
		"tile_occupied": "該地格已有建築",
		"invalid_tile_id": "地格編號無效",
		"terrain_not_flat": "地形尚未整平",
		"terrain_not_flattenable": "該地形不可整平",
		"terrain_in_use": "該地格有建物或工程，不能整平",
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
	return CitySimulationServiceScript.sum_int_values(_tax_revenues())

func _tax_revenues() -> Dictionary:
	return CitySimulationServiceScript.tax_revenues(
		_resident_income_tax_base(),
		population,
		_commercial_base_income(),
		_industrial_base_income(),
		tax_rates
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
	return vertical_slice.population.match_open_jobs(open_jobs, vertical_slice.game_day())


func _job_sector_for_building(building_name: String) -> String:
	return MunicipalEconomyServiceScript.job_sector_for_building(building_name, buildings)

func _commercial_base_income() -> int:
	return CitySimulationServiceScript.base_income(city_grid, buildings, "commercial_income")

func _industrial_base_income() -> int:
	return CitySimulationServiceScript.base_income(city_grid, buildings, "industrial_income")

func _business_income() -> int:
	return CitySimulationServiceScript.business_income(
		_commercial_base_income(),
		bool(active_policies.get("商業振興", false)),
		_active_law_value("business_bonus"),
		_tax_activity_factor("business"),
		_tax_activity_factor("consumption")
	)

func _industrial_income() -> int:
	return CitySimulationServiceScript.industrial_income(
		_industrial_base_income(),
		_tax_activity_factor("industry"),
		_active_law_value("industrial_bonus")
	)

func _tax_activity_factor(tax_key: String) -> float:
	return CitySimulationServiceScript.tax_activity_factor(
		int(tax_rates[tax_key]),
		int(TAX_DEFS[tax_key]["reasonable"])
	)

func _utility_income() -> int:
	var raw_total := 0.0
	for revenue: Variant in CitySimulationServiceScript.utility_revenues(
		population, city_grid, buildings, utility_fees, UTILITY_DEFS
	).values():
		raw_total += float(revenue)
	return int(round(raw_total))

func _utility_base_units(fee_key: String) -> float:
	return CitySimulationServiceScript.utility_base_units(fee_key, population, city_grid)

func _service_income() -> int:
	return CitySimulationServiceScript.sum_int_values(_service_revenues())

func _service_revenues() -> Dictionary:
	return CitySimulationServiceScript.service_revenues(
		population,
		city_grid,
		service_fees,
		SERVICE_DEFS
	)

func _service_fee_income(service_key: String) -> int:
	return CitySimulationServiceScript.service_fee_income(
		service_key,
		population,
		city_grid,
		service_fees,
		SERVICE_DEFS
	)

func _utility_fee_income(fee_key: String, base_units: float) -> float:
	return CitySimulationServiceScript.utility_fee_income(
		fee_key,
		base_units,
		city_grid,
		buildings,
		utility_fees,
		UTILITY_DEFS
	)

func _utility_efficiency_bonus(fee_key: String) -> float:
	return CitySimulationServiceScript.utility_efficiency_bonus(fee_key, city_grid, buildings)

func _maintenance_cost() -> int:
	return CitySimulationServiceScript.maintenance_cost(city_grid, buildings)

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

func _utility_detail_text(fee_key: String) -> String:
	var def: Dictionary = UTILITY_DEFS[fee_key]
	var has_building := _building_count(def["building"]) > 0
	var building_name := L10n.text(str(def["building"]))
	var note := (L10n.text("有%s") % building_name) if has_building else (L10n.text("缺%s") % building_name)
	var forecast := _fiscal_item_forecast("utility", fee_key)
	return L10n.text("收入 $%d｜%s｜%s") % [int(round(_utility_fee_income(fee_key, _utility_base_units(fee_key)))), note, forecast["summary"]]

func _service_detail_text(service_key: String) -> String:
	var def: Dictionary = SERVICE_DEFS[service_key]
	var has_building := _building_count(def["building"]) > 0
	var building_name := L10n.text(str(def["building"]))
	var note := (L10n.text("有%s") % building_name) if has_building else (L10n.text("缺%s") % building_name)
	var forecast := _fiscal_item_forecast("service", service_key)
	return L10n.text("收入 $%d｜%s｜%s") % [_service_fee_income(service_key), note, forecast["summary"]]

func _update_ui() -> void:
	_sync_vertical_state()
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
	for tax_key in tax_rates.keys():
		var tax_forecast := _fiscal_item_forecast("tax", tax_key)
		labels["tax_value_%s" % tax_key].text = "%d%%  ● %s" % [tax_rates[tax_key], tax_forecast["state_text"]]
		labels["tax_value_%s" % tax_key].add_theme_color_override("font_color", tax_forecast["color"])
		_apply_fee_slider_visual(tax_sliders[tax_key], str(tax_forecast["state"]))
		tax_sliders[tax_key].tooltip_text = str(tax_forecast["summary"])
	for fee_key in utility_fees.keys():
		var utility_forecast := _fiscal_item_forecast("utility", fee_key)
		labels["utility_%s" % fee_key].text = "%d / %s  ● %s" % [utility_fees[fee_key], UTILITY_DEFS[fee_key]["unit"], utility_forecast["state_text"]]
		labels["utility_%s" % fee_key].add_theme_color_override("font_color", utility_forecast["color"])
		_apply_fee_slider_visual(utility_sliders[fee_key], str(utility_forecast["state"]))
		utility_sliders[fee_key].tooltip_text = str(utility_forecast["summary"])
	for service_key in service_fees.keys():
		var service_forecast := _fiscal_item_forecast("service", service_key)
		labels["service_%s" % service_key].text = "%d / %s  ● %s" % [service_fees[service_key], SERVICE_DEFS[service_key]["unit"], service_forecast["state_text"]]
		labels["service_%s" % service_key].add_theme_color_override("font_color", service_forecast["color"])
		_apply_fee_slider_visual(service_sliders[service_key], str(service_forecast["state"]))
		service_sliders[service_key].tooltip_text = str(service_forecast["summary"])
	selected_label.text = L10n.text("%s　基礎造價 $%d\n%s") % [
		L10n.text(selected_building),
		buildings[selected_building]["cost"],
		_visual_effects(buildings[selected_building], 3)
	]
	report_label.text = _current_month_major_event_summary()
	if report_details_label != null:
		report_details_label.text = last_report_details
	_update_metric_visual("治安", security)
	_update_metric_visual("環境", environment)
	_update_metric_visual("交通", traffic)
	_update_metric_visual("教育", education)
	_update_metric_visual("醫療", healthcare)
	_update_city_metric_cards()

	var tax_revenues := _tax_revenues()
	for tax_key in tax_rates.keys():
		labels["tax_detail_%s" % tax_key].text = _tax_detail_text(tax_key, tax_revenues[tax_key])
	for fee_key in utility_fees.keys():
		labels["utility_detail_%s" % fee_key].text = _utility_detail_text(fee_key)
	for service_key in service_fees.keys():
		labels["service_detail_%s" % service_key].text = _service_detail_text(service_key)
	var tax_income := _total_tax_income()
	var business_income := _business_income()
	var industrial_income := _industrial_income()
	var utility_income := _utility_income()
	var service_income := _service_income()
	var maintenance := _maintenance_cost()
	var policy_expense := _policy_expense()
	var law_expense := _active_law_expense()
	var net_income := tax_income + business_income + industrial_income + utility_income + service_income - maintenance - policy_expense - law_expense
	if labels.has("income_tax"):
		labels["income_tax"].text = _tax_detail_text("income", tax_revenues["income"])
	if labels.has("consumption_tax"):
		labels["consumption_tax"].text = _tax_detail_text("consumption", tax_revenues["consumption"])
	if labels.has("business_tax"):
		labels["business_tax"].text = _tax_detail_text("business", tax_revenues["business"])
	if labels.has("industry_tax"):
		labels["industry_tax"].text = _tax_detail_text("industry", tax_revenues["industry"])
	var total_income := tax_income + business_income + industrial_income + utility_income + service_income
	var total_expense := maintenance + policy_expense + law_expense
	_refresh_city_data_dashboard({
		"tax_income": tax_income,
		"business_income": business_income,
		"industrial_income": industrial_income,
		"utility_income": utility_income,
		"service_income": service_income,
		"total_income": total_income,
		"total_expense": total_expense,
		"net_income": net_income,
	})
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
	_update_transport_runtime()
	_refresh_transport_planning_panel()

	for building_name in building_buttons.keys():
		var button: Button = building_buttons[building_name]
		var data: Dictionary = buildings[building_name]
		button.text = _building_visual_text(building_name, data)
		button.tooltip_text = "%s\n%s\n%s" % [L10n.text(building_name), L10n.text(str(data.get("description", ""))), _visual_effects(data, 8)]
		button.disabled = false
		_apply_building_button_style(button, building_name, building_name == selected_building)

	_refresh_governance_catalog()
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
	L10n.localize_tree(self)
	_sync_placement_banner()
	# Tile/NPC refreshes above restore their normal tooltip text. Re-apply the
	# current UI blocking state last so a start screen or modal remains authoritative.
	_sync_map_interaction_for_ui()

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
	_set_map_interaction_enabled(false)
	tutorial_overlay.open(true)
	_sync_time_pause_for_ui()


func _on_tutorial_audio_cue(cue: String) -> void:
	if audio_director != null:
		audio_director.play_cue(cue)


func _on_tutorial_completed(skipped: bool) -> void:
	tutorial_completed = true
	_sync_time_pause_for_ui()
	_set_hint("故事教學已略過；可從設定頁重播。" if skipped else "故事教學完成。從官方入門藍圖開始興建吧。", false)
	_autosave("tutorial:skipped" if skipped else "tutorial:completed")


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
	bill_buttons.clear()
	governance_status_tabs = null
	governance_status_grids.clear()
	governance_status_pagers.clear()
	governance_status_sections.clear()
	governance_status_empty_labels.clear()
	governance_bill_cards.clear()
	governance_policy_cards.clear()
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
	var min_value := 0
	var max_value := 0
	if kind == "tax":
		min_value = int(TAX_DEFS[key]["min"])
		max_value = int(TAX_DEFS[key]["max"])
		value = clampi(value, min_value, max_value)
		tax_rates[key] = value
		tax_rate = int(tax_rates["income"])
		tax_sliders[key].set_value_no_signal(value)
		_sync_number_input(tax_inputs, key, value, true)
	elif kind == "utility":
		min_value = int(UTILITY_DEFS[key]["min"])
		max_value = int(UTILITY_DEFS[key]["max"])
		value = clampi(value, min_value, max_value)
		utility_fees[key] = value
		utility_sliders[key].set_value_no_signal(value)
		_sync_number_input(utility_inputs, key, value, true)
	elif kind == "service":
		min_value = int(SERVICE_DEFS[key]["min"])
		max_value = int(SERVICE_DEFS[key]["max"])
		value = clampi(value, min_value, max_value)
		service_fees[key] = value
		service_sliders[key].set_value_no_signal(value)
		_sync_number_input(service_inputs, key, value, true)

	_recalculate_satisfaction()
	_recalculate_score()
	_update_ui()
	_autosave("action:%s_value_committed" % kind)

func _restore_number_input(kind: String, key: String) -> void:
	if kind == "tax":
		_sync_number_input(tax_inputs, key, tax_rates[key], true)
	elif kind == "utility":
		_sync_number_input(utility_inputs, key, utility_fees[key], true)
	elif kind == "service":
		_sync_number_input(service_inputs, key, service_fees[key], true)

func _sync_number_input(inputs: Dictionary, key: String, value: int, force: bool = false) -> void:
	if not inputs.has(key):
		return
	var input: LineEdit = inputs[key]
	if force or not input.has_focus():
		input.text = str(value)


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
	labels["month"].text = "%s %d/%d" % ["Ⅱ" if paused else "▶", month, day]
	labels["month"].tooltip_text = ""
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
	normal.bg_color = COLOR_WARNING if is_danger else (COLOR_ACCENT if is_primary else (Color(0.18, 0.25, 0.32) if is_dark_mode else Color(0.96, 0.91, 0.80)))
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.48, 0.05, 0.03) if is_danger else (COLOR_ACCENT_DARK if is_primary else (Color(0.58, 0.42, 0.22) if not is_dark_mode else _theme_border()))
	var hover := normal.duplicate()
	hover.bg_color = Color(0.92, 0.25, 0.12) if is_danger else (Color(0.08, 0.52, 0.82) if is_primary else (Color(0.23, 0.32, 0.42) if is_dark_mode else Color(1.0, 0.96, 0.84)))
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.48, 0.05, 0.03) if is_danger else (COLOR_ACCENT_DARK if is_primary else (Color(0.13, 0.22, 0.31) if is_dark_mode else Color(0.86, 0.75, 0.56)))
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.78, 0.82, 0.85)
	disabled.border_color = Color(0.56, 0.61, 0.66)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color.WHITE if is_primary or is_danger else _theme_text())
	button.add_theme_color_override("font_hover_color", Color.WHITE if is_primary or is_danger else _theme_text())
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.31, 0.36, 0.40))

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
	selected_style.bg_color = Color("28414a") if is_dark_mode else Color("fff4cf")
	selected_style.border_color = Color("d3aa58") if is_dark_mode else Color("d59a38")
	selected_style.shadow_color = Color(0, 0, 0, 0.16)
	selected_style.shadow_size = 2
	var hovered_style := unselected_style.duplicate() as StyleBoxFlat
	hovered_style.bg_color = Color("23414a") if is_dark_mode else Color("eaf7f4")
	hovered_style.border_color = Color("63a69b")
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
		var terrain_state: Dictionary = vertical_slice.terrain_state_for_tile(index) if vertical_slice != null else {}
		var terrain_buildable := bool(terrain_state.get("buildable", true))
		cell.call("set_tile", {
			"index": index,
			"building_name": building_name,
			"building_color": _building_color(building_name),
			"terrain_kind": _terrain_kind_for_cell(index, building_name),
			"terrain_type": str(terrain_state.get("effective_kind", "flat_grass")),
			"terrain_buildable": terrain_buildable,
			"terrain_flattenable": bool(terrain_state.get("flattenable", false)),
			"visual": BUILDING_VISUALS.get(building_name, {}),
			"customization": building_customizations.get(index, {}),
			"dark_mode": is_dark_mode,
			"selected": selected_cell_index == index,
			"is_building_mode": placement_mode_active,
			"placement_allowed": _is_tile_inside_hud_safe_area(index) and terrain_buildable,
			"construction": active_construction
		})
	else:
		cell.text = _tile_text(building_name, index)
		_apply_cell_style(cell, building_name)

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
	return Color(0.08, 0.11, 0.15) if is_dark_mode else Color(0.96, 0.98, 1.0)

func _theme_panel() -> Color:
	return Color(0.13, 0.18, 0.24) if is_dark_mode else Color.WHITE

func _theme_panel_alt() -> Color:
	return Color(0.11, 0.16, 0.21) if is_dark_mode else Color(0.98, 1.0, 0.99)


func _theme_report_bg() -> Color:
	return Color(0.06, 0.09, 0.13) if is_dark_mode else Color(0.08, 0.14, 0.20)

func _theme_text() -> Color:
	return Color(0.93, 0.96, 0.98) if is_dark_mode else COLOR_TEXT

func _theme_muted() -> Color:
	return Color(0.70, 0.76, 0.82) if is_dark_mode else COLOR_MUTED

func _theme_border() -> Color:
	return Color(0.31, 0.42, 0.52) if is_dark_mode else Color(0.72, 0.80, 0.86)

func _theme_accent_text() -> Color:
	return Color(0.55, 0.78, 1.0) if is_dark_mode else COLOR_ACCENT_DARK


func _theme_success_text() -> Color:
	return Color(0.38, 0.92, 0.66) if is_dark_mode else COLOR_SUCCESS

func _avg(values: Array) -> int:
	if values.is_empty():
		return 0
	var total := 0.0
	for value in values:
		total += float(value)
	return int(round(total / values.size()))

func _clamp_score(value: int) -> int:
	return clampi(value, 0, 100)
