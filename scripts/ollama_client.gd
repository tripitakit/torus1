extends Node

# The local Ollama server the people's minds run on (gemma3:1b for the words,
# on the GPU through Vulkan; embeddinggemma for the vectors, on the CPU to
# leave the graphics memory to the game). Started here when it is not up
# (OLLAMA_VULKAN=1 <binary> serve, the binary from the project setting
# torus1/npc/ollama_binary) and stopped on the way out, only if started
# here. Nothing blocks: the chat comes piece by piece (`piece`), then
# `finished(text, error)`, error "" when all went well.

signal piece(text: String)
signal finished(text: String, error: String)

const HOST := "127.0.0.1"
const PORT := 11434
const BINARY_SETTING := "torus1/npc/ollama_binary"
const BINARY_DEFAULT := "~/ollama/bin/ollama"
const CHAT_MODEL := "gemma3:1b"
const EMBED_MODEL := "embeddinggemma"
const KEEP_ALIVE := "30m"
const CHAT_OPTIONS := {"num_predict": 60, "temperature": 0.6}
# Waiting for a server we started.
const START_WAIT := 15.0
const START_POLL := 0.5

var _pid := -1
# Bumped by every new chat and by cancel(): an older chat stops reading.
var _chat_id := 0

func _exit_tree() -> void:
	stop_if_started()

# Up and answering, started if it was not: false when it could not be.
func ensure_running() -> bool:
	if await _alive():
		return true
	if _pid < 0:
		var binary := str(ProjectSettings.get_setting(BINARY_SETTING, BINARY_DEFAULT))
		if binary.begins_with("~"):
			binary = OS.get_environment("HOME") + binary.substr(1)
		# Its output away from the game's (a pipe held open by it would never
		# close); exec keeps the pid ours to stop.
		_pid = OS.create_process("/bin/sh", ["-c", "OLLAMA_VULKAN=1 exec \"$0\" serve >/dev/null 2>&1", binary])
		if _pid <= 0:
			_pid = -1
			return false
	var waited := 0.0
	while waited < START_WAIT:
		await get_tree().create_timer(START_POLL).timeout
		waited += START_POLL
		if await _alive():
			return true
	return false

func started_server() -> bool:
	return _pid >= 0

# The server we started, asked to stop (never one that was already up).
func stop_if_started() -> void:
	if _pid >= 0:
		OS.execute("kill", ["-TERM", str(_pid)])
		_pid = -1

func _alive() -> bool:
	var answer: Array = await _request("/api/version", HTTPClient.METHOD_GET, "", 1.0)
	return answer[0] == 200

# [status code (0 if none), body text].
func _request(path: String, method: int, body: String, timeout: float) -> Array:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var error := http.request("http://%s:%d%s" % [HOST, PORT, path], ["Content-Type: application/json"], method, body)
	if error != OK:
		http.queue_free()
		return [0, ""]
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return [0, ""]
	return [result[1], (result[3] as PackedByteArray).get_string_from_utf8()]

# The vector of `text` (unit long), worded as a search query for
# embeddinggemma; empty when the server failed.
func embed(text: String, as_query: bool = true) -> PackedFloat32Array:
	var input := ("task: search result | query: " if as_query else "title: none | text: ") + text
	var body := JSON.stringify({"model": EMBED_MODEL, "input": [input], "keep_alive": KEEP_ALIVE, "options": {"num_gpu": 0}})
	var answer: Array = await _request("/api/embed", HTTPClient.METHOD_POST, body, 60.0)
	if answer[0] != 200:
		return PackedFloat32Array()
	var data = JSON.parse_string(answer[1])
	if not data is Dictionary or not data.has("embeddings") or (data.embeddings as Array).is_empty():
		return PackedFloat32Array()
	return PackedFloat32Array(data.embeddings[0])

# The model's reply to `messages`, streamed: `piece` for every bit of
# text, then `finished`. A new chat or cancel() drops the one running.
func chat(messages: Array) -> void:
	_chat_id += 1
	_run_chat(messages, _chat_id)

func cancel() -> void:
	_chat_id += 1

func _run_chat(messages: Array, id: int) -> void:
	var http := HTTPClient.new()
	http.connect_to_host(HOST, PORT)
	while http.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		http.poll()
		await get_tree().process_frame
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		_finish(id, "", "connessione rifiutata")
		return
	var body := JSON.stringify({"model": CHAT_MODEL, "messages": messages, "stream": true, "keep_alive": KEEP_ALIVE, "options": CHAT_OPTIONS})
	http.request(HTTPClient.METHOD_POST, "/api/chat", ["Content-Type: application/json"], body)
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await get_tree().process_frame
	if not http.has_response() or http.get_response_code() != 200:
		_finish(id, "", "risposta %d" % http.get_response_code())
		http.close()
		return
	var rest := PackedByteArray()
	var text := ""
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if id != _chat_id:
			http.close()
			return
		if chunk.is_empty():
			await get_tree().process_frame
			continue
		var parsed := parse_lines(rest + chunk)
		rest = parsed[1]
		for line: Dictionary in parsed[0]:
			if line.has("error"):
				_finish(id, text, str(line.error))
				http.close()
				return
			var bit := str((line.get("message", {}) as Dictionary).get("content", ""))
			if bit != "":
				text += bit
				piece.emit(bit)
			if line.get("done", false):
				_finish(id, text, "")
				http.close()
				return
	_finish(id, text, "" if text != "" else "risposta vuota")
	http.close()

func _finish(id: int, text: String, error: String) -> void:
	if id == _chat_id:
		finished.emit(text, error)

# Ollama's stream: one JSON object a line. The whole lines of `buffer`
# parsed, and what is left after the last newline (a line, or a letter's
# bytes, cut between two pieces): [Array of Dictionary, PackedByteArray].
static func parse_lines(buffer: PackedByteArray) -> Array:
	var out := []
	var start := 0
	var end := buffer.find(10, start)
	while end >= 0:
		var data = JSON.parse_string(buffer.slice(start, end).get_string_from_utf8())
		if data is Dictionary:
			out.append(data)
		start = end + 1
		end = buffer.find(10, start)
	return [out, buffer.slice(start)]
