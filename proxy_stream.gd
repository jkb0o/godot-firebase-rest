extends Reference

signal event(name, data)

var stream
var path
var prefix_length = 0

static func create(path, stream):
	var stream_path = stream.path.substr(0, stream.path.length()-5) # omit .json
	#print("creating proxy stream for ", path, " from ", stream_path)
	assert(path.begins_with(stream_path))
	var ps = new()
	ps.path = path.substr(stream_path.length(), path.length())
	ps.stream = stream
	ps.prefix_length = path.length() - stream_path.length()
	stream.connect("event", ps, "on_stream_event")
	return ps
	
func on_stream_event(name, data):
	#print("stream event ", path, ": ", data)
	if !data["path"].begins_with(path):
		return
	var new_data = {}
	new_data.parse_json(data.to_json())
	new_data["path"] = new_data["path"].substr(prefix_length, new_data["path"].length())
	#print("proxy.on_stream_event(", name, ", ", data, ")")
	emit_signal("event", name, new_data)
