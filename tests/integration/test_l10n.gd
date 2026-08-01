extends SceneTree

func _init():
	var l10n = MayorLocalizationService.new()
	l10n._ready()
	l10n.set_locale("en")
	var source = "居民民怨：%d；越低越好。"
	var t = l10n.text(source)
	print("TEST OUTPUT FOR GRIEVANCE: ", t)
	
	source = "天氣：晴朗｜微風 %02d"
	t = l10n.text(source)
	print("TEST OUTPUT FOR WEATHER: ", t)
	
	source = "目前日期：第 %d 月第 %d 天｜自動時間：現實 2 分鐘＝遊戲 1 天"
	t = l10n.text(source)
	print("TEST OUTPUT FOR DATE: ", t)
	
	quit()
