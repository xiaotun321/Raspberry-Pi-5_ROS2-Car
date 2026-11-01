#pragma once

// 网页控制页面：内嵌在可执行文件中，不依赖外部静态资源，
// 断网的局域网也能直接打开。按住方向键持续下发指令，松开即停车。

namespace tb6612 {

inline constexpr char kWebControlPage[] = R"HTML(<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>TB6612 小车控制</title>
<style>
  :root {
    --bg: #14181f;
    --panel: #1e2530;
    --line: #2c3542;
    --text: #e8edf4;
    --muted: #93a1b5;
    --active: #2f81f7;
    --danger: #e5534b;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  body {
    margin: 0; padding: 16px; background: var(--bg); color: var(--text);
    font-family: system-ui, "Noto Sans CJK SC", "Microsoft YaHei", sans-serif;
    user-select: none; touch-action: manipulation;
  }
  h1 { font-size: 18px; margin: 0 0 4px; }
  .hint { color: var(--muted); font-size: 12px; margin-bottom: 14px; line-height: 1.6; }
  .status {
    background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
    padding: 10px 12px; font-size: 13px; margin-bottom: 14px;
  }
  .status b { color: var(--active); }
  .pad {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;
    max-width: 420px; margin: 0 auto 16px;
  }
  button {
    border: 1px solid var(--line); background: var(--panel); color: var(--text);
    border-radius: 12px; padding: 0; font-size: 20px; cursor: pointer;
    font-family: inherit; min-height: 64px;
  }
  button:active, button.on { background: var(--active); border-color: var(--active); }
  .blank { visibility: hidden; }
  .stop { background: var(--danger); border-color: var(--danger); font-size: 18px; }
  .sliders { max-width: 420px; margin: 0 auto; }
  .slider { background: var(--panel); border: 1px solid var(--line);
            border-radius: 10px; padding: 12px; margin-bottom: 10px; }
  .slider label { display: flex; justify-content: space-between; font-size: 13px;
                  margin-bottom: 8px; color: var(--muted); }
  .slider input { width: 100%; }
  .note { color: var(--muted); font-size: 12px; text-align: center; margin-top: 14px; }
</style>
</head>
<body>
<h1>TB6612 小车控制</h1>
<div class="hint">按住方向按钮持续下发指令，松开立即停车。浏览器关闭或网络中断超过
  超时时间也会自动停车。首次测试请架空车轮。</div>

<div class="status">状态：<b id="state">就绪</b></div>

<div class="pad">
  <div class="blank"></div>
  <button id="w" data-dir="w">前</button>
  <div class="blank"></div>
  <button id="a" data-dir="a">左</button>
  <button id="stop" class="stop">停</button>
  <button id="d" data-dir="d">右</button>
  <div class="blank"></div>
  <button id="x" data-dir="x">后</button>
  <div class="blank"></div>
</div>

<div class="sliders">
  <div class="slider">
    <label>线速度 <span id="linearValue">0.15</span></label>
    <input id="linear" type="range" min="0.02" max="0.5" step="0.01" value="0.15">
  </div>
  <div class="slider">
    <label>角速度 <span id="angularValue">0.80</span></label>
    <input id="angular" type="range" min="0.1" max="2.5" step="0.1" value="0.8">
  </div>
</div>

<div class="note">网页指令与键盘控制共用同一个 /cmd_vel，请勿同时使用。</div>

<script>
(function () {
  var token = new URLSearchParams(location.search).get('token') || '';
  var linear = 0.15;
  var angular = 0.8;
  var holdTimer = null;
  var holdDir = null;

  var stateEl = document.getElementById('state');
  var linearInput = document.getElementById('linear');
  var angularInput = document.getElementById('angular');

  function setState(text) { stateEl.textContent = text; }

  function send(lin, ang) {
    var headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    if (token) { headers['X-Car-Token'] = token; }
    fetch('/cmd', { method: 'POST', headers: headers,
                    body: 'linear=' + lin + '&angular=' + ang })
      .then(function (response) {
        if (response.status === 403) { setState('未授权：缺少或错误的 token'); }
        else if (!response.ok) { setState('指令失败 HTTP ' + response.status); }
        else { setState('运行中 linear=' + lin.toFixed(2) + ' angular=' + ang.toFixed(2)); }
      })
      .catch(function () { setState('连接中断，已停车'); });
  }

  function tick() {
    if (holdDir === 'w') { send(linear, 0); }
    else if (holdDir === 'x') { send(-linear, 0); }
    else if (holdDir === 'a') { send(0, angular); }
    else if (holdDir === 'd') { send(0, -angular); }
  }

  function press(dir) {
    holdDir = dir;
    tick();
    if (holdTimer) { clearInterval(holdTimer); }
    holdTimer = setInterval(tick, 150);
  }

  function release() {
    if (holdTimer) { clearInterval(holdTimer); holdTimer = null; }
    holdDir = null;
    send(0, 0);
    setState('已停止');
  }

  function bind(button) {
    button.addEventListener('pointerdown', function (event) {
      event.preventDefault();
      press(button.getAttribute('data-dir'));
    });
    ['pointerup', 'pointercancel', 'pointerleave'].forEach(function (name) {
      button.addEventListener(name, function (event) {
        event.preventDefault();
        release();
      });
    });
    button.addEventListener('contextmenu', function (event) {
      event.preventDefault();
    });
  }

  ['w', 'a', 'd', 'x'].forEach(function (id) {
    bind(document.getElementById(id));
  });

  document.getElementById('stop').addEventListener('pointerdown', function (event) {
    event.preventDefault();
    release();
  });

  var keys = { w: 'w', a: 'a', s: 'stop', d: 'd', x: 'x', ' ': 'stop' };
  document.addEventListener('keydown', function (event) {
    var dir = keys[event.key.toLowerCase()];
    if (!dir) { return; }
    event.preventDefault();
    if (dir === 'stop') { release(); } else { press(dir); }
  });
  document.addEventListener('keyup', function (event) {
    var dir = keys[event.key.toLowerCase()];
    if (!dir) { return; }
    event.preventDefault();
    release();
  });
  window.addEventListener('blur', release);

  function syncLabels() {
    linear = parseFloat(linearInput.value);
    angular = parseFloat(angularInput.value);
    document.getElementById('linearValue').textContent = linear.toFixed(2);
    document.getElementById('angularValue').textContent = angular.toFixed(2);
  }
  linearInput.addEventListener('input', syncLabels);
  angularInput.addEventListener('input', syncLabels);
  syncLabels();

  setInterval(function () {
    fetch('/state', { headers: token ? { 'X-Car-Token': token } : {} })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        if (data && data.active) {
          setState('运行中 linear=' + Number(data.linear).toFixed(2) +
                   ' angular=' + Number(data.angular).toFixed(2));
        }
      })
      .catch(function () {});
  }, 1000);
})();
</script>
</body>
</html>
)HTML";

}  // namespace tb6612
