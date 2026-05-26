extends Control

# ============================================================
#  常量 & 难度预设
# ============================================================
const CELL_SIZE = 30

var ROWS = 9
var COLS = 9
var MINES = 10

const DIFFICULTY_PRESETS = {
	"初级 9x9":    {"rows": 9,  "cols": 9,  "mines": 10},
	"中级 16x16":  {"rows": 16, "cols": 16, "mines": 40},
	"高级 30x16":  {"rows": 16, "cols": 30, "mines": 99},
}

# ============================================================
#  核心数据：5 张二维网格图
#    buttons   — 网格按钮引用
#    mine_map  — 地雷位置 (0/1)
#    number_map — 数字(-1=雷, 0~8)
#    revealed  — 揭开状态
#    flagged   — 旗子标记
# ============================================================
var buttons = []
var mine_map = []
var number_map = []
var revealed = []
var flagged = []

# ============================================================
#  运行时状态
# ============================================================
var game_over = false
var game_started = false
var timer = 0.0
var assist_mode = false

# ============================================================
#  场景节点引用
# ============================================================
@onready var grid = $VBoxContainer/Grid
@onready var mine_label = $VBoxContainer/HBoxContainer/MineLabel
@onready var time_label = $VBoxContainer/HBoxContainer/TimeLabel
@onready var reset_button = $VBoxContainer/HBoxContainer/ResetButton
@onready var difficulty_menu = $DifficultyMenu

# ============================================================
#  初始化 — 建立菜单、连接信号、开始新游戏
# ============================================================
func _ready():
	grid.columns = COLS
	reset_button.pressed.connect(new_game)
	reset_button.gui_input.connect(_on_reset_button_gui_input)

	var diff_submenu = PopupMenu.new()
	diff_submenu.name = "DifficultySubmenu"
	diff_submenu.add_item("初级 9x9", 0)
	diff_submenu.add_item("中级 16x16", 1)
	diff_submenu.add_item("高级 30x16", 2)
	diff_submenu.id_pressed.connect(_on_difficulty_selected)
	difficulty_menu.add_child(diff_submenu)

	difficulty_menu.add_item("难度选择", 0)
	difficulty_menu.set_item_submenu(0, "DifficultySubmenu")
	difficulty_menu.add_check_item("辅助模式", 1)
	difficulty_menu.add_item("（敬请期待）", 2)
	difficulty_menu.set_item_disabled(2, true)
	difficulty_menu.id_pressed.connect(_on_menu_item_pressed)

	new_game()

# ============================================================
#  新游戏 — 重置所有数据、重新布雷并生成界面
# ============================================================
func new_game():
	game_over = false
	game_started = false
	timer = 0.0

	for child in grid.get_children():
		child.queue_free()

	buttons = []
	mine_map = []
	number_map = []
	revealed = []
	flagged = []

	for i in range(ROWS):
		mine_map.append([])
		number_map.append([])
		revealed.append([])
		flagged.append([])
		for j in range(COLS):
			mine_map[i].append(0)
			number_map[i].append(0)
			revealed[i].append(false)
			flagged[i].append(false)

	place_mines()
	calculate_numbers()
	print_mine_map()
	create_buttons()
	update_ui_labels()

# ============================================================
#  布雷 — 随机放置 MINES 颗地雷
# ============================================================
func place_mines():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var count = 0
	while count < MINES:
		var row = rng.randi_range(0, ROWS - 1)
		var col = rng.randi_range(0, COLS - 1)
		if mine_map[row][col] == 0:
			mine_map[row][col] = 1
			count += 1

# ============================================================
#  首点保护 — 移除点击区域 3×3 内的地雷并重新分配到远处
# ============================================================
func ensure_safe_first_click(safe_row: int, safe_col: int):
	var mines_removed = 0
	for i in range(ROWS):
		for j in range(COLS):
			if abs(i - safe_row) <= 1 and abs(j - safe_col) <= 1:
				if mine_map[i][j] == 1:
					mine_map[i][j] = 0
					mines_removed += 1

	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var placed = 0
	while placed < mines_removed:
		var row = rng.randi_range(0, ROWS - 1)
		var col = rng.randi_range(0, COLS - 1)
		if not (abs(row - safe_row) <= 1 and abs(col - safe_col) <= 1) and mine_map[row][col] == 0:
			mine_map[row][col] = 1
			placed += 1

	calculate_numbers()
	print_mine_map()

# ============================================================
#  数字计算 — 每格统计周围 3×3 内的地雷数
# ============================================================
func calculate_numbers():
	for i in range(ROWS):
		for j in range(COLS):
			if mine_map[i][j] == 1:
				number_map[i][j] = -1
				continue
			var count = 0
			for di in [-1, 0, 1]:
				for dj in [-1, 0, 1]:
					var ni = i + di
					var nj = j + dj
					if ni >= 0 and ni < ROWS and nj >= 0 and nj < COLS:
						if mine_map[ni][nj] == 1:
							count += 1
			number_map[i][j] = count

# ============================================================
#  按钮生成 — 创建网格按钮并绑定输入事件
# ============================================================
func create_buttons():
	buttons.clear()
	for i in range(ROWS):
		buttons.append([])
		for j in range(COLS):
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			btn.text = ""
			btn.focus_mode = Control.FOCUS_NONE
			btn.gui_input.connect(_on_gui_input.bind(i, j))
			grid.add_child(btn)
			buttons[i].append(btn)

# ============================================================
#  交互入口 — 左键揭开/快速揭露，右键插旗
# ============================================================
func _on_gui_input(event: InputEvent, row: int, col: int):
	if game_over:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_flag(row, col)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if revealed[row][col]:
				quick_reveal(row, col)
			elif not flagged[row][col]:
				if not game_started:
					ensure_safe_first_click(row, col)
					game_started = true
				reveal_cell(row, col)
			check_victory()
			auto_flag_check()
			update_ui_labels()

# ============================================================
#  插旗 / 取消插旗
# ============================================================
func toggle_flag(row: int, col: int):
	if revealed[row][col]:
		return
	flagged[row][col] = not flagged[row][col]
	var btn = buttons[row][col]
	btn.text = "🚩" if flagged[row][col] else ""
	update_ui_labels()

# ============================================================
#  揭开核心 — 递归展开空白区，踩雷则结束游戏
# ============================================================
func reveal_cell(row: int, col: int):
	if revealed[row][col] or flagged[row][col]:
		return
	revealed[row][col] = true
	var btn = buttons[row][col]
	btn.disabled = true
	btn.text = ""

	if number_map[row][col] == -1:
		btn.text = "💣"
		game_over = true
		show_all_mines()
		return

	var number = number_map[row][col]
	if number > 0:
		btn.text = str(number)
	else:
		for di in [-1, 0, 1]:
			for dj in [-1, 0, 1]:
				var ni = row + di
				var nj = col + dj
				if ni >= 0 and ni < ROWS and nj >= 0 and nj < COLS:
					reveal_cell(ni, nj)

# ============================================================
#  快速揭露 — 旗数与数字匹配时揭开周围所有未标旗格子
# ============================================================
func quick_reveal(row: int, col: int):
	if not revealed[row][col] or number_map[row][col] <= 0:
		return
	var flag_count = count_adjacent_flags(row, col)
	if flag_count == number_map[row][col]:
		reveal_adjacent_cells(row, col)
		check_victory()

func count_adjacent_flags(row: int, col: int) -> int:
	var count = 0
	for di in [-1, 0, 1]:
		for dj in [-1, 0, 1]:
			if di == 0 and dj == 0:
				continue
			var ni = row + di
			var nj = col + dj
			if ni >= 0 and ni < ROWS and nj >= 0 and nj < COLS:
				if flagged[ni][nj]:
					count += 1
	return count

func reveal_adjacent_cells(row: int, col: int):
	for di in [-1, 0, 1]:
		for dj in [-1, 0, 1]:
			if di == 0 and dj == 0:
				continue
			var ni = row + di
			var nj = col + dj
			if ni >= 0 and ni < ROWS and nj >= 0 and nj < COLS:
				if not revealed[ni][nj] and not flagged[ni][nj]:
					reveal_cell(ni, nj)

# ============================================================
#  失败处理 — 显示所有地雷，标记误标旗
# ============================================================
func show_all_mines():
	for i in range(ROWS):
		for j in range(COLS):
			if mine_map[i][j] == 1:
				var btn = buttons[i][j]
				btn.disabled = true
				if not flagged[i][j]:
					btn.text = "💣"
			elif flagged[i][j] and mine_map[i][j] == 0:
				buttons[i][j].text = "❌"

# ============================================================
#  胜利判定 — 所有非雷格均已揭开即获胜
# ============================================================
func check_victory():
	if game_over:
		return
	var unrevealed_non_mines = 0
	for i in range(ROWS):
		for j in range(COLS):
			if not revealed[i][j] and mine_map[i][j] == 0:
				unrevealed_non_mines += 1
	if unrevealed_non_mines == 0:
		game_over = true
		for i in range(ROWS):
			for j in range(COLS):
				if mine_map[i][j] == 1:
					buttons[i][j].disabled = true
					buttons[i][j].text = "🚩"
		print("你赢了！")

# ============================================================
#  右键菜单 — 弹出难度/功能菜单
# ============================================================
func _on_reset_button_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			difficulty_menu.position = reset_button.get_screen_position() + Vector2(0, reset_button.size.y)
			difficulty_menu.popup()

# ============================================================
#  菜单项处理 — 切换辅助模式开关
# ============================================================
func _on_menu_item_pressed(id: int):
	if id == 1:
		assist_mode = not assist_mode
		difficulty_menu.set_item_checked(1, assist_mode)

# ============================================================
#  难度切换 — 根据选中预设重置网格尺寸与雷数
# ============================================================
func _on_difficulty_selected(id: int):
	var preset_names = DIFFICULTY_PRESETS.keys()
	if id < 0 or id >= preset_names.size():
		return
	var preset = DIFFICULTY_PRESETS[preset_names[id]]
	ROWS = preset["rows"]
	COLS = preset["cols"]
	MINES = preset["mines"]
	grid.columns = COLS
	new_game()

# ============================================================
#  辅助模式 — 扫描已揭开的数字，若全部未揭开格数 == 数字
#  则这些格必然都是地雷，自动标旗
# ============================================================
func auto_flag_check():
	if not assist_mode:
		return
	for i in range(ROWS):
		for j in range(COLS):
			if not revealed[i][j] or number_map[i][j] <= 0:
				continue
			var num = number_map[i][j]
			var unrevealed = []
			for di in [-1, 0, 1]:
				for dj in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var ni = i + di
					var nj = j + dj
					if ni >= 0 and ni < ROWS and nj >= 0 and nj < COLS:
						if not revealed[ni][nj]:
							unrevealed.append([ni, nj])
			if unrevealed.size() == num:
				for cell in unrevealed:
					var r = cell[0]
					var c = cell[1]
					if not flagged[r][c]:
						flagged[r][c] = true
						buttons[r][c].text = "🚩"

# ============================================================
#  UI 刷新 — 更新地雷计数 & 计时器
# ============================================================
func update_ui_labels():
	var flagged_count = 0
	for i in range(ROWS):
		for j in range(COLS):
			if flagged[i][j]:
				flagged_count += 1
	mine_label.text = "💣 %d" % (MINES - flagged_count)
	time_label.text = "⏱ %d" % int(timer)

func _process(delta):
	if game_started and not game_over:
		timer += delta
		update_ui_labels()

# ============================================================
#  调试 — 在控制台打印地雷位置棋盘
# ============================================================
func print_mine_map():
	print("地雷位置地图（* = 地雷，. = 安全）：")
	for i in range(ROWS):
		var row_str = ""
		for j in range(COLS):
			row_str += "* " if mine_map[i][j] == 1 else ". "
		print(row_str)
	print()
