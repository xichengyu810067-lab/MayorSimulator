extends SceneTree

const DatabaseScript := preload("res://systems/governance/lower-council/lower_council_database.gd")
const VoteModelScript := preload("res://systems/governance/lower-council/lower_council_vote_model.gd")

var failed := false


func _initialize() -> void:
	var database = DatabaseScript.new()
	var load_result: Dictionary = database.load_default()
	_check(bool(load_result.get("ok", false)), "30 位議員資料可載入且通過驗證")
	_check(database.members.size() == 30, "議員主檔固定為 30 筆")
	_check(database.majority_threshold == 16, "過半門檻固定為 16 票")
	_check(database.vote_history.size() == 240, "每位議員具有八筆初始化歷史投票")
	_check(database.members_by_caucus("財政與發展聯盟").size() == 7, "財政與發展聯盟七席")
	_check(database.members_by_caucus("社會民生聯盟").size() == 7, "社會民生聯盟七席")
	_check(database.members_by_caucus("綠色未來聯盟").size() == 6, "綠色未來聯盟六席")
	_check(database.members_by_caucus("公民地方聯盟").size() == 6, "公民地方聯盟六席")
	_check(database.members_by_caucus("無黨籍").size() == 4, "無黨籍四席")

	for member_id: String in database.sorted_member_ids():
		var member: Dictionary = database.get_member(member_id)
		var concerns: Array = member.get("concerns", [])
		var weight_total := 0
		for concern: Dictionary in concerns:
			weight_total += int(concern.get("weight", 0))
		_check(concerns.size() == 3 and weight_total == 100, "%s 有三項且合計 100 的關注權重" % member_id)
		_check(database.vote_history_for_member(member_id).size() == 8, "%s 有八筆歷史投票" % member_id)

	_check(database.update_dynamic_state("LC-001", {
		"mayor_relationship": 150,
		"district_support": -20,
		"fatigue": 120,
	}), "可更新議員動態狀態")
	var clamped_state: Dictionary = database.get_dynamic_state("LC-001")
	_check(int(clamped_state.get("mayor_relationship", 0)) == 100, "市長關係限制在 -100 至 100")
	_check(int(clamped_state.get("district_support", 0)) == 0, "選區支持度限制在 0 至 100")
	_check(int(clamped_state.get("fatigue", 0)) == 100, "疲勞限制在 0 至 100")
	_check(database.update_dynamic_state("LC-001", {
		"mayor_relationship": 0,
		"district_support": 50,
		"fatigue": 0,
	}), "可還原議員動態狀態")

	var model = VoteModelScript.new(database, 9_901)
	var bill := {
		"id": "environment_act",
		"version": 1,
		"name": "環境保護法案",
		"type": "environment",
		"risk_level": 45,
	}
	var context := {
		"game_day": 20,
		"public_support": 58,
		"regional_support": {"north": 65, "east": 54, "south": 60, "west": 56, "central": 59},
		"budget_health": 48,
		"economic_health": 55,
		"environment_health": 35,
		"feasibility": 62,
	}
	var first_preview: Dictionary = model.preview_vote(bill, context, "initial")
	var second_preview: Dictionary = model.preview_vote(bill, context, "initial")
	_check(bool(first_preview.get("ok", false)), "可預覽完整下議院表決")
	_check((first_preview.get("votes", []) as Array).size() == 30, "每項表決產生 30 筆個人選擇")
	_check(_tally_size(first_preview) == 30, "贊成、反對、棄權與缺席合計為 30")
	_check(int(first_preview.get("votes_for", 0)) > 0 and int(first_preview.get("votes_against", 0)) > 0, "個人模型能在同一法案產生不同立場")
	_check(JSON.stringify(first_preview) == JSON.stringify(second_preview), "相同輸入與種子產生可重現結果")

	var low_public: Dictionary = model.evaluate_member("LC-005", bill, {
		"game_day": 21,
		"regional_support": {"north": 10},
	}, "initial")
	var high_public: Dictionary = model.evaluate_member("LC-005", bill, {
		"game_day": 21,
		"regional_support": {"north": 90},
	}, "initial")
	_check(float(high_public.get("support_score", 0)) > float(low_public.get("support_score", 0)), "高民意敏感議員會回應選區民意")

	var before_debate: Dictionary = model.evaluate_member("LC-005", bill, context, "final", {})
	var after_debate: Dictionary = model.evaluate_member("LC-005", bill, context, "final", {"environment": 100})
	_check(float(after_debate.get("support_score", 0)) > float(before_debate.get("support_score", 0)), "對應關注點的辯論證據會提高支持分數")

	var initial_vote: Dictionary = model.conduct_vote(bill, context, "initial")
	var final_vote: Dictionary = model.conduct_vote(bill, context, "final", {
		"environment": 80,
		"budget": 60,
		"execution_feasibility": 75,
	})
	_check(_tally_size(initial_vote) == 30, "初審表決完整")
	_check(_tally_size(final_vote) == 30, "辯論後複決完整")
	_check(database.vote_history.size() == 300, "兩輪表決追加 60 筆歷史資料")
	_check(database.vote_history_for_bill("environment_act").size() == 90, "環境法案含 30 筆種子與 60 筆新紀錄")

	var absent_context: Dictionary = context.duplicate(true)
	absent_context["game_day"] = 22
	absent_context["absent_member_ids"] = ["LC-030"]
	var absent_vote: Dictionary = model.preview_vote(bill, absent_context, "final")
	_check(int(absent_vote.get("absences", 0)) == 1, "缺席狀態與立場評分分離")

	var duplicate_record: Dictionary = database.vote_history[database.vote_history.size() - 1].duplicate(true)
	_check(not database.append_vote(duplicate_record), "相同 vote_id 不可重複追加")

	var serialized: Variant = JSON.parse_string(JSON.stringify(database.to_dict()))
	var restored = DatabaseScript.new()
	var restore_result: Dictionary = restored.load_state(serialized)
	_check(bool(restore_result.get("ok", false)), "議員資料庫可完成 JSON 存檔往返")
	_check(restored.stable_hash() == database.stable_hash(), "存檔往返後資料雜湊一致")

	if not failed:
		print("Lower council self-test passed. Members=%d Votes=%d Hash=%s" % [
			database.members.size(),
			database.vote_history.size(),
			database.stable_hash(),
		])
	quit(1 if failed else 0)


func _tally_size(result: Dictionary) -> int:
	return (
		int(result.get("votes_for", 0))
		+ int(result.get("votes_against", 0))
		+ int(result.get("abstentions", 0))
		+ int(result.get("absences", 0))
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Lower council self-test failed: %s" % label)
