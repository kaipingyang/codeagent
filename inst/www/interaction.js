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
    var eyebrow = card.querySelector(".ca-q-eyebrow");
    if (eyebrow) eyebrow.textContent = page.getAttribute("data-header") || "";
    card.querySelectorAll(".ca-q-nav-item").forEach(function (b) {
      var k = parseInt(b.getAttribute("data-i"), 10), p = pageOf(card, k), cur = k === i;
      b.classList.toggle("is-current", cur);
      b.setAttribute("aria-selected", cur ? "true" : "false");
      var skipped = p.getAttribute("data-skipped") === "true";
      b.classList.toggle("is-skipped", skipped);
      b.classList.toggle("is-answered", !skipped && answered(p));
    });
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
    var navItem = e.target.closest(".ca-q-nav-item");
    if (navItem) { go(card, parseInt(navItem.getAttribute("data-i"), 10)); return; }
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
    if (card && e.target.classList.contains("ca-q-nav-item") && (e.key === "ArrowRight" || e.key === "ArrowLeft")) {
      e.preventDefault();
      var n = pages(card).length, k = current(card) + (e.key === "ArrowRight" ? 1 : -1);
      go(card, ((k - 1 + n) % n) + 1);
      var next = card.querySelector('.ca-q-nav-item[data-i="' + current(card) + '"]');
      if (next) next.focus();
      return;
    }
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
    grpInit(root);
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
  // ---- Grouping field (AskUserForm type "grouping") ---------------------------
  // Rows of [group name | drop-down checklist of the choices]; "+ Add group"
  // adds a row. A choice checked in one row is shown as taken (and disabled)
  // in the others. The rows go to input <data-input> as JSON [{name, items}].
  function grpRows(g) { return Array.prototype.slice.call(g.querySelectorAll(".ca-grp-rows > .ca-grp-row")); }
  function grpSync(g) {
    var rows = grpRows(g), owner = {};
    rows.forEach(function (r) {
      var name = r.querySelector(".ca-grp-name").value.trim() || "(unnamed)";
      r.querySelectorAll(".ca-grp-opt input:checked").forEach(function (c) { if (!(c.value in owner)) owner[c.value] = { row: r, name: name }; });
    });
    var value = rows.map(function (r) {
      var items = [];
      r.querySelectorAll(".ca-grp-opt input").forEach(function (c) {
        var o = owner[c.value], other = o && o.row !== r;
        if (other && c.checked) c.checked = false;
        c.disabled = !!other;
        c.closest(".ca-grp-opt").classList.toggle("is-taken", !!other);
        c.closest(".ca-grp-opt").querySelector(".ca-grp-taken").textContent = other ? "in " + o.name : "";
        if (c.checked) items.push(c.value);
      });
      var sum = r.querySelector(".ca-grp-summary");
      sum.textContent = items.length ? items.join(", ") : "Choose items";
      sum.classList.toggle("is-empty", !items.length);
      return { name: r.querySelector(".ca-grp-name").value.trim(), items: items };
    });
    var all = g.querySelectorAll(".ca-grp-rows .ca-grp-opt input").length / Math.max(rows.length, 1);
    var left = all - Object.keys(owner).length, note = g.querySelector(".ca-grp-left");
    if (note) note.textContent = left > 0 ? left + " item(s) not in a group stay on their own." : "";
    if (window.Shiny && Shiny.setInputValue) Shiny.setInputValue(g.getAttribute("data-input"), JSON.stringify(value), { priority: "event" });
  }
  function grpInit(root) {
    (root.querySelectorAll ? root : document).querySelectorAll(".ca-grouping:not([data-ready])").forEach(function (g) {
      g.setAttribute("data-ready", "true");
      grpSync(g);
    });
  }
  document.addEventListener("change", function (e) { var g = e.target.closest && e.target.closest(".ca-grouping"); if (g) grpSync(g); });
  document.addEventListener("input", function (e) { var g = e.target.closest && e.target.closest(".ca-grouping"); if (g && e.target.classList.contains("ca-grp-name")) grpSync(g); });
  document.addEventListener("click", function (e) {
    var g = e.target.closest && e.target.closest(".ca-grouping"); if (!g) return;
    if (e.target.closest(".ca-grp-add")) {
      var t = g.querySelector(".ca-grp-template"), rows = g.querySelector(".ca-grp-rows");
      var row = t.content.firstElementChild.cloneNode(true);
      var used = grpRows(g).map(function (r) { return r.querySelector(".ca-grp-name").value.trim(); });
      var n = grpRows(g).length + 1; while (used.indexOf("Group " + n) >= 0) n++;
      row.querySelector(".ca-grp-name").value = "Group " + n;
      rows.appendChild(row); grpSync(g); row.querySelector(".ca-grp-name").select();
    } else if (e.target.closest(".ca-grp-remove")) {
      if (grpRows(g).length > 1) e.target.closest(".ca-grp-row").remove();
      grpSync(g);
    }
  });
  // one drop-down open at a time; a click outside closes it
  document.addEventListener("click", function (e) {
    document.querySelectorAll(".ca-grp-pick[open]").forEach(function (d) { if (!d.contains(e.target)) d.removeAttribute("open"); });
  });

  // ---- Seat: the card floats right above the composer -------------------------
  // The card is rendered in the chat footer (below the composer). While one is
  // shown and the composer is visible, the output is positioned over the chat,
  // bottom edge just above the composer, same width, at most half the chat's
  // height. A hidden composer (theme "dsh" gives the card its seat) or a page
  // without one leaves the card where it is.
  var GAP = 8, observed = new WeakSet(), ro = window.ResizeObserver ? new ResizeObserver(placeAll) : null;
  function place(out) {
    var layout = out.closest(".shiny-chat-layout");
    var composer = layout && layout.querySelector(".shiny-chat-composer");
    var show = !!(composer && out.querySelector(".ca-interaction") && composer.offsetParent &&
                  composer.getBoundingClientRect().height > 0);
    out.classList.toggle("ca-ia-overlay", show);
    if (!show) { out.style.removeProperty("--ca-ia-left"); return; }
    if (ro && !observed.has(layout)) { ro.observe(layout); ro.observe(composer); observed.add(layout); }
    var l = layout.getBoundingClientRect(), c = composer.getBoundingClientRect();
    out.style.setProperty("--ca-ia-left", (c.left - l.left) + "px");
    out.style.setProperty("--ca-ia-width", c.width + "px");
    // The seat reaches down to the composer; its padding is the gap, painted
    // with the page background so nothing underneath shows between the two.
    out.style.setProperty("--ca-ia-bottom", (l.bottom - c.top) + "px");
    out.style.setProperty("--ca-ia-gap", GAP + "px");
    out.style.setProperty("--ca-ia-max-height", Math.max(160, Math.min(l.height * 0.5, c.top - l.top)) + "px");
  }
  // The slash-command palette (shinychat) floats at the caret, at most 400px
  // wide. Publish the composer's box so styles.css can give it the
  // composer's left edge and width, just above it.
  function composerVars() {
    var comp = Array.prototype.find.call(document.querySelectorAll(".shiny-chat-composer"),
      function (c) { return c.offsetParent && c.getBoundingClientRect().height > 0; });
    if (!comp) return;
    if (ro && !observed.has(comp)) { ro.observe(comp); observed.add(comp); }
    var c = comp.getBoundingClientRect(), root = document.documentElement.style;
    root.setProperty("--ca-composer-left", c.left + "px");
    root.setProperty("--ca-composer-width", c.width + "px");
    root.setProperty("--ca-composer-above", (window.innerHeight - c.top + GAP) + "px");
    document.documentElement.setAttribute("data-ca-composer", "");
  }
  // Running tools' progress (codeagent_progress(), agent.js renders it): the
  // same seat, stacked above a card when one is shown.
  function placeProgress(box) {
    if (ro && !observed.has(box)) { ro.observe(box); observed.add(box); }
    var layout = box.closest(".shiny-chat-layout");
    var composer = layout && layout.querySelector(".shiny-chat-composer");
    var show = !!(composer && box.classList.contains("ca-tool-progress--on") && composer.offsetParent &&
                  composer.getBoundingClientRect().height > 0);
    box.classList.toggle("ca-progress-overlay", show);
    if (!show) return;
    var l = layout.getBoundingClientRect(), c = composer.getBoundingClientRect();
    var card = layout.querySelector("#ca_interaction_ui.ca-ia-overlay");
    box.style.setProperty("--ca-ia-left", (c.left - l.left) + "px");
    box.style.setProperty("--ca-ia-width", c.width + "px");
    box.style.setProperty("--ca-ia-bottom", (l.bottom - c.top + GAP + (card ? card.getBoundingClientRect().height : 0)) + "px");
  }
  // A card whose UI brings new dependencies (a date picker, another widget
  // package) is inserted after they load, later than shiny:value: watch the
  // output itself and place it when its content changes.
  var watched = new WeakSet();
  function watch(out) {
    if (watched.has(out) || !window.MutationObserver) return;
    watched.add(out);
    new MutationObserver(function () { init(document); placeAll(); }).observe(out, { childList: true });
  }
  // A scrolling card body that has more below fades out at its bottom edge.
  function updateMore(body) {
    body.classList.toggle("ca-has-more", body.scrollTop + body.clientHeight < body.scrollHeight - 4);
  }
  document.addEventListener("scroll", function (e) {
    var t = e.target;
    if (t && t.matches && t.matches(".ca-interaction--scroll > .ca-interaction-body")) updateMore(t);
  }, true);
  function placeAll() {
    document.querySelectorAll(".ca-interaction--scroll > .ca-interaction-body").forEach(updateMore);
    document.querySelectorAll("#ca_interaction_ui").forEach(watch);
    document.querySelectorAll("#ca_interaction_ui").forEach(place);
    document.querySelectorAll("#ca_tool_progress").forEach(placeProgress);
    composerVars();
  }
  window.addEventListener("resize", placeAll);
  document.addEventListener("focusin", function (e) {
    if (e.target.closest && e.target.closest(".shiny-chat-composer")) composerVars();
  });
  document.addEventListener("DOMContentLoaded", function () { setTimeout(placeAll, 500); });

  // Form: Enter in a one-line field, Ctrl/Cmd+Enter anywhere, submits.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Enter" || e.isComposing || e.repeat) return;
    var form = e.target.closest && e.target.closest(".ca-interaction--form");
    if (!form) return;
    var multi = e.target.tagName === "TEXTAREA" || e.target.isContentEditable;
    if (e.target.closest("button, a") && !(e.ctrlKey || e.metaKey)) return;
    if (multi ? (e.ctrlKey || e.metaKey) : !e.shiftKey) {
      var submit = form.querySelector("#ca_form_submit");
      if (submit && !submit.disabled) { e.preventDefault(); submit.click(); }
    }
  });

  // Form submit refused (missing / invalid fields): say it in the form, mark
  // the fields, bring the first into view. Editing a field clears its mark.
  function formFeedback(m) {
    var card = document.querySelector(".ca-interaction--form");
    if (!card) return;
    var box = card.querySelector(".ca-form-feedback");
    if (box) box.textContent = m.message || "";
    card.querySelectorAll(".ca-form-cell.is-invalid").forEach(function (c) { c.classList.remove("is-invalid"); });
    var first = null;
    (m.fields || []).forEach(function (i) {
      var c = card.querySelector('.ca-form-cell[data-i="' + i + '"]');
      if (c) { c.classList.add("is-invalid"); first = first || c; }
    });
    if (first) {
      first.scrollIntoView({ block: "nearest" });
      var f = Array.prototype.find.call(
        first.querySelectorAll("input:not([type=hidden]), textarea, select, [contenteditable=true], [tabindex]:not([tabindex=\"-1\"])"),
        function (el) { return el.offsetParent !== null && !el.disabled && getComputedStyle(el).visibility !== "hidden"; });
      if (f) f.focus({ preventScroll: true });
    }
  }
  document.addEventListener("input", function (e) {
    var c = e.target.closest && e.target.closest(".ca-form-cell.is-invalid");
    if (c) c.classList.remove("is-invalid");
  }, true);
  var feedbackRegistered = false;
  function registerFeedback() {
    if (feedbackRegistered || !window.Shiny || !Shiny.addCustomMessageHandler) return;
    feedbackRegistered = true;
    Shiny.addCustomMessageHandler("ca_form_feedback", formFeedback);
  }
  registerFeedback();
  document.addEventListener("DOMContentLoaded", registerFeedback);
  if (window.jQuery) jQuery(document).on("shiny:connected", registerFeedback);

  if (window.jQuery) jQuery(document).on("shiny:value", function (e) {
    if (e.name === "ca_interaction_ui") setTimeout(function () { init(document); placeAll(); }, 0);
  });
  document.addEventListener("DOMContentLoaded", function () { init(document); });
})();
