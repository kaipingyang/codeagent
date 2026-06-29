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
    // Legacy skill-fill path (disabled)
    // Skills now use shinychat::update_chat_user_input() from the server.
    // Keep this block commented for reference/rollback only.
    // ---------------------------------------------------------------------------
    // Shiny.addCustomMessageHandler("fill_skill", function (data) {
    //   var inp = getChatInput();
    //   if (inp) {
    //     inp.value = data.text;
    //     inp.dispatchEvent(new Event("input", { bubbles: true }));
    //     inp.focus();
    //   }
    // });

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

    // ---------------------------------------------------------------------------
    // Tool card click → switch Output tab + select result (LiveTFLAI pattern)
    // MutationObserver binds click to shiny-tool-result elements
    // ---------------------------------------------------------------------------
    Shiny.addCustomMessageHandler("bind_tool_card", function (msg) {
      function tryBind() {
        var cards = document.querySelectorAll("shiny-tool-result");
        for (var i = cards.length - 1; i >= 0; i--) {
          var card = cards[i];
          if (!card.getAttribute("data-ca-bid")) {
            card.setAttribute("data-ca-bid", msg.button_id);
            card.style.cursor = "pointer";
            (function (c, bid) {
              c.addEventListener("click", function () {
                Shiny.setInputValue("select_tool_output", bid, { priority: "event" });
              });
            })(card, msg.button_id);
            return true;
          }
        }
        return false;
      }
      if (tryBind()) return;
      var done = false;
      var tHandle = setTimeout(function () {
        if (!done) observer.disconnect();
      }, 6000);
      var observer = new MutationObserver(function () {
        if (!done && tryBind()) {
          done = true;
          observer.disconnect();
          clearTimeout(tHandle);
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    });
  }
})();
