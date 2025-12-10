# AIのべりすとAPI通信クラス
extends Node
class_name AINovelAPI

signal response_received(text: String)
signal error_occurred(message: String)

const API_URL = "https://api.tringpt.com/api"

var api_key: String = ""
var http_request: HTTPRequest
var system_prompt: String = ""
var teacher_name: String = "カナタ"

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# APIキーを読み込み
	_load_api_key()

func _load_api_key():
	# .envファイルから読み込み（デスクトップ版用）
	var env_file = FileAccess.open("res://.env", FileAccess.READ)
	if env_file:
		while not env_file.eof_reached():
			var line = env_file.get_line()
			if line.begins_with("VITE_AI_NOVELIST_API_KEY="):
				api_key = line.substr(25)
				break
		env_file.close()
	
	# Web版ではファイルが読めないのでエラーにしない
	if api_key.is_empty():
		print("APIキーが設定されていません。set_api_key()で設定してください。")

func set_api_key(key: String) -> void:
	api_key = key
	print("APIキーが設定されました")

func set_system_prompt(prompt: String) -> void:
	system_prompt = prompt

func set_teacher_name(name: String) -> void:
	teacher_name = name

func generate_text(prompt: String, max_length: int = 500) -> void:
	if api_key.is_empty():
		error_occurred.emit("APIキーが設定されていません")
		return
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	# システムプロンプトとユーザープロンプトを結合
	var full_prompt = ""
	if not system_prompt.is_empty():
		full_prompt = "<|im_start|>マニュアル\n" + system_prompt + "<|im_end|>\n\n"
	full_prompt += prompt
	
	# stoptokensを先生名に基づいて動的生成
	var stop_tokens = teacher_name + "先生「<<|>>[#ユーザー]<<|>>---<<|>>[#"
	
	var body = {
		"text": full_prompt,
		"length": max_length,
		"temperature": 0.8,
		"top_p": 0.9,
		"rep_pen": 1.15,
		"model": "spiko_max",
		"stoptokens": stop_tokens,
	}
	
	var json_body = JSON.stringify(body)
	print("=== SENDING PROMPT ===")
	print(full_prompt.substr(0, 1000) + "...")  # 最初の1000文字だけ表示
	print("======================")
	
	var error = http_request.request(API_URL, headers, HTTPClient.METHOD_POST, json_body)
	
	if error != OK:
		error_occurred.emit("リクエストの送信に失敗しました")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit("通信エラーが発生しました")
		return
	
	if response_code != 200:
		error_occurred.emit("APIエラー: " + str(response_code))
		return
	
	var body_text = body.get_string_from_utf8()
	print("API Response: ", body_text.substr(0, 500))  # デバッグ用
	
	var json = JSON.new()
	var parse_result = json.parse(body_text)
	
	if parse_result != OK:
		error_occurred.emit("JSONパースエラー")
		return
	
	var data = json.get_data()
	
	# レスポンス形式を確認してテキストを抽出
	var response_text = ""
	
	if typeof(data) == TYPE_DICTIONARY:
		# { "data": {...} } 形式
		if data.has("data"):
			var data_field = data["data"]
			if typeof(data_field) == TYPE_ARRAY and data_field.size() > 0:
				response_text = str(data_field[0])
			elif typeof(data_field) == TYPE_DICTIONARY:
				# {"0": "text"} 形式
				if data_field.has("0"):
					response_text = str(data_field["0"])
				elif data_field.size() > 0:
					response_text = str(data_field.values()[0])
			elif typeof(data_field) == TYPE_STRING:
				response_text = data_field
		# { "text": "..." } 形式
		elif data.has("text"):
			response_text = str(data["text"])
		# { "output": "..." } 形式
		elif data.has("output"):
			response_text = str(data["output"])
		# { "result": "..." } 形式
		elif data.has("result"):
			response_text = str(data["result"])
		# その他の場合は最初の値を使用
		else:
			for key in data.keys():
				if typeof(data[key]) == TYPE_STRING:
					response_text = data[key]
					break
	elif typeof(data) == TYPE_STRING:
		response_text = data
	elif typeof(data) == TYPE_ARRAY and data.size() > 0:
		response_text = str(data[0])
	
	if response_text.is_empty():
		error_occurred.emit("応答データが空です")
		print("Full response data: ", data)
	else:
		response_received.emit(response_text)
