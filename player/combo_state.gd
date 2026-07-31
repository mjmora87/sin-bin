extends RefCounted
class_name ComboState

const MAX_HITS := 3

var current_hit: int = 0
var window_remaining: float = 0.0

func register_attack_press(combo_window_sec: float) -> int:
	if current_hit == 0 or current_hit >= MAX_HITS or window_remaining <= 0.0:
		current_hit = 1
	else:
		current_hit += 1
	window_remaining = combo_window_sec
	return current_hit

func tick(delta: float) -> void:
	if window_remaining > 0.0:
		window_remaining -= delta
		if window_remaining <= 0.0:
			window_remaining = 0.0
			current_hit = 0

func is_finisher() -> bool:
	return current_hit == MAX_HITS

func reset() -> void:
	current_hit = 0
	window_remaining = 0.0
