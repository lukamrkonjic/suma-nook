class_name FishingSessionStates
extends RefCounted
## The explicit fishing state vocabulary. There is deliberately no FAILED
## state: every completed cast produces a catch, attention only changes speed.

enum State {
	IDLE,
	CASTING,
	WAITING,
	BITE,
	MANUAL_REELING,
	AUTO_REELING,
	REVEALING,
	PAUSED_BASKET_FULL,
}

const NAMES := {
	State.IDLE: "idle",
	State.CASTING: "casting",
	State.WAITING: "waiting",
	State.BITE: "bite",
	State.MANUAL_REELING: "manual_reeling",
	State.AUTO_REELING: "auto_reeling",
	State.REVEALING: "revealing",
	State.PAUSED_BASKET_FULL: "paused_basket_full",
}


static func state_name(state: State) -> String:
	return String(NAMES.get(state, "unknown"))
