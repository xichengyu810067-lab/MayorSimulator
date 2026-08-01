class_name MayorPopulationRequest
extends RefCounted

## A deterministic resident request. Dialogue is presentation-only; payload drives rules.

const SCHEMA_VERSION := 2
const STATUS_PENDING := "pending"
const STATUS_ACCEPTED := "accepted"
const STATUS_REJECTED := "rejected"
const STATUS_COMPLETED := "completed"

var request_id: String = ""
var npc_id: String = ""
var request_type: String = ""
var title: String = ""
var description: String = ""
var status: String = STATUS_PENDING
var created_day: int = 0
var accepted_day: int = -1
var rejected_day: int = -1
var completed_day: int = -1
var payload: Dictionary = {}


func accept(game_day: int) -> bool:
	if status != STATUS_PENDING:
		return false
	status = STATUS_ACCEPTED
	accepted_day = game_day
	return true


func reject(game_day: int) -> bool:
	if status != STATUS_PENDING:
		return false
	status = STATUS_REJECTED
	rejected_day = game_day
	return true


func complete(game_day: int) -> bool:
	if status != STATUS_ACCEPTED:
		return false
	status = STATUS_COMPLETED
	completed_day = game_day
	return true


func is_active() -> bool:
	return status == STATUS_PENDING or status == STATUS_ACCEPTED


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"request_id": request_id,
		"npc_id": npc_id,
		"request_type": request_type,
		"title": title,
		"description": description,
		"status": status,
		"created_day": created_day,
		"accepted_day": accepted_day,
		"rejected_day": rejected_day,
		"completed_day": completed_day,
		"payload": payload.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var request = new()
	request.request_id = str(data.get("request_id", ""))
	request.npc_id = str(data.get("npc_id", ""))
	request.request_type = str(data.get("request_type", ""))
	request.title = str(data.get("title", ""))
	request.description = str(data.get("description", ""))
	request.status = str(data.get("status", STATUS_PENDING))
	request.created_day = int(data.get("created_day", 0))
	request.accepted_day = int(data.get("accepted_day", -1))
	request.rejected_day = int(data.get("rejected_day", -1))
	request.completed_day = int(data.get("completed_day", -1))
	request.payload = Dictionary(data.get("payload", {})).duplicate(true)
	return request
