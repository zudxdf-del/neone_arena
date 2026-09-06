extends Node
class_name NeonNetwork

signal message_received(data)
signal connected
signal disconnected
signal failed(reason)

const DEFAULT_URL := "wss://neone-arena.layero.app"
var url := DEFAULT_URL
var socket := WebSocketPeer.new()
var connected_once := false

func connect_to_server(target_url: String = DEFAULT_URL) -> void:
    url = target_url
    socket = WebSocketPeer.new()
    var err := socket.connect_to_url(url)
    if err != OK:
        failed.emit("Не удалось открыть WebSocket: %s" % err)

func _process(_delta: float) -> void:
    socket.poll()
    var state := socket.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if not connected_once:
            connected_once = true
            connected.emit()
        while socket.get_available_packet_count() > 0:
            var text := socket.get_packet().get_string_from_utf8()
            var json = JSON.parse_string(text)
            if json is Dictionary:
                message_received.emit(json)
    elif state == WebSocketPeer.STATE_CLOSED and connected_once:
        connected_once = false
        disconnected.emit()

func send_message(data: Dictionary) -> void:
    if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        socket.send_text(JSON.stringify(data))

func close() -> void:
    socket.close()
