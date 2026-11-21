/* ==========================================================================
 * Easy Engine · 3D 积木
 *
 * 这一组是 Scratch 里**根本不存在**的积木 —— 也正是"基于 Godot"的意义：
 * 同样是拖积木，但能做出 3D 的东西。
 *
 * 这些积木由 scratch-blocks 渲染（所以手感和其它积木一致），
 * 定义在网页这边；数据仍然走同一个桥，存进同一份 BlockProgram。
 * ========================================================================== */
(function () {
  'use strict';

  if (!window.Blockly || !Blockly.Blocks) return;

  var COLOUR = '#0FBD8C';

  // 给小孩用的颜色：给名字，不给十六进制
  var COLOR_OPTIONS = [
    ['红', '#ff4d4d'],
    ['橙', '#ff9c1a'],
    ['黄', '#ffd500'],
    ['绿', '#3ec46d'],
    ['青', '#0fbd8c'],
    ['蓝', '#4c97ff'],
    ['紫', '#9966ff'],
    ['白', '#ffffff'],
    ['黑', '#333333']
  ];

  var SHAPE_OPTIONS = [
    ['立方体', 'cube'],
    ['球体', 'sphere'],
    ['圆柱', 'cylinder']
  ];

  function num(name, value) {
    return { type: 'field_input', name: name, text: String(value) };
  }

  function stackDef(message, args) {
    return {
      init: function () {
        this.jsonInit({
          message0: message,
          args0: args,
          previousStatement: null,
          nextStatement: null,
          inputsInline: true,
          colour: COLOUR
        });
      }
    };
  }

  Blockly.Blocks['ee_3d_set_shape'] = stackDef('变成 %1 形状 颜色 %2', [
    { type: 'field_dropdown', name: 'KIND', options: SHAPE_OPTIONS },
    { type: 'field_dropdown', name: 'COLOR', options: COLOR_OPTIONS }
  ]);

  Blockly.Blocks['ee_3d_set_position'] = stackDef('移到 x %1 y %2 z %3', [
    num('X', 0), num('Y', 0), num('Z', 0)
  ]);

  Blockly.Blocks['ee_3d_change_position'] = stackDef('坐标增加 x %1 y %2 z %3', [
    num('DX', 0), num('DY', 0), num('DZ', 0)
  ]);

  Blockly.Blocks['ee_3d_set_rotation'] = stackDef('转到 x %1 y %2 z %3 度', [
    num('RX', 0), num('RY', 0), num('RZ', 0)
  ]);

  Blockly.Blocks['ee_3d_change_rotation'] = stackDef('转动 x %1 y %2 z %3 度', [
    num('DX', 0), num('DY', 5), num('DZ', 0)
  ]);

  Blockly.Blocks['ee_3d_set_scale'] = stackDef('大小设为 %1', [num('S', 1)]);

  Blockly.Blocks['ee_3d_set_color'] = stackDef('颜色设为 %1', [
    { type: 'field_dropdown', name: 'COLOR', options: COLOR_OPTIONS }
  ]);

  Blockly.Blocks['ee_3d_camera_follow'] = stackDef('镜头跟随自己 距离 %1 高度 %2', [
    num('DIST', 12), num('HEIGHT', 6)
  ]);

  // ---- 工具箱：加一个「3D」分类 ----
  // default_toolbox 是一段 XML 字符串，直接往末尾插一个分类最省事，
  // 也不用去改 vendor 里的原文件（以后重装 scratch-blocks 不会丢）。
  try {
    var tb = Blockly.Blocks.defaultToolbox;
    if (typeof tb === 'string' && tb.indexOf('ee_3d_set_shape') < 0) {
      var cat = '<category name="3D" id="ee3d" colour="' + COLOUR + '" secondaryColour="#0B9C73">' +
        '<block type="ee_3d_set_shape" id="ee3d_shape"></block>' +
        '<block type="ee_3d_camera_follow" id="ee3d_cam"></block>' +
        '<block type="ee_3d_set_position" id="ee3d_pos"></block>' +
        '<block type="ee_3d_change_position" id="ee3d_dpos"></block>' +
        '<block type="ee_3d_set_rotation" id="ee3d_rot"></block>' +
        '<block type="ee_3d_change_rotation" id="ee3d_drot"></block>' +
        '<block type="ee_3d_set_scale" id="ee3d_scale"></block>' +
        '<block type="ee_3d_set_color" id="ee3d_color"></block>' +
        '</category>';
      // 插在「变量」分类前面（别塞到最后，会被 Extensions 挤到看不见）
      var anchor = '<category name="%{BKY_CATEGORY_VARIABLES}"';
      Blockly.Blocks.defaultToolbox = (tb.indexOf(anchor) >= 0)
        ? tb.replace(anchor, cat + anchor)
        : tb.replace('</xml>', cat + '</xml>');
    }
  } catch (e) {
    // 加不上分类不影响已有功能
  }

  // ---- 给桥用的映射表（Scratch 积木类型 → 引擎积木 id）----
  window.ee3dMap = [
    { s: 'ee_3d_set_shape', e: 'core.3d.set_shape', fields: { KIND: 'KIND', COLOR: 'COLOR' } },
    { s: 'ee_3d_set_position', e: 'core.3d.set_position', fields: { X: 'X', Y: 'Y', Z: 'Z' } },
    { s: 'ee_3d_change_position', e: 'core.3d.change_position', fields: { DX: 'DX', DY: 'DY', DZ: 'DZ' } },
    { s: 'ee_3d_set_rotation', e: 'core.3d.set_rotation', fields: { RX: 'RX', RY: 'RY', RZ: 'RZ' } },
    { s: 'ee_3d_change_rotation', e: 'core.3d.change_rotation', fields: { DX: 'DX', DY: 'DY', DZ: 'DZ' } },
    { s: 'ee_3d_set_scale', e: 'core.3d.set_scale', fields: { S: 'S' } },
    { s: 'ee_3d_set_color', e: 'core.3d.set_color', fields: { COLOR: 'COLOR' } },
    { s: 'ee_3d_camera_follow', e: 'core.3d.camera_follow', fields: { DIST: 'DIST', HEIGHT: 'HEIGHT' } }
  ];
})();
