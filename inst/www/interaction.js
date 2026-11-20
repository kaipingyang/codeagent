// Interaction cards seated where the composer is (R/server_interaction.R).
// Question card: answers stay in the page while it is open and go to the server
// at once as input$ca_q_answers. Approval card: Enter = Allow once, a click
// locks the card so one request gets one answer.
(function () {
  "use strict";
  if (window.__caInteraction) return;
  window.__caInteraction = true;

  function send(name, value) {
    if (window.Shiny && Shiny.setInputValue) Shiny.setInputValue(name, value, { priority: "event" });
  }
  function pages(card) { return Array.prototype.slice.call(card.querySelectorAll(".ca-q-page")); }
  function current(card) { return parseInt(card.getAttribute("data-page") || "1", 10); }
  function pageOf(card, i) { return card.querySelector('.ca-q-page[data-i="' + i + '"]'); }
  function isMulti(page) { return page.getAttribute("data-multi") === "true"; }
  function text(page) { var t = page.querySelector(".ca-q-text"); return t ? t.value.trim() : ""; }

  function answered(page) {
    if (page.getAttribute("data-skipped") === "true") return true;
    return !!page.querySelector(".ca-q-option.is-selected") || text(page).length > 0;
  }

  function sync(card) {
    var n = pages(card).length, i = current(card), page = pageOf(card, i);
    pages(card).forEach(function (p) { p.hidden = p !== page; });
    card.querySelector(".ca-q-progress").textContent = i + " / " + n;
    card.querySelector(".ca-q-prev").disabled = i <= 1;
    card.querySelector(".ca-q-next-page").disabled = i >= n;
    var submit = card.querySelector(".ca-q-submit");
    submit.textContent = i < n ? "Next" : "Submit";
    submit.disabled = !answered(page);
    var mini = card.querySelector(".ca-q-mini-title");
    if (mini) mini.textContent = (page.querySelector(".ca-q-title") || {}).textContent || "";
    var custom = page.querySelector(".ca-q-custom");
    if (custom) {
      custom.classList.toggle("has-text", text(page).length > 0);
      custom.classList.toggle("is-yielded", !isMulti(page) && !!page.querySelector(".ca-q-option.is-selected"));
      var box = custom.querySelector(".ca-q-check");
      if (box) box.classList.toggle("is-checked", text(page).length > 0);
    }
    page.querySelectorAll(".ca-q-option").forEach(function (o) {
      o.setAttribute("aria-checked", o.classList.contains("is-selected") ? "true" : "false");
    });
  }

  function go(card, i) {
    var n = pages(card).length;
    card.setAttribute("data-page", String(Math.max(1, Math.min(n, i))));
    card.querySelector(".ca-q-feedback").textContent = "";
    var body = card.querySelector(".ca-q-body");
    if (body) body.scrollTop = 0;
    sync(card);
  }

  function collect(card) {
    return pages(card).map(function (p) {
      return {
        selected: Array.prototype.map.call(p.querySelectorAll(".ca-q-option.is-selected"),
          function (o) { return o.getAttribute("data-label"); }),
        custom: text(p),
        skipped: p.getAttribute("data-skipped") === "true"
      };
    });
  }

  function lock(card) {
    card.classList.add("is-busy");
    card.setAttribute("aria-busy", "true");
    card.querySelectorAll("button, textarea").forEach(function (b) { b.disabled = true; });
  }

  function submit(card) {
    var n = pages(card).length, i = current(card);
    if (i < n) { go(card, i + 1); return; }
    for (var k = 1; k <= n; k++) {
      if (!answered(pageOf(card, k))) {
        go(card, k);
        card.querySelector(".ca-q-feedback").textContent = "Please complete this question first.";
        return;
      }
    }
    lock(card);
    send("ca_q_answers", { answers: collect(card), nonce: Date.now() });
  }

  function autosize(t) {
    t.style.height = "auto";
    t.style.height = Math.min(t.scrollHeight, 144) + "px";
  }

  document.addEventListener("click", function (e) {
    var card = e.target.closest && e.target.closest(".ca-q-card");
    if (!card || card.classList.contains("is-busy")) return;
    var opt = e.target.closest(".ca-q-option");
    if (opt) {
      var page = opt.closest(".ca-q-page");
      page.removeAttribute("data-skipped");
      if (isMulti(page)) {
        opt.classList.toggle("is-selected");
      } else {
        page.querySelectorAll(".ca-q-option").forEach(function (o) { o.classList.toggle("is-selected", o === opt); });
        var t = page.querySelector(".ca-q-text");
        if (t) { t.value = ""; autosize(t); }
        sync(card);
        if (current(card) < pages(card).length) { go(card, current(card) + 1); return; }
      }
      sync(card);
      return;
    }
    if (e.target.closest(".ca-q-prev")) { go(card, current(card) - 1); return; }
    if (e.target.closest(".ca-q-next-page")) { go(card, current(card) + 1); return; }
    if (e.target.closest(".ca-q-skip")) {
      var p = pageOf(card, current(card));
      p.setAttribute("data-skipped", "true");
      if (current(card) < pages(card).length) go(card, current(card) + 1); else submit(card);
      return;
    }
    if (e.target.closest(".ca-q-submit")) { submit(card); return; }
    if (e.target.closest(".ca-q-minimise")) {
      var min = card.classList.toggle("is-minimised");
      var b = card.querySelector(".ca-q-minimise");
      b.setAttribute("aria-label", min ? "Expand" : "Minimize");
      b.setAttribute("title", min ? "Expand" : "Minimize");
      return;
    }
    if (e.target.closest(".ca-q-dismiss")) { lock(card); send("ca_q_answers", { dismissed: true, nonce: Date.now() }); }
  });

  document.addEventListener("input", function (e) {
    if (!e.target.classList || !e.target.classList.contains("ca-q-text")) return;
    var card = e.target.closest(".ca-q-card"), page = e.target.closest(".ca-q-page");
    autosize(e.target);
    page.removeAttribute("data-skipped");
    if (!isMulti(page) && e.target.value.trim().length)
      page.querySelectorAll(".ca-q-option").forEach(function (o) { o.classList.remove("is-selected"); });
    sync(card);
  });

  document.addEventListener("keydown", function (e) {
    if (e.isComposing || e.repeat) return;
    var card = e.target.closest && e.target.closest(".ca-q-card");
    if (card && e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.metaKey && !e.altKey) {
      if (e.target.classList.contains("ca-q-option") || e.target.classList.contains("ca-q-text")) {
        e.preventDefault();
        var page = pageOf(card, current(card));
        if (e.target.classList.contains("ca-q-option") || answered(page)) submit(card);
      }
      return;
    }
    var appr = e.target.closest && e.target.closest('[data-ca-keys="approval"]');
    if (appr && e.key === "Enter" && !e.shiftKey && !e.ctrlKey && !e.metaKey && !e.altKey &&
        !e.target.closest("button, a, input, textarea, select, [contenteditable]")) {
      e.preventDefault();
      var allow = appr.querySelector("#ca_tool_allow");
      if (allow && !allow.disabled) allow.click();
    }
  });

  // One answer per request: a click on an approval button locks the card.
  document.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest('[data-ca-keys="approval"] .ca-interaction-actions .btn');
    if (!b) return;
    var appr = b.closest('[data-ca-keys="approval"]');
    setTimeout(function () {
      appr.classList.add("is-busy");
      appr.setAttribute("aria-busy", "true");
      appr.querySelectorAll(".ca-interaction-actions .btn").forEach(function (x) { x.disabled = true; });
    }, 0);
  });

  // A newly shown card: set up its pages and take focus, so the keys work.
  function init(root) {
    (root.querySelectorAll ? root : document).querySelectorAll(".ca-q-card:not([data-page])").forEach(function (card) {
      card.setAttribute("data-page", "1");
      sync(card);
      var first = card.querySelector(".ca-q-page:not([hidden]) .ca-q-option.is-selected, .ca-q-page:not([hidden]) .ca-q-option, .ca-q-page:not([hidden]) .ca-q-text");
      if (first) first.focus({ preventScroll: true });
    });
    (root.querySelectorAll ? root : document).querySelectorAll('[data-ca-keys="approval"]:not([data-ready])').forEach(function (a) {
      a.setAttribute("data-ready", "true");
      var body = a.querySelector(".ca-interaction-body");
      if (body) { body.setAttribute("tabindex", "0"); body.focus({ preventScroll: true }); }
    });
  }
  if (window.jQuery) jQuery(document).on("shiny:value", function (e) {
    if (e.name === "ca_interaction_ui") setTimeout(function () { init(document); }, 0);
  });
  document.addEventListener("DOMContentLoaded", function () { init(document); });
})();
