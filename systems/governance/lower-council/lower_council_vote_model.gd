class_name LowerCouncilVoteModel
extends RefCounted

const DEFAULT_SEED := 20_260_722
const CHOICE_FOR := "for"
const CHOICE_AGAINST := "against"
const CHOICE_ABSTAIN := "abstain"
const CHOICE_ABSENT := "absent"

const CAUCUS_TYPE_BIASES := {
	"財政與發展聯盟": {
		"environment": -5.0, "traffic": 3.0, "business": 8.0, "welfare": -6.0,
		"security": 4.0, "utility": -4.0, "industry": 8.0, "housing": -5.0,
	},
	"社會民生聯盟": {
		"environment": 3.0, "traffic": 3.0, "business": -3.0, "welfare": 8.0,
		"security": 0.0, "utility": 7.0, "industry": -5.0, "housing": 8.0,
	},
	"綠色未來聯盟": {
		"environment": 9.0, "traffic": 6.0, "business": -2.0, "welfare": 3.0,
		"security": -1.0, "utility": 4.0, "industry": -9.0, "housing": 4.0,
	},
	"公民地方聯盟": {
		"environment": 1.0, "traffic": 6.0, "business": 2.0, "welfare": 1.0,
		"security": 5.0, "utility": 2.0, "industry": 2.0, "housing": 3.0,
	},
	"無黨籍": {},
}

const DEFAULT_CONCERN_IMPACTS := {
	"environment": {
		"environment": 85.0, "public_interest": 25.0, "budget": -30.0,
		"administrative_efficiency": -15.0, "economic_growth": -10.0, "roi": -10.0,
	},
	"traffic": {
		"transport": 85.0, "regional_balance": 45.0, "economic_growth": 35.0,
		"employment": 20.0, "environment": 20.0, "budget": -35.0, "roi": 25.0,
	},
	"business": {
		"economic_growth": 75.0, "roi": 70.0, "employment": 45.0,
		"budget": 20.0, "environment": -35.0, "transport": -20.0, "social_welfare": -10.0,
	},
	"welfare": {
		"social_welfare": 85.0, "public_opinion": 30.0, "healthcare": 25.0,
		"utility_affordability": 30.0, "public_interest": 45.0, "budget": -50.0, "roi": -20.0,
	},
	"security": {
		"public_safety": 90.0, "public_interest": 55.0,
		"administrative_efficiency": 20.0, "budget": -25.0,
	},
	"utility": {
		"utility_affordability": 90.0, "public_opinion": 35.0,
		"social_welfare": 50.0, "public_interest": 30.0, "budget": -35.0, "roi": -20.0,
	},
	"industry": {
		"economic_growth": 80.0, "employment": 70.0, "roi": 60.0,
		"budget": 25.0, "environment": -75.0, "healthcare": -25.0,
	},
	"housing": {
		"housing": 95.0, "social_welfare": 55.0, "public_opinion": 25.0,
		"employment": 15.0, "budget": -45.0, "regional_balance": 35.0,
	},
}

var database
var seed: int = DEFAULT_SEED


func _init(p_database, p_seed: int = DEFAULT_SEED) -> void:
	database = p_database
	seed = p_seed


func preview_vote(
	bill: Dictionary,
	context: Dictionary = {},
	stage: String = "final",
	debate_evidence: Dictionary = {}
) -> Dictionary:
	return _run_vote(bill, context, stage, debate_evidence, false)


func conduct_vote(
	bill: Dictionary,
	context: Dictionary = {},
	stage: String = "final",
	debate_evidence: Dictionary = {}
) -> Dictionary:
	return _run_vote(bill, context, stage, debate_evidence, true)


func evaluate_member(
	member_id: String,
	bill: Dictionary,
	context: Dictionary = {},
	stage: String = "final",
	debate_evidence: Dictionary = {}
) -> Dictionary:
	var member: Dictionary = database.get_member(member_id)
	if member.is_empty():
		return {"ok": false, "error": "member_not_found", "member_id": member_id}
	if str(bill.get("id", "")).is_empty() or str(bill.get("type", "")).is_empty():
		return {"ok": false, "error": "invalid_bill", "member_id": member_id}
	return _evaluate_member(member, bill, context, stage, debate_evidence)


func _run_vote(
	bill: Dictionary,
	context: Dictionary,
	stage: String,
	debate_evidence: Dictionary,
	persist: bool
) -> Dictionary:
	if database == null:
		return {"ok": false, "error": "database_missing"}
	var bill_id := str(bill.get("id", ""))
	var bill_type := str(bill.get("type", ""))
	if bill_id.is_empty() or bill_type.is_empty():
		return {"ok": false, "error": "invalid_bill"}
	var game_day := int(context.get("game_day", 0))
	var votes: Array[Dictionary] = []
	var counts := {CHOICE_FOR: 0, CHOICE_AGAINST: 0, CHOICE_ABSTAIN: 0, CHOICE_ABSENT: 0}
	for member_id: String in database.sorted_member_ids():
		var member: Dictionary = database.get_member(member_id)
		var result := _evaluate_member(member, bill, context, stage, debate_evidence)
		var choice := str(result.get("choice", CHOICE_ABSTAIN))
		counts[choice] = int(counts.get(choice, 0)) + 1
		var previous_choice := _previous_choice(member_id, bill_id, game_day)
		var record := {
			"vote_id": "vote_%d_%s_%s_%s" % [game_day, bill_id, stage, member_id],
			"member_id": member_id,
			"bill_id": bill_id,
			"bill_version": int(bill.get("version", 1)),
			"game_day": game_day,
			"stage": stage,
			"choice": choice,
			"support_score": result.get("support_score", 50.0),
			"primary_reason": result.get("primary_reason", "neutral"),
			"score_breakdown": result.get("score_breakdown", {}).duplicate(true),
			"public_opinion_snapshot": result.get("public_opinion_snapshot", 50),
			"budget_health_snapshot": int(context.get("budget_health", 50)),
			"caucus_recommendation": result.get("caucus_recommendation", "neutral"),
			"changed_vote": stage != "initial" and not previous_choice.is_empty() and previous_choice != choice,
		}
		if persist:
			record["persisted"] = database.append_vote(record)
		votes.append(record)
	var votes_for := int(counts[CHOICE_FOR])
	return {
		"ok": true,
		"bill_id": bill_id,
		"bill_type": bill_type,
		"game_day": game_day,
		"stage": stage,
		"votes_for": votes_for,
		"votes_against": int(counts[CHOICE_AGAINST]),
		"abstentions": int(counts[CHOICE_ABSTAIN]),
		"absences": int(counts[CHOICE_ABSENT]),
		"majority_threshold": database.majority_threshold,
		"passed": votes_for >= database.majority_threshold,
		"votes": votes,
	}


func _evaluate_member(
	member: Dictionary,
	bill: Dictionary,
	context: Dictionary,
	stage: String,
	debate_evidence: Dictionary
) -> Dictionary:
	var member_id := str(member.get("member_id", ""))
	var state: Dictionary = database.get_dynamic_state(member_id)
	var absent_ids: Array = context.get("absent_member_ids", [])
	if bool(state.get("suspended", false)) or absent_ids.has(member_id):
		return {
			"ok": true,
			"member_id": member_id,
			"choice": CHOICE_ABSENT,
			"support_score": 50.0,
			"primary_reason": "absence",
			"score_breakdown": {},
			"public_opinion_snapshot": _regional_public_support(member, context),
			"caucus_recommendation": "neutral",
		}

	var bill_type := str(bill.get("type", ""))
	var behavior: Dictionary = member.get("behavior", {})
	var impacts := _concern_impacts(bill)
	var concern_scores: Dictionary = {}
	var policy_component := 0.0
	var context_component := 0.0
	var debate_component := 0.0
	for value: Variant in member.get("concerns", []):
		if not value is Dictionary:
			continue
		var concern: Dictionary = value
		var key := str(concern.get("key", ""))
		var weight := float(concern.get("weight", 0)) / 100.0
		var policy_score := float(impacts.get(key, 0.0)) * weight * 0.22
		var live_score := _context_signal(key, member, context) * weight * 0.12
		var evidence_strength := 0.0 if stage == "initial" else clampf(float(debate_evidence.get(key, 0.0)), 0.0, 100.0)
		var resistance_factor := 1.0 - float(behavior.get("persuasion_resistance", 50)) / 100.0
		var evidence_score := evidence_strength / 100.0 * weight * resistance_factor * 12.0
		policy_component += policy_score
		context_component += live_score
		debate_component += evidence_score
		concern_scores[key] = snappedf(policy_score + live_score + evidence_score, 0.01)

	var public_support := _regional_public_support(member, context)
	var public_component := (public_support - 50.0) * float(behavior.get("public_sensitivity", 50)) / 100.0 * 0.25
	var caucus_component := _caucus_bias(member, bill_type)
	var caucus_recommendation := _caucus_recommendation(member, bill, context)
	var recommendation_component := _recommendation_component(caucus_recommendation, behavior)
	var history_component := _history_component(member, str(bill.get("id", "")))
	var risk_level := clampf(float(bill.get("risk_level", context.get("bill_risk", 50))), 0.0, 100.0)
	var risk_component := (float(behavior.get("risk_tolerance", 50)) - risk_level) * 0.05
	var relationship_component := float(state.get("mayor_relationship", 0)) * 0.04
	var jitter := _stable_jitter(member_id, str(bill.get("id", "")), int(context.get("game_day", 0)), stage)
	var score := 50.0
	score += policy_component
	score += context_component
	score += debate_component
	score += public_component
	score += caucus_component
	score += recommendation_component
	score += history_component
	score += risk_component
	score += relationship_component
	score += jitter
	score = clampf(score, 0.0, 100.0)

	var choice := CHOICE_ABSTAIN
	if score >= 55.0:
		choice = CHOICE_FOR
	elif score <= 45.0:
		choice = CHOICE_AGAINST
	elif float(behavior.get("caucus_discipline", 0)) >= 75.0 and caucus_recommendation in [CHOICE_FOR, CHOICE_AGAINST]:
		choice = caucus_recommendation

	return {
		"ok": true,
		"member_id": member_id,
		"choice": choice,
		"support_score": snappedf(score, 0.01),
		"primary_reason": _primary_reason(concern_scores),
		"public_opinion_snapshot": int(round(public_support)),
		"caucus_recommendation": caucus_recommendation,
		"score_breakdown": {
			"policy": snappedf(policy_component, 0.01),
			"live_context": snappedf(context_component, 0.01),
			"debate": snappedf(debate_component, 0.01),
			"public_opinion": snappedf(public_component, 0.01),
			"caucus_bias": snappedf(caucus_component, 0.01),
			"caucus_recommendation": snappedf(recommendation_component, 0.01),
			"history": snappedf(history_component, 0.01),
			"risk": snappedf(risk_component, 0.01),
			"mayor_relationship": snappedf(relationship_component, 0.01),
			"individual_variation": snappedf(jitter, 0.01),
			"concerns": concern_scores,
		},
	}


func _concern_impacts(bill: Dictionary) -> Dictionary:
	var bill_type := str(bill.get("type", ""))
	var impacts: Dictionary = (DEFAULT_CONCERN_IMPACTS.get(bill_type, {}) as Dictionary).duplicate(true)
	var overrides: Dictionary = bill.get("concern_impacts", {})
	for key: Variant in overrides.keys():
		impacts[str(key)] = clampf(float(overrides[key]), -100.0, 100.0)
	return impacts


func _context_signal(key: String, member: Dictionary, context: Dictionary) -> float:
	var custom_signals: Dictionary = context.get("concern_signals", {})
	if custom_signals.has(key):
		return clampf(float(custom_signals[key]), -50.0, 50.0)
	match key:
		"budget":
			return clampf(float(context.get("budget_health", 50)) - 50.0, -50.0, 50.0)
		"public_opinion":
			return _regional_public_support(member, context) - 50.0
		"roi":
			return clampf(float(context.get("projected_roi", 50)) - 50.0, -50.0, 50.0)
		"economic_growth":
			return clampf(float(context.get("economic_health", 50)) - 50.0, -50.0, 50.0)
		"employment":
			return clampf(float(context.get("employment_pressure", 50)) - 50.0, -50.0, 50.0)
		"environment":
			return clampf(50.0 - float(context.get("environment_health", 50)), -50.0, 50.0)
		"public_safety":
			return clampf(50.0 - float(context.get("security_health", 50)), -50.0, 50.0)
		"housing":
			return clampf(float(context.get("housing_pressure", 50)) - 50.0, -50.0, 50.0)
		"transport":
			return clampf(float(context.get("traffic_pressure", 50)) - 50.0, -50.0, 50.0)
		"execution_feasibility":
			return clampf(float(context.get("feasibility", 50)) - 50.0, -50.0, 50.0)
		"regional_balance":
			var regional_need: Dictionary = context.get("regional_need", {})
			return clampf(float(regional_need.get(str(member.get("region", "")), 50)) - 50.0, -50.0, 50.0)
		_:
			return 0.0


func _regional_public_support(member: Dictionary, context: Dictionary) -> float:
	var regional_support: Dictionary = context.get("regional_support", {})
	var region := str(member.get("region", ""))
	return clampf(float(regional_support.get(region, context.get("public_support", 50))), 0.0, 100.0)


func _caucus_bias(member: Dictionary, bill_type: String) -> float:
	var caucus := str(member.get("caucus", ""))
	var behavior: Dictionary = member.get("behavior", {})
	var biases: Dictionary = CAUCUS_TYPE_BIASES.get(caucus, {})
	return float(biases.get(bill_type, 0.0)) * float(behavior.get("caucus_discipline", 0)) / 100.0


func _caucus_recommendation(member: Dictionary, bill: Dictionary, context: Dictionary) -> String:
	var caucus := str(member.get("caucus", ""))
	var recommendations: Dictionary = context.get("caucus_recommendations", {})
	var explicit := str(recommendations.get(caucus, ""))
	if explicit in [CHOICE_FOR, CHOICE_AGAINST, "neutral"]:
		return explicit
	var biases: Dictionary = CAUCUS_TYPE_BIASES.get(caucus, {})
	var bias := float(biases.get(str(bill.get("type", "")), 0.0))
	if bias >= 3.0:
		return CHOICE_FOR
	if bias <= -3.0:
		return CHOICE_AGAINST
	return "neutral"


func _recommendation_component(recommendation: String, behavior: Dictionary) -> float:
	var direction := 0.0
	if recommendation == CHOICE_FOR:
		direction = 1.0
	elif recommendation == CHOICE_AGAINST:
		direction = -1.0
	return direction * 6.0 * float(behavior.get("caucus_discipline", 0)) / 100.0


func _history_component(member: Dictionary, bill_id: String) -> float:
	var seed_votes: Dictionary = member.get("seed_votes", {})
	match str(seed_votes.get(bill_id, CHOICE_ABSTAIN)):
		CHOICE_FOR:
			return 3.5
		CHOICE_AGAINST:
			return -3.5
		_:
			return 0.0


func _previous_choice(member_id: String, bill_id: String, game_day: int) -> String:
	for index: int in range(database.vote_history.size() - 1, -1, -1):
		var record: Dictionary = database.vote_history[index]
		if str(record.get("member_id", "")) != member_id:
			continue
		if str(record.get("bill_id", "")) != bill_id:
			continue
		if int(record.get("game_day", -1)) > game_day:
			continue
		return str(record.get("choice", ""))
	return ""


func _primary_reason(concern_scores: Dictionary) -> String:
	var best_key := "neutral"
	var best_strength := -1.0
	var keys: Array = concern_scores.keys()
	keys.sort()
	for value: Variant in keys:
		var key := str(value)
		var strength := absf(float(concern_scores[key]))
		if strength > best_strength:
			best_strength = strength
			best_key = key
	return best_key


func _stable_jitter(member_id: String, bill_id: String, game_day: int, stage: String) -> float:
	var value := "%d|%s|%s|%d|%s" % [seed, member_id, bill_id, game_day, stage]
	return float(_stable_int(value) % 401 - 200) / 100.0


static func _stable_int(value: String) -> int:
	var result := 17
	for index: int in value.length():
		result = int((result * 31 + value.unicode_at(index)) % 2_147_483_647)
	return result
