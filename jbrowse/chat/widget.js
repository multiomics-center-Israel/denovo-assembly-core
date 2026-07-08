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
  #spa-note{font-size:11px;color:#888;padding:2px 10px 8px;background:#f7f8fa}
  #spa-goto-btn{position:fixed;right:18px;bottom:78px;z-index:99999;
    width:52px;height:52px;border-radius:50%;border:none;cursor:pointer;
    background:#2e7d32;color:#fff;font-size:22px;box-shadow:0 2px 8px rgba(0,0,0,.35)}
  #spa-docs-btn{position:fixed;right:18px;bottom:138px;z-index:99999;
    width:52px;height:52px;border-radius:50%;border:none;cursor:pointer;
    background:#6a4bb0;color:#fff;font-size:22px;box-shadow:0 2px 8px rgba(0,0,0,.35)}
  .spa-mini{position:fixed;right:18px;bottom:80px;z-index:99999;width:380px;
    max-width:calc(100vw - 36px);display:none;flex-direction:column;background:#fff;
    border:1px solid #ccc;border-radius:10px;box-shadow:0 6px 24px rgba(0,0,0,.3);
    font:13px/1.45 system-ui,Segoe UI,Roboto,sans-serif;overflow:hidden}
  .spa-mini.open{display:flex}
  .spa-mini header{color:#fff;padding:9px 12px;font-weight:600;
    display:flex;justify-content:space-between;align-items:center}
  .spa-mini header .x{cursor:pointer;font-weight:400;font-size:18px;opacity:.85}
  #spa-goto header{background:#2e7d32}
  #spa-docs header{background:#6a4bb0}
  .spa-mini .foot{display:flex;border-bottom:1px solid #e2e4e8}
  .spa-mini .foot input{flex:1;border:none;padding:10px;font:inherit;outline:none}
  .spa-mini .foot button{border:none;color:#fff;padding:0 16px;cursor:pointer;font-weight:600}
  #spa-goto .foot button{background:#2e7d32}
  #spa-docs .foot button{background:#6a4bb0}
  .spa-mini .out{max-height:340px;overflow-y:auto;padding:8px 10px;background:#f7f8fa}
  .spa-mini .hint{font-size:11px;color:#888;padding:6px 10px;background:#f7f8fa}
  .spa-mini .res{margin:0 0 8px;padding:7px 9px;border-radius:7px;background:#fff;
    border:1px solid #e2e4e8;word-break:break-word}
  .spa-mini .res .src{font-weight:600;color:#4a3b6b;font-size:11.5px;display:block;margin-bottom:3px}
  .spa-mini .res.err{border-color:#e6b0b0;color:#8a2b2b}
  .spa-mini .res a{color:#1565c0}
  #spa-genes-btn{position:fixed;right:18px;bottom:198px;z-index:99999;
    width:52px;height:52px;border-radius:50%;border:none;cursor:pointer;
    background:#00838f;color:#fff;font-size:22px;box-shadow:0 2px 8px rgba(0,0,0,.35)}
  #spa-blast-btn{position:fixed;right:18px;bottom:258px;z-index:99999;
    width:52px;height:52px;border-radius:50%;border:none;cursor:pointer;
    background:#e65100;color:#fff;font-size:22px;box-shadow:0 2px 8px rgba(0,0,0,.35)}
  #spa-genes{width:470px}
  #spa-genes header{background:#00838f}
  #spa-blast header{background:#e65100}
  #spa-genes .foot button,#spa-genes .res a{color:inherit}
  .spa-qb{padding:8px 10px;background:#fff;border-bottom:1px solid #e2e4e8}
  .spa-qb .logic{font-size:12px;color:#444;margin-bottom:6px}
  .spa-qb .logic select{font:inherit;padding:2px 4px}
  .spa-cond{display:flex;gap:4px;margin-bottom:5px;align-items:center}
  .spa-cond select,.spa-cond input{font:inherit;padding:5px;border:1px solid #ccc;
    border-radius:5px;min-width:0}
  .spa-cond .f{flex:0 0 118px}
  .spa-cond .op{flex:0 0 86px}
  .spa-cond .v{flex:1}
  .spa-cond .rm{flex:0 0 auto;border:none;background:#eee;border-radius:5px;
    cursor:pointer;padding:5px 8px;color:#666}
  .spa-qb .bar{display:flex;justify-content:space-between;margin-top:4px}
  .spa-qb .add{border:none;background:#e0f2f1;color:#00695c;border-radius:5px;
    cursor:pointer;padding:6px 10px;font-weight:600}
  .spa-qb .run{border:none;background:#00838f;color:#fff;border-radius:5px;
    cursor:pointer;padding:6px 16px;font-weight:600}
  .spa-mini .foot textarea{flex:1;border:none;padding:10px;font:inherit;outline:none;
    resize:vertical;height:70px;font-family:ui-monospace,Menlo,monospace;font-size:11.5px}
  .spa-blast-ctl{display:flex;gap:6px;align-items:center;padding:8px 10px;
    background:#fff;border-bottom:1px solid #e2e4e8;flex-wrap:wrap}
  .spa-blast-ctl select,.spa-blast-ctl input[type=file]{font:inherit;padding:4px}
  .spa-blast-ctl .run{border:none;background:#e65100;color:#fff;border-radius:5px;
    cursor:pointer;padding:6px 16px;font-weight:600;margin-left:auto}
  .spa-mini .res .k{color:#555}`;
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

  // ---- Go-to + Docs-search panels (deterministic, no LLM) ---------------
  var gotoBtn = el("button", { id: "spa-goto-btn", title: "Jump to a genome region / gene" });
  gotoBtn.textContent = "📍";
  var gotoPanel = el("div", { id: "spa-goto", class: "spa-mini" });
  gotoPanel.innerHTML =
    '<header><span>Go to location</span><span class="x" title="close">×</span></header>' +
    '<div class="foot"><input id="spa-goto-in" placeholder="gene id, symbol, or contig:start-end">' +
    '<button id="spa-goto-go">Go</button></div>' +
    '<div class="hint">Coordinates (e.g. ptg000004l:1-200000), a gene id, or a gene symbol.</div>' +
    '<div class="out" id="spa-goto-out"></div>';

  var docsBtn = el("button", { id: "spa-docs-btn", title: "Search the documentation" });
  docsBtn.textContent = "📖";
  var docsPanel = el("div", { id: "spa-docs", class: "spa-mini" });
  docsPanel.innerHTML =
    '<header><span>Search docs</span><span class="x" title="close">×</span></header>' +
    '<div class="foot"><input id="spa-docs-in" placeholder="search pipeline & genome docs">' +
    '<button id="spa-docs-go">Search</button></div>' +
    '<div class="hint">Full-text (BM25) search over the project documentation.</div>' +
    '<div class="out" id="spa-docs-out"></div>';

  var genesBtn = el("button", { id: "spa-genes-btn", title: "Advanced gene search (SQL)" });
  genesBtn.textContent = "🔎";
  var genesPanel = el("div", { id: "spa-genes", class: "spa-mini" });
  genesPanel.innerHTML =
    '<header><span>Gene search</span><span class="x" title="close">×</span></header>' +
    '<div class="spa-qb">' +
    '<div class="logic">Match <select id="spa-genes-logic">' +
    '<option value="AND">all</option><option value="OR">any</option></select> of these:</div>' +
    '<div id="spa-genes-conds"></div>' +
    '<div class="bar"><button class="add" id="spa-genes-add">+ condition</button>' +
    '<button class="run" id="spa-genes-run">Search</button></div></div>' +
    '<div class="hint">Pure SQL over the functional annotation table — no LLM.</div>' +
    '<div class="out" id="spa-genes-out"></div>';

  var blastBtn = el("button", { id: "spa-blast-btn", title: "BLAST search" });
  blastBtn.textContent = "🧪";
  var blastPanel = el("div", { id: "spa-blast", class: "spa-mini" });
  blastPanel.innerHTML =
    '<header><span>BLAST search</span><span class="x" title="close">×</span></header>' +
    '<div class="spa-blast-ctl">' +
    '<select id="spa-blast-prog">' +
    '<option value="blastn">blastn (nucl→genome)</option>' +
    '<option value="tblastn">tblastn (prot→genome)</option>' +
    '<option value="blastp">blastp (prot→proteins)</option>' +
    '<option value="blastx">blastx (nucl→proteins)</option></select>' +
    '<input type="file" id="spa-blast-file" accept=".fa,.fasta,.fna,.faa,.txt">' +
    '<button class="run" id="spa-blast-run">Run</button></div>' +
    '<div class="foot"><textarea id="spa-blast-seq" placeholder="Paste a sequence or FASTA (or choose a file above)…"></textarea></div>' +
    '<div class="hint">Runs server-side against the local DBs; hits become the blast_hits track.</div>' +
    '<div class="out" id="spa-blast-out"></div>';

  document.body.appendChild(gotoBtn);
  document.body.appendChild(docsBtn);
  document.body.appendChild(genesBtn);
  document.body.appendChild(blastBtn);
  document.body.appendChild(gotoPanel);
  document.body.appendChild(docsPanel);
  document.body.appendChild(genesPanel);
  document.body.appendChild(blastPanel);

  // Only one panel open at a time.
  function openOnly(target) {
    [panel, gotoPanel, docsPanel, genesPanel, blastPanel].forEach(function (p) {
      if (p !== target) p.classList.remove("open");
    });
    var willOpen = !target.classList.contains("open");
    target.classList.toggle("open", willOpen);
    return willOpen;
  }

  btn.onclick = function () {
    if (openOnly(panel)) input.focus();
  };
  panel.querySelector(".x").onclick = function () {
    panel.classList.remove("open");
  };
  gotoPanel.querySelector(".x").onclick = function () {
    gotoPanel.classList.remove("open");
  };
  docsPanel.querySelector(".x").onclick = function () {
    docsPanel.classList.remove("open");
  };

  var gotoIn = gotoPanel.querySelector("#spa-goto-in");
  var gotoOut = gotoPanel.querySelector("#spa-goto-out");
  var docsIn = docsPanel.querySelector("#spa-docs-in");
  var docsOut = docsPanel.querySelector("#spa-docs-out");

  gotoBtn.onclick = function () {
    if (openOnly(gotoPanel)) gotoIn.focus();
  };
  docsBtn.onclick = function () {
    if (openOnly(docsPanel)) docsIn.focus();
  };

  gotoPanel.querySelector("#spa-goto-go").onclick = gotoSubmit;
  gotoIn.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); gotoSubmit(); }
  });
  docsPanel.querySelector("#spa-docs-go").onclick = docsSubmit;
  docsIn.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); docsSubmit(); }
  });

  function miniResult(out, cls, srcText, bodyText, url) {
    var d = el("div", { class: "res" + (cls ? " " + cls : "") });
    if (srcText) {
      var s = el("span", { class: "src" });
      s.textContent = srcText;
      d.appendChild(s);
    }
    if (bodyText) d.appendChild(linkify(bodyText));
    if (url) {
      var a = el("a", { href: url });
      a.textContent = "open in browser";
      d.appendChild(document.createElement("br"));
      d.appendChild(a);
    }
    out.appendChild(d);
    return d;
  }

  function gotoSubmit() {
    var q = gotoIn.value.trim();
    if (!q) return;
    gotoOut.textContent = "";
    miniResult(gotoOut, "", null, "resolving…", null);
    fetch(AGENT + "/goto?q=" + encodeURIComponent(q))
      .then(function (r) { return r.json(); })
      .then(function (res) {
        gotoOut.textContent = "";
        if (res && res.found && res.view) {
          var v = res.view;
          var label =
            (res.gene ? res.gene.id + " — " : "") +
            v.contig + ":" + v.start + "-" + v.end;
          miniResult(gotoOut, "", "jumping to", label, res.url);
          if (res.url) location.href = res.url; // JBrowse reads the URL params
        } else {
          miniResult(gotoOut, "err", null,
            (res && res.reason) ? res.reason : "not found: " + q, null);
        }
      })
      .catch(function (err) {
        gotoOut.textContent = "";
        miniResult(gotoOut, "err", null, "⚠ " + err.message, null);
      });
  }

  function docsSubmit() {
    var q = docsIn.value.trim();
    if (!q) return;
    docsOut.textContent = "";
    miniResult(docsOut, "", null, "searching…", null);
    fetch(AGENT + "/docs/search?q=" + encodeURIComponent(q) + "&k=6")
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (res) {
        docsOut.textContent = "";
        var hits = (res && res.hits) || [];
        if (!hits.length) {
          miniResult(docsOut, "", null, "no matches for “" + q + "”", null);
          return;
        }
        hits.forEach(function (h) {
          var t = h.text || "";
          if (t.length > 320) t = t.slice(0, 320) + "…";
          var d = miniResult(docsOut, "", h.source || "doc", t, null);
          if (h.source) {
            var a = el("a", {
              href: AGENT + "/docs/view?source=" + encodeURIComponent(h.source),
              target: "_blank",
            });
            a.textContent = "open full text ↗";
            d.appendChild(document.createElement("br"));
            d.appendChild(a);
          }
        });
      })
      .catch(function (err) {
        docsOut.textContent = "";
        miniResult(docsOut, "err", null,
          "⚠ " + err.message + "  (docs index built on the agent?)", null);
      });
  }

  // ---- Gene search (advanced query builder, pure SQL) -------------------
  var FIELD_OPTS = [
    ["any", "Any field"], ["product", "Product / function"], ["go", "GO term"],
    ["pfam", "PFAM"], ["interpro", "InterPro"], ["ec", "EC number"],
    ["cog", "COG"], ["contig", "Contig"], ["gene_id", "Gene ID"],
    ["transcript_id", "Transcript ID"], ["name", "Name"], ["notes", "Notes"],
  ];
  var OP_OPTS = [["contains", "contains"], ["equals", "equals"], ["regex", "regex"]];
  var genesConds = genesPanel.querySelector("#spa-genes-conds");
  var genesOut = genesPanel.querySelector("#spa-genes-out");

  function optionList(opts, sel) {
    return opts
      .map(function (o) {
        return '<option value="' + o[0] + '"' +
          (o[0] === sel ? " selected" : "") + ">" + o[1] + "</option>";
      })
      .join("");
  }
  function addCond(field, op, value) {
    var row = el("div", { class: "spa-cond" });
    row.innerHTML =
      '<select class="f">' + optionList(FIELD_OPTS, field || "product") + "</select>" +
      '<select class="op">' + optionList(OP_OPTS, op || "contains") + "</select>" +
      '<input class="v" placeholder="value" value="' + (value || "") + '">' +
      '<button class="rm" title="remove">×</button>';
    row.querySelector(".rm").onclick = function () {
      if (genesConds.children.length > 1) genesConds.removeChild(row);
    };
    row.querySelector(".v").addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); genesRun(); }
    });
    genesConds.appendChild(row);
  }
  addCond("product", "contains", "");

  function genesRun() {
    var conds = [];
    Array.prototype.forEach.call(genesConds.children, function (row) {
      var v = row.querySelector(".v").value.trim();
      if (!v) return;
      conds.push({
        field: row.querySelector(".f").value,
        op: row.querySelector(".op").value,
        value: v,
      });
    });
    if (!conds.length) {
      genesOut.textContent = "";
      miniResult(genesOut, "err", null, "enter at least one value", null);
      return;
    }
    var payload = { logic: genesPanel.querySelector("#spa-genes-logic").value, conditions: conds };
    genesOut.textContent = "";
    miniResult(genesOut, "", null, "searching…", null);
    fetch(AGENT + "/genes/search?limit=50&q=" + encodeURIComponent(JSON.stringify(payload)))
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (res) {
        genesOut.textContent = "";
        var rows = (res && res.rows) || [];
        if (res && res.error) { miniResult(genesOut, "err", null, res.error, null); return; }
        if (!rows.length) { miniResult(genesOut, "", null, "no genes matched", null); return; }
        var head = el("div", { class: "hint" });
        head.textContent = rows.length + " gene(s)" + (rows.length >= 50 ? " (showing first 50)" : "");
        genesOut.appendChild(head);
        rows.forEach(function (g) {
          var meta = [];
          if (g.EC_number) meta.push("EC " + g.EC_number);
          if (g.PFAM) meta.push("PFAM " + g.PFAM);
          if (g.COG) meta.push("COG " + String(g.COG).slice(0, 40));
          var body =
            (g.Product || "(no product)") +
            "\n" + (g.Contig || "?") + ":" + g.Start + "-" + g.Stop +
            " (" + (g.Strand || "?") + ")" +
            (meta.length ? "\n" + meta.join("  ·  ") : "");
          miniResult(genesOut, "", g.GeneID + (g.Name ? "  [" + g.Name + "]" : ""),
            body, g.jbrowse || null);
        });
      })
      .catch(function (err) {
        genesOut.textContent = "";
        miniResult(genesOut, "err", null, "⚠ " + err.message, null);
      });
  }
  genesPanel.querySelector("#spa-genes-add").onclick = function () { addCond(); };
  genesPanel.querySelector("#spa-genes-run").onclick = genesRun;
  genesBtn.onclick = function () {
    if (openOnly(genesPanel)) genesConds.querySelector(".v").focus();
  };

  // ---- BLAST search (file upload or pasted sequence) --------------------
  var blastSeq = blastPanel.querySelector("#spa-blast-seq");
  var blastFile = blastPanel.querySelector("#spa-blast-file");
  var blastOut = blastPanel.querySelector("#spa-blast-out");

  blastFile.addEventListener("change", function () {
    var f = blastFile.files && blastFile.files[0];
    if (!f) return;
    var rd = new FileReader();
    rd.onload = function () { blastSeq.value = rd.result; };
    rd.readAsText(f);
  });

  function blastRun() {
    var seq = blastSeq.value.trim();
    if (!seq) {
      blastOut.textContent = "";
      miniResult(blastOut, "err", null, "paste a sequence or choose a FASTA file", null);
      return;
    }
    var prog = blastPanel.querySelector("#spa-blast-prog").value;
    blastOut.textContent = "";
    miniResult(blastOut, "", null, "running " + prog + "… (can take a while)", null);
    fetch(AGENT + "/blast", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: seq, program: prog }),
    })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (o) {
        blastOut.textContent = "";
        var res = o.j || {};
        if (!o.ok || res.error) {
          miniResult(blastOut, "err", null, res.error || res.detail || "BLAST failed", null);
          return;
        }
        var lines = prog + " · " + (res.n_hits || 0) + " hit(s)";
        if (res.evalue) lines += " · e≤" + res.evalue;
        if (res.top_hit) {
          var t = res.top_hit;
          lines += "\ntop: " + (t.name || t.contig) + " " + t.contig +
            ":" + t.start + "-" + t.end + "  " + t.pident + "% id, bit " + t.bitscore;
        }
        if (res.note) lines += "\n" + res.note;
        miniResult(blastOut, "", "BLAST result", lines, res.jbrowse_url || null);
      })
      .catch(function (err) {
        blastOut.textContent = "";
        miniResult(blastOut, "err", null, "⚠ " + err.message, null);
      });
  }
  blastPanel.querySelector("#spa-blast-run").onclick = blastRun;
  blastBtn.onclick = function () {
    if (openOnly(blastPanel)) blastSeq.focus();
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
