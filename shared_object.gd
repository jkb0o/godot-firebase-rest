extends Reference

signal changed(prop, value)

var _props = {}
var _observers = {}


func _get_mapping():
	return {

	}
	
func get(prop, default):
	pass
	
func set(prop, value):
	pass
	
func observe(scheme):
	if _observers.has("scheme"):
		return
	var o = firebase.get_ref(scheme + id)
	o.on("value", self, "from_dict")
	o.on("child_chaged", self, "from_dict")
	_observers[scheme] = o
	
func ignore(scheme):
	pass
	
func _get_props():
	return {
		"name": ["default", "meta"],
		"avatar/path": { "default": "avatar/path", "meta": "avatar" },
		"avatar/name": "default",
		"squad/size": "default",
		"squad/raws_gap": "default",
		"squad/cols_gap": "default"
	}

func _get_schemes():
	return {
		"default": "config/squads/",
		"meta": "config/squads_meta/"
	}
	
func from_dict(dict, prefix = ""):
	for key in dict.keys():
		var path = key
		if prefix:
			path = prefix + "/" + path
		var value = dict[key]
		if _get_props().has(path):
			_write(path, value)
		elif typeof(value) == TYPE_DICTIONARY:
			from_dict(value, path)
			
static func _new():
	return new()
			
static func create():
	pass
	