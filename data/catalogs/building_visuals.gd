class_name BuildingVisuals
extends RefCounted

# Canonical visual registry for every buildable catalog entry.  The UI cards
# and the city map read the same asset path so a building never changes visual
# identity between selection and placement.
const ROOT := "res://assets/images/world/buildings/storybook_v1"

const BY_DISPLAY_NAME := {
	"住宅": {"id": "residence", "shape": "藍頂小屋", "detail": "煙囪 花窗", "asset": ROOT + "/residence/clean.png"},
	"社會住宅": {"id": "social_housing", "shape": "溫馨宅群", "detail": "連排小屋", "asset": ROOT + "/social_housing/clean.png"},
	"商店": {"id": "shop", "shape": "招牌店舖", "detail": "櫥窗 棚架", "asset": ROOT + "/shop/clean.png"},
	"大型商場": {"id": "mall", "shape": "宮殿商館", "detail": "拱門 彩旗", "asset": ROOT + "/mall/clean.png"},
	"工廠": {"id": "factory", "shape": "童話工坊", "detail": "煙囪 齒輪", "asset": ROOT + "/factory/clean.png"},
	"公園": {"id": "park", "shape": "花園廣場", "detail": "樹木 噴泉", "asset": ROOT + "/park/clean.png"},
	"體育館": {"id": "stadium", "shape": "圓頂競技館", "detail": "彩帶 看台", "asset": ROOT + "/stadium/clean.png"},
	"學校": {"id": "school", "shape": "鐘樓學院", "detail": "書本 鐘塔", "asset": ROOT + "/school/clean.png"},
	"圖書館": {"id": "library", "shape": "石造書館", "detail": "書卷 石柱", "asset": ROOT + "/library/clean.png"},
	"醫院": {"id": "hospital", "shape": "白塔診所", "detail": "醫療徽記 花圃", "asset": ROOT + "/hospital/clean.png"},
	"警局": {"id": "police_station", "shape": "藍盾哨所", "detail": "盾徽 瞭望塔", "asset": ROOT + "/police_station/clean.png"},
	"消防局": {"id": "fire_station", "shape": "紅磚救援站", "detail": "火焰徽記 鐘鈴", "asset": ROOT + "/fire_station/clean.png"},
	"停車場": {"id": "parking_lot", "shape": "石磚車場", "detail": "停車格 入口亭", "asset": ROOT + "/parking_lot/clean.png"},
	"公車站": {"id": "bus_station", "shape": "小亭車站", "detail": "車輪徽記 長椅", "asset": ROOT + "/bus_station/clean.png"},
	"捷運站": {"id": "metro_station", "shape": "穹頂入口", "detail": "列車徽記 階梯", "asset": ROOT + "/metro_station/clean.png"},
	"火車站": {"id": "train_station", "shape": "鐘樓火車站", "detail": "月台 鐘塔", "asset": ROOT + "/train_station/clean.png"},
	"機場": {"id": "airport", "shape": "王國航站", "detail": "航管塔 航站廳", "asset": ROOT + "/airport/clean.png"},
	"發電廠": {"id": "power_plant", "shape": "星火電塔", "detail": "煙囪 電力徽記", "asset": ROOT + "/power_plant/clean.png"},
	"核能發電廠": {"id": "nuclear_power_plant", "shape": "核塔電廠", "detail": "冷卻塔 能源核心", "asset": ROOT + "/nuclear_power_plant/clean.png"},
	"瓦斯場": {"id": "gas_works", "shape": "紫晶氣罐", "detail": "儲氣槽 管線", "asset": ROOT + "/gas_works/clean.png"},
	"加油站": {"id": "gas_station", "shape": "加油島", "detail": "油滴徽記 油泵", "asset": ROOT + "/gas_station/clean.png"},
	"自來水廠": {"id": "water_works", "shape": "藍塔水廠", "detail": "水塔 淨水池", "asset": ROOT + "/water_works/clean.png"},
	"游泳池": {"id": "swimming_pool", "shape": "藍鏡池域", "detail": "泳道 看台", "asset": ROOT + "/swimming_pool/clean.png"},
	"垃圾處理場": {"id": "waste_center", "shape": "潔淨回收屋", "detail": "分類箱 綠棚", "asset": ROOT + "/waste_center/clean.png"},
	"法院": {"id": "court", "shape": "白石審判庭", "detail": "天秤 石柱", "asset": ROOT + "/court/clean.png"},
	"監察所": {"id": "oversight_office", "shape": "青塔監察院", "detail": "明鏡 瞭望塔", "asset": ROOT + "/oversight_office/clean.png"},
	"市政府": {"id": "city_hall", "shape": "鐘樓市政廳", "detail": "鐘樓 市徽", "asset": ROOT + "/city_hall/clean.png"},
}


static func definition(building_name: String) -> Dictionary:
	return Dictionary(BY_DISPLAY_NAME.get(building_name, {})).duplicate(true)


static func asset_path(building_name: String) -> String:
	return str(BY_DISPLAY_NAME.get(building_name, {}).get("asset", ""))
