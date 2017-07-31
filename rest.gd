extends Node

const DataRef = preload("dataref.gd")
const METHODS = {
	0:"GET",
	1:"HEAD",
	2:"POST",
	3:"PUT",
	4:"DELETE",
	5:"OPTIONS",
	6:"TRACE",
	7:"CONNECT",
	8:"MAX"
}

var client
var db
var tasks = []
var complete = []
var worker

func start(db):
	self.db = db
	db.add_child(self)
	#worker = Thread.new()
	#worker.start(self, "serve")
	call_deferred("serve")
	call_deferred("serve_complete")
	
func serve_complete():
	while true:
		if !complete.size():
			yield(db, "frame")
			continue
		var task = complete[0]
		complete.pop_front()
		task.emit_signal("ready")

signal reconnected
func reconnect():
	if client.get_status() == HTTPClient.STATUS_CONNECTED:
		return call_deferred("emit_signal", "reconnected")
	while !db.host:
		yield(get_tree(), "idle_frame")
	var err = client.connect(db.host, 443, true, true)
	assert(err == OK)
	while client.get_status() == HTTPClient.STATUS_CONNECTING || client.get_status() == HTTPClient.STATUS_RESOLVING:
		if !is_inside_tree():
			return
		yield(get_tree(), "idle_frame")
		client.poll()
		continue
	call_deferred("emit_signal", "reconnected")
		
func serve(a=null):
	while is_inside_tree():
		while !tasks.size():
			yield(get_tree(), "idle_frame")
			if !is_inside_tree():
				return
		client = HTTPClient.new()
		call_deferred("reconnect")
		yield(self, "reconnected")
		
		var task = tasks[0]
		tasks.pop_front()
		print("fb.rest >>> [", task.method_str, "] ", task.path + ".json")
		print("fb.rest >>> ", task.body)
		var err = client.request(task.method, "/" + task.path + ".json", task.headers, task.body)
		if err != OK:
			client.close()
			yield(db.wait(3), "timeout")
			print("fb.rest >>> error while processing request, code: " + str(err) + ", retry in 3 sec")
			continue
		while !client.has_response():
			yield(get_tree(), "idle_frame")
			client.poll()
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			yield(get_tree(), "idle_frame")
			client.poll()	
		var code = client.get_response_code()

			
		var size
		var body
		client.poll()
		yield(get_tree(), "idle_frame")
		if client.get_status() == HTTPClient.STATUS_BODY:
			size = client.get_response_body_length()
			body = client.read_response_body_chunk()
		#print("fb.rest <<< [", code, "] ", body.get_string_from_utf8())
			while body.size() < size:
				body.append_array(client.read_response_body_chunk())
				yield(get_tree(), "idle_frame")
				client.poll()
			task.resp = body.get_string_from_utf8()
		if client.get_response_code() == 200:
			complete.append(task)
			
		
		
		
		

func write(path, data):
	pass
	
func GET(path):
	var task = Task.create("get", path)
	#var task = Task.new()
	#task.method = HTTPClient.METHOD_GET
	#task.headers = []
	#task.body = ""
	#task.path = path
	tasks.append(task)
	task.connect("ready", self, "on_get", [task], CONNECT_ONESHOT)
	return task
	
func on_get(task):
	var json = {}
	json.parse_json(task.resp)
	firebase.write_cache(task.path, json)
	task.emit_signal("value", json)
	
func PUT(path, data):
	firebase.write_cache(path, data)
	var ref = firebase.get_ref(path)
	if ref.has_emitter():
		ref.get_emitter().emit_signal("value", data)
	var task = Task.create("put", path, data)
	task.connect("ready", self, "on_put", [task], CONNECT_ONESHOT)
	tasks.append(task)
	return task
	
func on_put(task):
	pass
	
func DELETE(path):
	var task = Task.create("delete", path)
	tasks.append(task)
	
	
func PATCH(path, value):
	#firebase.update_cache(path, value)
	var task = Task.create("patch", path, value)
	#var task = Task.new()
	#task.method = HTTPClient.METHOD_POST
	#task.headers = ["X-HTTP-Method-Override: PATCH"]
	#task.body = encode_json(value)
	#task.path = path
	tasks.append(task)
	task.connect("ready", self, "on_patch", [task], CONNECT_ONESHOT)
	
func on_patch(task):
	pass
	#var json = {}
	#json.parse_json(task.resp)
	#task.emit_signal("complete", json)
	
func push(path, data=null):
	var task = Task.create("push", path, data)
	tasks.append(task)
	task.connect("ready", self, "on_push", [task, data], CONNECT_ONESHOT)
	return task

func on_push(task, data):
	var json = {}
	json.parse_json(task.resp)
	var ref = firebase.get_ref(task.path + "/" + json["name"])
	firebase.write_cache(ref.path, data)
	task.emit_signal("complete", ref)
	var child = null
	while ref != null:
		if ref.has_emitter():
			if child == null:
				#print("emitting value with ", data)
				ref.get_emitter().emit_signal("value", data)
			else:
				#print("emitting child_added")
				ref.get_emitter().emit_signal("child_added", child)
		data = {ref.key:data}
		child = ref
		ref = ref.get_parent()

	
	
	
	
class Task:
	extends Reference
	signal ready
	signal complete(result)
	signal value(result)
	var method
	var method_str
	var path
	var headers
	var args
	var body
	var resp
	var json_resp setget set_json_resp, get_json_resp
	func get_json_resp():
		if !json_resp:
			json_resp = deconde_json(resp)
		return json_resp
	func set_json_resp(value):
		json_resp = value
	
	static func create(api_method, path, data=null):
		var t = new()
		t.headers = []
		if api_method == "put" || api_method == "patch":
			if typeof(data) == TYPE_DICTIONARY:
					if !data.has(".sv"):
						data["@session"] = firebase.session()
			else:
				var key = path.get_file()
				path = path.get_base_dir()
				data = {"@session": firebase.session(), key: data}
				api_method = "patch"
		elif api_method == "push" && !path.begins_with("@sessions"):
			if data == null:
				data = {}
			data["@session"] = firebase.session_id
		
		if api_method == "get":
			t.method = HTTPClient.METHOD_GET
			t.method_str = "GET"
		elif api_method == "put":
			t.method = HTTPClient.METHOD_PUT
			t.method_str = "PUT"
		elif api_method == "patch":
			t.method = HTTPClient.METHOD_POST
			t.method_str = "PATCH"
			t.headers.append("X-HTTP-Method-Override: PATCH")
		elif api_method == "push":
			t.method = HTTPClient.METHOD_POST
			t.method_str = "POST"
		elif api_method == "delete":
			t.method = HTTPClient.METHOD_DELETE
			t.method_str = "DELETE"
		
		t.path = path
		if api_method == "get" || api_method == "delete":
			t.body = ""
		elif api_method == "patch":
			#print("flat: ", data, " => ", flattern(data))
			t.body = encode_json(flattern(data))
		else:
			t.body = encode_json(data)
		return t
		
	static func encode_json(data):
		var json = ""
		if typeof(data) == TYPE_DICTIONARY:
			json = data.to_json()
		else:
			json = {"d":data}.to_json()
			json = json.substr(5, json.length()-6)
		return json
	static func decode_json(string):
		if !string.begins_with("{"):
			if string.is_valid_float():
				return float(string)
			elif string.is_valid_integer():
				return int(string)
			else:
				return string
		var json = {}
		json.parse_json(string)
		return json
	# convert {a:{b:c},x:{y:z}} to {a/b:c,x/y:z}
	static func flattern(dict, prefix=""):
		var flat = {}
		for key in dict.keys():
			var path = key
			if prefix:
				path = prefix + "/" + path
			var value = dict[key]
			if typeof(value) == TYPE_DICTIONARY:
				var subflat = flattern(value, path)
				for k in subflat.keys():
					flat[k] = subflat[k]
			else:
				flat[path] = value
		return flat
					
			
			
