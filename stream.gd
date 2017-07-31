extends Reference

signal event(name, data)

var host
var path
var firebase
var client = HTTPClient.new()
var worker = null
var message_queue = []

func begin(firebase, host, path):
	self.host = host
	self.path = path
	self.firebase = firebase
	#client = HTTPClient.new()
	call_deferred("_begin", host, path)
	
func _begin(host, path):
	print("Connecting to ", host, "/", path)
	var err = client.connect(host, 443, true, true)
	client.set_blocking_mode(false)
	while (client.get_status() == HTTPClient.STATUS_CONNECTING || client.get_status() == HTTPClient.STATUS_RESOLVING):
		client.poll()
		yield(firebase, "frame")
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		yield(firebase.wait(3), "timeout")
		return call_deferred("_begin", host, path)
	var err = client.request(HTTPClient.METHOD_GET, "/" + path, ["Accept: text/event-stream"])
	
	if err != OK:
		yield(firebase.wait(5), "timeout")
		return call_deferred("_begin", host, path)
	while !client.has_response():
		yield(firebase, "frame")
		client.poll()
		
	var code = client.get_response_code()
	var headers = client.get_response_headers_as_dictionary()
	if client.get_response_code() == HTTPClient.RESPONSE_TEMPORARY_REDIRECT:
		var url = headers["Location"]
		url = url.replace("https://", "")
		var delim = url.find("/")
		var new_host = url.substr(0, delim)
		var new_path = url.substr(delim, url.length())
		client.close()
		while client.get_status() != HTTPClient.STATUS_DISCONNECTED:
			yield(firebase, "frame")
			client.poll()
		call_deferred("_begin", new_host, new_path)
		return
	
	worker = Thread.new()
	worker.start(self, "surve")
	while worker.is_active():
		if !message_queue.size():
			yield(firebase, "frame")
			continue
		var attrs = message_queue[0]
		message_queue.pop_front()
		if !is_self_event(attrs[1]):
			emit_signal("event", attrs[0], attrs[1])
		else:
			print("stream won't emit self event")
	call_deferred("_begin", host, path)

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
	return data["@session"].begins_with(firebase.session_id)
	
func surve(p):	
	var stream = client.get_connection()
	while true:
		
		var event = ""
		var c = stream.get_utf8_string(1)
		while c != "\n":											# event: put\n
			event += c
			c = stream.get_utf8_string(1)
		#print("fb.strm [", path, "] <<< ", event)
		var data = ""
		c = stream.get_utf8_string(1)
		while c != "\n":											# data: { path: "/name", value: "bob" }\n
			data += c
			c = stream.get_utf8_string(1)
		#print("fb.strm [", path, "] <<< ", data)
		stream.get_utf8_string(1) 						# \n
		#print("fb.strm [", path, "] <<< \\n")
		event = event.substr(7, event.length())
		data = data.substr(6, data.length())
		if event == "keep-alive":
			continue
		var json = {}
		if data == "null":
			json = null
		else:
			json.parse_json(data)
		#if json != null:
			#json["path"] = path.replace(".json", "/"+json["path"].substr(1,json["path"].length()))
		message_queue.append([event, json])