extends SceneTree

const CityReportHistoryServiceScript = preload("res://scripts/app/city_report_history_service.gd")

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = CityReportHistoryServiceScript.new()
	var metrics := _metrics()
	var monthly_alias: Array[Dictionary] = service.monthly_report_history
	var event_alias: Array[Dictionary] = service.major_event_history

	_check(not bool(service.last_month_summary.get("available", true)), "new service starts with an unavailable month summary")
	_check(monthly_alias.is_empty() and event_alias.is_empty(), "new service starts with empty stable histories")

	var day_zero: Dictionary = service.date_for_game_time(0)
	var day_twenty_nine: Dictionary = service.date_for_game_time(29)
	var day_thirty: Dictionary = service.date_for_game_time(30)
	var next_year: Dictionary = service.date_for_game_time(360)
	_check(day_zero == {"year": 1, "month": 1, "day": 1, "game_time": 0}, "day zero maps to the first calendar day")
	_check(int(day_twenty_nine["month"]) == 1 and int(day_twenty_nine["day"]) == 30, "day 29 remains the last day of month one")
	_check(int(day_thirty["month"]) == 2 and int(day_thirty["day"]) == 1, "day 30 begins month two")
	_check(int(next_year["year"]) == 2 and int(next_year["month"]) == 1 and int(next_year["day"]) == 1, "day 360 begins year two")

	var summary := {
		"available": true,
		"income": 1000,
		"expense": 800,
		"net": 200,
		"population_change": 3,
		"satisfaction_change": 1,
		"security_change": -1,
		"environment_change": 2,
		"traffic_change": 0,
		"education_change": 1,
		"healthcare_change": 1,
	}
	var recorded_month: Dictionary = service.record_month(summary, 1000, 800, 1.5, metrics)
	_check(int(recorded_month.get("period_index", 0)) == 1, "first recorded month keeps period index one")
	_check(int(recorded_month.get("net", 0)) == 200 and is_equal_approx(float(recorded_month.get("coverage_rate", 0.0)), 125.0), "month snapshot preserves net and coverage calculations")
	_check(int(recorded_month.get("population", 0)) == 320 and int(recorded_month.get("security", 0)) == 71, "month snapshot copies authoritative metric inputs")
	_check(service.last_month_summary == summary, "recorded month owns the normalized public summary")
	var monthly_before_self_replace: Array[Dictionary] = monthly_alias.duplicate(true)
	service.replace_monthly_report_history(monthly_alias, metrics)
	_check(monthly_alias == monthly_before_self_replace, "self-assignment through the monthly compatibility alias preserves data")

	var zero_expense: Dictionary = service.make_monthly_report_snapshot(10, 0, 0.0, metrics)
	var zero_income: Dictionary = service.make_monthly_report_snapshot(0, 0, 0.0, metrics)
	_check(is_equal_approx(float(zero_expense.get("coverage_rate", 0.0)), 100.0), "positive income with no expense keeps 100 percent coverage")
	_check(is_equal_approx(float(zero_income.get("coverage_rate", -1.0)), 0.0), "zero income and expense keeps zero coverage")

	var authority_snapshot: Dictionary = service.snapshot()
	_check(
		_sorted_strings(authority_snapshot.keys()) == [
			"last_month_summary",
			"major_event_history",
			"monthly_report_history",
		],
		"snapshot preserves the exact three player-shell field names"
	)
	var copied_months: Array = authority_snapshot["monthly_report_history"]
	var copied_month: Dictionary = copied_months[0]
	copied_month["income"] = 999999
	_check(int(service.monthly_report_history[0].get("income", 0)) == 1000, "snapshot returns a deep copy of report authority")
	var round_trip = CityReportHistoryServiceScript.new()
	round_trip.restore(
		authority_snapshot["last_month_summary"],
		authority_snapshot["monthly_report_history"],
		authority_snapshot["major_event_history"],
		metrics
	)
	_check(round_trip.snapshot() == authority_snapshot, "complete report snapshot round-trips without shape or value drift")

	service.reset()
	_check(monthly_alias.is_empty() and event_alias.is_empty(), "reset clears retained Array aliases in place")
	for index in range(25):
		service.record_month(summary, 100 + index, 50, 0.0, metrics)
	_check(monthly_alias.size() == service.MONTHLY_REPORT_HISTORY_LIMIT, "monthly history keeps its exact 24-entry bound")
	_check(int(monthly_alias[0].get("income", 0)) == 101 and int(monthly_alias[-1].get("income", 0)) == 124, "monthly trimming removes only the oldest entry")
	var twenty_sixth_month: Dictionary = service.record_month(summary, 125, 50, 0.0, metrics)
	_check(int(twenty_sixth_month.get("period_index", 0)) == 26, "period index remains monotonic after the 24-entry window fills")
	_check(monthly_alias.size() == 24 and int(monthly_alias[0].get("income", 0)) == 102, "month 26 keeps the bounded window while evicting only month two")
	var latest_copy: Dictionary = service.latest_monthly_report_snapshot()
	latest_copy["income"] = -5
	_check(int(service.monthly_report_history[-1].get("income", 0)) == 125, "latest month accessor returns a deep copy")

	service.reset()
	_check(service.record_major_event("building_completed", "市民會館", "", "event:once", 30), "first unique event is accepted")
	_check(not service.record_major_event("building_completed", "市民會館", "", "event:once", 30), "duplicate event key is rejected")
	_check(int(event_alias[0].get("month", 0)) == 2 and int(event_alias[0].get("day", 0)) == 1, "recorded event uses the shared calendar conversion")
	var events_before_self_replace: Array[Dictionary] = event_alias.duplicate(true)
	service.replace_major_event_history(event_alias)
	_check(event_alias == events_before_self_replace, "self-assignment through the event compatibility alias preserves data")
	_check(not service.record_major_event("", "", "", "blank", 0), "blank event type is rejected")
	service.reset()
	for index in range(201):
		service.record_major_event("building_completed", "建築%d" % index, "", "event:%d" % index, index)
	_check(event_alias.size() == service.MAJOR_EVENT_HISTORY_LIMIT, "major-event history keeps its exact 200-entry bound")
	_check(str(event_alias[0].get("event_key", "")) == "event:1" and str(event_alias[-1].get("event_key", "")) == "event:200", "major-event trimming preserves newest-first chronology")

	var raw_months: Array = []
	for index in range(26):
		raw_months.append({
			"period_index": index + 1,
			"income": index,
			"expense": -10,
			"population": 0,
			"coverage_rate": 20000.0,
			"security": 999,
		})
	var raw_events: Array = [{"event_type": "", "event_key": "invalid"}]
	for index in range(201):
		raw_events.append({
			"event_type": "building_completed",
			"event_key": "restored:%d" % index,
			"game_time": index,
			"month": 99,
			"day": 99,
		})
	service.restore(summary, raw_months, raw_events, metrics)
	_check(monthly_alias.size() == 24 and event_alias.size() == 200, "restore trims both retained aliases without replacing them")
	_check(int(monthly_alias[0].get("expense", -1)) == 0 and int(monthly_alias[0].get("population", 0)) == 1, "restored month snapshots clamp saved bounds")
	_check(int(monthly_alias[0].get("security", 0)) == 100, "restored service metrics clamp to score bounds")
	_check(int(event_alias[0].get("month", 0)) == 12 and int(event_alias[0].get("day", 0)) == 30, "restored event dates clamp to calendar bounds")
	monthly_alias.append({"period_index": 999})
	_check(service.monthly_report_history.size() == 25, "pre-restore monthly alias still points at service authority")
	monthly_alias.pop_back()
	event_alias.append({"event_key": "alias"})
	_check(service.major_event_history.size() == 201, "pre-restore event alias still points at service authority")
	event_alias.pop_back()

	var legacy = CityReportHistoryServiceScript.new()
	legacy.restore(summary, [], [], metrics)
	_check(legacy.monthly_report_history.size() == 1, "available legacy summary restores one comparison snapshot")
	_check(int(legacy.monthly_report_history[0].get("population", 0)) == 320, "legacy snapshot uses supplied authoritative population")

	var l10n = root.get_node_or_null("L10n")
	var original_locale := str(l10n.current_locale) if l10n != null else "zh_TW"
	if l10n != null:
		l10n.set_locale("zh_TW", false)
	legacy.reset()
	legacy.record_major_event("petition_accepted", "改善交通", "增加公車", "petition:1", 0, "npc_1")
	legacy.record_major_event("building_completed", "跨月建築", "", "month:2", 30)
	var actor_name_resolver := func(actor_id: String) -> String:
		return "測試居民-%s" % actor_id
	var text_resolver := func(source: String) -> String:
		return str(l10n.text(source)) if l10n != null else source
	var localized_summary: String = legacy.current_month_major_event_summary(
		1,
		1,
		actor_name_resolver,
		text_resolver
	)
	_check(localized_summary.contains("陳情受理") and localized_summary.contains("測試居民-npc_1"), "event projection preserves localized actor-aware petition text")
	_check(not localized_summary.contains("跨月建築"), "current-month summary filters events by year and month")
	if l10n != null:
		l10n.set_locale(original_locale, false)

	if failed:
		quit(1)
	else:
		print("City report history service self-test passed. Months=%d Events=%d" % [
			service.monthly_report_history.size(),
			service.major_event_history.size(),
		])
		quit(0)


func _metrics() -> Dictionary:
	return {
		"population": 320,
		"satisfaction": 72,
		"score": 68,
		"security": 71,
		"environment": 73,
		"traffic": 64,
		"education": 76,
		"healthcare": 74,
	}


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("City report history service self-test failed: %s" % label)
