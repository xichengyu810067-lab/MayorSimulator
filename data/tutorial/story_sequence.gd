class_name IntroStorySequence
extends RefCounted

## R4-A owns this fixed, code-reviewed sequence. The cinematic deliberately
## has no deserialization API: callers cannot inject paths, methods, or saves.
const SHOTS: Array[Dictionary] = [
	{"id": "prosperity", "title": "城諾市：重光之日", "subtitle": "五業共榮，城市曾是豐饒的應許之地", "asset": "res://assets/images/tutorial/cg_v1/shot_01_prosperity.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_foliage.png", "portrait": 0, "seconds": 5.0},
	{"id": "decline", "title": "榮光褪色", "subtitle": "賴依德的獨裁與貪腐，讓橋梁、商街與家庭逐漸失去依靠", "asset": "res://assets/images/tutorial/cg_v1/shot_02_decline.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_rain_lanterns.png", "portrait": 2, "seconds": 5.0},
	{"id": "uprising", "title": "致諾三年五月三日", "subtitle": "市民走上街頭，決定把城市的未來拿回手中", "asset": "res://assets/images/tutorial/cg_v1/shot_03_uprising.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_rain_lanterns.png", "portrait": 1, "seconds": 5.0},
	{"id": "leader", "title": "年輕的引路人", "subtitle": "二十二歲的程安致，與留守居民一起點燃希望", "asset": "res://assets/images/tutorial/cg_v1/shot_04_leader.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_foliage.png", "portrait": 1, "seconds": 5.0},
	{"id": "mayor", "title": "臨危受命", "subtitle": "在百廢待興之中，他被託付為城諾市的新任市長", "asset": "res://assets/images/tutorial/cg_v1/shot_05_mayor.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_dawn_plans.png", "portrait": 2, "seconds": 5.0},
	{"id": "xiaoli", "title": "小莉的引導", "subtitle": "冷靜專業的首席助手，陪你把改革藍圖化為每一步行動", "asset": "res://assets/images/tutorial/cg_v1/shot_06_xiaoli_guides.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_dawn_plans.png", "portrait": 0, "seconds": 5.0},
	{"id": "shadows", "title": "暗流未止", "subtitle": "潰散的利益結構仍在陰影中重組，考驗才正要開始", "asset": "res://assets/images/tutorial/cg_v1/shot_07_shadow_network.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_rain_lanterns.png", "portrait": 2, "seconds": 5.0},
	{"id": "dawn", "title": "把黎明留在城諾", "subtitle": "在小莉與居民的陪伴下，從第一項建設開始重建城市", "asset": "res://assets/images/tutorial/cg_v1/shot_08_dawn.png", "foreground": "res://assets/images/tutorial/cg_v1/foreground_dawn_plans.png", "portrait": 3, "seconds": 5.0},
]


static func shots() -> Array[Dictionary]:
	return SHOTS.duplicate(true)


static func is_valid() -> bool:
	if SHOTS.size() != 8:
		return false
	var ids := {}
	for shot in SHOTS:
		var id := str(shot.get("id", ""))
		if id.is_empty() or ids.has(id):
			return false
		ids[id] = true
		if not str(shot.get("asset", "")).begins_with("res://assets/images/tutorial/cg_v1/shot_"):
			return false
		if not str(shot.get("foreground", "")).begins_with("res://assets/images/tutorial/cg_v1/foreground_"):
			return false
	return true
