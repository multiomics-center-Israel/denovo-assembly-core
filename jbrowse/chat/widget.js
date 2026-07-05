/* Spalangia agent chat panel, injected into the JBrowse page (local stack).
 * Talks to the FastAPI agent's SSE /chat endpoint. No dependencies.
 * Agent URL: same host, port 8001 (overridable via window.SPALANGIA_AGENT). */
(function () {
  "use strict";
  var AGENT =
    window.SPALANGIA_AGENT ||
    location.protocol + "//" + location.hostname + ":8001";

  // ---- styles ------------------------------------------------------------
  var css = `
  #spa-chat-btn{position:fixed;right:18px;bottom:18px;z-index:99999;
    width:52px;height:52px;border-radius:50%;border:none;cursor:pointer;
    background:#1565c0;color:#fff;font-size:22px;box-shadow:0 2px 8px rgba(0,0,0,.35)}
  #spa-chat{position:fixed;right:18px;bottom:80px;z-index:99999;width:380px;
    max-width:calc(100vw - 36px);height:520px;max-height:calc(100vh - 110px);
    display:none;flex-direction:column;background:#fff;border:1px solid #ccc;
    border-radius:10px;box-shadow:0 6px 24px rgba(0,0,0,.3);
    font:13px/1.45 system-ui,Segoe UI,Roboto,sans-serif;overflow:hidden}
  #spa-chat.open{display:flex}
  #spa-chat header{background:#1565c0;color:#fff;padding:9px 12px;font-weight:600;
    display:flex;justify-content:space-between;align-items:center}
  #spa-chat header .x{cursor:pointer;font-weight:400;font-size:18px;opacity:.85}
  #spa-log{flex:1;overflow-y:auto;padding:10px;background:#f7f8fa}
  #spa-log .msg{margin:0 0 10px;padding:8px 10px;border-radius:8px;white-space:pre-wrap;
    word-break:break-word}
  #spa-log .user{background:#1565c0;color:#fff;margin-left:40px}
  #spa-log .bot{background:#fff;border:1px solid #e2e4e8}
  #spa-log .tool{background:#eef3fb;border:1px solid #d6e2f5;color:#274b73;
    font-family:ui-monospace,Menlo,monospace;font-size:11.5px;margin-left:14px}
  #spa-log .tool b{color:#1565c0}
  #spa-log details.think{background:#f3eefc;border:1px solid #e0d6f3;border-radius:8px;
    margin:0 0 10px;padding:4px 10px;color:#4a3b6b;margin-left:14px}
  #spa-log details.think summary{cursor:pointer;font-size:12px;color:#6a4bb0;outline:none}
  #spa-log details.think .body{white-space:pre-wrap;font-size:12px;margin-top:6px;
    max-height:220px;overflow-y:auto}
  #spa-log a{color:#1565c0}
  #spa-foot{display:flex;border-top:1px solid #e2e4e8;background:#fff}
  #spa-in{flex:1;border:none;padding:10px;font:inherit;resize:none;outline:none;height:42px}
  #spa-send{border:none;background:#1565c0;color:#fff;padding:0 16px;cursor:pointer;font-weight:600}
  #spa-send:disabled{opacity:.5;cursor:default}
  #spa-note{font-size:11px;color:#888;padding:2px 10px 8px;background:#f7f8fa}`;
  var style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  // ---- DOM ---------------------------------------------------------------
  var btn = el("button", { id: "spa-chat-btn", title: "Ask the genome agent" });
  btn.textContent = "🧬";
  var panel = el("div", { id: "spa-chat" });
  panel.innerHTML =
    '<header><span>Spalangia genome agent</span><span class="x" title="close">×</span></header>' +
    '<div id="spa-log"></div>' +
    '<div id="spa-note">Ask about genes, functions, contigs, or project results.</div>' +
    '<div id="spa-foot"><textarea id="spa-in" placeholder="e.g. How many contigs? What does BRK_g323 do?"></textarea>' +
    '<button id="spa-send">Send</button></div>';
  document.body.appendChild(btn);
  document.body.appendChild(panel);

  var log = panel.querySelector("#spa-log");
  var input = panel.querySelector("#spa-in");
  var send = panel.querySelector("#spa-send");

  btn.onclick = function () {
    panel.classList.toggle("open");
    if (panel.classList.contains("open")) input.focus();
  };
  panel.querySelector(".x").onclick = function () {
    panel.classList.remove("open");
  };
  input.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  });
  send.onclick = submit;

  // ---- helpers -----------------------------------------------------------
  function el(tag, attrs) {
    var n = document.createElement(tag);
    if (attrs) for (var k in attrs) n.setAttribute(k, attrs[k]);
    return n;
  }
  function add(cls, text) {
    var d = el("div", { class: "msg " + cls });
    d.appendChild(linkify(text));
    log.appendChild(d);
    log.scrollTop = log.scrollHeight;
    return d;
  }
  function addThinking(text) {
    var d = el("details", { class: "think" });
    var s = el("summary");
    s.textContent = "🧠 thinking";
    var b = el("div", { class: "body" });
    b.textContent = text;
    d.appendChild(s);
    d.appendChild(b);
    log.appendChild(d);
    log.scrollTop = log.scrollHeight;
  }
  function linkify(text) {
    var frag = document.createDocumentFragment();
    var re = /(https?:\/\/[^\s)]+)/g;
    var last = 0,
      m;
    while ((m = re.exec(text))) {
      if (m.index > last)
        frag.appendChild(document.createTextNode(text.slice(last, m.index)));
      var a = el("a", { href: m[1] });
      // JBrowse deep links (same host) navigate this page; others open a tab.
      if (m[1].indexOf(location.hostname + ":" + location.port) === -1)
        a.setAttribute("target", "_blank");
      a.textContent = m[1];
      frag.appendChild(a);
      last = m.index + m[1].length;
    }
    if (last < text.length)
      frag.appendChild(document.createTextNode(text.slice(last)));
    return frag;
  }

  // ---- chat over SSE -----------------------------------------------------
  function submit() {
    var q = input.value.trim();
    if (!q) return;
    input.value = "";
    add("user", q);
    send.disabled = true;
    var bot = null;

    fetch(AGENT + "/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ q: q, max_turns: 6 }),
    })
      .then(function (r) {
        if (!r.ok || !r.body) throw new Error("agent HTTP " + r.status);
        var reader = r.body.getReader();
        var dec = new TextDecoder();
        var buf = "";
        (function pump() {
          return reader.read().then(function (res) {
            if (res.done) {
              send.disabled = false;
              return;
            }
            buf += dec.decode(res.value, { stream: true });
            var parts = buf.split("\n\n");
            buf = parts.pop();
            parts.forEach(function (chunk) {
              var line = chunk.replace(/^data: ?/, "");
              if (!line) return;
              var ev;
              try {
                ev = JSON.parse(line);
              } catch (e) {
                return;
              }
              if (ev.type === "thinking") {
                addThinking(ev.text);
              } else if (ev.type === "text") {
                bot = add("bot", ev.text);
              } else if (ev.type === "tool_use") {
                add("tool", "▸ " + ev.name + "(" + JSON.stringify(ev.input || {}) + ")");
              } else if (ev.type === "tool_result") {
                // keep it short — full JSON can be large
                var s = JSON.stringify(ev.result);
                if (s.length > 300) s = s.slice(0, 300) + "…";
                add("tool", "  ⤷ " + s);
              } else if (ev.type === "done") {
                send.disabled = false;
              }
            });
            return pump();
          });
        })();
      })
      .catch(function (err) {
        add(
          "bot",
          "⚠ " +
            err.message +
            "  (is the agent up on " +
            AGENT +
            " and is OPENROUTER_API_KEY set?)"
        );
        send.disabled = false;
      });
  }
})();
