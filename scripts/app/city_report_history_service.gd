class_name CityReportHistoryService
extends RefCounted

## Owns the bounded, save-compatible city report history.
##
## The application shell still decides when a month settles, resolves NPC names,
## and animates visible controls. This service owns only deterministic report
## data, normalization, record-time event de-duplication, history limits, and
## localized text projection from already-recorded facts.

const MONTHLY_REPORT_HISTORY_LIMIT := 24
const MAJOR_EVENT_HISTORY_LIMIT := 200
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12

var last_month_summary: Dictionary = {}
var monthly_report_history: Array[Dictionary] = []
var major_event_history: Array[Dictionary] = []


func _init() -> void:
	reset()


func reset() -> void:
	last_month_summary = _default_last_month_summary()
	# Keep both Array instances stable. Main exposes compatibility aliases and
	# existing callers may retain those references across a reset or restore.
	monthly_report_history.clear()
	major_event_history.clear()


func snapshot() -> Dictionary:
	return {
		"last_month_summary": last_month_summary.duplicate(true),
		"monthly_report_history": monthly_report_history.duplicate(true),
		"major_event_history": major_event_history.duplicate(true),
	}


func restore(
		last_summary_variant: Variant,
		monthly_history_variant: Variant,
		major_history_variant: Variant,
		metric_defaults: Dictionary
) -> void:
	set_last_month_summary(last_summary_variant if last_summary_variant is Dictionary else {})
	replace_monthly_report_history(monthly_history_variant, metric_defaults)
	if monthly_report_history.is_empty() and bool(last_month_summary.get("available", false)):
		monthly_report_history.append(_legacy_monthly_report_snapshot(metric_defaults))
	replace_major_event_history(major_history_variant)


func set_last_month_summary(summary: Dictionary) -> void:
	last_month_summary = _sanitize_last_month_summary(summary)


func replace_monthly_report_history(history_variant: Variant, metric_defaults: Dictionary) -> void:
	var history_copy: Array = []
	if history_variant is Array:
		history_copy = history_variant.duplicate(true)
	monthly_report_history.clear()
	for snapshot_variant: Variant in history_copy:
		if snapshot_variant is Dictionary:
			monthly_report_history.append(
				sanitize_monthly_report_snapshot(snapshot_variant, metric_defaults)
			)
	_trim_monthly_history()


func replace_major_event_history(history_variant: Variant) -> void:
	var history_copy: Array = []
	if history_variant is Array:
		history_copy = history_variant.duplicate(true)
	major_event_history.clear()
	for event_variant: Variant in history_copy:
		if not event_variant is Dictionary:
			continue
		var sanitized_event := sanitize_major_event(event_variant)
		if not sanitized_event.is_empty():
			major_event_history.append(sanitized_event)
	_trim_major_event_history()


func record_month(
		summary: Dictionary,
		income: int,
		expense: int,
		population_rate: float,
		metrics: Dictionary
) -> Dictionary:
	set_last_month_summary(summary)
	var report_snapshot := make_monthly_report_snapshot(income, expense, population_rate, metrics)
	monthly_report_history.append(report_snapshot)
	_trim_monthly_history()
	return report_snapshot.duplicate(true)


func make_monthly_report_snapshot(
		income: int,
		expense: int,
		population_rate: float,
		metrics: Dictionary
) -> Dictionary:
	var coverage_rate := 100.0 if expense <= 0 and income > 0 else 0.0
	if expense > 0:
		coverage_rate = float(income) / float(expense) * 100.0
	return {
		"period_index": _next_period_index(),
		"income": income,
		"expense": maxi(0, expense),
		"net": income - expense,
		"coverage_rate": coverage_rate,
		"population": int(metrics.get("population", 300)),
		"population_rate": population_rate,
		"satisfaction": int(metrics.get("satisfaction", 70)),
		"score": int(metrics.get("score", 0)),
		"security": int(metrics.get("security", 70)),
		"environment": int(metrics.get("environment", 70)),
		"traffic": int(metrics.get("traffic", 70)),
		"education": int(metrics.get("education", 70)),
		"healthcare": int(metrics.get("healthcare", 70)),
	}


func sanitize_monthly_report_snapshot(snapshot: Dictionary, metric_defaults: Dictionary) -> Dictionary:
	return {
		"period_index": maxi(1, int(snapshot.get("period_index", 1))),
		"income": int(snapshot.get("income", 0)),
		"expense": maxi(0, int(snapshot.get("expense", 0))),
		"net": int(snapshot.get("net", 0)),
		"coverage_rate": clampf(float(snapshot.get("coverage_rate", 0.0)), 0.0, 10000.0),
		"population": maxi(1, int(snapshot.get("population", metric_defaults.get("population", 300)))),
		"population_rate": clampf(float(snapshot.get("population_rate", 0.0)), -100.0, 10000.0),
		"satisfaction": clampi(int(snapshot.get("satisfaction", metric_defaults.get("satisfaction", 70))), 0, 100),
		"score": clampi(int(snapshot.get("score", metric_defaults.get("score", 0))), 0, 100),
		"security": clampi(int(snapshot.get("security", metric_defaults.get("security", 70))), 0, 100),
		"environment": clampi(int(snapshot.get("environment", metric_defaults.get("environment", 70))), 0, 100),
		"traffic": clampi(int(snapshot.get("traffic", metric_defaults.get("traffic", 70))), 0, 100),
		"education": clampi(int(snapshot.get("education", metric_defaults.get("education", 70))), 0, 100),
		"healthcare": clampi(int(snapshot.get("healthcare", metric_defaults.get("healthcare", 70))), 0, 100),
	}


func latest_monthly_report_snapshot() -> Dictionary:
	if monthly_report_history.is_empty():
		return {}
	return monthly_report_history[monthly_report_history.size() - 1].duplicate(true)


func game_time_for_calendar(month: int, day: int) -> int:
	return maxi(0, (month - 1) * DAYS_PER_MONTH + day - 1)


func date_for_game_time(game_time: int) -> Dictionary:
	var safe_time := maxi(0, game_time)
	var year := int(safe_time / (DAYS_PER_MONTH * MONTHS_PER_YEAR)) + 1
	var year_day := safe_time % (DAYS_PER_MONTH * MONTHS_PER_YEAR)
	return {
		"year": year,
		"month": int(year_day / DAYS_PER_MONTH) + 1,
		"day": year_day % DAYS_PER_MONTH + 1,
		"game_time": safe_time,
	}


func record_major_event(
		event_type: String,
		subject: String = "",
		details: String = "",
		event_key: String = "",
		game_time: int = 0,
		actor_id: String = ""
) -> bool:
	if event_type.is_empty():
		return false
	var resolved_time := maxi(0, game_time)
	var date := date_for_game_time(resolved_time)
	var resolved_key := event_key
	if resolved_key.is_empty():
		resolved_key = "%s:%d:%s:%s" % [event_type, resolved_time, subject, actor_id]
	for existing: Dictionary in major_event_history:
		if str(existing.get("event_key", "")) == resolved_key:
			return false
	major_event_history.append({
		"event_type": event_type,
		"event_key": resolved_key,
		"game_time": resolved_time,
		"year": int(date["year"]),
		"month": int(date["month"]),
		"day": int(date["day"]),
		"subject": subject,
		"details": details,
		"actor_id": actor_id,
	})
	_trim_major_event_history()
	return true


func sanitize_major_event(event: Dictionary) -> Dictionary:
	var event_type := str(event.get("event_type", "")).strip_edges()
	var event_key := str(event.get("event_key", "")).strip_edges()
	if event_type.is_empty() or event_key.is_empty():
		return {}
	var game_time := maxi(0, int(event.get("game_time", 0)))
	var date := date_for_game_time(game_time)
	return {
		"event_type": event_type,
		"event_key": event_key,
		"game_time": game_time,
		"year": clampi(int(event.get("year", date["year"])), 1, 9999),
		"month": clampi(int(event.get("month", date["month"])), 1, MONTHS_PER_YEAR),
		"day": clampi(int(event.get("day", date["day"])), 1, DAYS_PER_MONTH),
		"subject": str(event.get("subject", "")),
		"details": str(event.get("details", "")),
		"actor_id": str(event.get("actor_id", "")),
	}


func current_month_major_event_summary(
		current_year: int,
		current_month: int,
		actor_name_resolver: Callable,
		text_resolver: Callable
) -> String:
	var lines := PackedStringArray()
	for event: Dictionary in major_event_history:
		if int(event.get("year", 0)) != current_year or int(event.get("month", 0)) != current_month:
			continue
		lines.append(
			_text(text_resolver, "第 %d 天｜%s") % [
				int(event.get("day", 1)),
				format_major_event(event, actor_name_resolver, text_resolver),
			]
		)
	if lines.is_empty():
		return _text(text_resolver, "本月尚無重大改革或事件。")
	return "\n".join(lines)


func format_major_event(event: Dictionary, actor_name_resolver: Callable, text_resolver: Callable) -> String:
	var subject := _text(text_resolver, str(event.get("subject", "")))
	var details := _text(text_resolver, str(event.get("details", "")))
	var actor_name := _text(text_resolver, "居民")
	if actor_name_resolver.is_valid():
		actor_name = str(actor_name_resolver.call(str(event.get("actor_id", ""))))
	match str(event.get("event_type", "")):
		"blueprint_approved":
			return _text(text_resolver, "藍圖核准｜「%s」藍圖通過審核並永久存入藍圖庫。") % subject
		"building_completed":
			return _text(text_resolver, "建築完工｜「%s」正式完工並投入使用。") % subject
		"building_demolished":
			return _text(text_resolver, "建築拆除｜「%s」完成拆除，原地恢復可建造。") % subject
		"policy_enabled":
			return _text(text_resolver, "政策頒布｜「%s」正式啟用。") % subject
		"policy_disabled":
			return _text(text_resolver, "政策終止｜「%s」停止施行。") % subject
		"bill_enacted":
			return _text(text_resolver, "法案頒布｜「%s」通過兩院並正式生效。") % subject
		"bill_force_enacted":
			return _text(text_resolver, "法案強制施行｜「%s」未經兩院同意而生效，司法與監察程序已啟動。") % subject
		"petition_accepted":
			return _text(text_resolver, "陳情受理｜%s「%s」：%s") % [actor_name, subject, details]
		"petition_completed":
			return _text(text_resolver, "陳情完成｜%s「%s」：%s") % [actor_name, subject, details]
		"rebellion":
			return _text(text_resolver, "民變爆發｜民怨超過 80，城市治理失序。")
		"governance_failure":
			return _text(text_resolver, "重大治理危機｜%s") % details
		"judicial_ruling":
			return _text(text_resolver, "司法裁決｜%s") % details
		"impeachment":
			return _text(text_resolver, "監察彈劾｜%s") % details
	return _text(text_resolver, "重大事件｜%s") % (details if not details.is_empty() else subject)


func _legacy_monthly_report_snapshot(metric_defaults: Dictionary) -> Dictionary:
	var income := int(last_month_summary.get("income", 0))
	var expense := maxi(0, int(last_month_summary.get("expense", 0)))
	var population_change := int(last_month_summary.get("population_change", 0))
	var population := maxi(1, int(metric_defaults.get("population", 300)))
	var previous_population := maxi(1, population - population_change)
	return make_monthly_report_snapshot(
		income,
		expense,
		float(population_change) / float(previous_population) * 100.0,
		metric_defaults
	)


func _sanitize_last_month_summary(summary: Dictionary) -> Dictionary:
	return {
		"available": bool(summary.get("available", false)),
		"income": int(summary.get("income", 0)),
		"expense": maxi(0, int(summary.get("expense", 0))),
		"net": int(summary.get("net", 0)),
		"population_change": int(summary.get("population_change", 0)),
		"satisfaction_change": int(summary.get("satisfaction_change", 0)),
		"security_change": int(summary.get("security_change", 0)),
		"environment_change": int(summary.get("environment_change", 0)),
		"traffic_change": int(summary.get("traffic_change", 0)),
		"education_change": int(summary.get("education_change", 0)),
		"healthcare_change": int(summary.get("healthcare_change", 0)),
	}


func _default_last_month_summary() -> Dictionary:
	return _sanitize_last_month_summary({})


func _next_period_index() -> int:
	var highest_period_index := 0
	for snapshot: Dictionary in monthly_report_history:
		highest_period_index = maxi(
			highest_period_index,
			int(snapshot.get("period_index", 0))
		)
	return maxi(1, highest_period_index + 1)


func _text(text_resolver: Callable, source: String) -> String:
	if text_resolver.is_valid():
		return str(text_resolver.call(source))
	return source


func _trim_monthly_history() -> void:
	while monthly_report_history.size() > MONTHLY_REPORT_HISTORY_LIMIT:
		monthly_report_history.pop_front()


func _trim_major_event_history() -> void:
	while major_event_history.size() > MAJOR_EVENT_HISTORY_LIMIT:
		major_event_history.pop_front()
