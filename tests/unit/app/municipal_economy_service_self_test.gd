extends SceneTree

const MunicipalEconomyServiceScript = preload("res://scripts/app/municipal_economy_service.gd")

var failed := false


func _initialize() -> void:
	_check(
		is_equal_approx(MunicipalEconomyServiceScript.resident_income_tax_base(1_000_000, 0.0005), 500.0),
		"resident income uses the documented personal-to-treasury scale"
	)
	_check(
		MunicipalEconomyServiceScript.resident_income_tax_base(-1, 0.0005) == 0.0,
		"invalid negative resident income cannot create a negative tax base"
	)
	_check(
		MunicipalEconomyServiceScript.resident_income_tax_base(1_000_000, -1.0) == 0.0,
		"invalid negative treasury scale cannot invert the tax base"
	)

	var buildings := {
		"大型商場": {"category": "商業類", "job_attraction": 3},
		"工廠": {"category": "產業類", "job_attraction": 2},
		"市政府": {"category": "行政類", "job_attraction": 1},
		"公園": {"category": "休閒類", "job_attraction": 0},
		"損壞定義": "not-a-dictionary",
	}
	var city_grid := ["大型商場", "", "工廠", "未知建築", "市政府", "損壞定義", "公園"]
	var building_only: Array[Dictionary] = MunicipalEconomyServiceScript.build_open_jobs(
		city_grid,
		buildings,
		4,
		0.0
	)
	_check(building_only.size() == 2, "only declared jobs inside the requested grid boundary are emitted")
	_check(str(building_only[0].get("job_id", "")) == "building:000:商業", "commercial job ID is stable and namespaced")
	_check(int(building_only[0].get("slots", 0)) == 3, "commercial capacity matches job_attraction")
	_check(str(building_only[1].get("job_id", "")) == "building:002:工業", "industrial job ID is stable and namespaced")
	_check(int(building_only[1].get("slots", 0)) == 2, "industrial capacity matches job_attraction")
	_check(building_only.all(func(job: Dictionary) -> bool: return int(job.get("salary", 0)) == -1), "job offers never invent salary data")

	var with_policy: Array[Dictionary] = MunicipalEconomyServiceScript.build_open_jobs(
		city_grid,
		buildings,
		city_grid.size(),
		2.4
	)
	_check(with_policy.size() == 4, "building and active-law capacity coexist without changing either source")
	_check(str(with_policy[2].get("job_id", "")) == "building:004:服務業", "uncategorized administrative work keeps the existing service-sector mapping")
	_check(str(with_policy[3].get("job_id", "")) == "policy:public_service", "active-law jobs keep the existing public-service namespace")
	_check(int(with_policy[3].get("slots", 0)) == 2, "active-law capacity retains the existing rounding rule")

	var authoritative_records := {
		"building_000004": {
			"building_id": "building_000004",
			"building_name": "工廠",
			"occupied_tile_ids": [12, 13],
			"status": "active",
		},
		"building_000005": {
			"building_id": "building_000005",
			"building_name": "大型商場",
			"occupied_tile_ids": [20, 21, 22],
			"status": "active",
		},
		"building_000006": {
			"building_id": "building_000006",
			"building_name": "工廠",
			"occupied_tile_ids": [30, 31],
			"status": "scrapped",
		},
	}
	var authoritative_jobs: Array[Dictionary] = MunicipalEconomyServiceScript.build_open_jobs(
		authoritative_records,
		{
			"工廠": {"category": "產業類", "job_capacity": 8, "job_attraction": 99},
			"大型商場": {"category": "商業類", "job_capacity": 5},
		},
		100,
		0.0
	)
	_check(authoritative_jobs.size() == 2, "authoritative building records emit one job offer per active building, not per occupied cell")
	_check(str(authoritative_jobs[0].get("job_id", "")) == "building:building_000004:工業", "authoritative job ID uses the stable building record ID")
	_check(int(authoritative_jobs[0].get("slots", 0)) == 8, "job_capacity overrides the legacy job_attraction fallback")
	_check(int(authoritative_jobs[1].get("slots", 0)) == 5, "multi-cell commercial building capacity is counted once")
	_check(authoritative_jobs.all(func(job: Dictionary) -> bool: return not str(job.get("job_id", "")).contains("building_000006")), "scrapped building offers no jobs")

	_check(MunicipalEconomyServiceScript.job_sector_for_building("大型商場", buildings) == "商業", "commercial category mapping is preserved")
	_check(MunicipalEconomyServiceScript.job_sector_for_building("工廠", buildings) == "工業", "industrial category mapping is preserved")
	_check(MunicipalEconomyServiceScript.job_sector_for_building("未知建築", buildings) == "服務業", "missing definitions fail safely to the existing service sector")

	if failed:
		quit(1)
	else:
		print("Municipal economy service self-test passed. Jobs=%d" % with_policy.size())
		quit(0)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Municipal economy service self-test failed: %s" % label)
