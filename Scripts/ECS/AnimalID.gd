class_name AnimalID
extends RefCounted

const INVALID: int = 0
const PART_MASK: int = 0xFFFFFFFF

# Pack an unsigned slot and nonzero life serial into a signed 64-bit identity.
# e.g. make(3, 7) returns 12884901895.
static func make(slot: int, uid: int) -> int:
	if slot < 0 or slot > PART_MASK or uid <= 0 or uid > PART_MASK:
		push_error("AnimalID requires a 32-bit slot and nonzero 32-bit life serial.")
		return INVALID

	return (slot << 32) | uid

# Extract the unsigned slot without depending on the identity's sign.
# e.g. get_slot(make(0xFFFFFFFF, 7)) returns 0xFFFFFFFF.
static func get_slot(id: int) -> int:
	return (id >> 32) & PART_MASK

# Check the identity format; storage separately checks ownership and life state.
# e.g. is_valid(INVALID) returns false, while is_valid(make(3, 7)) returns true.
static func is_valid(id: int) -> bool:
	return (id & PART_MASK) != 0
