extends RefCounted

static func all() -> Dictionary:
	return {
		"環保政策": {
			"tag": "環境",
			"expense": 260,
			"environment": 3,
			"satisfaction": 1,
			"description": "環境上升、滿意度上升；每月支出增加。"
		},
		"教育補助": {
			"tag": "教育",
			"expense": 300,
			"education": 3,
			"satisfaction": 1,
			"description": "教育上升、滿意度上升；每月支出增加。"
		},
		"治安強化": {
			"tag": "治安",
			"expense": 280,
			"security": 3,
			"satisfaction": 1,
			"description": "治安上升、滿意度上升；每月支出增加。"
		},
		"商業振興": {
			"tag": "經濟",
			"expense": 0,
			"income_bonus": 0.25,
			"environment": -2,
			"traffic": -3,
			"description": "收入上升；環境下降、交通壓力上升。"
		}
	}
