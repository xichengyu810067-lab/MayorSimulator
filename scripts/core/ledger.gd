extends RefCounted

## The only object allowed to mutate treasury balance. Every mutation creates
## an auditable entry tied to a DomainEvent sequence and a reason tag.

var _balance: int = 0
var _entries: Array[Dictionary] = []


func _init(opening_balance: int = 0, opening_game_time: int = 0) -> void:
	if opening_balance != 0:
		post(0, opening_game_time, opening_balance, "opening_balance", "city", {"category": "opening"}, true)


func get_balance() -> int:
	return _balance


func get_entries() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		copy.append(entry.duplicate(true))
	return copy


func can_post(amount: int, allow_overdraft: bool = false) -> bool:
	return allow_overdraft or amount >= 0 or _balance + amount >= 0


func post(
		event_sequence: int,
		game_time: int,
		amount: int,
		reason_tag: String,
		source_id: String = "city",
		metadata: Dictionary = {},
		allow_overdraft: bool = false
) -> Dictionary:
	if not can_post(amount, allow_overdraft):
		return {}
	_balance += amount
	var entry := {
		"entry_id": "ledger_%010d" % _entries.size(),
		"event_sequence": event_sequence,
		"game_time": game_time,
		"amount": amount,
		"balance_after": _balance,
		"reason_tag": reason_tag if not reason_tag.is_empty() else "unspecified",
		"source_id": source_id,
		"metadata": metadata.duplicate(true),
	}
	_entries.append(entry)
	return entry.duplicate(true)


func verify_balance() -> bool:
	var calculated := 0
	for entry: Dictionary in _entries:
		calculated += int(entry.get("amount", 0))
	return calculated == _balance


func to_dict() -> Dictionary:
	return {
		"balance": _balance,
		"entries": get_entries(),
	}


static func from_dict(data: Dictionary):
	var ledger = new()
	ledger._balance = int(data.get("balance", 0))
	ledger._entries.clear()
	for raw_entry: Variant in data.get("entries", []):
		if raw_entry is Dictionary:
			ledger._entries.append((raw_entry as Dictionary).duplicate(true))
	if not ledger.verify_balance():
		push_error("Ledger snapshot failed balance verification.")
		return null
	return ledger
