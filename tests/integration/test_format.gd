extends SceneTree

func _init():
	var grievance = 10
	var t = "Residents’ complaints: %d; the lower, the better."
	print("RESULT 1: ", t % grievance)
	
	var drift = 5
	var weather = "Weather: Sunny | Breeze %02d"
	print("RESULT 2: ", weather % drift)
	quit()
