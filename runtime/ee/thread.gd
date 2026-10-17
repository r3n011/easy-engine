# Thread：一段正在执行的脚本。
#
# 关键设计：**用显式的帧栈表示执行位置**，而不是用协程/await。
#
# 为什么不用 await：积木语言必须能在任意让步点被"从外部"暂停、检查、杀死
# （想想「停止这个脚本」「停止全部」），协程做不到这点。scratch-vm 也是这么做的。
#
# 帧（Frame）是一个字典：
#   { ops: Array, idx: int, loop: "", left: 0, cond: Variant, warp: bool }
#   loop = ""       普通顺序执行
#   loop = "repeat" 执行 left 次
#   loop = "forever"永远重复
#   loop = "while"  每次迭代前重算 cond
extends RefCounted

enum Status {
	RUNNING,      # 可以继续执行
	YIELD_TICK,   # 挂起到下一帧
	YIELD_TIME,   # 挂起到某个时刻
	YIELD_UNTIL,  # 挂起到条件成立
	YIELD_THREADS,# 挂起到一组线程结束
	DONE,         # 正常结束
	KILLED,       # 被停止
	ERROR,        # 运行时错误
}

var target                # Target
var frames: Array = []    # 帧栈，最后一个在栈顶
var status := Status.RUNNING
var is_hat := false       # 由事件启动（绿旗/广播/克隆启动）

# 让步信息
var resume_at := 0.0
var wait_cond: Variant = null
var wait_threads: Array = []

# warp（原子执行）：> 0 时循环不再让步
var warp_depth := 0
var warp_started := 0.0

# 统计与保护
var ops_executed := 0
var ops_this_frame := 0
var error_message := ""
var hat_kind := ""
var thread_id := 0

static var _next_id := 0

static func create(p_target, p_frames: Array, p_hat := false) -> RefCounted:
	var t = new()
	_next_id += 1
	t.thread_id = _next_id
	t.target = p_target
	t.frames = p_frames
	t.is_hat = p_hat
	return t


func reset_frame_budget(budget: int) -> void:
	ops_this_frame = 0
	_frame_budget = budget

var _frame_budget := 1000000

func budget_left() -> int:
	return _frame_budget - ops_this_frame

func tick_op() -> void:
	ops_executed += 1
	ops_this_frame += 1

func is_active() -> bool:
	return status == Status.RUNNING or status == Status.YIELD_TICK \
		or status == Status.YIELD_TIME or status == Status.YIELD_UNTIL \
		or status == Status.YIELD_THREADS

func is_done() -> bool:
	return status == Status.DONE or status == Status.KILLED or status == Status.ERROR

# ---- 帧栈操作 ---------------------------------------------------------

func push(frame: Dictionary) -> void:
	frames.append(frame)

func pop() -> void:
	if not frames.is_empty():
		frames.pop_back()

func top() -> Dictionary:
	if frames.is_empty():
		return {}
	return frames[frames.size() - 1]

func depth() -> int:
	return frames.size()

# ---- 让步 -------------------------------------------------------------

func yield_tick() -> void:
	status = Status.YIELD_TICK

func yield_time(at_time: float) -> void:
	status = Status.YIELD_TIME
	resume_at = at_time

func yield_until(cond: Variant) -> void:
	status = Status.YIELD_UNTIL
	wait_cond = cond

func yield_threads(threads: Array) -> void:
	status = Status.YIELD_THREADS
	wait_threads = threads

func resume() -> void:
	status = Status.RUNNING
	wait_cond = null
	wait_threads = []

func finish() -> void:
	status = Status.DONE

func kill() -> void:
	status = Status.KILLED

func fail(msg: String) -> void:
	status = Status.ERROR
	error_message = msg

# ---- warp -------------------------------------------------------------

func enter_warp(now: float) -> void:
	if warp_depth == 0:
		warp_started = now
	warp_depth += 1

func exit_warp() -> void:
	warp_depth = maxi(0, warp_depth - 1)

func in_warp() -> bool:
	return warp_depth > 0

func describe() -> String:
	return "[线程 %d @ %s] 帧深 %d，opus=%d，状态=%d%s" % [
		thread_id, target.describe() if target != null else "?",
		frames.size(), ops_executed, status, " [warp]" if in_warp() else ""]
