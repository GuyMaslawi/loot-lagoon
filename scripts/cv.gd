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

# Per-island color identity for the SPIN page, one entry per ISLANDS entry.
#   deep   darkest ambient — page vignette, cabinet body
#   mid    room/stage light — page gradient top
#   accent trim metal — marquee, frame border, reel edges
#   spin   the hero SPIN button's base hue
#   glow   bloom color for spotlights and the button halo
# Everything else (reel face, marquee ink, bevels) is derived from these
# so a new island only needs five colors to feel like its own place.
const ISLAND_PALETTES := [
	# Green Meadows
	{"deep": Color(0.082, 0.196, 0.122), "mid": Color(0.184, 0.42, 0.235),
	 "accent": Color(0.949, 0.773, 0.239), "spin": Color(0.957, 0.333, 0.18), "glow": Color(1, 0.82, 0.4)},
	# Pirate Cove
	{"deep": Color(0.063, 0.133, 0.18), "mid": Color(0.137, 0.286, 0.361),
	 "accent": Color(0.878, 0.702, 0.337), "spin": Color(0.851, 0.231, 0.231), "glow": Color(1, 0.769, 0.42)},
	# Desert Oasis
	{"deep": Color(0.227, 0.141, 0.075), "mid": Color(0.541, 0.353, 0.169),
	 "accent": Color(1, 0.824, 0.478), "spin": Color(0.91, 0.384, 0.165), "glow": Color(1, 0.851, 0.627)},
	# Snowy Peaks
	{"deep": Color(0.071, 0.141, 0.227), "mid": Color(0.184, 0.361, 0.525),
	 "accent": Color(0.812, 0.91, 1), "spin": Color(0.914, 0.294, 0.416), "glow": Color(0.659, 0.863, 1)},
	# Jungle Ruins
	{"deep": Color(0.071, 0.161, 0.102), "mid": Color(0.176, 0.373, 0.216),
	 "accent": Color(0.847, 0.706, 0.353), "spin": Color(0.886, 0.337, 0.169), "glow": Color(0.714, 0.878, 0.478)},
	# Candy Land
	{"deep": Color(0.231, 0.063, 0.188), "mid": Color(0.49, 0.137, 0.349),
	 "accent": Color(1, 0.82, 0.91), "spin": Color(1, 0.302, 0.553), "glow": Color(1, 0.702, 0.871)},
	# Space Colony
	{"deep": Color(0.043, 0.059, 0.169), "mid": Color(0.137, 0.188, 0.42),
	 "accent": Color(0.498, 0.89, 1), "spin": Color(1, 0.302, 0.427), "glow": Color(0.498, 0.847, 1)},
	# Coral Reef
	{"deep": Color(0.02, 0.157, 0.227), "mid": Color(0.063, 0.38, 0.478),
	 "accent": Color(1, 0.824, 0.541), "spin": Color(1, 0.42, 0.29), "glow": Color(0.498, 0.941, 0.878)},
	# Volcano Isle
	{"deep": Color(0.149, 0.039, 0.039), "mid": Color(0.42, 0.122, 0.078),
	 "accent": Color(1, 0.69, 0.227), "spin": Color(1, 0.325, 0.125), "glow": Color(1, 0.541, 0.235)},
	# Fairy Forest
	{"deep": Color(0.102, 0.071, 0.212), "mid": Color(0.263, 0.153, 0.431),
	 "accent": Color(0.902, 0.863, 1), "spin": Color(0.91, 0.294, 0.749), "glow": Color(0.725, 0.549, 1)},
	# Wild West
	{"deep": Color(0.18, 0.102, 0.063), "mid": Color(0.478, 0.29, 0.141),
	 "accent": Color(0.941, 0.765, 0.306), "spin": Color(0.824, 0.251, 0.184), "glow": Color(1, 0.812, 0.478)},
	# Ancient Egypt
	{"deep": Color(0.169, 0.125, 0.031), "mid": Color(0.478, 0.373, 0.094),
	 "accent": Color(1, 0.847, 0.302), "spin": Color(0.09, 0.647, 0.769), "glow": Color(1, 0.878, 0.478)},
	# Samurai Village
	{"deep": Color(0.137, 0.063, 0.102), "mid": Color(0.361, 0.122, 0.165),
	 "accent": Color(0.91, 0.812, 0.604), "spin": Color(0.847, 0.208, 0.184), "glow": Color(1, 0.69, 0.627)},
	# Viking Fjord
	{"deep": Color(0.055, 0.11, 0.149), "mid": Color(0.169, 0.29, 0.361),
	 "accent": Color(0.725, 0.776, 0.831), "spin": Color(0.816, 0.353, 0.165), "glow": Color(0.624, 0.843, 0.91)},
	# Sky Kingdom
	{"deep": Color(0.086, 0.133, 0.31), "mid": Color(0.247, 0.42, 0.71),
	 "accent": Color(1, 0.914, 0.659), "spin": Color(1, 0.478, 0.302), "glow": Color(0.812, 0.894, 1)},
	# Spooky Hollow
	{"deep": Color(0.082, 0.047, 0.133), "mid": Color(0.227, 0.122, 0.302),
	 "accent": Color(1, 0.624, 0.235), "spin": Color(0.482, 0.184, 0.949), "glow": Color(0.525, 0.878, 0.18)},
	# Greek Isle
	{"deep": Color(0.047, 0.137, 0.251), "mid": Color(0.122, 0.373, 0.62),
	 "accent": Color(0.949, 0.941, 0.902), "spin": Color(0.949, 0.42, 0.227), "glow": Color(0.659, 0.847, 1)},
	# Neon City
	{"deep": Color(0.031, 0.024, 0.102), "mid": Color(0.106, 0.063, 0.314),
	 "accent": Color(0.204, 0.961, 0.878), "spin": Color(1, 0.176, 0.584), "glow": Color(0.478, 0.176, 1)},
	# Safari Savanna
	{"deep": Color(0.18, 0.141, 0.063), "mid": Color(0.49, 0.396, 0.133),
	 "accent": Color(0.961, 0.812, 0.416), "spin": Color(0.878, 0.392, 0.165), "glow": Color(1, 0.863, 0.541)},
	# Arctic Base
	{"deep": Color(0.027, 0.102, 0.165), "mid": Color(0.078, 0.259, 0.369),
	 "accent": Color(0.718, 0.941, 1), "spin": Color(0.184, 0.827, 0.604), "glow": Color(0.475, 1, 0.839)},
	# Mushroom Vale
	{"deep": Color(0.114, 0.078, 0.141), "mid": Color(0.29, 0.169, 0.243),
	 "accent": Color(0.941, 0.788, 0.529), "spin": Color(0.878, 0.333, 0.247), "glow": Color(1, 0.698, 0.478)},
	# Steampunk Port
	{"deep": Color(0.141, 0.086, 0.031), "mid": Color(0.42, 0.263, 0.094),
	 "accent": Color(0.851, 0.631, 0.353), "spin": Color(0.09, 0.635, 0.722), "glow": Color(1, 0.769, 0.439)},
	# Blossom Vale
	{"deep": Color(0.169, 0.071, 0.149), "mid": Color(0.431, 0.165, 0.306),
	 "accent": Color(1, 0.851, 0.91), "spin": Color(1, 0.373, 0.494), "glow": Color(1, 0.722, 0.816)},
	# Lost Atlantis
	{"deep": Color(0.016, 0.122, 0.2), "mid": Color(0.059, 0.333, 0.439),
	 "accent": Color(0.561, 0.941, 0.902), "spin": Color(1, 0.69, 0.227), "glow": Color(0.373, 0.878, 1)},
	# Chocolate Alps
	{"deep": Color(0.141, 0.071, 0.031), "mid": Color(0.361, 0.184, 0.078),
	 "accent": Color(1, 0.851, 0.659), "spin": Color(0.878, 0.478, 0.165), "glow": Color(1, 0.78, 0.541)},
	# Robot Works
	{"deep": Color(0.078, 0.09, 0.11), "mid": Color(0.2, 0.235, 0.278),
	 "accent": Color(0.784, 0.824, 0.863), "spin": Color(1, 0.541, 0.122), "glow": Color(0.431, 0.878, 1)},
	# Dino Valley
	{"deep": Color(0.11, 0.141, 0.063), "mid": Color(0.29, 0.361, 0.133),
	 "accent": Color(0.847, 0.769, 0.478), "spin": Color(0.91, 0.392, 0.165), "glow": Color(0.784, 0.878, 0.478)},
	# Moon Base
	{"deep": Color(0.039, 0.047, 0.078), "mid": Color(0.149, 0.169, 0.22),
	 "accent": Color(0.847, 0.878, 0.933), "spin": Color(1, 0.353, 0.235), "glow": Color(0.624, 0.706, 0.847)},
	# Magic Library
	{"deep": Color(0.102, 0.063, 0.031), "mid": Color(0.29, 0.184, 0.086),
	 "accent": Color(0.91, 0.788, 0.541), "spin": Color(0.478, 0.302, 1), "glow": Color(0.784, 0.627, 1)},
	# Golden Capital
	{"deep": Color(0.169, 0.122, 0.024), "mid": Color(0.42, 0.322, 0.063),
	 "accent": Color(1, 0.878, 0.478), "spin": Color(1, 0.239, 0.353), "glow": Color(1, 0.824, 0.302)},
]

# The rival population.
#
# Raiding needs somebody on the other end of it, and for a long while after
# launch there will not be enough live players to find one -- a matchmaking
# search across a hundred accounts would hand you the same three islands every
# spin, and the ones it did find would be strangers getting hammered all day.
# So the raid net is stocked with bots, and it is stocked deep: forty-odd
# rivals with their own faces, homes and vaults, drawn from every corner of the
# map, so the search always has a crowd to sift through and the crowd always
# looks like a player base rather than a cast of five.
#
# The region code is not decoration. It is the one field that makes a rival
# read as somebody who logged in from somewhere, which is exactly the
# impression the matchmaking screen is built to sell. It is a code rather than
# a flag emoji because the bundled emoji font has no country flags in it and
# substitutes the same black pennant for all of them.
const BOT_DEFS := [
	{"name": "Olga", "emoji": "👵", "flag": "RU"},
	{"name": "Boris", "emoji": "🧔", "flag": "RU"},
	{"name": "Mimi", "emoji": "👩‍🦰", "flag": "FR"},
	{"name": "Rex", "emoji": "👨‍🎨", "flag": "US"},
	{"name": "Luna", "emoji": "👧", "flag": "ES"},
	{"name": "Kai", "emoji": "🏄", "flag": "AU"},
	{"name": "Nina", "emoji": "👩‍🦱", "flag": "BR"},
	{"name": "Diego", "emoji": "🧑‍🌾", "flag": "MX"},
	{"name": "Yuki", "emoji": "👘", "flag": "JP"},
	{"name": "Amir", "emoji": "🧑‍🦲", "flag": "AE"},
	{"name": "Freya", "emoji": "👱‍♀️", "flag": "SE"},
	{"name": "Tomas", "emoji": "👨‍🔧", "flag": "CZ"},
	{"name": "Priya", "emoji": "👩‍🏫", "flag": "IN"},
	{"name": "Marco", "emoji": "🧑‍🍳", "flag": "IT"},
	{"name": "Zoe", "emoji": "👩‍🎤", "flag": "GR"},
	{"name": "Hugo", "emoji": "🧑‍✈️", "flag": "PT"},
	{"name": "Lena", "emoji": "👩‍💻", "flag": "DE"},
	{"name": "Sami", "emoji": "🧑‍🚀", "flag": "FI"},
	{"name": "Noor", "emoji": "🧕", "flag": "MA"},
	{"name": "Jonas", "emoji": "👨‍🌾", "flag": "NO"},
	{"name": "Carla", "emoji": "💃", "flag": "AR"},
	{"name": "Ravi", "emoji": "🧑‍🎓", "flag": "IN"},
	{"name": "Elif", "emoji": "👩", "flag": "TR"},
	{"name": "Milo", "emoji": "👦", "flag": "BE"},
	{"name": "Ines", "emoji": "👩‍⚕️", "flag": "PT"},
	{"name": "Otto", "emoji": "👨‍🚒", "flag": "AT"},
	{"name": "Sora", "emoji": "🧑‍🎤", "flag": "KR"},
	{"name": "Bella", "emoji": "👩‍🦳", "flag": "GB"},
	{"name": "Pavel", "emoji": "🕵️", "flag": "PL"},
	{"name": "Anika", "emoji": "👩‍🔬", "flag": "NL"},
	{"name": "Theo", "emoji": "👨‍🏫", "flag": "IE"},
	{"name": "Tara", "emoji": "👩‍🚀", "flag": "CA"},
	{"name": "Enzo", "emoji": "🧑‍🏭", "flag": "IT"},
	{"name": "Maya", "emoji": "👩‍🎨", "flag": "IL"},
	{"name": "Idan", "emoji": "🧑‍💻", "flag": "IL"},
	{"name": "Rosa", "emoji": "👩‍🌾", "flag": "CO"},
	{"name": "Nils", "emoji": "🧑‍🔬", "flag": "DK"},
	{"name": "Ayla", "emoji": "👸", "flag": "TR"},
	{"name": "Bruno", "emoji": "🤠", "flag": "BR"},
	{"name": "Kofi", "emoji": "🧑‍🎨", "flag": "GH"},
	{"name": "Sasha", "emoji": "🧑‍🦰", "flag": "UA"},
	{"name": "Mei", "emoji": "👩‍🍳", "flag": "CN"},
	{"name": "Dara", "emoji": "🧑‍🌾", "flag": "ID"},
	{"name": "Iva", "emoji": "👩‍✈️", "flag": "HR"},
	{"name": "Jax", "emoji": "🧑‍🚒", "flag": "ZA"},
	{"name": "Vera", "emoji": "👩‍🚒", "flag": "RS"},
]

# How many rivals the raid net keeps warm at a time. The pool is what the
# search screen flicks through and what the leaderboard ranks you against, so
# it wants to be big enough to feel like a room and small enough that you meet
# the same faces often enough to hold a grudge.
const RIVAL_POOL := 9

# Real-money store packs (prototype — purchases are simulated).
# Modeled on Coin Master-style stores: a one-time starter offer,
# three card chests of rising rarity, spin packs and coin packs.
const STARTER_PACK := {"id": "starter", "name": "First Timer Pack", "sub": "60 Spins + %s Coins + Golden Chest", "emoji": "🎁", "price": "$1.99", "tag": "250% VALUE", "once": true, "spins": 60, "coins": 50000, "cards": 4, "tier": 1}

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

# Price ladders.
#
# The genre's stores all run six or seven rungs from $0.99 to $99.99, and they
# are shaped so the value per dollar climbs the whole way up -- Coin Master's
# top spin tier is worth roughly 2.2x its bottom one. That slope is the entire
# product: the small packs exist to be compared against, and the revenue comes
# from the rungs above them. A ladder that stops at $7.99 has no top half,
# which is where the paying players actually live.
#
# Rungs here run 30 spins/$ at the bottom to 75 at the top (2.5x), and
# 25k coins/$ to 50k (2.0x). BASE_RATE is the entry rung, and every tile quotes
# its own rate against it as a "+N% MORE" chip.
const SPIN_BASE_RATE := 30.0 / 0.99
const COIN_BASE_RATE := 25000.0 / 0.99

const SPIN_PACKS := [
	{"id": "spins_s", "name": "Breeze", "sub": "30 Spins", "emoji": "🌀", "price": "$0.99", "spins": 30},
	{"id": "spins_m", "name": "Storm", "sub": "80 Spins", "emoji": "⚡", "price": "$1.99", "spins": 80, "tag": "POPULAR", "tag_color": Color(0.88, 0.28, 0.38)},
	{"id": "spins_l", "name": "Cyclone", "sub": "200 Spins", "emoji": "🔥", "price": "$3.99", "spins": 200},
	{"id": "spins_xl", "name": "Hurricane", "sub": "450 Spins", "emoji": "🌪️", "price": "$7.99", "spins": 450},
	{"id": "spins_2xl", "name": "Monsoon", "sub": "1,200 Spins", "emoji": "🌊", "price": "$19.99", "spins": 1200},
	{"id": "spins_3xl", "name": "Maelstrom", "sub": "3,400 Spins", "emoji": "🌌", "price": "$49.99", "spins": 3400, "tag": "BEST VALUE", "tag_color": Color(0.55, 0.3, 0.85)},
	{"id": "spins_4xl", "name": "Leviathan", "sub": "7,500 Spins", "emoji": "🐋", "price": "$99.99", "spins": 7500, "tag": "MAX VALUE", "tag_color": Color(0.2, 0.55, 0.9)},
]

const COIN_PACKS := [
	{"id": "coins_s", "name": "Sack of Coins", "sub": "%s Coins", "emoji": "💰", "price": "$0.99", "coins": 25000},
	{"id": "coins_m", "name": "Wagon of Coins", "sub": "%s Coins", "emoji": "🪙", "price": "$2.99", "coins": 90000, "tag": "POPULAR", "tag_color": Color(0.88, 0.28, 0.38)},
	{"id": "coins_l", "name": "Galleon of Coins", "sub": "%s Coins", "emoji": "⛵", "price": "$9.99", "coins": 350000},
	{"id": "coins_xl", "name": "Reef of Coins", "sub": "%s Coins", "emoji": "🪸", "price": "$24.99", "coins": 1000000},
	{"id": "coins_2xl", "name": "Trench of Coins", "sub": "%s Coins", "emoji": "🌊", "price": "$59.99", "coins": 2700000, "tag": "BEST VALUE", "tag_color": Color(0.55, 0.3, 0.85)},
	{"id": "coins_3xl", "name": "Sunken City", "sub": "%s Coins", "emoji": "🏛️", "price": "$99.99", "coins": 5000000, "tag": "MAX VALUE", "tag_color": Color(0.2, 0.55, 0.9)},
]

# Mixed bundles -- spins AND coins AND cards in one box.
#
# Every top-grossing game in the genre sells these alongside the single-resource
# ladders, because they are the only product that fits a player who is short of
# everything at once. They are also where the high price points stop feeling
# like "a lot of spins" and start feeling like a shortcut through the whole
# game, which is what a $49.99 buyer is actually paying for. Each is priced
# under the sum of its parts bought separately -- that gap is the pitch.
const BUNDLE_PACKS := [
	{"id": "bundle_s", "name": "Deckhand's Haul", "sub": "150 Spins + %s Coins + 2 Cards", "emoji": "🧳", "price": "$4.99",
	 "spins": 150, "coins": 150000, "cards": 2, "tier": 1, "value": 140,
	 "color": Color(0.35, 0.75, 1.0)},
	{"id": "bundle_m", "name": "Quartermaster's Haul", "sub": "700 Spins + %s Coins + 5 Cards", "emoji": "🗺️", "price": "$19.99",
	 "spins": 700, "coins": 700000, "cards": 5, "tier": 2, "value": 150,
	 "color": Color(1.0, 0.78, 0.25), "tag": "POPULAR", "tag_color": Color(0.88, 0.28, 0.38)},
	{"id": "bundle_l", "name": "Captain's Hoard", "sub": "2,000 Spins + %s Coins + 12 Cards", "emoji": "👑", "price": "$49.99",
	 "spins": 2000, "coins": 2000000, "cards": 12, "tier": 2, "guarantee5": true, "value": 165,
	 "color": Color(0.72, 0.45, 1.0), "tag": "5★ GUARANTEED", "tag_color": Color(0.55, 0.3, 0.85)},
]

# The piggy bank.
#
# The highest-converting mechanic in casual games, and the one this store was
# most obviously missing. It fills with coins as a side-effect of ordinary play
# -- the player watches their own winnings pile up behind glass -- and breaking
# it costs one fixed price no matter how full it is. The offer therefore gets
# better every session the player doesn't take it, which is the opposite of a
# discount that decays, and it converts because by the time it is full the
# player feels they are buying back something already theirs.
#
# Full, it beats the best rung of the coin ladder (63k coins/$ against 50k), so
# a patient player who buys it is genuinely getting the store's best deal.
const PIGGY_CAP := 250000       # island-1 units, scaled like every other coin figure
const PIGGY_PER_SPIN := 1200    # a slow drip, so filling it takes a few sessions
const PIGGY_PER_RAID := 6000    # raids and attacks fatten it noticeably faster
const PIGGY_PRICE := "$3.99"

# The piggy is sold like any other pack, so it needs a pack-shaped record for
# the purchase path to carry. It has no contents field -- what it pays out is
# whatever the player already banked, not a fixed amount.
const PIGGY_PACK := {"id": "piggy", "name": "Piggy Bank", "emoji": "\U0001F437", "price": PIGGY_PRICE}

# Rotating limited-time offer.
#
# Coin Master keeps one of these live nearly all the time -- five minutes to a
# couple of hours, with a loud percentage on it -- and it is what makes opening
# the store feel like checking whether something is happening rather than
# browsing a price list. The countdown does the work; the pack behind it only
# has to be plainly better than the standing shelf.
const OFFER_DURATION := 7200.0   # 2 hours live
const OFFER_COOLDOWN := 18000.0  # 5 hours dark before the next one rolls

const TIMED_OFFERS := [
	{"id": "to_squall", "name": "Squall Bundle", "sub": "150 Spins + %s Coins + 1 Card", "emoji": "🌬️", "price": "$2.99",
	 "spins": 150, "coins": 120000, "cards": 1, "tier": 1, "value": 300},
	{"id": "to_tide", "name": "High Tide Chest", "sub": "120 Spins + %s Coins + 3 Cards", "emoji": "🌊", "price": "$4.99",
	 "spins": 120, "coins": 250000, "cards": 3, "tier": 1, "value": 380},
	{"id": "to_moon", "name": "Moonlit Raid Pack", "sub": "260 Spins + %s Coins + 2 Cards", "emoji": "🌙", "price": "$6.99",
	 "spins": 260, "coins": 400000, "cards": 2, "tier": 2, "value": 420},
	{"id": "to_kraken", "name": "Kraken's Cut", "sub": "400 Spins + %s Coins + 4 Cards", "emoji": "🦑", "price": "$9.99",
	 "spins": 400, "coins": 600000, "cards": 4, "tier": 2, "guarantee5": true, "value": 450},
]

# Every money pack, found by its short id. The product ids Apple knows are
# these same strings behind a bundle prefix, so this is what turns a finished
# transaction back into the thing the player bought.
static func pack_by_id(id: String) -> Dictionary:
	if id == String(STARTER_PACK["id"]):
		return STARTER_PACK
	if id == String(PIGGY_PACK["id"]):
		return PIGGY_PACK
	for group in [CHEST_PACKS, SPIN_PACKS, COIN_PACKS, BUNDLE_PACKS, TIMED_OFFERS]:
		for p in group:
			if String(p["id"]) == id:
				return p
	return {}

# "$19.99" -> 19.99. Prices are carried as display strings so the tiles never
# have to reformat them, and this is the one place that needs the number.
static func price_usd(pack: Dictionary) -> float:
	return String(pack.get("price", "$0")).substr(1).to_float()

# How much more per dollar a rung gives than the entry rung of its ladder.
# Bundles and timed offers carry a hand-set "value" instead, since there is no
# single base rate to measure a mixed box against.
static func bonus_pct(pack: Dictionary) -> int:
	if pack.has("value"):
		return int(pack["value"]) - 100
	var usd := price_usd(pack)
	if usd <= 0.0:
		return 0
	var has_spins: bool = int(pack.get("spins", 0)) > 0
	var has_coins: bool = int(pack.get("coins", 0)) > 0
	if has_spins and not has_coins:
		return int(round((float(pack["spins"]) / usd) / SPIN_BASE_RATE * 100.0)) - 100
	if has_coins and not has_spins:
		return int(round((float(pack["coins"]) / usd) / COIN_BASE_RATE * 100.0)) - 100
	return 0

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

# Duplicate cards are melted down for stars, and stars open these. Three boxes
# so the choice is real: bank a cheap one now, or hold out for odds that can
# actually finish a Hard set. Tier indexes CHEST_STAR_WEIGHTS, so a Treasure
# Vault draws on exactly the same table the paid Magical Chest does -- the
# money buys the shortcut, not the ceiling.
const CARD_BOXES := [
	{"id": "box_s", "name": "Driftwood Box", "sub": "2 cards", "emoji": "\U0001F4E6", "stars": 12, "cards": 2, "tier": 0,
	 "color": Color(0.72, 0.5, 0.3), "art_tint": Color(0.74, 0.62, 0.52)},
	{"id": "box_m", "name": "Brass Coffer", "sub": "4 cards \u2014 better odds", "emoji": "\U0001F9F0", "stars": 40, "cards": 4, "tier": 1,
	 "color": Color(1.0, 0.78, 0.25), "art_tint": Color(1.0, 1.0, 1.0)},
	{"id": "box_l", "name": "Treasure Vault", "sub": "6 cards \u2014 5\u2605 guaranteed", "emoji": "\U0001F52E", "stars": 110, "cards": 6, "tier": 2,
	 "color": Color(0.72, 0.45, 1.0), "guarantee5": true, "art_tint": Color(0.82, 0.64, 1.0)},
]

const COLLECTION_SEASON_DAYS := 30
# Collections pay in spins and nothing else. Coins are what a spin produces,
# so paying coins for a month of collecting handed the player the output and
# skipped the machine; spins hand back the thing that makes everything else
# happen -- raids, cards, buildings -- and send them straight to the reels.
const COLLECTION_MEGA_SPINS := 3000
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
	 "reward_spins": 60,
	 "items": [["🐚", "Seashell", 1], ["🦀", "Crab", 1], ["⛱️", "Umbrella", 1], ["🍦", "Ice Cream", 2], ["🕶️", "Shades", 2], ["🏄", "Surfboard", 3]]},
	{"id": "fruits", "name": "Fruit Basket", "icon": "🧺", "diff": "Easy", "weight": 26,
	 "reward_spins": 100,
	 "items": [["🍎", "Apple", 1], ["🍌", "Banana", 1], ["🍇", "Grapes", 2], ["🍉", "Watermelon", 2], ["🍍", "Pineapple", 3], ["🥝", "Kiwi", 3]]},
	{"id": "pirate", "name": "Pirate Treasure", "icon": "🏴‍☠️", "diff": "Medium", "weight": 17,
	 "reward_spins": 250,
	 "items": [["🗺️", "Old Map", 2], ["🧭", "Compass", 2], ["⚓", "Anchor", 2], ["🦜", "Parrot", 3], ["💰", "Gold Bag", 3], ["🗡️", "Cutlass", 3], ["🛢️", "Rum Barrel", 4], ["☠️", "Jolly Roger", 4]]},
	{"id": "ocean", "name": "Ocean Life", "icon": "🌊", "diff": "Medium", "weight": 13,
	 "reward_spins": 400,
	 "items": [["🐠", "Reef Fish", 2], ["🪸", "Coral", 2], ["🐙", "Octopus", 3], ["🐬", "Dolphin", 3], ["🐢", "Turtle", 3], ["🦈", "Shark", 4], ["🐳", "Whale", 4], ["🦞", "Lobster", 4]]},
	{"id": "relics", "name": "Mystic Relics", "icon": "🔮", "diff": "Hard", "weight": 9,
	 "reward_spins": 1000,
	 "items": [["📿", "Prayer Beads", 3], ["🏺", "Amphora", 3], ["🕯️", "Ritual Candle", 3], ["🗿", "Stone Idol", 4], ["⚱️", "Ancient Urn", 4], ["🪬", "Amulet", 4], ["📜", "Lost Scroll", 4], ["🔮", "Crystal Orb", 5], ["🪄", "Wand", 5], ["🧿", "Evil Eye", 5]]},
	{"id": "royal", "name": "Royal Jewels", "icon": "👑", "diff": "Hard", "weight": 5,
	 "reward_spins": 2000,
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

# The average colour along the very top of a background image. An island page
# hangs its art off the safe area rather than stretching it into the notch, so
# the strip above needs a colour that reads as more of the same sky.
static func bg_top_color(img: Image, fallback: Color) -> Color:
	if img == null:
		return fallback
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return fallback
	var sum := Vector3.ZERO
	var n := 0
	for y in mini(4, h):
		for x in range(0, w, maxi(1, w / 24)):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return fallback
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z)

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

static func island_palette(level: int) -> Dictionary:
	return ISLAND_PALETTES[(level - 1) % ISLAND_PALETTES.size()]

# Reel faces stay bright enough for the symbol art to read, but pick up a
# hint of the island's trim so they don't look pasted in from another game.
static func palette_reel(p: Dictionary) -> Color:
	return Color(1, 0.98, 0.94).lerp(p["accent"], 0.18)

# Ink for text sitting on an accent-colored fill.
static func palette_ink(p: Dictionary) -> Color:
	var a: Color = p["accent"]
	return a.darkened(0.72) if a.get_luminance() > 0.42 else Color(1, 0.97, 0.9)

static func island_building_name(level: int, i: int) -> String:
	return island_theme(level)["buildings"][i]

static func island_building_tex(level: int, i: int) -> Texture2D:
	var idx := (level - 1) % ISLANDS.size()
	var t := tex("res://assets/art/islands/island_%02d/b%d.png" % [idx + 1, i])
	if t == null:
		t = building_tex(BUILDINGS[i]["id"])
	return t

# How big a hut stands at each of its five levels.
#
# Levels used to be a row of stars under an unchanging drawing, which meant a
# raid could take one off a building and the island looked identical -- the
# only evidence was a star that had gone. A hut that grows as it is upgraded
# gives the level a silhouette, so losing one is visible from across the
# screen. Scaled about its own base, so it grows upward out of its footprint
# rather than sinking into the grass.
# The spread is deliberately wide -- a 5\u2605 hut is half again the size of a
# 1\u2605 one. A gentler ladder was tried first and it failed the only test that
# matters: a raid takes a level off, and you could not tell from the island
# that anything had happened.
static func level_scale(level: int) -> float:
	return 0.58 + 0.084 * float(clampi(level, 0, MAX_STAR))

static func island_bg_tex(level: int) -> Texture2D:
	var idx := (level - 1) % ISLANDS.size()
	var t := tex("res://assets/art/islands/island_%02d/bg.png" % (idx + 1))
	if t == null:
		t = bg_tex("village")
	return t

# Coins on the 1.6x-per-island curve, snapped to three significant digits so a
# payout reads as "+660" and "+1.25M" rather than "+655" and "+1,246,151".
static func scaled(base: int, level: int) -> int:
	if base <= 0:
		return 0
	var v: float = base * pow(1.6, level - 1)
	var step := 10.0
	while v / step >= 1000.0:
		step *= 10.0
	return int(round(v / step)) * int(step)

# A fresh rival. Vaults are written in island-1 units like every other coin
# figure in the game and scaled where they are shown or paid out, so a bot is
# worth the same fraction of a building whichever island you meet it on.
#
# `near` is your own island. Rivals cluster within a couple of hops of it: far
# enough apart that the raid screen keeps showing you new scenery, close enough
# that you never sail into somebody whose huts make yours look like a hamlet.
# One rival in six is loaded, which is what makes the search worth watching.
static func new_npc(def: Dictionary, near := 0) -> Dictionary:
	var b := []
	for i in BUILDINGS.size():
		b.append(randi_range(1, 4))
	var home := randi_range(1, ISLANDS.size())
	if near > 0:
		home = clampi(near + randi_range(-2, 2), 1, ISLANDS.size())
	var purse := randi_range(1500, 6000)
	if randf() < 0.17:
		purse = randi_range(9000, 16000)
	return {
		"name": def["name"],
		"emoji": def["emoji"],
		"flag": def.get("flag", "??"),
		"coins": purse,
		"buildings": b,
		"shield": randf() < 0.35,
		"island": home,
	}

# Draws `count` rivals whose names are not already taken. Used to stock the
# pool at boot and to replace anyone you have finished picking clean.
static func draw_rivals(count: int, near: int, taken: Array) -> Array:
	var free := []
	for def in BOT_DEFS:
		if not taken.has(def["name"]):
			free.append(def)
	free.shuffle()
	var out := []
	for i in mini(count, free.size()):
		out.append(new_npc(free[i], near))
	return out

# The face a rival wears in the search, for the flicker before the match lands.
static func bot_face(i: int) -> Dictionary:
	return BOT_DEFS[i % BOT_DEFS.size()]
