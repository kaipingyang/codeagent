// Workspace tabs (codeagent_workspace_ui): strip events -> input$<ws>_event,
// and the server's "ca_ws_show" message -> which pane is visible. Panes stay
// in the page while hidden, so an iframe in a tab does not reload.
(function () {
  "use strict";
  if (window.__caWorkspace) return;
  window.__caWorkspace = true;

  function wsOf(el) { var w = el.closest("[data-ca-ws]"); return w ? w.getAttribute("data-ca-ws") : null; }
  function send(ws, action, tab) {
    if (!ws || !window.Shiny || !Shiny.setInputValue) return;
    Shiny.setInputValue(ws + "_event", { action: action, tab: tab, nonce: Date.now() }, { priority: "event" });
  }
  function closeMenu() { document.querySelectorAll(".ca-ws-menu").forEach(function (m) { m.remove(); }); }

  document.addEventListener("click", function (e) {
    if (!e.target.closest(".ca-ws-menu")) closeMenu();
    var close = e.target.closest(".ca-ws-tab-close");
    var tab = e.target.closest(".ca-ws-tab");
    if (!tab) return;
    var ws = wsOf(tab), id = tab.getAttribute("data-tab");
    if (close) { e.stopPropagation(); if (isFloating(ws, id)) dockTab(ws, id); send(ws, "close", id); return; }
    if (isFloating(ws, id)) return;        // its window was brought forward (below)
    send(ws, "focus", id);
  });

  // Middle click closes (auxclick; mousedown keeps the browser from autoscrolling).
  document.addEventListener("mousedown", function (e) {
    if (e.button === 1 && e.target.closest(".ca-ws-tab")) e.preventDefault();
  });
  document.addEventListener("auxclick", function (e) {
    var tab = e.target.closest(".ca-ws-tab");
    if (!tab || e.button !== 1) return;
    e.preventDefault();
    if (tab.getAttribute("data-pinned") !== "true") send(wsOf(tab), "close", tab.getAttribute("data-tab"));
  });

  document.addEventListener("contextmenu", function (e) {
    var tab = e.target.closest(".ca-ws-tab");
    if (!tab) return;
    e.preventDefault();
    closeMenu();
    var ws = wsOf(tab), id = tab.getAttribute("data-tab"), pinned = tab.getAttribute("data-pinned") === "true";
    var menu = document.createElement("div");
    menu.className = "ca-ws-menu";
    menu.setAttribute("role", "menu");
    var floating = isFloating(ws, id);
    [[floating ? "dock" : "float", floating ? "Dock" : "Pop out", false],
     ["close", "Close", pinned], ["close_others", "Close others", false],
     [pinned ? "unpin" : "pin", pinned ? "Unpin" : "Pin", false]].forEach(function (it) {
      var b = document.createElement("button");
      b.type = "button"; b.className = "ca-ws-menu-item"; b.setAttribute("role", "menuitem");
      b.textContent = it[1]; b.disabled = it[2];
      b.addEventListener("click", function () {
        closeMenu();
        if (it[0] === "float") floatTab(ws, id);
        else if (it[0] === "dock") dockTab(ws, id);
        else send(ws, it[0], id);
      });
      menu.appendChild(b);
    });
    document.body.appendChild(menu);
    var r = menu.getBoundingClientRect();
    menu.style.left = Math.min(e.clientX, window.innerWidth - r.width - 8) + "px";
    menu.style.top = Math.min(e.clientY, window.innerHeight - r.height - 8) + "px";
    var first = menu.querySelector("button:not([disabled])");
    if (first) first.focus();
  });

  // WAI-ARIA tabs, manual activation: arrows move focus, Enter/Space shows,
  // Delete closes; Escape closes the menu.
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { closeMenu(); return; }
    var tab = e.target.closest && e.target.closest(".ca-ws-tab");
    if (!tab) return;
    var tabs = Array.prototype.slice.call(tab.parentNode.querySelectorAll(".ca-ws-tab"));
    var i = tabs.indexOf(tab);
    if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
      e.preventDefault();
      var next = tabs[(i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
      next.focus();
    } else if (e.key === "Enter" || e.key === " ") {
      e.preventDefault(); send(wsOf(tab), "focus", tab.getAttribute("data-tab"));
    } else if (e.key === "Delete" && tab.getAttribute("data-pinned") !== "true") {
      e.preventDefault(); send(wsOf(tab), "close", tab.getAttribute("data-tab"));
    }
  });

  // Wheel over the strip scrolls it sideways.
  document.addEventListener("wheel", function (e) {
    var strip = e.target.closest && e.target.closest(".ca-ws-strip");
    if (!strip || strip.scrollWidth <= strip.clientWidth || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
    strip.scrollLeft += e.deltaY;
    e.preventDefault();
  }, { passive: false });

  // ---- Floating tabs ---------------------------------------------------------
  // A tab pulled off the strip (drag it down, double-click it, or "Pop out")
  // becomes a window over the page: drag its bar, resize its corner, "Dock"
  // puts it back, x closes the tab. The chat stays usable. The pane is not
  // moved in the page -- only positioned -- so an iframe in it does not reload.
  // Floating is per page (not saved with the conversation).
  var floatState = {};          // ws -> { tab id -> true }
  var zTop = 1060;
  function paneOf(ws, id) {
    var root = document.querySelector('[data-ca-ws="' + ws + '"]');
    return root && root.querySelector('.ca-ws-pane[data-tab="' + id + '"]');
  }
  function isFloating(ws, id) { return !!(floatState[ws] && floatState[ws][id]); }
  function tabTitle(ws, id) {
    var t = document.querySelector('[data-ca-ws="' + ws + '"] .ca-ws-tab[data-tab="' + id + '"] .ca-ws-tab-title');
    return t ? t.textContent.trim() : "";
  }
  function front(pane) { pane.style.zIndex = String(++zTop); }
  function floatTab(ws, id, x, y) {
    var pane = paneOf(ws, id);
    if (!pane || pane.classList.contains("is-floating")) return;
    (floatState[ws] = floatState[ws] || {})[id] = true;
    var n = Object.keys(floatState[ws]).length - 1;
    var w = Math.min(720, window.innerWidth - 40), h = Math.min(520, window.innerHeight - 80);
    var left = x !== undefined ? x - 60 : window.innerWidth - w - 40 - n * 28;
    var strip = document.querySelector('[data-ca-ws="' + ws + '"] .ca-ws-strip');
    var below = strip ? strip.getBoundingClientRect().bottom + 12 : 80;
    var top = y !== undefined ? y - 14 : below + n * 28;
    pane.style.left = Math.max(8, Math.min(left, window.innerWidth - 120)) + "px";
    pane.style.top = Math.max(8, Math.min(top, window.innerHeight - 60)) + "px";
    pane.style.width = w + "px"; pane.style.height = h + "px";
    var bar = document.createElement("div");
    bar.className = "ca-ws-float-bar";
    bar.innerHTML = '<span class="ca-ws-float-title"></span>' +
      '<button type="button" class="ca-ws-float-dock" title="Dock">Dock</button>' +
      '<button type="button" class="ca-ws-float-close" title="Close" aria-label="Close">&times;</button>';
    bar.querySelector(".ca-ws-float-title").textContent = tabTitle(ws, id);
    pane.insertBefore(bar, pane.firstChild);
    pane.classList.add("is-floating"); front(pane);
    // the docked area shows another tab
    var tabs = Array.prototype.slice.call(document.querySelectorAll('[data-ca-ws="' + ws + '"] .ca-ws-tab'))
      .filter(function (t) { return !isFloating(ws, t.getAttribute("data-tab")); });
    var other = tabs.filter(function (t) { return t.getAttribute("data-pinned") !== "true"; }).pop() || tabs[0];
    if (other) send(ws, "focus", other.getAttribute("data-tab"));
    markFloating(ws);
    if (window.jQuery) jQuery(pane).trigger("shown");
  }
  function dockTab(ws, id) {
    var pane = paneOf(ws, id);
    if (floatState[ws]) delete floatState[ws][id];
    if (pane) {
      pane.classList.remove("is-floating");
      ["left", "top", "width", "height", "zIndex"].forEach(function (k) { pane.style[k] = ""; });
      var bar = pane.querySelector(":scope > .ca-ws-float-bar"); if (bar) bar.remove();
    }
    send(ws, "focus", id); markFloating(ws);
  }
  function markFloating(ws) {
    var st = floatState[ws] || {};
    Object.keys(st).forEach(function (id) { if (!paneOf(ws, id)) delete st[id]; });   // closed tabs
    document.querySelectorAll('[data-ca-ws="' + ws + '"] .ca-ws-tab').forEach(function (t) {
      t.classList.toggle("is-floating", !!st[t.getAttribute("data-tab")]);
    });
  }
  document.addEventListener("dblclick", function (e) {
    var tab = e.target.closest && e.target.closest(".ca-ws-tab");
    if (!tab || e.target.closest(".ca-ws-tab-close")) return;
    var ws = wsOf(tab), id = tab.getAttribute("data-tab");
    if (isFloating(ws, id)) dockTab(ws, id); else floatTab(ws, id);
  });
  document.addEventListener("click", function (e) {
    var pane = e.target.closest && e.target.closest(".ca-ws-pane.is-floating");
    if (!pane) {
      var tab = e.target.closest && e.target.closest(".ca-ws-tab.is-floating");
      if (tab) { var p = paneOf(wsOf(tab), tab.getAttribute("data-tab")); if (p) front(p); }
      return;
    }
    var ws = wsOf(pane), id = pane.getAttribute("data-tab");
    front(pane);
    if (e.target.closest(".ca-ws-float-dock")) dockTab(ws, id);
    else if (e.target.closest(".ca-ws-float-close")) { dockTab(ws, id); send(ws, "close", id); }
  }, true);
  // dragging: a floating window by its bar; a tab off the strip (down > 40px)
  var drag = null;
  document.addEventListener("pointerdown", function (e) {
    if (e.button !== 0) return;
    var bar = e.target.closest && e.target.closest(".ca-ws-float-bar");
    if (bar && !e.target.closest("button")) {
      var pane = bar.parentNode, r = pane.getBoundingClientRect();
      drag = { pane: pane, dx: e.clientX - r.left, dy: e.clientY - r.top }; front(pane);
      e.preventDefault(); return;
    }
    var tab = e.target.closest && e.target.closest(".ca-ws-tab");
    if (tab && !e.target.closest(".ca-ws-tab-close")) drag = { tab: tab, x0: e.clientX, y0: e.clientY };
  });
  document.addEventListener("pointermove", function (e) {
    if (!drag) return;
    if (drag.pane) {
      drag.pane.style.left = Math.max(0, Math.min(e.clientX - drag.dx, window.innerWidth - 80)) + "px";
      drag.pane.style.top = Math.max(0, Math.min(e.clientY - drag.dy, window.innerHeight - 40)) + "px";
    } else if (drag.tab && e.clientY - drag.y0 > 40) {
      var ws = wsOf(drag.tab), id = drag.tab.getAttribute("data-tab");
      drag = null;
      if (!isFloating(ws, id)) {
        floatTab(ws, id, e.clientX, e.clientY);
        var pane = paneOf(ws, id);
        if (pane) drag = { pane: pane, dx: 60, dy: 14 };
      }
    }
  });
  document.addEventListener("pointerup", function () { drag = null; });

  function show(data) {
    var root = document.querySelector('[data-ca-ws="' + data.ws + '"]');
    if (!root) return;
    root.querySelectorAll(".ca-ws-pane").forEach(function (p) {
      p.classList.toggle("is-active", p.getAttribute("data-tab") === data.tab);
    });
    root.classList.toggle("has-tabs", !!data.tab);
    markFloating(data.ws);
    var active = root.querySelector('.ca-ws-tab[data-tab="' + data.tab + '"]');
    if (active && active.scrollIntoView) active.scrollIntoView({ block: "nearest", inline: "nearest" });
    if (window.Shiny && Shiny.bindAll) $(root).trigger("shown");
  }
  var registered = false;
  function register() {
    if (registered || !window.Shiny || !Shiny.addCustomMessageHandler) return;
    registered = true;
    Shiny.addCustomMessageHandler("ca_ws_show", function (data) {
      // The strip re-renders in the same flush: apply after it lands.
      setTimeout(function () { show(data); }, 0);
    });
  }
  register();
  document.addEventListener("DOMContentLoaded", register);
  if (window.jQuery) jQuery(document).on("shiny:connected", register);
})();
