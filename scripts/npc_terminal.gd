extends CanvasLayer

# The talk on a 1970s terminal across the bottom of the screen (Moonbase
# Alpha's monitors): amber letters of fixed width on black, a header with
# who is speaking, the last lines of the talk, the reply written as it
# comes in behind a blinking block, and the line to type on. Enter asks
# (`asked`), Esc says goodbye (`closed`).

signal asked(text: String)
signal closed

const AMBER := Color(1.0, 0.69, 0.0)
const DIM_AMBER := Color(0.75, 0.5, 0.0)
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.85)
const FONT_SIZE := 18
# Share of the screen's height, from the bottom.
const HEIGHT_SHARE := 0.36
const MARGIN := 24.0
const LINES_KEPT := 8
const BLINK := 0.5
const PLAYER := "TU"

var _lines: Array = []
var _waiting := false
var _blink := 0.0
var _panel: PanelContainer
var _header: Label
var _log: Label
var _typing: LineEdit

func _ready() -> void:
	layer = 20
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Monospace"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme = theme
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0 - HEIGHT_SHARE
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = DIM_AMBER
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	_header = Label.new()
	_header.name = "Header"
	_header.add_theme_color_override("font_color", AMBER)
	column.add_child(_header)
	var rule := ColorRect.new()
	rule.color = DIM_AMBER
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	column.add_child(rule)
	_log = Label.new()
	_log.name = "Log"
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.clip_text = true
	_log.add_theme_color_override("font_color", AMBER)
	column.add_child(_log)
	var row := HBoxContainer.new()
	column.add_child(row)
	var prompt := Label.new()
	prompt.text = "> "
	prompt.add_theme_color_override("font_color", AMBER)
	row.add_child(prompt)
	_typing = LineEdit.new()
	_typing.name = "Input"
	_typing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_typing.max_length = 200
	_typing.caret_blink = true
	_typing.add_theme_color_override("font_color", AMBER)
	_typing.add_theme_color_override("caret_color", AMBER)
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "focus", "read_only"]:
		_typing.add_theme_stylebox_override(state, flat)
	_typing.text_submitted.connect(submit)
	row.add_child(_typing)
	var keys := Label.new()
	keys.text = "INVIO: PARLA    ESC: SALUTA"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.add_theme_color_override("font_color", DIM_AMBER)
	column.add_child(keys)

func _process(delta: float) -> void:
	if not visible:
		return
	_blink = fmod(_blink + delta, BLINK * 2.0)
	_show()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		closed.emit()

# Shown with `label` at the top and `lines` ([who, text]) of earlier talk.
func open(label: String, lines: Array = []) -> void:
	_lines = []
	for line in lines:
		_lines.append([str(line[0]), str(line[1])])
	_trim()
	_header.text = ">> " + label.to_upper()
	_waiting = false
	_typing.text = ""
	_typing.editable = true
	visible = true
	_show()
	_typing.grab_focus()

func close() -> void:
	visible = false
	_typing.release_focus()

func is_open() -> bool:
	return visible

func header_text() -> String:
	return _header.text

func typed_text() -> String:
	return _typing.text

# The talk as text, one "WHO: words" a line (no blinking block).
func log_text() -> String:
	var out := PackedStringArray()
	for line in _lines:
		out.append("%s: %s" % line)
	return "\n".join(out)

# Enter: words typed are asked (not while a reply is awaited).
func submit(text: String) -> void:
	var words := text.strip_edges()
	if words == "" or _waiting:
		return
	_typing.text = ""
	add_line(PLAYER, words)
	asked.emit(words)

func add_line(who: String, text: String) -> void:
	_lines.append([who.to_upper(), text])
	_trim()
	_show()

# A reply begins: an empty line of `who`'s, filled by append().
func begin_reply(who: String) -> void:
	add_line(who, "")

func append(text: String) -> void:
	if _lines.is_empty():
		return
	_lines[-1][1] += text
	_show()

func replace_reply(text: String) -> void:
	if _lines.is_empty():
		return
	_lines[-1][1] = text
	_show()

# A reply on its way: the block blinks, Enter waits.
func set_waiting(waiting: bool) -> void:
	_waiting = waiting
	_typing.editable = not waiting
	if not waiting and visible:
		_typing.grab_focus()
	_show()

func show_error(text: String) -> void:
	add_line("ERRORE", text)

func _trim() -> void:
	if _lines.size() > LINES_KEPT:
		_lines = _lines.slice(_lines.size() - LINES_KEPT)

func _show() -> void:
	if _log == null:
		return
	var cursor := "█" if _waiting and _blink < BLINK else ""
	_log.text = log_text() + cursor
