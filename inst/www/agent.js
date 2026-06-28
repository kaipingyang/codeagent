/* codeagent agent.js — browser-side helpers */

(function () {
  "use strict";

  // ---------------------------------------------------------------------------
  // ESC key → interrupt_flag
  // ---------------------------------------------------------------------------
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if (typeof Shiny === "undefined" || !Shiny.setInputValue) return;
    Shiny.setInputValue("esc", Date.now(), { priority: "event" });
  });

  // ---------------------------------------------------------------------------
  // Token budget bar + text update
  // ---------------------------------------------------------------------------
  if (typeof Shiny !== "undefined") {
    Shiny.addCustomMessageHandler("update_budget", function (data) {
      // Text
      var el = document.getElementById("token-budget-text");
      if (el) el.textContent = data.text;
      // Bar
      var pct = data.pct || 0;
      var fill = document.querySelector(".token-budget-bar-fill");
      if (fill) {
        fill.style.width = Math.min(100, Math.max(0, pct)) + "%";
        fill.classList.remove("warn", "danger");
        if (pct >= 90) fill.classList.add("danger");
        else if (pct >= 70) fill.classList.add("warn");
      }
    });

    // Legacy bar-only handler (kept for compatibility)
    Shiny.addCustomMessageHandler("update_token_bar", function (pct) {
      var fill = document.querySelector(".token-budget-bar-fill");
      if (!fill) return;
      fill.style.width = Math.min(100, Math.max(0, pct)) + "%";
      fill.classList.remove("warn", "danger");
      if (pct >= 90) fill.classList.add("danger");
      else if (pct >= 70) fill.classList.add("warn");
    });

    // ---------------------------------------------------------------------------
    // Fill chat input when a skill button is clicked
    // ---------------------------------------------------------------------------
    Shiny.addCustomMessageHandler("fill_skill", function (data) {
      var inp = document.querySelector("shiny-chat-input textarea");
      if (!inp) inp = document.querySelector("[id$='_user_input']");
      if (!inp) inp = document.getElementById("chat_user_input");
      if (inp) {
        inp.value = data.text;
        inp.dispatchEvent(new Event("input", { bubbles: true }));
        inp.focus();
      }
    });

    // ---------------------------------------------------------------------------
    // Two-phase display: tool returns → immediate push → renderUI replaces
    // ---------------------------------------------------------------------------
    Shiny.addCustomMessageHandler("show_ca_immediate", function (data) {
      var area = document.getElementById("ca_immediate_area");
      if (!area) return;
      area.innerHTML = data.html;
      area.style.display = "block";
      var preview = document.getElementById("main_output");
      if (preview) preview.style.visibility = "hidden";
    });

    $(document).on("shiny:value", function (event) {
      if (event.target.id === "main_output") {
        var area = document.getElementById("ca_immediate_area");
        if (area) { area.innerHTML = ""; area.style.display = "none"; }
        event.target.style.visibility = "visible";
      }
    });
    Shiny.addCustomMessageHandler("set_theme", function (data) {
      document.documentElement.setAttribute("data-theme", data.theme);
    });
  }
})();
