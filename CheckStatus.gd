# 確認事項の状態管理
extends Resource
class_name CheckStatus

enum Status { UNCHECKED, PASS, VIOLATION }

@export var upper_body: Status = Status.UNCHECKED
@export var upper_body_detail: String = ""

@export var lower_body: Status = Status.UNCHECKED
@export var lower_body_detail: String = ""

@export var belongings: Status = Status.UNCHECKED
@export var belongings_detail: String = ""

@export var genitals: Status = Status.UNCHECKED
@export var genitals_detail: String = ""

func get_status_text(status: Status) -> String:
	match status:
		Status.UNCHECKED:
			return "未確認"
		Status.PASS:
			return "合格"
		Status.VIOLATION:
			return "校則違反"
	return ""

func has_any_violation() -> bool:
	return upper_body == Status.VIOLATION or \
		   lower_body == Status.VIOLATION or \
		   belongings == Status.VIOLATION or \
		   genitals == Status.VIOLATION

func has_any_unchecked() -> bool:
	return upper_body == Status.UNCHECKED or \
		   lower_body == Status.UNCHECKED or \
		   belongings == Status.UNCHECKED or \
		   genitals == Status.UNCHECKED

func is_all_pass() -> bool:
	return upper_body == Status.PASS and \
		   lower_body == Status.PASS and \
		   belongings == Status.PASS and \
		   genitals == Status.PASS

func format_for_display(teacher_name: String, bag_type: String) -> String:
	var text = "# 確認事項\n"
	text += "－ 上半身：%s（%s）\n" % [get_status_text(upper_body), upper_body_detail if upper_body_detail else "未確認"]
	text += "－ 下半身：%s（%s）\n" % [get_status_text(lower_body), lower_body_detail if lower_body_detail else "未確認"]
	
	if belongings == Status.UNCHECKED:
		text += "－ 持ち物：未確認（%sを確認してください）\n" % bag_type
	else:
		text += "－ 持ち物：%s（%s）\n" % [get_status_text(belongings), belongings_detail]
	
	if genitals == Status.UNCHECKED:
		text += "－ 女性器：未確認（女性器を確認してください）\n"
	else:
		text += "－ 女性器：%s（%s）\n" % [get_status_text(genitals), genitals_detail]
	
	text += "%s先生はどうしますか？" % teacher_name
	return text
