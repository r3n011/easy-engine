/* ==========================================================================
 * Easy Engine · 积木工作区的对话框
 *
 * 三件事：新建变量、新建列表、制作新的积木。
 *
 * 为什么不用 window.prompt：WebView2 里能用，但样式和编辑器完全不搭，
 * 而且"制作新的积木"需要多参数编辑，prompt 做不了。
 * ========================================================================== */
(function () {
  'use strict';

  var CSS = [
    '.ee-mask{position:fixed;inset:0;background:rgba(22,28,40,.38);display:flex;align-items:center;',
    'justify-content:center;z-index:99999;font:14px/1.5 "Helvetica Neue",Helvetica,Arial,"Microsoft YaHei",sans-serif}',
    '.ee-card{background:#fff;color:#575e75;border-radius:10px;box-shadow:0 12px 40px rgba(0,0,0,.28);',
    'min-width:380px;max-width:520px;padding:20px 22px;box-sizing:border-box}',
    '.ee-card h3{margin:0 0 14px;font-size:17px;color:#2f3648;font-weight:700}',
    '.ee-row{display:flex;align-items:center;gap:8px;margin-bottom:10px}',
    '.ee-row label{width:92px;flex:none;color:#6b7488}',
    '.ee-card input[type=text]{flex:1;min-width:0;padding:7px 10px;border:1px solid #ccd3de;border-radius:6px;',
    'font:inherit;color:#2f3648;outline:none}',
    '.ee-card input[type=text]:focus{border-color:#4c97ff;box-shadow:0 0 0 2px rgba(76,151,255,.18)}',
    '.ee-params{max-height:180px;overflow:auto;margin:4px 0 10px}',
    '.ee-param{display:flex;gap:6px;align-items:center;margin-bottom:6px}',
    '.ee-param input{flex:1}',
    '.ee-param select{padding:6px 8px;border:1px solid #ccd3de;border-radius:6px;font:inherit;color:#2f3648;background:#fff}',
    '.ee-mini{border:0;background:#eef1f6;color:#4a5468;border-radius:6px;padding:6px 10px;cursor:pointer;font:inherit}',
    '.ee-mini:hover{background:#e2e7f0}',
    '.ee-del{background:#fdecec;color:#c0392b;width:28px;height:28px;padding:0;border-radius:6px;border:0;cursor:pointer;font-size:15px}',
    '.ee-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:16px}',
    '.ee-btn{border:0;border-radius:6px;padding:8px 16px;font:inherit;cursor:pointer}',
    '.ee-ok{background:#4c97ff;color:#fff}.ee-ok:hover{background:#3f86ea}',
    '.ee-cancel{background:#eef1f6;color:#4a5468}.ee-cancel:hover{background:#e2e7f0}',
    '.ee-warp{display:flex;align-items:center;gap:8px;color:#6b7488;margin-top:2px}',
    '.ee-hint{color:#97a0b3;font-size:12px;margin:-4px 0 8px}'
  ].join('');

  var style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);

  function el(tag, attrs, text) {
    var n = document.createElement(tag);
    if (attrs) { for (var k in attrs) { n.setAttribute(k, attrs[k]); } }
    if (text !== undefined) { n.textContent = text; }
    return n;
  }

  function mask(card) {
    var m = el('div', { 'class': 'ee-mask' });
    m.appendChild(card);
    document.body.appendChild(m);
    return m;
  }

  function close(m) {
    if (m && m.parentNode) { m.parentNode.removeChild(m); }
  }

  // ---------------------------------------------------------------- 单输入框

  function prompt(title, labelText, defaultValue, onOk) {
    var card = el('div', { 'class': 'ee-card' });
    card.appendChild(el('h3', null, title));

    var row = el('div', { 'class': 'ee-row' });
    row.appendChild(el('label', null, labelText));
    var input = el('input', { type: 'text', value: defaultValue || '' });
    row.appendChild(input);
    card.appendChild(row);

    var actions = el('div', { 'class': 'ee-actions' });
    var cancel = el('button', { 'class': 'ee-btn ee-cancel' }, '取消');
    var ok = el('button', { 'class': 'ee-btn ee-ok' }, '确定');
    actions.appendChild(cancel);
    actions.appendChild(ok);
    card.appendChild(actions);

    var m = mask(card);
    input.focus();
    input.select();

    function done(v) { close(m); onOk(v); }

    ok.onclick = function () {
      var v = (input.value || '').trim();
      if (!v) { input.focus(); return; }
      done(v);
    };
    cancel.onclick = function () { done(null); };
    input.onkeydown = function (e) {
      if (e.key === 'Enter') { ok.onclick(); }
      if (e.key === 'Escape') { done(null); }
    };
  }

  // ---------------------------------------------------------------- 制作新的积木

  function procedure(initialProccode, onOk) {
    var card = el('div', { 'class': 'ee-card' });
    card.appendChild(el('h3', null, '制作新的积木'));

    var nameRow = el('div', { 'class': 'ee-row' });
    nameRow.appendChild(el('label', null, '积木名字'));
    // 初始名字可能带 %s 占位符，剥掉
    var initialName = (initialProccode || '').replace(/\s*%[sb]/g, '').trim();
    var nameInput = el('input', { type: 'text', value: initialName || '我的积木' });
    nameRow.appendChild(nameInput);
    card.appendChild(nameRow);

    card.appendChild(el('div', { 'class': 'ee-hint' }, '可以加参数，参数会变成积木里的圆角输入框'));

    var paramsBox = el('div', { 'class': 'ee-params' });
    card.appendChild(paramsBox);

    var params = []; // {name, type: 's' | 'b'}

    function render() {
      paramsBox.innerHTML = '';
      params.forEach(function (p, i) {
        var row = el('div', { 'class': 'ee-param' });
        var ni = el('input', { type: 'text', value: p.name });
        ni.oninput = function () { p.name = ni.value; };
        var sel = el('select');
        [['s', '文本/数字'], ['b', '布尔']].forEach(function (opt) {
          var o = el('option', { value: opt[0] }, opt[1]);
          if (p.type === opt[0]) { o.selected = true; }
          sel.appendChild(o);
        });
        sel.onchange = function () { p.type = sel.value; };
        var del = el('button', { 'class': 'ee-del', title: '删除' }, '×');
        del.onclick = function () { params.splice(i, 1); render(); };
        row.appendChild(ni);
        row.appendChild(sel);
        row.appendChild(del);
        paramsBox.appendChild(row);
      });
    }

    var addText = el('button', { 'class': 'ee-mini' }, '+ 文本/数字参数');
    addText.onclick = function () {
      params.push({ name: '参数' + (params.length + 1), type: 's' });
      render();
    };
    var addBool = el('button', { 'class': 'ee-mini' }, '+ 布尔参数');
    addBool.onclick = function () {
      params.push({ name: '条件' + (params.length + 1), type: 'b' });
      render();
    };
    var bar = el('div', { 'class': 'ee-row' });
    bar.appendChild(addText);
    bar.appendChild(addBool);
    card.appendChild(bar);

    var warpRow = el('div', { 'class': 'ee-warp' });
    var warp = el('input', { type: 'checkbox' });
    warpRow.appendChild(warp);
    warpRow.appendChild(el('span', null, '运行时不刷新屏幕'));
    card.appendChild(warpRow);

    var actions = el('div', { 'class': 'ee-actions' });
    var cancel = el('button', { 'class': 'ee-btn ee-cancel' }, '取消');
    var ok = el('button', { 'class': 'ee-btn ee-ok' }, '确定');
    actions.appendChild(cancel);
    actions.appendChild(ok);
    card.appendChild(actions);

    var m = mask(card);
    nameInput.focus();
    nameInput.select();

    function done(v) { close(m); onOk(v); }

    ok.onclick = function () {
      var name = (nameInput.value || '').trim();
      if (!name) { nameInput.focus(); return; }

      var names = [];
      var defaults = [];
      var ids = [];
      var code = name;
      params.forEach(function (p, i) {
        var pn = (p.name || '').trim() || ('参数' + (i + 1));
        names.push(pn);
        ids.push('arg' + i);
        code += (p.type === 'b') ? ' %b' : ' %s';
        defaults.push(p.type === 'b' ? 'false' : '');
      });

      done({
        proccode: code,
        argumentnames: names,
        argumentids: ids,
        argumentdefaults: defaults,
        warp: !!warp.checked
      });
    };
    cancel.onclick = function () { done(null); };
    nameInput.onkeydown = function (e) {
      if (e.key === 'Enter') { ok.onclick(); }
      if (e.key === 'Escape') { done(null); }
    };

    render();
  }

  window.eeDialogs = { prompt: prompt, procedure: procedure };
})();
