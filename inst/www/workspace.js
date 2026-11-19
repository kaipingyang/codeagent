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
    if (close) { e.stopPropagation(); send(ws, "close", id); return; }
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
    [["close", "Close", pinned], ["close_others", "Close others", false],
     [pinned ? "unpin" : "pin", pinned ? "Unpin" : "Pin", false]].forEach(function (it) {
      var b = document.createElement("button");
      b.type = "button"; b.className = "ca-ws-menu-item"; b.setAttribute("role", "menuitem");
      b.textContent = it[1]; b.disabled = it[2];
      b.addEventListener("click", function () { closeMenu(); send(ws, it[0], id); });
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

  function show(data) {
    var root = document.querySelector('[data-ca-ws="' + data.ws + '"]');
    if (!root) return;
    root.querySelectorAll(".ca-ws-pane").forEach(function (p) {
      p.classList.toggle("is-active", p.getAttribute("data-tab") === data.tab);
    });
    root.classList.toggle("has-tabs", !!data.tab);
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
