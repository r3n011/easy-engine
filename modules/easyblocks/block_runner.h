/**************************************************************************/
/*  block_runner.h                                                        */
/*  Easy Engine —— 积木运行器（Node）                                       */
/**************************************************************************/

#pragma once

#include "core/io/resource.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "scene/main/node.h"

class BlockProgram;

/**
 * 执行一份积木程序。
 *
 * 它是个 **Node**，挂在场景里。语义照 M2 定稿的那套（一条没改）：
 *   · 显式帧栈（不用协程），所以能被外部暂停/检查/杀掉
 *   · 循环每轮让步；warp 内不让步
 *   · 广播与克隆体后续补上
 */
class BlockRunner : public Node {
	GDCLASS(BlockRunner, Node);

public:
	enum ThreadStatus {
		THREAD_RUNNING,
		THREAD_YIELD_TICK,
		THREAD_YIELD_TIME,
		THREAD_YIELD_UNTIL,
		THREAD_DONE,
		THREAD_KILLED,
		THREAD_ERROR,
	};

private:
	enum LoopKind {
		LOOP_SEQ,
		LOOP_REPEAT,
		LOOP_FOREVER,
		LOOP_WHILE,
		LOOP_WARP,
	};

	struct Frame {
		Array ops;
		int idx = 0;
		int loop = LOOP_SEQ;
		int left = 0;
		Variant cond;
	};

	struct RunnerThread {
		Node *target = nullptr;
		Vector<Frame> frames;
		int status = THREAD_RUNNING;
		double resume_at = 0.0;
		Variant wait_cond;
		ObjectID wait_audio; // 等音频播完（wait until 的一种特例）
		int warp_depth = 0;
		double warp_started = 0.0;
		String error;
		int ops_run = 0;
	};

	Ref<BlockProgram> program;
	String program_json_path;
	NodePath target_path;
	bool auto_start = true;
	bool debug_print = false;

	Vector<RunnerThread *> threads;
	HashMap<String, Variant> globals;
	HashMap<String, Array> global_lists;
	Vector<ObjectID> clones; // 本运行器造出来的克隆体

	double now = 0.0;
	int frame_count = 0;
	Array errors;
	Array warnings;
	bool started = false;
	int trace_count = 0;
	bool warned_list_show = false;

	void _clear_threads();
	RunnerThread *_new_thread(Node *p_target, const Array &p_body);

	void _step(double p_delta);
	void _step_thread(RunnerThread *t);
	void _close_iteration(RunnerThread *t);
	void _loop_yield(RunnerThread *t);

	Variant _exec(RunnerThread *t, const Dictionary &p_op);
	Variant _eval(RunnerThread *t, const Variant &p_v);
	Node *_resolve_target(RunnerThread *t, const Variant &p_ref);

	void _push_seq(RunnerThread *t, const Array &p_ops);
	void _push_loop(RunnerThread *t, int p_kind, const Array &p_ops, int p_count, const Variant &p_cond);
	void _push_warp(RunnerThread *t, const Array &p_ops);

	Variant _get_var(const String &p_name, const String &p_scope, RunnerThread *t);
	void _set_var(const String &p_name, const Variant &p_value, const String &p_scope, RunnerThread *t);
	Array _get_list(const String &p_name, const String &p_scope, RunnerThread *t);
	/** 取列表本体（可修改）。不存在就建一个空的。 */
	Array *_list_ptr(const String &p_name);
	/** Scratch 的下标语义：1 起，支持 last / random / any。 */
	int _list_index(const Variant &p_index, int p_size, bool p_for_insert);

public:
	/** 给编辑器/测试做内省用的只读访问口。 */
	Array get_list_values(const String &p_name) const;
	Variant get_variable(const String &p_name) const;

private:

	void _warn(const String &p_msg);
	void _fail(RunnerThread *t, const String &p_msg);

	// ---- 造型 / 声音 / 克隆 ----
	void _apply_costume(Node *p_target, const String &p_name, const String &p_mode);
	Node *_find_audio(Node *p_target, const String &p_name);
	void _stop_all_sounds(Node *p_target);
	BlockRunner *_find_runner_in(Node *p_node) const;
	int _alive_clones();

	Error _start_impl(bool p_clone_only);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_program(const Ref<BlockProgram> &p_program);
	Ref<BlockProgram> get_program() const;

	void set_program_json_path(const String &p_path);
	String get_program_json_path() const;

	void set_target_path(const NodePath &p_path);
	NodePath get_target_path() const;

	void set_auto_start(bool p_enabled);
	bool is_auto_start() const;

	void set_debug_print(bool p_enabled);
	bool is_debug_print() const;

	/** 启动：编译程序（如需要）并启动所有帽子脚本。 */
	Error start();
	/** 作为克隆体启动：只跑「作为克隆体启动时」的脚本。 */
	int start_clone_hats();
	void stop();

	Array get_errors() const;
	Array get_warnings() const;
	int get_thread_count() const;
	double get_time() const;

	BlockRunner();
	~BlockRunner();
};
