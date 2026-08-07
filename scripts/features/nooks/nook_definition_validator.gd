class_name NookDefinitionValidator
extends RefCounted
## Content contract for the Unfolding World. Stamps reference palette slots,
## biomes resolve slots to real tile/structure IDs, treasure tables reference
## real reward pools, and every discovery definition points at content that
## exists. Dangling references are hard errors so a bad edit can never
## partially publish.

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)
const EDGE_LABELS := [
	"land", "water", "water_in", "water_out", "path", "any",
]
const DENSITY_BANDS := ["open", "seeded", "grown"]


static func validate(snapshot, issues: Array) -> void:
	_validate_biomes(snapshot, issues)
	_validate_stamps(snapshot, issues)
	_validate_moods(snapshot, issues)
	_validate_treasure_tables(snapshot, issues)
	_validate_firsts(snapshot, issues)
	_validate_dormants(snapshot, issues)
	_validate_moments(snapshot, issues)


static func _validate_biomes(snapshot, issues: Array) -> void:
	for biome in snapshot.nook_biomes.values():
		var source = snapshot.source("nook_biomes", biome.id)
		if not biome.resolve.has("ground"):
			_error(
				issues, "nook.biome.ground", source, "resolve",
				"biome '%s' must resolve the 'ground' slot" % biome.id
			)
		for slot: String in biome.resolve:
			var pool = biome.resolve[slot]
			if pool.is_empty():
				_error(
					issues, "nook.biome.slot.empty", source, "resolve.%s" % slot,
					"biome '%s' slot '%s' resolves to nothing" % [biome.id, slot]
				)
			for content_id: String in pool.ids:
				if not snapshot.tiles.has(content_id) \
					and not snapshot.structures.has(content_id):
					_error(
						issues, "nook.biome.slot.missing", source,
						"resolve.%s" % slot,
						"biome '%s' slot '%s' references unknown content '%s'"
						% [biome.id, slot, content_id]
					)
		for band: String in DENSITY_BANDS:
			if not biome.density.has(band):
				_error(
					issues, "nook.biome.density", source, "density",
					"biome '%s' is missing density band '%s'" % [biome.id, band]
				)
		for mood_id: String in biome.mood_ids:
			if not snapshot.nook_moods.has(mood_id):
				_error(
					issues, "nook.biome.mood.missing", source, "moods",
					"biome '%s' references unknown mood '%s'" % [biome.id, mood_id]
				)
		for band: String in biome.treasure_tables:
			var table_id: String = biome.treasure_tables[band]
			if not snapshot.treasure_tables.has(table_id):
				_error(
					issues, "nook.biome.treasure.missing", source,
					"treasure_tables.%s" % band,
					"biome '%s' references unknown treasure table '%s'"
					% [biome.id, table_id]
				)
		for slot_name: String in biome.scatter.ids:
			if not biome.resolve.has(slot_name):
				_error(
					issues, "nook.biome.scatter.slot", source, "scatter",
					"biome '%s' scatters unresolved slot '%s'"
					% [biome.id, slot_name]
				)


static func _validate_stamps(snapshot, issues: Array) -> void:
	for stamp in snapshot.nook_stamps.values():
		var source = snapshot.source("nook_stamps", stamp.id)
		if stamp.rows.size() != stamp.size.y:
			_error(
				issues, "nook.stamp.rows", source, "rows",
				"stamp '%s' declares height %d but has %d rows"
				% [stamp.id, stamp.size.y, stamp.rows.size()]
			)
		for row_index in stamp.rows.size():
			if stamp.rows[row_index].length() != stamp.size.x:
				_error(
					issues, "nook.stamp.row.width", source,
					"rows[%d]" % row_index,
					"stamp '%s' row %d width != declared %d"
					% [stamp.id, row_index, stamp.size.x]
				)
			for key in stamp.rows[row_index]:
				if key != "." and not stamp.legend.has(key):
					_error(
						issues, "nook.stamp.legend.missing", source,
						"rows[%d]" % row_index,
						"stamp '%s' uses legend key '%s' that is not declared"
						% [stamp.id, key]
					)
		for side: String in stamp.edges:
			if not EDGE_LABELS.has(stamp.edges[side]):
				_error(
					issues, "nook.stamp.edge.label", source, "edges.%s" % side,
					"stamp '%s' edge '%s' has unknown label '%s'"
					% [stamp.id, side, stamp.edges[side]]
				)
		for biome_id: String in stamp.biome_ids:
			if not snapshot.nook_biomes.has(biome_id):
				_error(
					issues, "nook.stamp.biome.missing", source, "biomes",
					"stamp '%s' references unknown biome '%s'"
					% [stamp.id, biome_id]
				)
			else:
				var biome = snapshot.nook_biomes[biome_id]
				for slot: Variant in stamp.legend.values():
					if String(slot) != "" and not biome.resolve.has(String(slot)):
						_error(
							issues, "nook.stamp.slot.unresolved", source, "legend",
							"stamp '%s' slot '%s' is not resolved by biome '%s'"
							% [stamp.id, String(slot), biome_id]
						)
				for feature: Dictionary in stamp.features:
					var slot_name := String(feature.get("slot", ""))
					if not biome.resolve.has(slot_name):
						_error(
							issues, "nook.stamp.feature.slot", source, "features",
							"stamp '%s' feature slot '%s' is not resolved by biome '%s'"
							% [stamp.id, slot_name, biome_id]
						)
		for feature: Dictionary in stamp.features:
			var cell: Vector2i = feature.get("cell", Vector2i.ZERO)
			if cell.x < 0 or cell.x >= stamp.size.x \
				or cell.y < 0 or cell.y >= stamp.size.y:
				_error(
					issues, "nook.stamp.feature.bounds", source, "features",
					"stamp '%s' feature cell %s is outside the stamp"
					% [stamp.id, cell]
				)
		if stamp.dormant_socket and (
			stamp.dormant_cell.x < 0 or stamp.dormant_cell.x >= stamp.size.x
			or stamp.dormant_cell.y < 0 or stamp.dormant_cell.y >= stamp.size.y
		):
			_error(
				issues, "nook.stamp.dormant.bounds", source, "dormant_cell",
				"stamp '%s' dormant cell %s is outside the stamp"
				% [stamp.id, stamp.dormant_cell]
			)


static func _validate_moods(snapshot, issues: Array) -> void:
	for mood in snapshot.nook_moods.values():
		var source = snapshot.source("nook_moods", mood.id)
		if mood.weather == "":
			_error(
				issues, "nook.mood.weather", source, "weather",
				"mood '%s' must name a weather state" % mood.id
			)


static func _validate_treasure_tables(snapshot, issues: Array) -> void:
	for table in snapshot.treasure_tables.values():
		var source = snapshot.source("treasure_tables", table.id)
		if table.slots.is_empty():
			_error(
				issues, "nook.treasure.slots.empty", source, "slots",
				"treasure table '%s' has no slots" % table.id
			)
		for index in table.slots.size():
			var slot: Dictionary = table.slots[index]
			var pool_id := String(slot.get("pool", ""))
			if pool_id == "" or not snapshot.reward_pools.has(pool_id):
				_error(
					issues, "nook.treasure.pool.missing", source,
					"slots[%d]" % index,
					"treasure table '%s' references unknown reward pool '%s'"
					% [table.id, pool_id]
				)
			if float(slot.get("chance", 0.0)) <= 0.0 \
				and int(slot.get("guaranteed", 0)) <= 0:
				_error(
					issues, "nook.treasure.slot.dead", source,
					"slots[%d]" % index,
					"treasure table '%s' slot %d can never place anything"
					% [table.id, index]
				)


static func _validate_firsts(snapshot, issues: Array) -> void:
	for first in snapshot.firsts.values():
		var source = snapshot.source("firsts", first.id)
		if first.signal_name == "":
			_error(
				issues, "nook.first.signal", source, "signal",
				"first '%s' must listen to a world signal" % first.id
			)
		if not ["chunk", "world"].has(first.scope):
			_error(
				issues, "nook.first.scope", source, "scope",
				"first '%s' has unknown scope '%s'" % [first.id, first.scope]
			)
		for sid: String in first.unlock_structures:
			if not snapshot.structures.has(sid):
				_error(
					issues, "nook.first.unlock.missing", source,
					"unlock_structures",
					"first '%s' unlocks unknown structure '%s'" % [first.id, sid]
				)
		for tid: String in first.unlock_tiles:
			if not snapshot.tiles.has(tid):
				_error(
					issues, "nook.first.unlock.missing", source, "unlock_tiles",
					"first '%s' unlocks unknown tile '%s'" % [first.id, tid]
				)


static func _validate_dormants(snapshot, issues: Array) -> void:
	for dormant in snapshot.dormants.values():
		var source = snapshot.source("dormants", dormant.id)
		if dormant.structure_id == "" \
			or not snapshot.structures.has(dormant.structure_id):
			_error(
				issues, "nook.dormant.structure.missing", source, "structure",
				"dormant '%s' references unknown structure '%s'"
				% [dormant.id, dormant.structure_id]
			)
		if dormant.woken_structure_id != "" \
			and not snapshot.structures.has(dormant.woken_structure_id):
			_error(
				issues, "nook.dormant.woken.missing", source, "woken_structure",
				"dormant '%s' references unknown woken structure '%s'"
				% [dormant.id, dormant.woken_structure_id]
			)
		if dormant.reward_pool_id != "" \
			and not snapshot.reward_pools.has(dormant.reward_pool_id):
			_error(
				issues, "nook.dormant.pool.missing", source, "reward_pool",
				"dormant '%s' references unknown reward pool '%s'"
				% [dormant.id, dormant.reward_pool_id]
			)


static func _validate_moments(snapshot, issues: Array) -> void:
	for moment in snapshot.moments.values():
		var source = snapshot.source("moments", moment.id)
		if not ["counter", "cooccurrence"].has(moment.kind):
			_error(
				issues, "nook.moment.kind", source, "kind",
				"moment '%s' has unknown kind '%s'" % [moment.id, moment.kind]
			)
		if moment.kind == "counter" and moment.signal_name == "":
			_error(
				issues, "nook.moment.signal", source, "signal",
				"counter moment '%s' must count a world signal" % moment.id
			)
		if moment.kind == "cooccurrence" and moment.conditions.is_empty():
			_error(
				issues, "nook.moment.conditions", source, "conditions",
				"cooccurrence moment '%s' has no conditions" % moment.id
			)
		if moment.keepsake_structure_id != "" \
			and not snapshot.structures.has(moment.keepsake_structure_id):
			_error(
				issues, "nook.moment.keepsake.missing", source,
				"keepsake_structure",
				"moment '%s' references unknown structure '%s'"
				% [moment.id, moment.keepsake_structure_id]
			)


static func _error(
	issues: Array, code: String, source, field: String, message: String
) -> void:
	issues.append(ValidationIssueScript.new(
		ValidationIssueScript.Severity.ERROR, code, source, field, message
	))
