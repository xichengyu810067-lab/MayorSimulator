extends SceneTree

const JusticeScript := preload("res://systems/governance/justice-oversight/justice_oversight_system.gd")

var failed := false


func _initialize() -> void:
	var system = JusticeScript.new(7_701)
	var initialized: Dictionary = system.initialize()
	_check(bool(initialized.get("ok", false)), "司法與監察委員資料通過驗證")
	_check(system.active_member_ids("judicial_committee").size() == 15, "司法委員會有 15 名現任委員")
	_check(system.active_member_ids("oversight_committee").size() == 10, "監察委員會有 10 名現任委員")
	_check(int(system.committees["judicial_committee"]["term_years"]) == 5, "司法委員任期五個遊戲年")
	_check(int(system.committees["oversight_committee"]["term_years"]) == 3, "監察委員任期三個遊戲年")
	_check(system.office_registry.size() == 55, "30 位下議員與 25 位委員均納入一人一職登錄")

	for person_id: String in system.sorted_member_ids():
		var member: Dictionary = system.get_member(person_id)
		_check(not str(member.get("name", "")).is_empty(), "%s 有姓名" % person_id)
		_check(not str(member.get("gender", "")).is_empty(), "%s 有性別" % person_id)
		_check(int(member.get("age", 0)) >= 18, "%s 有有效年齡" % person_id)
		_check((member.get("personality_tags", []) as Array).size() >= 3, "%s 有性格資料" % person_id)
		_check(not (member.get("major_cases", []) as Array).is_empty(), "%s 有重大案件紀錄" % person_id)

	var duplicate_lower_council: Dictionary = system.register_administrative_official("LC-001", "林若衡", "finance_director", "財政局長")
	_check(not bool(duplicate_lower_council.get("ok", false)), "下議員不得兼任行政官員")
	var duplicate_committee_name: Dictionary = system.register_administrative_official("admin_duplicate", "沈知衡", "legal_director", "法務局長")
	_check(not bool(duplicate_committee_name.get("ok", false)), "同名司法委員不得兼任行政官員")
	var mayor_registration: Dictionary = system.register_administrative_official("official_mayor", "現任市長", "mayor", "市長")
	_check(bool(mayor_registration.get("ok", false)), "可登錄未兼職的行政官員")
	var invalid_legislator_target: Dictionary = system.open_oversight_case("LC-001", ["不適用的行政調查"], 90, 1)
	_check(not bool(invalid_legislator_target.get("ok", false)), "監察案件只以行政官員為調查對象")

	var opened: Dictionary = system.open_judicial_case("environment_act", 10, 46, "環境法案強制施行案")
	_check(bool(opened.get("ok", false)), "司法委員會可受理重大行政案件")
	var court_case: Dictionary = opened.get("case", {})
	_check((court_case.get("committee_member_ids", []) as Array).size() == 15, "案件交由全體 15 名司法委員審理")
	_check((court_case.get("presiding_member_ids", []) as Array).size() == 3, "案件排定三席可視主審合議庭")
	_check((court_case.get("docket_entries", []) as Array).size() == 1, "立案時建立第一筆程序紀錄")
	_check(
		int(court_case.get("opened_day", 0)) <= int(court_case.get("preparation_day", 0))
		and int(court_case.get("preparation_day", 0)) <= int(court_case.get("hearing_day", 0))
		and int(court_case.get("hearing_day", 0)) <= int(court_case.get("deliberation_day", 0))
		and int(court_case.get("deliberation_day", 0)) <= int(court_case.get("decision_day", 0)),
		"司法程序日程依立案、準備、開庭、合議、宣判排序"
	)
	_check(bool(system.submit_defense(str(court_case.get("id", "")), "public_interest").get("ok", false)), "案件可提交抗辯資料")
	system.advance_judicial_procedures(int(court_case.get("hearing_day", 0)))
	_check(str(system.judicial_cases[str(court_case.get("id", ""))].get("procedural_stage", "")) == "hearing", "到開庭日進入開庭陳述階段")
	system.advance_judicial_procedures(int(court_case.get("deliberation_day", 0)))
	_check(str(system.judicial_cases[str(court_case.get("id", ""))].get("procedural_stage", "")) == "deliberation", "到合議日進入評議階段")
	_check(not bool(system.submit_defense(str(court_case.get("id", "")), "fiscal_emergency").get("ok", false)), "合議開始後不得更換辯護書狀")
	var judgment: Dictionary = system.resolve_judicial_case(str(court_case.get("id", "")), int(court_case.get("decision_day", 0)), {})
	_check(bool(judgment.get("ok", false)), "司法委員會可完成審判")
	var resolved_case: Dictionary = judgment.get("payload", {}).get("case", {})
	_check((resolved_case.get("member_votes", []) as Array).size() == 15, "審判保存 15 筆個別委員意見")
	_check(str(resolved_case.get("procedural_stage", "")) == "judgment", "裁判完成後程序進入宣判階段")
	_check(str(resolved_case.get("outcome", "")) in ["fine", "stop_order", "prison"], "審判產生有效裁決")

	var oversight_opened: Dictionary = system.open_oversight_case(
		"official_mayor",
		["違法強制執行法案", "未依議會決議辦理"],
		85,
		20
	)
	_check(bool(oversight_opened.get("ok", false)), "監察委員會可調查行政官員")
	var oversight_case: Dictionary = oversight_opened.get("case", {})
	_check(bool(system.submit_oversight_defense(str(oversight_case.get("id", "")), "full_disclosure").get("ok", false)), "彈劾質詢可提交完整揭露答辯")
	var oversight_baseline = JusticeScript.new(7_701)
	oversight_baseline.initialize()
	oversight_baseline.register_administrative_official("official_mayor", "現任市長", "mayor", "市長")
	var baseline_opened: Dictionary = oversight_baseline.open_oversight_case(
		"official_mayor",
		["違法強制執行法案", "未依議會決議辦理"],
		85,
		20
	)
	var baseline_case: Dictionary = baseline_opened.get("case", {})
	var baseline_events: Array[Dictionary] = oversight_baseline.resolve_due_oversight_cases(int(baseline_case.get("decision_day", 0)), {})
	var oversight_events: Array[Dictionary] = system.resolve_due_oversight_cases(int(oversight_case.get("decision_day", 0)), {})
	_check(oversight_events.size() == 1, "監察案件到期後完成表決")
	var resolved_oversight: Dictionary = oversight_events[0].get("payload", {}).get("case", {})
	var baseline_resolved: Dictionary = baseline_events[0].get("payload", {}).get("case", {})
	_check((resolved_oversight.get("member_votes", []) as Array).size() == 10, "彈劾案保存 10 筆個別監察委員意見")
	_check(str(resolved_oversight.get("defense_template_id", "")) == "full_disclosure", "監察案件保存玩家的彈劾答辯")
	_check(
		float((resolved_oversight.get("member_votes", []) as Array)[0].get("score", 0))
		< float((baseline_resolved.get("member_votes", []) as Array)[0].get("score", 0)),
		"完整揭露答辯會降低監察委員的彈劾支持分數"
	)
	_check(str(resolved_oversight.get("outcome", "")) == "impeached", "高證據強度案件通過彈劾")
	_check(int(resolved_oversight.get("votes_for_impeachment", 0)) >= 6, "彈劾須取得 10 席中的至少 6 票")

	var serialized: Variant = JSON.parse_string(JSON.stringify(system.to_dict()))
	var restored = JusticeScript.new()
	var restore_result: Dictionary = restored.load_state(serialized)
	_check(bool(restore_result.get("ok", false)), "司法系統可完成 JSON 存檔往返")
	_check(restored.stable_hash() == system.stable_hash(), "存檔往返後資料一致")
	_check(str(restored.judicial_cases.get(str(court_case.get("id", "")), {}).get("defense_template_id", "")) == "public_interest", "司法抗辯於存檔往返後保留")
	_check(str(restored.oversight_cases.get(str(oversight_case.get("id", "")), {}).get("defense_template_id", "")) == "full_disclosure", "監察答辯於存檔往返後保留")

	var year_four_events: Array[Dictionary] = system.advance_year(4)
	_check(year_four_events.size() == 10, "第四年開始時十名監察委員任期屆滿")
	_check(system.active_member_ids("oversight_committee").is_empty(), "三年任期結束後監察席次空缺")
	_check(system.active_member_ids("judicial_committee").size() == 15, "第四年司法委員仍在五年任期內")
	var year_six_events: Array[Dictionary] = system.advance_year(6)
	_check(year_six_events.size() == 15, "第六年開始時十五名司法委員任期屆滿")
	_check(system.active_member_ids("judicial_committee").is_empty(), "五年任期結束後司法席次空缺")

	if not failed:
		print("Justice and oversight self-test passed. Members=25 JudicialCases=%d OversightCases=%d Hash=%s" % [
			system.judicial_cases.size(),
			system.oversight_cases.size(),
			restored.stable_hash(),
		])
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Justice and oversight self-test failed: %s" % label)
