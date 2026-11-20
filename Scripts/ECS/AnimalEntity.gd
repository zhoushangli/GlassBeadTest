class_name AnimalEntity
extends RefCounted

enum Kind { SHEEP, WOLF, SHEEPDOG }
enum Behavior { FLOCK, ALERT, HERDED, FLEE, SEARCH, STALK, CHASE, PATROL, COLLECT, DRIVE, RETURN, REST, RETREAT, DEAD }

enum Strategy { FRONTAL, SIDE, REAR, HOWL }

const BEHAVIOR_NAMES := [
	"Flock", "Alert", "Herded", "Flee", "Search", "Stalk", "Chase",
	"Patrol", "Collect", "Drive off", "Return", "Rest", "Retreat", "Dead"
]
const KIND_NAMES := ["Sheep", "Wolf", "Sheepdog"]

const STRATEGY_NAMES := ["Frontal", "Side", "Rear", "Howl"]

var id: int = AnimalID.INVALID

# Track the current data row; only storage lifecycle code updates it.
# e.g. a row swap preserves id while updating row.
var row: int = -1

var enabled: bool:
	get:
		return g_gameplayEngine.data_service.animals.live(self) != null
