extends RefCounted

const VERSION := "storybook_v2"
const ROOT_PATH := "res://assets/images/ui/icons/storybook_v2"
const FALLBACK_FILENAME := "fallback.png"

# One canonical delivery file per visual concept. Aliases below may intentionally
# share a file when the same visual meaning appears in more than one UI surface.
const CANONICAL_FILENAMES: PackedStringArray = [
	"blueprint.png",
	"blueprint_decoration.png",
	"blueprint_floors.png",
	"blueprint_material.png",
	"blueprint_size.png",
	"blueprint_workers.png",
	"building_civic.png",
	"building_community.png",
	"building_economy.png",
	"building_housing.png",
	"building_mobility.png",
	"building_utilities.png",
	"buildings.png",
	"city_data.png",
	"city_hall.png",
	"city_level.png",
	"complaint.png",
	"customize.png",
	"demolish.png",
	"education.png",
	"environment.png",
	"exit.png",
	"governance.png",
	"healthcare.png",
	"justice.png",
	"oversight.png",
	"population.png",
	"public_affairs.png",
	"report.png",
	"score.png",
	"settings.png",
	"theme.png",
	"time.png",
	"treasury.png",
	"trust.png",
	"wellbeing.png",
	FALLBACK_FILENAME,
]

const KEY_TO_FILENAME := {
	# Persistent HUD and application actions.
	"month": "time.png",
	"time": "time.png",
	"next_day": "time.png",
	"next_month": "time.png",
	"continue": "time.png",
	"funds": "treasury.png",
	"finance": "treasury.png",
	"treasury": "treasury.png",
	"population": "population.png",
	"capacity": "building_housing.png",
	"satisfaction": "wellbeing.png",
	"wellbeing": "wellbeing.png",
	"security": "building_civic.png",
	"environment": "environment.png",
	"traffic": "building_mobility.png",
	"education": "education.png",
	"healthcare": "healthcare.png",
	"grievance": "complaint.png",
	"complaint": "complaint.png",
	"trust": "trust.png",
	"score": "score.png",
	"rating": "city_level.png",
	"city_level": "city_level.png",
	"municipal": "city_hall.png",
	"new": "city_hall.png",
	"city_hall": "city_hall.png",
	"settings": "settings.png",
	"theme": "theme.png",
	"exit": "exit.png",
	# Municipal destinations.
	"buildings": "buildings.png",
	"governance": "governance.png",
	"justice": "justice.png",
	"judicial": "justice.png",
	"oversight": "oversight.png",
	"blueprint": "blueprint.png",
	"public_affairs": "public_affairs.png",
	"city_data": "city_data.png",
	"report": "report.png",
	# Building families and local actions.
	"building_housing": "building_housing.png",
	"building_economy": "building_economy.png",
	"building_community": "building_community.png",
	"building_mobility": "building_mobility.png",
	"building_utilities": "building_utilities.png",
	"building_civic": "building_civic.png",
	"customize": "customize.png",
	"style": "customize.png",
	"roof": "building_housing.png",
	"exterior": "buildings.png",
	"maintenance": "building_utilities.png",
	"demolish": "demolish.png",
	# Blueprint parameter cards.
	"material": "blueprint_material.png",
	"size": "blueprint_size.png",
	"floors": "blueprint_floors.png",
	"workers": "blueprint_workers.png",
	"decoration": "blueprint_decoration.png",
}


static func path_for(icon_key: String) -> String:
	var filename := str(KEY_TO_FILENAME.get(icon_key, FALLBACK_FILENAME))
	return "%s/%s" % [ROOT_PATH, filename]


static func texture(icon_key: String) -> Texture2D:
	if not KEY_TO_FILENAME.has(icon_key):
		push_warning("Unknown UI icon key; using neutral fallback: %s" % icon_key)
	var requested_path := path_for(icon_key)
	if ResourceLoader.exists(requested_path):
		return load(requested_path) as Texture2D
	var fallback_path := "%s/%s" % [ROOT_PATH, FALLBACK_FILENAME]
	push_warning("UI icon is unavailable: key=%s path=%s" % [icon_key, requested_path])
	if ResourceLoader.exists(fallback_path):
		return load(fallback_path) as Texture2D
	push_error("UI icon fallback is unavailable: %s" % fallback_path)
	return null


static func has_key(icon_key: String) -> bool:
	return KEY_TO_FILENAME.has(icon_key)
