About
=====

This is buggy almost certainly endless wip of Google Firebase REST api implementation for Godot. It supports GET/PUT/PATCH/PUSH/DELETE via single http call. It is also support event streaming api.

Instalation
===========

- Download or clone repo into your project.
- Add firebase.tscn to autoload (Project Settings -> Autoload)
- If you didn't setup ssl before, specify path to sertifacte (ca-certificates.crt) at Project Settings -> SSL -> Sertificates
- Init firebase with 
```gdscript
func _ready():
    firebase.init("https://path-to-domain.firebaseio.com")
```

Usage
=====

```gdscript


# get data once
var data = yield(firebase.get_ref("users/ilya").once(), "value")

# push data
var ref = yield(firebase.get_ref("messages").push({"key":"value"}), "complete")
print(ref.key)

# put
var ref = firebase.get_ref("users")
ref.child("ilya").put({"name":"ilya", "color":"white"})

#update
var ref = firebase.get_ref("users/ilya")
ref.update({"color":"black"})

#delete
firebase.get_ref("users/ilya/color").delete()

# subscribe to event stream
func _ready():
    firebase.get_ref("users/ilya").on("value", self, "ilya_changed")
    firebase.get_ref("users/ilya").on("child_changed", self, "ilya_changed")

func ilya_changed(data):
    # only updated data here as far as i know =)
    print(data)

# using server values
var task = firebase.get_ref("servertime").put({".sv":"timestamp"})
yield(task, "complete")
print("Server time: ", task.resp)
```
