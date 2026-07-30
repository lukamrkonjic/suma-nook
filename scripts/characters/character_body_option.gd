class_name CharacterBodyOption
extends Resource
## One complete body choice exposed by the character creator. The appearance
## supplies the mannequin/socket contract while the asset profile supplies the
## shared animation and presentation contract used by PlayerVisual.

@export var option_id := ""
@export var display_name := ""
@export var appearance: CharacterAppearancePreset
@export var asset_profile: PlayerAssetProfile


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if option_id.is_empty():
		errors.append("body option has no option_id")
	if display_name.is_empty():
		errors.append("body option '%s' has no display_name" % option_id)
	if appearance == null:
		errors.append("body option '%s' has no appearance" % option_id)
	else:
		errors.append_array(appearance.validation_errors())
	if asset_profile == null:
		errors.append("body option '%s' has no asset profile" % option_id)
	else:
		errors.append_array(asset_profile.validation_errors())
	if (
		appearance != null
		and appearance.body_profile != null
		and asset_profile != null
		and appearance.body_profile.asset_id != asset_profile.asset_id
	):
		errors.append(
			"body option '%s' appearance/asset ids do not match" % option_id
		)
	return errors
