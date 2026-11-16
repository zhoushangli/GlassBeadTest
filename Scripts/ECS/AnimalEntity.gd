class_name AnimalEntity
extends RefCounted

enum Kind { SHEEP, WOLF, SHEEPDOG }
enum Behavior { FLOCK, ALERT, HERDED, FLEE, SEARCH, STALK, CHASE, PATROL, COLLECT, DRIVE, RETURN, REST, RETREAT, DEAD }

const BEHAVIOR_NAMES := [
	"Flock", "Alert", "Herded", "Flee", "Search", "Stalk", "Chase",
	"Patrol", "Collect", "Drive off", "Return", "Rest", "Retreat", "Dead"
]
const KIND_NAMES := ["Sheep", "Wolf", "Sheepdog"]

enum Strategy { FRONTAL, SIDE, REAR, HOWL }
const STRATEGY_NAMES := ["Frontal", "Side", "Rear", "Howl"]

var slot: int = -1
var uid: int = 0
# Track the current data row; only storage lifecycle code updates it.
# e.g. a row swap preserves slot and uid while updating row.
var row: int = -1
var enabled: bool:
	get:
		return g_gameplayEngine.entity_service.data.live(self) != null
