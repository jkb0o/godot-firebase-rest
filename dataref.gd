extends Node

const Stream = preload("stream.gd")

var db
var path
#var parent setget set_parent, get_parent
var key
var emitter

func get_parent():
	if !path:
		return null
	else:
		return db.get_ref(path.substr(0, path.length()-key.length()-1))

func on(event="value", target=null, method=null, args=[], flags=0):
	var emmiter = get_emitter()
	if event == "value":
		var cached = db.read_cache(path)
		if cached != null:
			emitter.call_deferred("emit_signal", "value", cached)
	if target == null:
		return emitter
	emitter.connect(event, target, method, args, flags)
	return emitter

func once():
	return db.rest.GET(path)
func off(target=null):
	if target == null:
		if emitter:
			emitter = null
			firebase.dispose_stream(path)
	elif emitter:
		for sig_conf in emitter.get_signal_list():
			for conf in emitter.get_signal_connection_list(sig_conf["name"]):
				if conf["target"] == target:
					emitter.disconnect(sig_conf["name"], target, conf["method"])
	
func has_emitter():
	return emitter != null
func get_emitter(once=false):
	if emitter:
		return emitter
	emitter = Emitter.new()
	var stream = db.get_stream(path)
	stream.connect("event", self, "_on_event", [emitter])
	return emitter
	
func get_cached():
	return db.read_cache(path)
	
func provide_value_cached(p_args):
	var args = ["value", "some_cached_value"]
	for a in p_args:
		args.append(a)
	emitter.callv("emit_signal", args)

func _on_event(name, data, emitter):
	print("[", path, "] DataRef.event(", name, ", ", data, ", ", emitter)
	if name == "put":
		var data_path = path + data["path"]
		var cache = firebase.read_cache(data_path)
		if data["path"] == "/" || !data["path"] :
			firebase.write_cache(path, data["data"])
			emitter.emit_signal("value", data["data"])
			#print("emitting value")
		if data["data"] == null:
			# removed
			pass
		elif cache == null:
			var ref = firebase.get_ref(data_path)
			firebase.write_cache(data_path, data["data"])
			emitter.emit_signal("child_added", ref)
			#print("emitting child added ", data_path)
		else:
			var changes = expand_dict(data["path"], data["data"])
			changes = firebase.get_cache_diff(path, changes)
			#print("emitting child changed ", changes.any(), ":",changes.data)
			if changes.any():
				firebase.call_deferred("update_cache", path, changes.data)
				emitter.emit_signal("child_changed", changes.data)
	elif name == "patch":
		var data_path = data["path"].substr(1, data["path"].length())
		#print("patching ", data["path"])
		#var cache = firebase.read_cache(path + "/" + data_path)
		#if cache == null:
		#	print("want emit child_added ")
		#firebase.update_cache(path + "/" + data_path, data["data"])
		
		#var changes = _flat_changes(data["data"])
		#for key in changes.keys():
		#	var p = key
		#	if data_path:
		#		p = data_path + "/" + key
		#	print(path, " child changed ", p, " -> ", changes[key])
		#var data = {}
		#for key in data["data"].keys():
		#	data[data_path + "/" + key] = data["data"][key]
		var patch = unflat(data["data"])
		if data_path:
			patch = {data_path:patch}
		emitter.emit_signal("child_changed", patch)

# convert {a/b:c, x/y:z} to {a:{b:c}, x:{y:z}}
func unflat(dict):
	var unflat = {}
	for key in dict.keys():
		if key.find("/") >= 0:
			var root = unflat
			var parts = Array(key.split("/"))
			while parts.size() > 1:
				if !root.has(parts[0]):
					root[parts[0]] = {}
				root = root[parts[0]]
				parts.pop_front()
			root[parts[0]] = dict[key]
		else:
			unflat[key] = dict[key]
	return unflat
			
func is_self_event(data):
	#print(data)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if !data.has("data"):
		return false
	data = data["data"]
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if !data.has("@session"):
		return false
	return data["@session"] == db.session_id

func _flat_changes(dict):
	var changes = {}
	for key in dict.keys():
		if typeof(dict[key]) == TYPE_DICTIONARY:
			var flat = _flat_changes(dict[key])
			for ch in flat.keys():
				changes[key+"/"+ch]=flat[ch]
		else:
			changes[key] = dict[key]
	return changes
	
func expand_dict(path, value):
	while path.begins_with("/"):
		path = path.substr(1, path.length())
	if !path:
		return value
	var result = {}
	var dict = result
	var keys = Array(path.split("/"))
	while keys.size():
		var key = keys[0]
		keys.pop_front()
		if keys.size():
			dict[key] = {}
			dict = dict[key]
		else:
			dict[key] = value
	return result
	
static func create(db, path):
	var ref = new()
	ref.path = path
	ref.key = path.substr(path.rfind("/")+1, path.length())
	ref.db = db
	return ref

func get_cache():
	return db.read_cache(path)
func child(p):
	if p.begins_with("/"):
		p = p.substr(1, p.length())
	if !path:
		return db.get_ref("/"+p)
	else:
		#print("get child(", p, ") -> ", path+"/"+p)
		return db.get_ref(path + "/" + p)
		

func update(data):
	var changes = db.get_cache_diff(path, data)
	if !changes.any():
		return
	db.call_deferred("update_cache", path, changes.data)
	var parent = get_parent()
	var p = "/" + key
	while parent:
		#print("parent path: ", parent.path)
		if db.streams.has(parent.path) && db.streams[parent.path] extends Stream:
			#print("simulating put ", {"path":p,"data":changes.data})
			#var data = {}
			#for key in changes.data:
			#	data[p.substr(1,p.length())+"/"+key] = changes.data[key]
			db.streams[parent.path].emit_signal("event", "patch", {"path":p,"data":changes.data})
		p = "/" + parent.key + p
		parent = parent.get_parent()
		#for k in changes.data.keys():
		#	changes.data[key+"/"+k] = changes.data[k]
	return db.rest.PATCH(path, data)
	
func push(data=null):
	return db.rest.push(path, data)
	
func delete():
	db.write_cache(path, null)
	db.rest.DELETE(path)
	
func put(data):
	if typeof(data) == TYPE_DICTIONARY && data.has(".sv"):
		return db.rest.PUT(path, data)
	var changes = db.get_cache_diff(path, data)
	if !changes.any():
		return
	db.call_deferred("update_cache", path, changes.data)
	var parent = get_parent()
	var p = "/" + key
	while parent:
		if db.streams.has(parent.path) && db.streams[parent.path] extends Stream:
			db.streams[parent.path].emit_signal("event", "put", {"path":p,"data":changes.data})
		p = "/" + parent.key + p
		parent = parent.get_parent()

	return db.rest.PUT(path, data)

class Emitter:
	extends Reference
	signal value(value)
	signal child_changed(path, value)
	signal child_added(dataref)
	signal value_requested(extra_args)
	
	func ___connect(sig, obj, method, args=[], flags=0):
		.connect(sig, obj, method, args, flags)
		if sig == "value":
			emit_signal("value_requested", args)