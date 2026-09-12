class_name CityBackdropTerrainCatalog
extends RefCounted

## Natural backdrop geometry authored in fixed map-stage coordinates.
## This catalog deliberately has no navigation dependency so layout, navigation,
## and later terrain authority work consume the same immutable source records.

const KIND_RIVER_LAKE := "river_lake"
const KIND_HILL_CLIFF := "hill_cliff"
const KIND_TREES_SCENERY := "trees_scenery"


static func static_polygons() -> Array[Dictionary]:
	return [
		{"id": "river_north", "kind": KIND_RIVER_LAKE, "points": PackedVector2Array([Vector2(778, -12), Vector2(895, -12), Vector2(879, 42), Vector2(846, 88), Vector2(858, 139), Vector2(843, 185), Vector2(808, 221), Vector2(780, 201), Vector2(792, 156), Vector2(779, 111), Vector2(791, 66)])},
		{"id": "lake_north_central", "kind": KIND_RIVER_LAKE, "points": PackedVector2Array([Vector2(468, 224), Vector2(518, 200), Vector2(581, 196), Vector2(641, 207), Vector2(701, 214), Vector2(757, 194), Vector2(807, 215), Vector2(810, 261), Vector2(778, 301), Vector2(718, 329), Vector2(638, 336), Vector2(564, 330), Vector2(507, 310), Vector2(475, 281)])},
		{"id": "northwest_cliffs", "kind": KIND_HILL_CLIFF, "points": PackedVector2Array([Vector2(-12, -12), Vector2(466, -12), Vector2(456, 68), Vector2(418, 98), Vector2(402, 141), Vector2(367, 164), Vector2(365, 207), Vector2(321, 228), Vector2(281, 215), Vector2(247, 243), Vector2(205, 233), Vector2(187, 268), Vector2(135, 285), Vector2(87, 258), Vector2(38, 269), Vector2(-12, 239)])},
		{"id": "northern_cliffs", "kind": KIND_HILL_CLIFF, "points": PackedVector2Array([Vector2(438, -12), Vector2(781, -12), Vector2(776, 66), Vector2(746, 99), Vector2(731, 142), Vector2(697, 171), Vector2(651, 170), Vector2(624, 192), Vector2(570, 184), Vector2(542, 166), Vector2(501, 173), Vector2(456, 147), Vector2(428, 105)])},
		{"id": "northeast_cliffs", "kind": KIND_HILL_CLIFF, "points": PackedVector2Array([Vector2(884, -12), Vector2(1132, -12), Vector2(1132, 290), Vector2(1082, 276), Vector2(1042, 250), Vector2(1010, 253), Vector2(982, 231), Vector2(944, 239), Vector2(911, 214), Vector2(875, 203), Vector2(861, 168), Vector2(881, 121)])},
		{"id": "west_cliff_spur", "kind": KIND_HILL_CLIFF, "points": PackedVector2Array([Vector2(-12, 238), Vector2(56, 246), Vector2(101, 264), Vector2(141, 286), Vector2(178, 311), Vector2(202, 337), Vector2(188, 367), Vector2(154, 381), Vector2(119, 361), Vector2(82, 377), Vector2(42, 358), Vector2(-12, 369)])},
		{"id": "west_forest", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(-12, 216), Vector2(49, 226), Vector2(82, 255), Vector2(91, 300), Vector2(111, 340), Vector2(100, 394), Vector2(119, 438), Vector2(99, 484), Vector2(118, 529), Vector2(96, 575), Vector2(119, 625), Vector2(102, 678), Vector2(64, 711), Vector2(-12, 708)])},
		{"id": "east_forest", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(1017, 244), Vector2(1065, 235), Vector2(1132, 218), Vector2(1132, 691), Vector2(1069, 678), Vector2(1038, 647), Vector2(1048, 603), Vector2(1027, 568), Vector2(1044, 525), Vector2(1021, 484), Vector2(1036, 446), Vector2(1012, 405), Vector2(1029, 363), Vector2(1007, 319)])},
		{"id": "southwest_forest", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(-12, 688), Vector2(76, 679), Vector2(143, 699), Vector2(203, 679), Vector2(259, 705), Vector2(310, 688), Vector2(354, 717), Vector2(375, 756), Vector2(361, 832), Vector2(-12, 832)])},
		{"id": "southcentral_forest", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(337, 717), Vector2(390, 686), Vector2(450, 681), Vector2(500, 703), Vector2(548, 686), Vector2(603, 701), Vector2(647, 680), Vector2(702, 692), Vector2(749, 722), Vector2(763, 762), Vector2(749, 832), Vector2(330, 832)])},
		{"id": "southeast_forest", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(729, 742), Vector2(775, 704), Vector2(827, 690), Vector2(878, 704), Vector2(921, 681), Vector2(973, 694), Vector2(1013, 672), Vector2(1057, 688), Vector2(1132, 675), Vector2(1132, 832), Vector2(730, 832)])},
		{"id": "south_meadow_rocks", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(657, 625), Vector2(695, 603), Vector2(739, 600), Vector2(779, 616), Vector2(797, 644), Vector2(778, 674), Vector2(736, 685), Vector2(691, 675), Vector2(663, 653)])},
		{"id": "west_lower_tree_grove", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(88, 520), Vector2(119, 505), Vector2(153, 514), Vector2(184, 533), Vector2(202, 554), Vector2(201, 583), Vector2(180, 611), Vector2(143, 624), Vector2(106, 612), Vector2(90, 582)])},
		{"id": "south_meadow_tree_grove", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(748, 612), Vector2(772, 586), Vector2(807, 575), Vector2(844, 588), Vector2(874, 609), Vector2(867, 641), Vector2(842, 669), Vector2(805, 682), Vector2(778, 666), Vector2(758, 642)])},
		{"id": "east_path_rock_garden_upper", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(899, 537), Vector2(914, 523), Vector2(939, 519), Vector2(958, 530), Vector2(957, 549), Vector2(940, 562), Vector2(914, 562), Vector2(899, 550)])},
		{"id": "east_path_rock_garden_lower", "kind": KIND_TREES_SCENERY, "points": PackedVector2Array([Vector2(947, 577), Vector2(959, 565), Vector2(977, 567), Vector2(988, 579), Vector2(982, 593), Vector2(964, 599), Vector2(949, 591)])},
	]
