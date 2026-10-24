/* ==========================================================================
 * Easy Engine · 积木桥
 *
 * 职责：Scratch 积木工作区  <->  引擎的积木程序 JSON
 *
 * 为什么转换放在网页这边：积木是什么形状、什么字段、什么输入名，
 * 只有 scratch-blocks 自己最清楚。放在这边转换，引擎只要认自己的 JSON。
 *
 * 引擎侧格式（BlockProgram.scripts）：
 *   [ { "top": 积木 }, ... ]
 *   积木 = { "block": "core.xxx",
 *            "inputs": { "ARG": { "value": 字面量 或 子积木 } | { "stack": 积木串 },
 *                        ... },
 *            "next": 积木 | 省略 }
 * ========================================================================== */
(function () {
  'use strict';

  // 一条映射 = 一个 Scratch 积木类型 对应 我们的一个积木定义
  //   s        Scratch 类型
  //   e        我们的积木 id
  //   const    固定参数（用来区分同一个积木的不同形态，比如 show / hide）
  //   fields   Scratch 字段 -> 我们的参数
  //   inputs   Scratch 值输入 -> 我们的参数
  //   substack Scratch 语句输入 -> 我们的参数
  const MAP = [
    // ---- 事件 ----
    { s: 'event_whenflagclicked', e: 'core.event.when_flag_clicked', nextFrom: 'BODY' },
    { s: 'event_whenkeypressed', e: 'core.event.when_key_pressed', nextFrom: 'BODY', fields: { KEY_OPTION: 'KEY' } },
    { s: 'event_whenbroadcastreceived', e: 'core.event.when_broadcast_received', nextFrom: 'BODY', fields: { BROADCAST_OPTION: 'MSG' } },
    { s: 'event_broadcast', e: 'core.event.broadcast', fields: { BROADCAST_OPTION: 'MSG' } },
    { s: 'event_broadcastandwait', e: 'core.event.broadcast_and_wait', fields: { BROADCAST_OPTION: 'MSG' } },

    // ---- 控制 ----
    { s: 'control_wait', e: 'core.control.wait', inputs: { DURATION: 'SECS' } },
    { s: 'control_repeat', e: 'core.control.repeat', inputs: { TIMES: 'TIMES' }, substack: { SUBSTACK: 'BODY' } },
    { s: 'control_forever', e: 'core.control.forever', substack: { SUBSTACK: 'BODY' } },
    { s: 'control_if', e: 'core.control.if', inputs: { CONDITION: 'COND' }, substack: { SUBSTACK: 'BODY' } },
    { s: 'control_if_else', e: 'core.control.if_else', inputs: { CONDITION: 'COND' }, substack: { SUBSTACK: 'THEN', SUBSTACK2: 'ELSE' } },
    { s: 'control_repeat_until', e: 'core.control.repeat_until', inputs: { CONDITION: 'COND' }, substack: { SUBSTACK: 'BODY' } },
    { s: 'control_wait_until', e: 'core.control.wait_until', inputs: { CONDITION: 'COND' } },
    { s: 'control_stop', e: 'core.control.stop', fields: { STOP_OPTION: 'MODE' } },

    // ---- 运动 ----
    { s: 'motion_movesteps', e: 'core.motion.move_steps', inputs: { STEPS: 'STEPS' } },
    { s: 'motion_gotoxy', e: 'core.motion.set_position', inputs: { X: 'X', Y: 'Y' } },
    { s: 'motion_changexby', e: 'core.motion.change_x', inputs: { DX: 'DX' } },
    { s: 'motion_changeyby', e: 'core.motion.change_y', inputs: { DY: 'DY' } },
    { s: 'motion_setx', e: 'core.motion.set_x', inputs: { X: 'X' } },
    { s: 'motion_sety', e: 'core.motion.set_y', inputs: { Y: 'Y' } },
    { s: 'motion_pointindirection', e: 'core.motion.point_direction', inputs: { DIRECTION: 'DIR' } },
    { s: 'motion_turnright', e: 'core.motion.turn', const: { MODE: 'cw' }, inputs: { DEGREE: 'DELTA' } },
    { s: 'motion_turnleft', e: 'core.motion.turn', const: { MODE: 'ccw' }, inputs: { DEGREE: 'DELTA' } },
    { s: 'motion_xposition', e: 'core.motion.x' },
    { s: 'motion_yposition', e: 'core.motion.y' },
    { s: 'motion_direction', e: 'core.motion.direction' },

    // ---- 外观 ----
    { s: 'looks_say', e: 'core.looks.say', inputs: { MESSAGE: 'TEXT' } },
    { s: 'looks_sayforsecs', e: 'core.looks.say_for', inputs: { MESSAGE: 'TEXT', SECS: 'SECS' } },
    { s: 'looks_show', e: 'core.looks.set_visible', const: { MODE: 'show' } },
    { s: 'looks_hide', e: 'core.looks.set_visible', const: { MODE: 'hide' } },
    { s: 'looks_setsizeto', e: 'core.looks.set_size', const: { MODE: 'set' }, inputs: { SIZE: 'PCT' } },
    { s: 'looks_changesizeby', e: 'core.looks.set_size', const: { MODE: 'change' }, inputs: { CHANGE: 'PCT' } },
    {
      s: 'looks_switchcostumeto', e: 'core.looks.set_costume', const: { MODE: 'set' },
      inputs: { COSTUME: 'NAME' },
      shadows: { COSTUME: { type: 'looks_costume', field: 'COSTUME' } }
    },
    { s: 'looks_nextcostume', e: 'core.looks.set_costume', const: { MODE: 'next' } },

    // ---- 声音 ----
    {
      s: 'sound_play', e: 'core.sound.play', const: { MODE: 'start' },
      inputs: { SOUND_MENU: 'NAME' },
      shadows: { SOUND_MENU: { type: 'sound_sounds_menu', field: 'SOUND_MENU' } }
    },
    {
      s: 'sound_playuntildone', e: 'core.sound.play', const: { MODE: 'wait' },
      inputs: { SOUND_MENU: 'NAME' },
      shadows: { SOUND_MENU: { type: 'sound_sounds_menu', field: 'SOUND_MENU' } }
    },
    { s: 'sound_stopallsounds', e: 'core.sound.stop_all' },

    // ---- 克隆 ----
    { s: 'control_start_as_clone', e: 'core.event.when_clone_start', nextFrom: 'BODY' },
    {
      s: 'control_create_clone_of', e: 'core.control.create_clone',
      inputs: { CLONE_OPTION: 'TARGET' },
      shadows: { CLONE_OPTION: { type: 'control_create_clone_of_menu', field: 'CLONE_OPTION' } }
    },
    { s: 'control_delete_this_clone', e: 'core.control.delete_clone' },

    // ---- 侦测 ----
    { s: 'sensing_keypressed', e: 'core.sensing.key_pressed', fields: { KEY_OPTION: 'KEY' } },
    { s: 'sensing_mousex', e: 'core.sensing.mouse_x' },
    { s: 'sensing_mousey', e: 'core.sensing.mouse_y' },
    { s: 'sensing_mousedown', e: 'core.sensing.mouse_down' },
    { s: 'sensing_timer', e: 'core.sensing.timer' },
    { s: 'sensing_resettimer', e: 'core.sensing.reset_timer' },

    // ---- 运算 ----
    { s: 'operator_add', e: 'core.operator.add', inputs: { NUM1: 'A', NUM2: 'B' } },
    { s: 'operator_subtract', e: 'core.operator.sub', inputs: { NUM1: 'A', NUM2: 'B' } },
    { s: 'operator_multiply', e: 'core.operator.mul', inputs: { NUM1: 'A', NUM2: 'B' } },
    { s: 'operator_divide', e: 'core.operator.div', inputs: { NUM1: 'A', NUM2: 'B' } },
    { s: 'operator_mod', e: 'core.operator.mod', inputs: { NUM1: 'A', NUM2: 'B' } },
    { s: 'operator_round', e: 'core.operator.round', inputs: { NUM: 'A' } },
    { s: 'operator_random', e: 'core.operator.random', inputs: { FROM: 'FROM', TO: 'TO' } },
    { s: 'operator_gt', e: 'core.operator.gt', inputs: { OPERAND1: 'A', OPERAND2: 'B' } },
    { s: 'operator_lt', e: 'core.operator.lt', inputs: { OPERAND1: 'A', OPERAND2: 'B' } },
    { s: 'operator_equals', e: 'core.operator.eq', inputs: { OPERAND1: 'A', OPERAND2: 'B' } },
    { s: 'operator_and', e: 'core.operator.and', inputs: { OPERAND1: 'A', OPERAND2: 'B' } },
    { s: 'operator_or', e: 'core.operator.or', inputs: { OPERAND1: 'A', OPERAND2: 'B' } },
    { s: 'operator_not', e: 'core.operator.not', inputs: { OPERAND: 'A' } },
    { s: 'operator_join', e: 'core.operator.join', inputs: { STRING1: 'A', STRING2: 'B' } },
    { s: 'operator_letter_of', e: 'core.operator.letter_of', inputs: { LETTER: 'I', STRING: 'S' } },
    { s: 'operator_length', e: 'core.operator.length', inputs: { STRING: 'S' } },
    { s: 'operator_contains', e: 'core.operator.contains', inputs: { STRING1: 'S', STRING2: 'SUB' } },

    // ---- 变量 ----
    { s: 'data_variable', e: 'core.data.var', fields: { VARIABLE: 'NAME' } },
    { s: 'data_setvariableto', e: 'core.data.set_var', fields: { VARIABLE: 'NAME' }, inputs: { VALUE: 'VALUE' } },
    { s: 'data_changevariableby', e: 'core.data.change_var', fields: { VARIABLE: 'NAME' }, inputs: { VALUE: 'DELTA' } }
  ];

  const byScratch = {};
  const byEngine = {};
  MAP.forEach(function (m) {
    byScratch[m.s] = m;
    (byEngine[m.e] = byEngine[m.e] || []).push(m);
  });

  var workspace = null;
  var suppress = false;      // 从引擎灌入程序时，别把它又当成"用户修改"发回去
  var lastSent = null;       // 上一次推给引擎的程序，用来去重
  var lastUnsupported = [];

  // ---------------------------------------------------------------- 工具

  function post(obj) {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(obj);
    }
  }

  function isBlock(v) {
    return v && typeof v === 'object' && typeof v.block === 'string';
  }

  function str(v) {
    if (v === null || v === undefined) return '';
    if (typeof v === 'boolean') return v ? 'true' : 'false';
    return String(v);
  }

  function constMatches(entry, inputs) {
    var c = entry.const || {};
    for (var k in c) {
      var box = inputs[k];
      if (!box || !('value' in box)) return false;
      if (str(box.value) !== str(c[k])) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- 网页 -> 引擎

  function blockToEE(b) {
    var entry = byScratch[b.type];
    if (!entry) {
      lastUnsupported.push(b.type);
      return null;
    }
    var node = { block: entry.e, inputs: {} };

    // 固定参数
    var c = entry.const || {};
    for (var ck in c) node.inputs[ck] = { value: c[ck] };

    // 字段
    var f = entry.fields || {};
    for (var sf in f) {
      var fv = b.getFieldValue(sf);
      if (fv !== null && fv !== undefined) node.inputs[f[sf]] = { value: fv };
    }

    // 值输入
    var ins = entry.inputs || {};
    for (var si in ins) {
      var target = b.getInputTargetBlock(si);
      if (!target) continue;
      if (isShadow(target)) {
        var sv = readShadowValue(target);
        if (sv !== null) node.inputs[ins[si]] = { value: sv };
        continue;
      }
      var child = blockToEE(target);
      if (child) node.inputs[ins[si]] = { value: child };
    }

    // 帽子积木：下面那一串在 Scratch 里是 next 连接，在我们的格式里是 BODY 参数
    if (entry.nextFrom) {
      var tail = stackToEE(b.getNextBlock());
      if (tail) node.inputs[entry.nextFrom] = { stack: tail };
    }

    // 语句输入
    var st = entry.substack || {};
    for (var ssi in st) {
      var first = b.getInputTargetBlock(ssi);
      if (!first) continue;
      var stack = stackToEE(first);
      if (stack) node.inputs[st[ssi]] = { stack: stack };
    }

    return node;
  }

  function stackToEE(first) {
    var out = null;
    var prev = null;
    var b = first;
    var guard = 0;
    while (b && guard++ < 5000) {
      var node = blockToEE(b);
      if (node) {
        if (!out) out = node;
        if (prev) prev.next = node;
        prev = node;
      }
      b = b.getNextBlock();
    }
    return out;
  }

  // 影子积木（数字框/文本框/真假框）= 一个普通值，不该当成积木转换
  function readShadowValue(b) {
    switch (b.type) {
      case 'math_number':
      case 'math_whole_number':
      case 'math_positive_number':
      case 'math_angle':
        return Number(b.getFieldValue('NUM'));
      case 'logic_boolean':
        return b.getFieldValue('BOOL') === 'TRUE';
      case 'text':
        return b.getFieldValue('TEXT');
      // Scratch 的"下拉菜单"也是影子积木，值在字段里
      case 'looks_costume':
        return b.getFieldValue('COSTUME');
      case 'sound_sounds_menu':
        return b.getFieldValue('SOUND_MENU');
      case 'control_create_clone_of_menu': {
        var v = b.getFieldValue('CLONE_OPTION');
        return v === '_myself_' ? '@self' : v;
      }
      default:
        return null;
    }
  }

  function isShadow(b) {
    return !!(b.isShadow ? b.isShadow() : b.isShadow_);
  }

  function workspaceToProgram() {
    lastUnsupported = [];
    var program = [];
    // 连续工具箱（continuous toolbox）会把分类里的积木画在主工作区，
    // 它们不是用户的程序，必须排除。
    var tops = workspace ? workspace.getTopBlocks(true) : [];
    tops = tops.filter(function (b) { return !b.isInFlyout && !isShadow(b); });
    tops.forEach(function (b) {
      var node = blockToEE(b);
      if (node) program.push({ top: node });
    });
    return { program: program, unsupported: lastUnsupported.slice() };
  }

  function pushToEngine() {
    if (!workspace || suppress) return;
    var result = workspaceToProgram();
    var key = JSON.stringify(result.program);
    if (key === lastSent) return;
    lastSent = key;
    post({
      type: 'program',
      program: result.program,
      unsupported: result.unsupported
    });
  }

  // ---------------------------------------------------------------- 引擎 -> 网页

  function shadowFor(value) {
    if (typeof value === 'boolean') {
      return '<shadow type="logic_boolean"><field name="BOOL">' + (value ? 'TRUE' : 'FALSE') + '</field></shadow>';
    }
    if (typeof value === 'number') {
      return '<shadow type="math_number"><field name="NUM">' + value + '</field></shadow>';
    }
    var s = str(value);
    // 纯数字字符串也走数字框，看起来更像 Scratch
    if (s !== '' && !isNaN(Number(s))) {
      return '<shadow type="math_number"><field name="NUM">' + s + '</field></shadow>';
    }
    return '<shadow type="text"><field name="TEXT">' + escapeXml(s) + '</field></shadow>';
  }

  function escapeXml(s) {
    return str(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
  }

  function pickEntry(ee) {
    var list = byEngine[ee.block];
    if (!list) return null;
    if (list.length === 1) return list[0];
    for (var i = 0; i < list.length; i++) {
      if (constMatches(list[i], ee.inputs || {})) return list[i];
    }
    return list[0];
  }

  function blockToXml(ee) {
    var entry = pickEntry(ee);
    if (!entry) return '';
    var x = '<block type="' + entry.s + '">';
    var inputs = ee.inputs || {};

    var f = entry.fields || {};
    for (var sf in f) {
      var box = inputs[f[sf]];
      if (box && 'value' in box && !isBlock(box.value)) {
        x += '<field name="' + sf + '">' + escapeXml(box.value) + '</field>';
      }
    }

    var ins = entry.inputs || {};
    var shadows = entry.shadows || {};
    for (var si in ins) {
      var b2 = inputs[ins[si]];
      if (!b2 || !('value' in b2)) continue;
      x += '<value name="' + si + '">';
      if (isBlock(b2.value)) {
        x += blockToXml(b2.value);
      } else if (shadows[si]) {
        // 造型/声音/克隆对象这类下拉菜单，要用 Scratch 自己的菜单影子块
        var shadowValue = b2.value;
        if (shadows[si].type === 'control_create_clone_of_menu' && shadowValue === '@self') {
          shadowValue = '_myself_'; // Scratch 里显示为「自己」
        }
        x += '<shadow type="' + shadows[si].type + '"><field name="' + shadows[si].field + '">' +
          escapeXml(shadowValue) + '</field></shadow>';
      } else {
        x += shadowFor(b2.value);
      }
      x += '</value>';
    }

    var st = entry.substack || {};
    for (var ssi in st) {
      var s2 = inputs[st[ssi]];
      if (!s2 || !('stack' in s2) || !s2.stack) continue;
      x += '<statement name="' + ssi + '">' + blockToXml(s2.stack) + '</statement>';
    }

    if (entry.nextFrom) {
      var body = inputs[entry.nextFrom];
      if (body && 'stack' in body && body.stack) {
        x += '<next>' + blockToXml(body.stack) + '</next>';
      }
    } else if (ee.next) {
      x += '<next>' + blockToXml(ee.next) + '</next>';
    }

    x += '</block>';
    return x;
  }

  function programToXml(program) {
    var xml = '<xml xmlns="http://www.w3.org/1999/xhtml">';
    var i = 0;
    (program || []).forEach(function (item) {
      var top = item && item.top ? item.top : item;
      if (!top) return;
      var body = blockToXml(top);
      if (!body) return;
      var x = 40 + (i % 3) * 300;
      var y = 40 + Math.floor(i / 3) * 220;
      body = body.replace('<block ', '<block x="' + x + '" y="' + y + '" ');
      xml += body;
      i++;
    });
    xml += '</xml>';
    return xml;
  }

  // 引擎调用的入口
  window.eeLoadProgram = function (program) {
    if (!workspace) return;
    // 关键：必须等字体就绪再建积木。
    // 否则 Blockly 用备用字体的窄宽度算中文，clip 路径会短一截，
    // 积木右边就被裁掉了（看起来像"少了半个积木"）。
    var fonts = (document.fonts && document.fonts.ready) ? document.fonts.ready : Promise.resolve();
    fonts.then(function () {
      loadNow(program);
    });
  };

  function loadNow(program) {
    suppress = true;
    try {
      workspace.clear();
      var xml = programToXml(program);
      Blockly.Xml.domToWorkspace(Blockly.Xml.textToDom(xml), workspace);

      // 再强制排一次版：字体/缩放变化后 clip 路径需要重建
      if (Blockly.svgResize) {
        Blockly.svgResize(workspace);
      }
      workspace.getAllBlocks(false).forEach(function (b) {
        if (b.render) b.render();
      });

      // 容器尺寸在网页刚显示时可能还没定下来，画出来的路径会短一截。
      // 等一两帧再重排一次（Blockly 这类"积木被切掉"的经典解法）。
      [120, 400].forEach(function (ms) {
        setTimeout(function () {
          if (!workspace) return;
          if (Blockly.svgResize) Blockly.svgResize(workspace);
          workspace.getAllBlocks(false).forEach(function (b) {
            if (b.renderDraw_) b.renderDraw_(); else if (b.render) b.render();
          });
        }, ms);
      });

      // 往返校验：把"网页理解的程序"再发回引擎一次。
      // 如果两边对不上（比如某个积木在网页里画不出来），引擎那边会立刻发现。
      var round = workspaceToProgram();
      lastSent = JSON.stringify(round.program);
      post({ type: 'program', program: round.program, unsupported: round.unsupported, echo: true,
        tops: (workspace.getTopBlocks(true) || []).map(function (b) {
          return b.type + '@' + (b.workspace ? b.workspace.id : '?') + (b.isInFlyout ? '(flyout)' : '');
        }) });

      if (round.unsupported.length) {
        toast('有 ' + round.unsupported.length + ' 个积木还不支持，暂时跳过：' + round.unsupported.join('、'), true);
      }
    } catch (e) {
      post({ type: 'js_error', message: String(e && e.stack ? e.stack : e) });
    } finally {
      suppress = false;
    }
  }

  window.eeSetReadOnly = function (flag) {
    if (workspace) workspace.options.readOnly = !!flag;
  };

  window.eeBridge = {
    engineReady: function () {
      post({ type: 'ready' });
    },
    // 调试用
    toProgram: workspaceToProgram
  };

  window.eeAttach = function (pWorkspace) {
    workspace = pWorkspace;
    var timer = null;
    workspace.addChangeListener(function (ev) {
      if (suppress) return;
      // UI 事件（选中、缩放、拖视口）不算修改
      if (ev && ev.isUiEvent) return;
      // 工具箱/浮出层自己的事件不算程序变化
      if (ev && ev.workspaceId && ev.workspaceId !== workspace.id) return;
      if (timer) clearTimeout(timer);
      timer = setTimeout(pushToEngine, 250);
    });
    post({ type: 'bridge_ready' });
  };
})();
