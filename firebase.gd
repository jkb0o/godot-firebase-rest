extends Node

signal frame

const Stream = preload("stream.gd")
const ProxyStream = preload("proxy_stream.gd")
const DataRef = preload("dataref.gd")
const Rest = preload("rest.gd")

var rest
var streams = {}
var refs = {}
var host = ""
var root setget set_root, get_root
var cache = {}
var session_id
var request_id = 0

func session():
	request_id += 1
	return session_id+"::"+str(request_id)


func _ready():
	randomize()
	rest = Rest.new()
	get_tree().connect("idle_frame", self, "emit_signal", ["frame"])
	
func wait(time):
	var t = Timer.new()
	add_child(t)
	t.set_wait_time(time)
	t.set_one_shot(true)
	t.connect("timeout", t, "queue_free")
	t.start()
	return t
	
func init(host):
	self.host = host
	rest.start(self)
	
	#var sid_file = "user://session.id"
	#var f = File.new()
	#if f.file_exists(sid_file):
	#	f.open(sid_file, File.READ)
	#	session_id = f.get_as_text()
	#else:
	session_id = gen_session()
	
func set_root(val):
	pass
func get_root():
	return get_ref("/")
	

func gen_session():
	var sid = ""
	for i in range(32):
		sid += "0123456789abcdef"[int(rand_range(0, 16))]
	return sid
	
	
func get_ref(path):
	if refs.has(path):
		return refs[path]
	var ref = DataRef.create(self, path)
	refs[path] = ref
	return ref
	
func write_cache(path, data):
	#print("write cache ", path)
	var keys = Array(path.split("/"))
	var root = cache
	while keys.size() > 1:
		if !root.has(keys[0]) || typeof(root[keys[0]]) != TYPE_DICTIONARY:
			root[keys[0]] = {}
		root = root[keys[0]]
		keys.pop_front()
	if data == null:
		root.erase(keys[0])
	else:
		root[keys[0]] = data
	
func trim_path(path):
	while path.begins_with("/"):
		path = path.substr(1, path.length())
	while path.ends_with("/"):
		path = path.substr(0, path.length()-1)
	return path
	
func update_cache(path, data):
	#print("update cache ", path)
	path = trim_path(path)
	var root = cache
	var changes
	if !path:
		changes = _update_cache(root, data)
	else:
		var keys = Array(path.split("/"))
		while keys.size() > 1:
			if !root.has(keys[0]):
				root[keys[0]] = {}
			root = root[keys[0]]
			keys.pop_front()
		changes = _update_cache(root, {keys[0]:data})
		if changes.has(keys[0]):
			changes = changes[keys[0]]
	return Changes.create(changes)
	
func _update_cache(root, data):
	var changes = {}
	for key in data.keys():
		var value = data[key]
		if !root.has(key):
			root[key] = value
			changes[key] = value
		elif typeof(value) == TYPE_DICTIONARY && typeof(root[key]) == TYPE_DICTIONARY:
			var child_changes = _update_cache(root[key], value)
			if child_changes.size():
				changes[key] = child_changes
		elif typeof(root[key]) != typeof(value) || root[key] != value:
			root[key] = value
			changes[key] = value
	return changes
	
func get_cache_diff(path, data):
	path = trim_path(path)
	var root = cache
	var changes
	if path:
		var keys = Array(path.split("/"))
		while keys.size():
			if root.has(keys[0]):
				root = root[keys[0]]
			else:
				return Changes.create(data)
			keys.pop_front()
	return Changes.create(_get_diff(root, data))
	

func _get_diff(root, data):
	var changes = {}
	if typeof(root) != typeof(data):
		return data
	elif typeof(data) == TYPE_DICTIONARY:
		for key in data.keys():
			if root.has(key):
				var lc = _get_diff(root[key], data[key])
				if lc != null:
					changes[key] = lc
			else:
				changes[key] = data[key]
	elif root != data:
		return data
	if changes.size():
		return changes
	else:
		return null
			
func read_cache(path):
	if path.begins_with("/"):
		path = path.substr(1, path.length())
	if path.ends_with("/"):
		path = path.substr(0, path.length()-1)
	var keys = Array(path.split("/"))
	var root = cache
	while keys.size() > 0:
		#print(keys)
		if root.has(keys[0]):
			root = root[keys[0]]
		else:
			return null
		keys.pop_front()
		if root == null:
			return null
	return root
	
	
func get_stream(path):
	if streams.has(path):
		return streams[path]
	for existed_path in streams.keys():
		if !(streams[existed_path] extends Stream):
			continue
		if path.begins_with(existed_path):
			var proxy = ProxyStream.create(path, streams[existed_path])
			streams[path] = proxy
			proxy.call_deferred("emit_signal", "event", "put", {"path":"/","data":read_cache(path)})
			return proxy
	var stream = Stream.new()
	stream.begin(self, host, path + ".json")
	streams[path] = stream
	return stream

func dispose_stream(path):
	# TODO: respect proxy streams someway
	if streams.has(path):
		streams.erase(path)
			
class Changes:
	extends Reference
	var data
	func any():
		if data == null:
			return false
		elif typeof(data) == TYPE_DICTIONARY:
			return data.size() > 0
		else:
			return true
	static func create(data):
		var changes = new()
		changes.data = data
		return changes