extends SceneTree
## Run once when changing controller bindings, then commit the generated .tres.
func _initialize() -> void:
	var action_map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "gameplay"
	action_set.localized_name = "Déplacements"
	action_map.add_action_set(action_set)
	var actions := {}
	for entry in [["move", 2], ["jump", 0], ["reset", 0], ["sprint", 0], ["grip", 3], ["quality", 0], ["aim", 3], ["web_fire", 1], ["web_reel", 1], ["haptic", 4]]:
		var action := OpenXRAction.new()
		action.resource_name = entry[0]
		action.localized_name = entry[0]
		action.action_type = entry[1]
		action.toplevel_paths = PackedStringArray(["/user/hand/left", "/user/hand/right"])
		action_set.add_action(action)
		actions[entry[0]] = action
	var profile := OpenXRInteractionProfile.new()
	profile.interaction_profile_path = "/interaction_profiles/oculus/touch_controller"
	for side in ["left", "right"]:
		for entry in [["move", "thumbstick"], ["grip", "grip/pose"], ["aim", "aim/pose"], ["web_fire", "trigger/value"], ["web_reel", "squeeze/value"]]:
			_bind(profile, actions[entry[0]], "/user/hand/%s/input/%s" % [side, entry[1]])
		_bind(profile, actions.haptic, "/user/hand/%s/output/haptic" % side)
	_bind(profile, actions.jump, "/user/hand/right/input/a/click")
	_bind(profile, actions.reset, "/user/hand/right/input/b/click")
	_bind(profile, actions.sprint, "/user/hand/left/input/thumbstick/click")
	_bind(profile, actions.quality, "/user/hand/left/input/y/click")
	action_map.add_interaction_profile(profile)
	var result := ResourceSaver.save(action_map, "res://config/openxr_action_map.tres")
	quit(result)

func _bind(profile: OpenXRInteractionProfile, action: OpenXRAction, path: String) -> void:
	var binding := OpenXRIPBinding.new()
	binding.action = action
	binding.binding_path = path
	profile.bindings.append(binding)
