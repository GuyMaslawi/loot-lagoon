class_name CV
extends RefCounted

const SYMBOLS := ["coin", "bag", "gem", "hammer", "steal", "shield", "bolt"]

const SYMBOL_EMOJI := {
	"coin": "🪙", "bag": "💰", "gem": "💎", "hammer": "🔨",
	"steal": "🦝", "shield": "🛡️", "bolt": "⚡",
}

const MAX_STAR := 5

const BUILDINGS := [
	{"id": "house", "name": "Cottage", "emoji": "🏠"},
	{"id": "windmill", "name": "Windmill", "emoji": "🏰"},
	{"id": "farm", "name": "Farm", "emoji": "🌾"},
	{"id": "boat", "name": "Boat", "emoji": "⛵"},
	{"id": "well", "name": "Well", "emoji": "🪣"},
]

const SLOT_RECTS := [
	Rect2(50, 190, 270, 300),
	Rect2(400, 170, 270, 320),
	Rect2(40, 560, 290, 290),
	Rect2(400, 560, 280, 290),
	Rect2(230, 862, 260, 262),
]

const ISLANDS := [
	{"name": "Green Meadows", "buildings": ["Cottage", "Windmill", "Farm", "Boat", "Well"]},
	{"name": "Pirate Cove", "buildings": ["Tavern", "Watchtower", "Dock", "Shipwreck", "Vault"]},
	{"name": "Desert Oasis", "buildings": ["Adobe Home", "Palm Garden", "Camel Stable", "Bazaar", "Oasis Well"]},
	{"name": "Snowy Peaks", "buildings": ["Log Cabin", "Ice Tower", "Sled Shop", "Ice Pier", "Hearth"]},
	{"name": "Jungle Ruins", "buildings": ["Treehouse", "Temple", "Bridge Hut", "Totem", "Vine Garden"]},
	{"name": "Candy Land", "buildings": ["Gingerbread", "Cane Mill", "Choco Fountain", "Lolli Garden", "Cupcake Stand"]},
	{"name": "Space Colony", "buildings": ["Dome Home", "Rocket Pad", "Solar Array", "Robot Garage", "Observatory"]},
	{"name": "Coral Reef", "buildings": ["Coral House", "Sub Dock", "Kelp Farm", "Pearl Vault", "Lighthouse"]},
	{"name": "Volcano Isle", "buildings": ["Obsidian Hut", "Lava Forge", "Ember Tower", "Hot Spring", "Dragon Perch"]},
	{"name": "Fairy Forest", "buildings": ["Mushroom Home", "Fairy Fountain", "Glow Tree", "Petal Mill", "Acorn Store"]},
	{"name": "Wild West", "buildings": ["Saloon", "Sheriff", "Gold Mine", "Ranch Barn", "Water Tower"]},
	{"name": "Ancient Egypt", "buildings": ["Pyramid", "Sphinx", "Papyrus Hut", "Obelisk", "Nile Dock"]},
	{"name": "Samurai Village", "buildings": ["Pagoda", "Dojo", "Zen Garden", "Tea House", "Torii Gate"]},
	{"name": "Viking Fjord", "buildings": ["Longhouse", "Mead Hall", "Rune Stone", "Drakkar", "Forge"]},
	{"name": "Sky Kingdom", "buildings": ["Cloud Castle", "Balloon Dock", "Wind Turbine", "Rainbow Bridge", "Star Tower"]},
	{"name": "Spooky Hollow", "buildings": ["Haunted House", "Pumpkin Patch", "Witch Hut", "Chapel", "Bat Tower"]},
	{"name": "Greek Isle", "buildings": ["Temple", "Olive Grove", "Amphora Shop", "Pier", "Statue Plaza"]},
	{"name": "Neon City", "buildings": ["Arcade", "Noodle Bar", "Holo Tower", "Subway", "Sky Garden"]},
	{"name": "Safari Savanna", "buildings": ["Lodge", "Baobab Home", "Waterhole", "Jeep Garage", "Lookout"]},
	{"name": "Arctic Base", "buildings": ["Station", "Igloo", "Radar Dish", "Snowcat", "Aurora Tower"]},
	{"name": "Mushroom Vale", "buildings": ["Shroom Home", "Spore Mill", "Snail Stable", "Moss Garden", "Lantern Post"]},
	{"name": "Steampunk Port", "buildings": ["Gear Factory", "Airship Dock", "Clocktower", "Engine House", "Inventor Lab"]},
	{"name": "Blossom Vale", "buildings": ["Shrine", "Koi Pond", "Lantern House", "Bamboo Grove", "Festival Stage"]},
	{"name": "Lost Atlantis", "buildings": ["Crystal Palace", "Trident Forge", "Seahorse Stable", "Bubble Garden", "Ruins Arch"]},
	{"name": "Chocolate Alps", "buildings": ["Cocoa Chalet", "Fondue Mill", "Mallow Farm", "Caramel Falls", "Cable Car"]},
	{"name": "Robot Works", "buildings": ["Assembly", "Battery Farm", "Scrapyard", "Control Tower", "Charge Station"]},
	{"name": "Dino Valley", "buildings": ["Dino Nest", "Fern Farm", "Bone Bridge", "Cave Home", "Lookout Rock"]},
	{"name": "Moon Base", "buildings": ["Lunar Dome", "Crater Mine", "Antenna Array", "Rover Garage", "Earth Deck"]},
	{"name": "Magic Library", "buildings": ["Book Tower", "Ink Fountain", "Scroll Mill", "Owl Post", "Archive"]},
	{"name": "Golden Capital", "buildings": ["Palace", "Mint", "Fountain", "Market Hall", "Arch"]},
]

const NPC_DEFS := [
	{"name": "Olga", "emoji": "👵"},
	{"name": "Boris", "emoji": "🧔"},
	{"name": "Mimi", "emoji": "👩‍🦰"},
	{"name": "Rex", "emoji": "👨‍🎨"},
	{"name": "Luna", "emoji": "👧"},
]

# Real-money store packs (prototype — purchases are simulated).
# Modeled on Coin Master-style stores: a one-time starter offer,
# three card chests of rising rarity, spin packs and coin packs.
const STARTER_PACK := {"id": "starter", "name": "First Timer Pack", "sub": "60 Spins + 50,000 Coins + Golden Chest", "emoji": "🎁", "price": "$1.99", "tag": "250% VALUE", "once": true, "spins": 60, "coins": 50000, "cards": 4, "tier": 1}

# Chest tiers: pricier chests hold more cards and shift the star odds
# upward. The Magical Chest always contains at least one 5-star card.
# art_tint modulates the shared treasure-chest sprite per tier.
const CHEST_PACKS := [
	{"id": "chest_w", "name": "Wooden Chest", "sub": "2 Cards", "emoji": "📦", "price": "$0.99", "cards": 2, "tier": 0,
	 "color": Color(0.72, 0.5, 0.3), "tag": "BASIC", "tag_color": Color(0.45, 0.42, 0.5), "star_cap": 2,
	 "art_tint": Color(0.74, 0.62, 0.52)},
	{"id": "chest_g", "name": "Golden Chest", "sub": "4 Cards — better star odds", "emoji": "🧰", "price": "$2.99", "cards": 4, "tier": 1,
	 "color": Color(1.0, 0.78, 0.25), "tag": "POPULAR", "tag_color": Color(0.88, 0.28, 0.38), "star_cap": 4,
	 "art_tint": Color(1.0, 1.0, 1.0)},
	{"id": "chest_m", "name": "Magical Chest", "sub": "6 Cards — 5★ guaranteed", "emoji": "🔮", "price": "$6.99", "cards": 6, "tier": 2,
	 "color": Color(0.72, 0.45, 1.0), "tag": "BEST VALUE", "tag_color": Color(0.55, 0.3, 0.85), "star_cap": 5, "guarantee5": true,
	 "art_tint": Color(0.82, 0.64, 1.0)},
]

# Chance weights for a drawn card's star rating (1..5), per chest tier.
const CHEST_STAR_WEIGHTS := [
	[50, 30, 14, 5, 1],
	[18, 30, 28, 16, 8],
	[5, 15, 27, 30, 23],
]

const SPIN_PACKS := [
	{"id": "spins_s", "name": "Breeze", "sub": "30 Spins", "emoji": "🌀", "price": "$0.99", "spins": 30},
	{"id": "spins_m", "name": "Storm", "sub": "80 Spins", "emoji": "⚡", "price": "$1.99", "spins": 80, "tag": "POPULAR", "tag_color": Color(0.88, 0.28, 0.38)},
	{"id": "spins_l", "name": "Cyclone", "sub": "200 Spins", "emoji": "🔥", "price": "$3.99", "spins": 200},
	{"id": "spins_xl", "name": "Hurricane", "sub": "450 Spins", "emoji": "🌪️", "price": "$7.99", "spins": 450, "tag": "BEST VALUE", "tag_color": Color(0.55, 0.3, 0.85)},
]

const COIN_PACKS := [
	{"id": "coins_s", "name": "Sack of Coins", "sub": "25,000 Coins", "emoji": "💰", "price": "$0.99", "coins": 25000},
	{"id": "coins_m", "name": "Wagon of Coins", "sub": "90,000 Coins", "emoji": "🪙", "price": "$2.99", "coins": 90000, "tag": "x3.6 VALUE", "tag_color": Color(0.3, 0.68, 0.35)},
]

# Free gift claimable in the shop once every 24 hours.
const SHOP_FREE_COOLDOWN := 86400.0
const SHOP_FREE_COINS := 2500
const SHOP_FREE_SPINS := 10

# star rating (1..5) → display color, index star-1
const STAR_COLORS := [
	Color(0.62, 0.66, 0.72),
	Color(0.45, 0.8, 0.45),
	Color(0.4, 0.65, 1.0),
	Color(0.75, 0.5, 1.0),
	Color(1.0, 0.8, 0.25),
]

const COLLECTION_SEASON_DAYS := 30
const COLLECTION_MEGA_COINS := 100000
const COLLECTION_MEGA_SPINS := 50
const CARD_DROP_CHANCE := 0.25

# Relative chance a spin-dropped card has a given star rating (index star-1).
# High-star cards must stay rare or a season is over in days, not a month.
const DROP_STAR_WEIGHTS := [50, 28, 13, 6, 3]

# weight = relative chance a dropped card comes from this collection.
# Easy sets drop often; hard sets are rare and long.
# Each item is [emoji, name, stars]. Stars (1..5) are the card's rarity —
# 5-star cards only exist in Hard sets, so chest star odds drive set odds.
const COLLECTIONS := [
	{"id": "beach", "name": "Beach Day", "icon": "🏖️", "diff": "Easy", "weight": 30,
	 "reward_coins": 3000, "reward_spins": 0,
	 "items": [["🐚", "Seashell", 1], ["🦀", "Crab", 1], ["⛱️", "Umbrella", 1], ["🍦", "Ice Cream", 2], ["🕶️", "Shades", 2], ["🏄", "Surfboard", 3]]},
	{"id": "fruits", "name": "Fruit Basket", "icon": "🧺", "diff": "Easy", "weight": 26,
	 "reward_coins": 4000, "reward_spins": 5,
	 "items": [["🍎", "Apple", 1], ["🍌", "Banana", 1], ["🍇", "Grapes", 2], ["🍉", "Watermelon", 2], ["🍍", "Pineapple", 3], ["🥝", "Kiwi", 3]]},
	{"id": "pirate", "name": "Pirate Treasure", "icon": "🏴‍☠️", "diff": "Medium", "weight": 17,
	 "reward_coins": 8000, "reward_spins": 10,
	 "items": [["🗺️", "Old Map", 2], ["🧭", "Compass", 2], ["⚓", "Anchor", 2], ["🦜", "Parrot", 3], ["💰", "Gold Bag", 3], ["🗡️", "Cutlass", 3], ["🛢️", "Rum Barrel", 4], ["☠️", "Jolly Roger", 4]]},
	{"id": "ocean", "name": "Ocean Life", "icon": "🌊", "diff": "Medium", "weight": 13,
	 "reward_coins": 10000, "reward_spins": 10,
	 "items": [["🐠", "Reef Fish", 2], ["🪸", "Coral", 2], ["🐙", "Octopus", 3], ["🐬", "Dolphin", 3], ["🐢", "Turtle", 3], ["🦈", "Shark", 4], ["🐳", "Whale", 4], ["🦞", "Lobster", 4]]},
	{"id": "relics", "name": "Mystic Relics", "icon": "🔮", "diff": "Hard", "weight": 9,
	 "reward_coins": 20000, "reward_spins": 20,
	 "items": [["📿", "Prayer Beads", 3], ["🏺", "Amphora", 3], ["🕯️", "Ritual Candle", 3], ["🗿", "Stone Idol", 4], ["⚱️", "Ancient Urn", 4], ["🪬", "Amulet", 4], ["📜", "Lost Scroll", 4], ["🔮", "Crystal Orb", 5], ["🪄", "Wand", 5], ["🧿", "Evil Eye", 5]]},
	{"id": "royal", "name": "Royal Jewels", "icon": "👑", "diff": "Hard", "weight": 5,
	 "reward_coins": 30000, "reward_spins": 30,
	 "items": [["⚜️", "Fleur-de-Lis", 3], ["🥇", "Medal", 3], ["🛡️", "Crest", 3], ["💍", "Royal Ring", 4], ["🏆", "Gold Cup", 4], ["⚔️", "Twin Swords", 4], ["👑", "Crown", 5], ["💎", "Diamond", 5], ["🔱", "Trident", 5], ["🎖️", "Royal Order", 5]]},
]

static var _efont: Font
static var _ground_mat: ShaderMaterial
static var _shadow_mat: ShaderMaterial

# Melts a building sprite's baked-in ground into the island terrain:
# the lower part gets an organic, wavy alpha falloff toward its outer
# edges so the sprite's grass cross-fades with the island's grass
# instead of ending in a hard rectangular cut.
static func ground_blend_material() -> ShaderMaterial:
	if _ground_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;

uniform vec3 terrain_col = vec3(0.45, 0.7, 0.42);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float wob = sin(UV.x * 19.0 + 1.3) * 0.030 + sin(UV.x * 43.0 + 0.7) * 0.016 + sin(UV.y * 27.0) * 0.018;
	float blend_start = 0.32;
	float depth = clamp((UV.y - blend_start) / (1.0 - blend_start), 0.0, 1.0);
	float half_w = mix(0.52, 0.36, depth * depth);
	float dx = abs(UV.x - 0.5);
	float side = 1.0 - smoothstep(half_w - 0.18 + wob, half_w + wob, dx);
	float bottom = 1.0 - smoothstep(0.82 + wob * 2.0, 0.98, UV.y);
	float mask = mix(1.0, clamp(min(side, bottom), 0.0, 1.0), smoothstep(0.0, 0.1, depth));
	// thin organic frame fade so no baked-in edge ever shows as a straight cut
	float frame = 1.0 - smoothstep(0.455 + wob, 0.5 + wob, dx);
	// pull the sprite's baked-in ground toward the island's real terrain color
	// so its grass takes on the local hue instead of clashing with it
	float edge_w = max(smoothstep(half_w * 0.45, half_w + 0.05, dx), smoothstep(0.72, 0.95, UV.y));
	float cm = smoothstep(0.05, 0.7, depth) * edge_w * 0.75;
	c.rgb = mix(c.rgb, terrain_col, cm);
	// soft contact darkening at the very base grounds the building
	c.rgb *= mix(1.0, 0.94, smoothstep(0.84, 0.99, UV.y));
	c.a *= mask * frame;
	COLOR = c;
}
"""
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = sh
	return _ground_mat

static func contact_shadow_material() -> ShaderMaterial:
	if _shadow_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	float a = (1.0 - smoothstep(0.35, 1.0, d)) * 0.40;
	COLOR = vec4(0.02, 0.06, 0.03, a);
}
"""
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = sh
	return _shadow_mat

# Average color of the island bg image directly under a building slot,
# mapping through the same cover-fit the bg TextureRect uses on a 720x1280 page.
static func terrain_color_at(img: Image, rect: Rect2, base_offset: float) -> Color:
	var fallback := Color(0.45, 0.7, 0.42)
	if img == null:
		return fallback
	var w := float(img.get_width())
	var h := float(img.get_height())
	if w <= 0.0 or h <= 0.0:
		return fallback
	var s := maxf(720.0 / w, 1280.0 / h)
	var off := Vector2(720.0 - w * s, 1280.0 - h * s) * 0.5
	var base := rect.position + Vector2(rect.size.x * 0.5, rect.size.y - base_offset)
	var sum := Vector3.ZERO
	var n := 0
	for d in [Vector2(-90, 0), Vector2(-55, 8), Vector2(0, 14), Vector2(55, 8), Vector2(90, 0), Vector2(-30, -6), Vector2(30, -6)]:
		var px := (base + (d as Vector2) - off) / s
		if px.x >= 0.0 and px.y >= 0.0 and px.x < w and px.y < h:
			var col := img.get_pixel(int(px.x), int(px.y))
			sum += Vector3(col.r, col.g, col.b)
			n += 1
	if n == 0:
		return fallback
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z)

static func bg_image(t: Texture2D) -> Image:
	if t == null:
		return null
	var img := t.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img

# Bundled color emoji font — system emoji fonts aren't reachable on iOS,
# so the app ships Noto Color Emoji and falls back to system fonts.
static func emoji_font() -> Font:
	if _efont == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"])
		var bundled: Font = tex_font("res://assets/fonts/NotoColorEmoji.ttf")
		if bundled != null:
			var v := FontVariation.new()
			v.base_font = bundled
			v.fallbacks = [sys]
			_efont = v
		else:
			_efont = sys
	return _efont

static func tex_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func symbol_tex(id: String) -> Texture2D:
	return tex("res://assets/art/symbols/%s.png" % id)

static func building_tex(id: String) -> Texture2D:
	return tex("res://assets/art/buildings/%s.png" % id)

static func bg_tex(id: String) -> Texture2D:
	return tex("res://assets/art/bg/%s.png" % id)

static func prop_tex(id: String) -> Texture2D:
	return tex("res://assets/art/props/%s.png" % id)

static func island_theme(level: int) -> Dictionary:
	return ISLANDS[(level - 1) % ISLANDS.size()]

static func island_building_name(level: int, i: int) -> String:
	return island_theme(level)["buildings"][i]

static func island_building_tex(level: int, i: int) -> Texture2D:
	var idx := (level - 1) % ISLANDS.size()
	var t := tex("res://assets/art/islands/island_%02d/b%d.png" % [idx + 1, i])
	if t == null:
		t = building_tex(BUILDINGS[i]["id"])
	return t

static func island_bg_tex(level: int) -> Texture2D:
	var idx := (level - 1) % ISLANDS.size()
	var t := tex("res://assets/art/islands/island_%02d/bg.png" % (idx + 1))
	if t == null:
		t = bg_tex("village")
	return t

static func new_npc(def: Dictionary) -> Dictionary:
	var b := []
	for i in BUILDINGS.size():
		b.append(randi_range(1, 4))
	return {
		"name": def["name"],
		"emoji": def["emoji"],
		"coins": randi_range(1500, 6000),
		"buildings": b,
		"shield": randf() < 0.35,
		"island": randi_range(1, ISLANDS.size()),
	}
