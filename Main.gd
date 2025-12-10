# メインゲームロジック
extends Control

enum GamePhase { INTRO, SCENE_A, SCENE_B }

@onready var text_display: TextEdit = $MarginContainer/VBoxContainer/TextPanel/TextEdit
@onready var status_panel: Panel = $MarginContainer/VBoxContainer/StatusPanel
@onready var upper_label: RichTextLabel = $MarginContainer/VBoxContainer/StatusPanel/VBoxContainer/UpperLabel
@onready var lower_label: RichTextLabel = $MarginContainer/VBoxContainer/StatusPanel/VBoxContainer/LowerLabel
@onready var belongings_label: RichTextLabel = $MarginContainer/VBoxContainer/StatusPanel/VBoxContainer/BelongingsLabel
@onready var genitals_label: RichTextLabel = $MarginContainer/VBoxContainer/StatusPanel/VBoxContainer/GenitalsLabel
@onready var input_field: LineEdit = $MarginContainer/VBoxContainer/InputArea/LineEdit
@onready var speak_button: Button = $MarginContainer/VBoxContainer/InputArea/SpeakButton
@onready var next_button: Button = $MarginContainer/VBoxContainer/SelectButtons/NextButton
@onready var settings_button: Button = $MarginContainer/VBoxContainer/SelectButtons/SettingsButton
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/SelectButtons/RefreshButton
@onready var retry_button: Button = $MarginContainer/VBoxContainer/ActionButtons/RetryButton
@onready var undo_button: Button = $MarginContainer/VBoxContainer/ActionButtons/UndoButton
@onready var sync_button: Button = $MarginContainer/VBoxContainer/ActionButtons/SyncButton
@onready var loading_label: Label = $MarginContainer/VBoxContainer/LoadingLabel
@onready var notification_label: Label = $NotificationLabel

var api: AINovelAPI
var prompt_generator: PromptGenerator
var current_student: StudentData
var check_status: CheckStatus
var current_phase: GamePhase = GamePhase.INTRO
var teacher_name: String = "カナタ"
var conversation_history: String = ""
var is_loading: bool = false

# 履歴管理（リトライ・取り消し用）
var display_history: Array = []  # 表示履歴
var last_player_speech: String = ""  # 最後のプレイヤー発言
var last_conversation_history: String = ""  # 最後の会話履歴バックアップ
var last_check_status: CheckStatus  # 最後の確認事項バックアップ

func _ready():
	# APIとプロンプトジェネレーターの初期化
	api = AINovelAPI.new()
	add_child(api)
	api.response_received.connect(_on_api_response)
	api.error_occurred.connect(_on_api_error)
	
	prompt_generator = PromptGenerator.new()
	prompt_generator.set_teacher_name(teacher_name)
	
	if notification_label == null:
		print("ERROR: NotificationLabel is null!")
		# バックアップ策として検索
		notification_label = get_node_or_null("NotificationLabel")
		if notification_label == null:
			print("CRITICAL: NotificationLabel not found in scene tree")
	else:
		print("NotificationLabel found successfully")
	
	# APIにシステムプロンプトと先生名を設定
	api.set_system_prompt(prompt_generator.generate_system_prompt())
	api.set_teacher_name(teacher_name)
	
	# ボタンの接続
	speak_button.pressed.connect(_on_speak_pressed)
	next_button.pressed.connect(_on_next_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	undo_button.pressed.connect(_on_undo_pressed)
	sync_button.pressed.connect(_on_sync_pressed)
	input_field.text_submitted.connect(_on_input_submitted)
	
	# 初期状態
	check_status = CheckStatus.new()
	loading_label.visible = false
	
	# ゲーム開始
	_show_intro()

func _show_intro():
	current_phase = GamePhase.INTRO
	text_display.text = """========== 制服チェックミニゲーム ==========

あなたは学校の先生です。
学校の風紀を守るため、生徒をチェックしましょう！

校則違反はないですか？
ボタンはちゃんと閉めていますか？
スカートは短くないですか？
持ち物は大丈夫？
あぁそれから…女性器もチェックが必要です。

生徒と会話して校則違反を直しましょう！

→「次の生徒へ」ボタンでゲーム開始"""
	_scroll_to_bottom()
	
	_update_status_display()

func _start_new_student(request: String = ""):
	current_phase = GamePhase.SCENE_A
	current_student = StudentData.new()
	check_status = CheckStatus.new()
	conversation_history = ""
	
	_set_loading(true)
	
	var prompt = prompt_generator.generate_scene_a_prompt(request)
	api.generate_text(prompt, 800)  # 十分な長さで生成

func _process_player_speech(speech: String):
	if current_student == null or current_student.student_name.is_empty():
		text_display.text += "\n\n✗ まず生徒を呼んでください"
		return
	
	# バックアップを保存（取り消し用）
	last_player_speech = speech
	last_conversation_history = conversation_history
	last_check_status = check_status.duplicate()
	display_history.append(text_display.text)
	
	current_phase = GamePhase.SCENE_B
	
	# 先生の発言を会話履歴に追加
	conversation_history += "\n%s先生「%s」" % [teacher_name, speech]
	
	# 先生の発言を表示に追加
	text_display.text += "\n\n%s先生「%s」" % [teacher_name, speech]
	
	_set_loading(true)
	
	var prompt = prompt_generator.generate_scene_b_prompt(current_student, check_status, speech, conversation_history)
	print("=== SCENE_B PROMPT ===")
	print(prompt)
	print("======================")
	api.generate_text(prompt, 600)
	_scroll_to_bottom()

func _on_api_response(response: String):
	_set_loading(false)
	
	# 先生のセリフ（改行後に「カナタ先生「」）が含まれているかチェック
	# 「カナタ先生！」などの呼びかけは除外
	var has_teacher_speech = false
	var teacher_speech_pattern = RegEx.new()
	teacher_speech_pattern.compile("\\n\\s*" + teacher_name + "先生「")
	if teacher_speech_pattern.search(response):
		has_teacher_speech = true
	
	# レスポンスを解析
	_parse_response(response)
	
	# 会話履歴に追加（セリフ部分のみを抽出して追加）
	var clean_response = _extract_dialogue_only(response)
	if has_teacher_speech:
		# 先生のセリフ以降を削除
		var match = teacher_speech_pattern.search(clean_response)
		if match:
			clean_response = clean_response.substr(0, match.get_start())
	if not clean_response.is_empty():
		conversation_history += "\n" + clean_response
	
	# 場面Aの場合は生徒情報を表示
	if current_phase == GamePhase.SCENE_A:
		var formatted = _format_scene_a(response)
		text_display.text = formatted
	else:
		# 場面Bは生徒の反応を追加
		var formatted = _format_scene_b(response)
		text_display.text += "\n" + formatted
		
		# 先生のセリフが含まれていた場合はリトライ推奨
		if has_teacher_speech:
			text_display.text += "\n※ AIが先生のセリフを生成しました。リトライをお試しください"
	
	# 確認事項パネルを更新
	_update_status_display()
	_scroll_to_bottom()

func _format_scene_a(response: String) -> String:
	# 場面A: 生徒紹介のフォーマット
	var formatted = "【生徒情報】\n"
	formatted += "・名前：%s\n" % current_student.student_name
	formatted += "・容姿：%s\n" % current_student.appearance
	formatted += "・性格：%s\n" % current_student.personality
	formatted += "\n【会話】\n"
	
	# セリフ部分を抽出
	var speech_part = _extract_speech_part(response)
	formatted += speech_part
	
	return formatted

func _format_scene_b(response: String) -> String:
	# 場面B: 生徒の反応のフォーマット
	var text = response.strip_edges()
	
	# 「がない場合、プロンプトの続き（セリフの中身だけ）なので補完
	if "「" not in text:
		# 生徒名と「」を追加
		var dialogue = text
		# 末尾に」があれば除去（重複防止）
		if dialogue.ends_with("」"):
			dialogue = dialogue.substr(0, dialogue.length() - 1)
		return "\n%s「%s」\n" % [current_student.student_name, dialogue]
	
	return _extract_speech_part(response)

func _extract_speech_part(response: String) -> String:
	# 生徒のセリフ、行動、心の声を抽出してフォーマット
	var result = ""
	
	# まず # ロールプレー 以降の部分を取得
	var roleplay_pos = response.find("# ロールプレー")
	if roleplay_pos == -1:
		roleplay_pos = response.find("#ロールプレー")
	if roleplay_pos == -1:
		roleplay_pos = response.find("# ロールプレイ")
	
	var speech_text = response
	if roleplay_pos >= 0:
		speech_text = response.substr(roleplay_pos + 10)  # "# ロールプレー" の後
	
	# 確認事項より前で切る
	var check_patterns = [
		"# 確認事項", "#確認事項", 
		"- 上半身", "-上半身", "－ 上半身", "－上半身",
		"先生はどうしますか？"
	]
	for pattern in check_patterns:
		var pos = speech_text.find(pattern)
		if pos > 0:
			speech_text = speech_text.substr(0, pos)
			break
	
	# 先生のセリフ以降を削除（改行後の「カナタ先生「」形式のみ）
	var teacher_regex = RegEx.new()
	teacher_regex.compile("\\n\\s*" + teacher_name + "先生「")
	var teacher_match = teacher_regex.search(speech_text)
	if teacher_match:
		speech_text = speech_text.substr(0, teacher_match.get_start())
	
	# セリフを全て抽出（「〜」形式）
	var speech_regex = RegEx.new()
	speech_regex.compile("([^「」\\n]+)「([^」]+)」")
	var speech_matches = speech_regex.search_all(speech_text)
	for speech_match in speech_matches:
		var speaker = speech_match.get_string(1).strip_edges()
		var dialogue = speech_match.get_string(2)
		# 先生の発言は除外
		if "先生" not in speaker:
			# 生徒のフルネームを使用
			var display_name = speaker
			if current_student and not current_student.student_name.is_empty():
				# 1-2文字の短い名前、または名前の一部が含まれている場合はフルネームに置換
				if speaker.length() <= 2:
					display_name = current_student.student_name
				else:
					var student_parts = current_student.student_name.split(" ")
					for part in student_parts:
						if not part.is_empty() and part in speaker:
							display_name = current_student.student_name
							break
			# speakerが空の場合はフルネームを使用
			if display_name.is_empty():
				display_name = current_student.student_name if current_student else "生徒"
			result += "\n%s「%s」\n" % [display_name, dialogue]
	
	# 行動を抽出（（〜）形式）
	var action_regex = RegEx.new()
	action_regex.compile("[（\\(]([^）\\)]+)[）\\)]")
	var action_matches = action_regex.search_all(speech_text)
	for action_match in action_matches:
		var action = action_match.get_string(1)
		result += "（%s）\n" % action
	
	# 心の声を抽出（<〜>形式）
	var thought_regex = RegEx.new()
	thought_regex.compile("[<＜]([^>＞]+)[>＞]")
	var thought_matches = thought_regex.search_all(speech_text)
	for thought_match in thought_matches:
		var thought = thought_match.get_string(1)
		result += "<%s>\n" % thought
	
	# 地の文を抽出（セリフ、行動、心の声以外）
	var narrative_text = speech_text
	# セリフを除去
	narrative_text = speech_regex.sub(narrative_text, "", true)
	# 行動を除去
	narrative_text = action_regex.sub(narrative_text, "", true)
	# 心の声を除去
	narrative_text = thought_regex.sub(narrative_text, "", true)
	# 残りを地の文として追加
	narrative_text = narrative_text.strip_edges()
	if not narrative_text.is_empty() and narrative_text.length() > 5:
		result += "\n%s\n" % narrative_text
	
	if result.is_empty():
		# フォールバック：整形したテキストを表示
		result = speech_text.strip_edges()
	
	return result

func _extract_dialogue_only(response: String) -> String:
	# 会話履歴用：セリフと行動のみを抽出（確認事項や生徒情報は除外）
	var result = ""
	var text = response
	
	# # ロールプレー 以降を取得
	var roleplay_pos = text.find("# ロールプレー")
	if roleplay_pos >= 0:
		text = text.substr(roleplay_pos + 10)
	
	# # 確認事項 より前で切る
	var check_pos = text.find("# 確認事項")
	if check_pos > 0:
		text = text.substr(0, check_pos)
	
	# 「〜」形式のセリフを抽出
	var speech_regex = RegEx.new()
	speech_regex.compile("([^「」\\n]+)「([^」]+)」")
	var matches = speech_regex.search_all(text)
	for m in matches:
		var speaker = m.get_string(1).strip_edges()
		var dialogue = m.get_string(2)
		# 名前が短い場合（2文字以下）は生徒のフルネームに置換
		if current_student and not current_student.student_name.is_empty():
			if speaker.length() <= 2 or "先生" not in speaker:
				var student_parts = current_student.student_name.split(" ")
				for part in student_parts:
					if not part.is_empty() and part in speaker:
						speaker = current_student.student_name
						break
				# それでも2文字以下ならフルネームに
				if speaker.length() <= 2:
					speaker = current_student.student_name
		result += speaker + "「" + dialogue + "」 "
	
	return result.strip_edges()


func _parse_response(response: String):
	# 生徒情報をパース（場面Aの場合）
	if current_phase == GamePhase.SCENE_A:
		print("Parsing SCENE_A response...")
		
		# 新形式: 「－ 名前：〜」形式に対応
		# 名前を抽出
		var name_extracted = _extract_field(response, "名前")
		
		# フィールドとして見つからない場合、最初の行を名前として使用
		if name_extracted.is_empty():
			var lines = response.strip_edges().split("\n")
			if lines.size() > 0:
				name_extracted = lines[0].strip_edges()
				print("Using first line as name: ", name_extracted)
		
		if not name_extracted.is_empty():
			# (17歳)などを除去
			var paren_pos = name_extracted.find("(")
			if paren_pos == -1:
				paren_pos = name_extracted.find("（")
			if paren_pos > 0:
				name_extracted = name_extracted.substr(0, paren_pos)
			current_student.student_name = name_extracted.strip_edges()
			print("Name: ", current_student.student_name)
		
		# 容姿を抽出
		var appearance_extracted = _extract_field(response, "容姿")
		if not appearance_extracted.is_empty():
			current_student.appearance = appearance_extracted
			print("Appearance: ", current_student.appearance)
		
		# 性格を抽出
		var personality_extracted = _extract_field(response, "性格")
		if not personality_extracted.is_empty():
			# # ロールプレー などが続く場合があるので切り詰め
			var hash_pos = personality_extracted.find("#")
			if hash_pos > 0:
				personality_extracted = personality_extracted.substr(0, hash_pos).strip_edges()
			current_student.personality = personality_extracted
			print("Personality: ", current_student.personality)
	
	# 確認事項をパース
	_parse_check_status(response)

func _parse_check_status(response: String):
	# 上半身
	var upper = _extract_check_item(response, "上半身")
	if not upper.is_empty():
		if "合格" in upper:
			check_status.upper_body = CheckStatus.Status.PASS
		elif "校則違反" in upper:
			check_status.upper_body = CheckStatus.Status.VIOLATION
		check_status.upper_body_detail = upper
	
	# 下半身
	var lower = _extract_check_item(response, "下半身")
	if not lower.is_empty():
		if "合格" in lower:
			check_status.lower_body = CheckStatus.Status.PASS
		elif "校則違反" in lower:
			check_status.lower_body = CheckStatus.Status.VIOLATION
		check_status.lower_body_detail = lower
	
	# 持ち物
	var belongings = _extract_check_item(response, "持ち物")
	if not belongings.is_empty():
		if "合格" in belongings:
			check_status.belongings = CheckStatus.Status.PASS
		elif "校則違反" in belongings:
			check_status.belongings = CheckStatus.Status.VIOLATION
		elif "未確認" in belongings:
			check_status.belongings = CheckStatus.Status.UNCHECKED
		check_status.belongings_detail = belongings
	
	# 女性器
	var genitals = _extract_check_item(response, "女性器")
	if not genitals.is_empty():
		if "合格" in genitals:
			check_status.genitals = CheckStatus.Status.PASS
		elif "校則違反" in genitals:
			check_status.genitals = CheckStatus.Status.VIOLATION
		elif "未確認" in genitals:
			check_status.genitals = CheckStatus.Status.UNCHECKED
		check_status.genitals_detail = genitals

func _extract_field(text: String, field_name: String) -> String:
	var regex = RegEx.new()
	
	# パターン1: 「－ 名前：〜」形式（全角ダッシュ）
	regex.compile("－\\s*" + field_name + "[:：]\\s*([^\\n－]+)")
	var result = regex.search(text)
	if result:
		var extracted = result.get_string(1).strip_edges()
		print("Extracted %s (pattern1): %s" % [field_name, extracted])
		return extracted
	
	# パターン2: 「- 名前：〜」形式（半角ダッシュ）
	regex.compile("-\\s*" + field_name + "[:：]\\s*([^\\n-]+)")
	result = regex.search(text)
	if result:
		var extracted = result.get_string(1).strip_edges()
		print("Extracted %s (pattern2): %s" % [field_name, extracted])
		return extracted
	
	# パターン3: 「名前：〜」形式（ダッシュなし）
	regex.compile(field_name + "[:：]\\s*([^\\n]+)")
	result = regex.search(text)
	if result:
		var extracted = result.get_string(1).strip_edges()
		print("Extracted %s (pattern3): %s" % [field_name, extracted])
		return extracted
	
	print("Failed to extract: %s" % field_name)
	return ""

func _extract_check_item(text: String, item_name: String) -> String:
	var regex = RegEx.new()
	
	# パターン1: 「－ 上半身：合格（詳細）」形式
	regex.compile("[-－]\\s*" + item_name + "[:：]\\s*([^－\\-\\n]+)")
	var result = regex.search(text)
	if result:
		var extracted = result.get_string(1).strip_edges()
		print("Extracted %s (pattern1): %s" % [item_name, extracted])
		return extracted
	
	# パターン2: 「上半身:合格」形式（ダッシュなし）
	regex.compile(item_name + "[:：]\\s*([^\\n－\\-]+)")
	result = regex.search(text)
	if result:
		var extracted = result.get_string(1).strip_edges()
		print("Extracted %s (pattern2): %s" % [item_name, extracted])
		return extracted
	
	return ""

func _update_status_display():
	# 詳細情報付きで表示
	var upper_text = _get_status_colored(check_status.upper_body)
	if not check_status.upper_body_detail.is_empty():
		upper_text += " [color=gray](%s)[/color]" % _get_detail_short(check_status.upper_body_detail)
	upper_label.text = "上半身：%s" % upper_text
	
	var lower_text = _get_status_colored(check_status.lower_body)
	if not check_status.lower_body_detail.is_empty():
		lower_text += " [color=gray](%s)[/color]" % _get_detail_short(check_status.lower_body_detail)
	lower_label.text = "下半身：%s" % lower_text
	
	var belongings_text = _get_status_colored(check_status.belongings)
	if not check_status.belongings_detail.is_empty():
		belongings_text += " [color=gray](%s)[/color]" % _get_detail_short(check_status.belongings_detail)
	belongings_label.text = "持ち物：%s" % belongings_text
	
	var genitals_text = _get_status_colored(check_status.genitals)
	if not check_status.genitals_detail.is_empty():
		genitals_text += " [color=gray](%s)[/color]" % _get_detail_short(check_status.genitals_detail)
	genitals_label.text = "女性器：%s" % genitals_text

func _get_detail_short(detail: String) -> String:
	# 詳細情報を短く切り詰め（30文字以内）
	# 合格/校則違反の後の括弧内を抽出
	var start = detail.find("(")
	var end = detail.find(")")
	if start == -1:
		start = detail.find("（")
		end = detail.find("）")
	
	if start >= 0 and end > start:
		var content = detail.substr(start + 1, end - start - 1)
		if content.length() > 30:
			return content.substr(0, 27) + "..."
		return content
	return ""

func _get_status_colored(status: CheckStatus.Status) -> String:
	match status:
		CheckStatus.Status.UNCHECKED:
			return "[color=gray]未確認[/color]"
		CheckStatus.Status.PASS:
			return "[color=green]合格[/color]"
		CheckStatus.Status.VIOLATION:
			return "[color=red]校則違反[/color]"
	return ""

func _set_loading(loading: bool):
	is_loading = loading
	loading_label.visible = loading
	speak_button.disabled = loading
	next_button.disabled = loading
	settings_button.disabled = loading
	refresh_button.disabled = loading
	input_field.editable = not loading

func _on_api_error(message: String):
	_set_loading(false)
	text_display.text += "\n\n✗ エラー: %s" % message
	_scroll_to_bottom()

func _on_speak_pressed():
	if not input_field.text.is_empty():
		_process_player_speech(input_field.text)
		input_field.text = ""

func _on_input_submitted(text: String):
	if not text.is_empty():
		_process_player_speech(text)
		input_field.text = ""

func _on_next_pressed():
	if current_phase == GamePhase.INTRO:
		_start_new_student()
		return
	
	if check_status.is_all_pass():
		text_display.text = "=== ✔ 成功！ ===\n\n全ての確認事項が合格しました。\n次の生徒が来ます..."
	else:
		text_display.text = "=== ✗ 失敗... ===\n\n校則違反が残っています。\n次の生徒が来ます..."
	
	_scroll_to_bottom()
	await get_tree().create_timer(2.0).timeout
	_start_new_student()

func _on_settings_pressed():
	# 設定追加モード
	var dialog = AcceptDialog.new()
	dialog.title = "設定追加"
	dialog.dialog_text = "どのような生徒にしますか？\n（例：真面目なロリっ子、小悪魔系の美少女など）"
	
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "リクエストを入力..."
	dialog.add_child(line_edit)
	
	dialog.confirmed.connect(func():
		if not line_edit.text.is_empty():
			_start_new_student(line_edit.text)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	
	add_child(dialog)
	dialog.popup_centered()

func _on_refresh_pressed():
	if current_student == null or current_student.student_name.is_empty():
		return
	
	_set_loading(true)
	var prompt = prompt_generator.generate_refresh_prompt(current_student, conversation_history)
	api.generate_text(prompt, 600)

func _on_retry_pressed():
	# AIの直前の発言を消して再生成
	if last_player_speech.is_empty():
		text_display.text += "\n\n※ リトライする発言がありません"
		return
	
	if display_history.is_empty():
		return
	
	# 表示を前の状態に戻す
	# 表示を前の状態に戻す
	text_display.text = display_history.pop_back()
	_scroll_to_bottom()
	
	# 会話履歴を復元
	conversation_history = last_conversation_history
	
	# 確認事項を復元
	if last_check_status:
		check_status = last_check_status.duplicate()
		_update_status_display()
	
	# 同じ発言で再生成
	_process_player_speech(last_player_speech)

func _on_undo_pressed():
	# 直前の発言を取り消す（自分とAIの両方）
	if display_history.is_empty():
		text_display.text += "\n\n※ 取り消す発言がありません"
		return
	
	# 表示を前の状態に戻す
	# 表示を前の状態に戻す
	text_display.text = display_history.pop_back()
	_scroll_to_bottom()
	
	# 会話履歴を復元
	if not last_conversation_history.is_empty():
		conversation_history = last_conversation_history
	
	# 確認事項を復元
	if last_check_status:
		check_status = last_check_status.duplicate()
		_update_status_display()
	
	# 最後の発言をクリア
	last_player_speech = ""

func _on_sync_pressed():
	# 編集した内容をAI用履歴に反映
	if current_phase == GamePhase.INTRO:
		show_notification("ゲーム開始前は履歴を反映できません", true)
		return
	
	# text_displayからセリフを抽出
	var display_text = text_display.text
	
	# 【会話】セクション以降を取得
	var conv_pos = display_text.find("【会話】")
	if conv_pos >= 0:
		var conversation_section = display_text.substr(conv_pos + 4)
		
		# 新しい履歴を構築
		var new_history = ""
		
		# 「〜」形式のセリフを抽出
		var speech_regex = RegEx.new()
		speech_regex.compile("([^「」\\n]+)「([^」]+)」")
		var matches = speech_regex.search_all(conversation_section)
		for m in matches:
			var speaker = m.get_string(1).strip_edges()
			var dialogue = m.get_string(2)
			if not speaker.is_empty() and not dialogue.is_empty():
				new_history += speaker + "「" + dialogue + "」\n"
		
		# 履歴を更新
		if not new_history.is_empty():
			conversation_history = new_history.strip_edges()
			show_notification("履歴に反映しました")
			print("=== SYNCED HISTORY ===")
			print(conversation_history)
			print("======================")
		else:
			show_notification("反映するセリフが見つかりませんでした", true)
			# フォールバック：全体を履歴に追加
			conversation_history = display_text.strip_edges()
			show_notification("AIの記憶を更新しました（全体）")
			print("=== SYNCED HISTORY (FULL) ===")
			print(conversation_history)
			print("=============================")

func show_notification(message: String, is_error: bool = false):
	# ノードが取れていない場合の再取得試行
	if notification_label == null:
		notification_label = get_node_or_null("NotificationLabel")
	
	if notification_label == null:
		print("WARNING: NotificationLabel missing, using fallback")
		var prefix = "✗ " if is_error else "✔ "
		text_display.text += "\n\n" + prefix + message
		_scroll_to_bottom()
		return

	notification_label.text = message
	var style = notification_label.get_node("Panel").get_theme_stylebox("panel")
	if style and style is StyleBoxFlat:
		style.bg_color = Color(0.5, 0, 0, 0.8) if is_error else Color(0, 0.5, 0, 0.8)
	
	notification_label.modulate.a = 1.0
	notification_label.visible = true
	
	# アニメーション（フェードアウト）
	# 既存のTweenがあれば停止（簡易的）
	# 新しいTweenを作成
	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(notification_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): notification_label.visible = false)

func _scroll_to_bottom():
	# 少し待ってからスクロール（レイアウト更新待ち）
	await get_tree().process_frame
	text_display.scroll_vertical = text_display.get_line_count()
	# カーソルも末尾へ
	text_display.set_caret_line(text_display.get_line_count())
