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
      if (window.Prism && Prism.highlightAllUnder) {
        setTimeout(function () { try { Prism.highlightAllUnder(area); } catch (e) {} }, 0);
      }
    });

    $(document).on("shiny:value", function (event) {
      if (event.target.id === "main_output") {
        var area = document.getElementById("ca_immediate_area");
        if (area) { area.innerHTML = ""; area.style.display = "none"; }
        event.target.style.visibility = "visible";
        // Re-run Prism highlight on freshly rendered code/diff cards
        if (window.Prism && Prism.highlightAllUnder) {
          setTimeout(function () {
            try { Prism.highlightAllUnder(event.target); } catch (e) {}
          }, 0);
        }
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
          if (!card.getAttribute("data-toolcard-bid")) {
            card.setAttribute("data-toolcard-bid", msg.button_id);
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

  // ---------------------------------------------------------------------------
  // Tool-card interactivity (delegated — right panel re-renders constantly)
  // ---------------------------------------------------------------------------

  // Copy to clipboard
  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-toolcard-copy]");
    if (!btn) return;
    var sel = btn.getAttribute("data-toolcard-copy");
    var node = sel ? document.querySelector(sel) : null;
    var text = node ? node.textContent : "";
    if (!text) return;
    var done = function () {
      var old = btn.getAttribute("title");
      btn.classList.add("toolcard-copied");
      btn.setAttribute("title", "Copied");
      setTimeout(function () {
        btn.classList.remove("toolcard-copied");
        btn.setAttribute("title", old || "Copy");
      }, 1200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(function () {});
    } else {
      var ta = document.createElement("textarea");
      ta.value = text; document.body.appendChild(ta); ta.select();
      try { document.execCommand("copy"); done(); } catch (err) {}
      document.body.removeChild(ta);
    }
  });

  // Image zoom (CSS transform on raster PNG)
  function applyToolcardZoom(frame, mode) {
    var img = frame.querySelector(".toolcard-zoomable");
    if (!img) return;
    var scale = parseFloat(frame.getAttribute("data-toolcard-scale") || "1");
    if (mode === "in")  scale = Math.min(8, scale * 1.25);
    if (mode === "out") scale = Math.max(0.25, scale / 1.25);
    if (mode === "fit") scale = 1;
    frame.setAttribute("data-toolcard-scale", scale);
    img.style.transform = "scale(" + scale + ")";
    img.style.transformOrigin = "top left";
  }

  document.addEventListener("click", function (e) {
    var zb = e.target.closest("[data-toolcard-zoom]");
    if (zb) {
      var frame = zb.closest(".toolcard-img-frame");
      if (frame) applyToolcardZoom(frame, zb.getAttribute("data-toolcard-zoom"));
      return;
    }
    var fb = e.target.closest("[data-toolcard-fullscreen]");
    if (fb) {
      var f = fb.closest(".toolcard-img-frame");
      if (f) {
        if (f.requestFullscreen) f.requestFullscreen();
        else f.classList.toggle("toolcard-fullscreen-overlay");
      }
      return;
    }
    var db = e.target.closest("[data-toolcard-download]");
    if (db) {
      var src = db.getAttribute("data-toolcard-src");
      if (src) {
        var a = document.createElement("a");
        a.href = src; a.download = "plot.png";
        document.body.appendChild(a); a.click(); document.body.removeChild(a);
      }
    }
  });

  // ---------------------------------------------------------------------------
  // Slash-command autocomplete dropdown
  // Layer 1 of the slash-command UX: type "/" in the chat input to see a
  // filtered candidate list. Select a skill → fill+focus; select a local
  // command → fill+submit (so it reaches the .preprocess_input router).
  // The command list is sent by the server via ca_slash_commands once on start.
  // ---------------------------------------------------------------------------
  (function () {
    var cmds = [];          // [{name, description, has_args, type}]
    var dropEl = null;      // the dropdown <ul> element
    var chatId = "chat";    // shinychat id (codeagent uses "chat")

    // Receive command list from server (server_chat.R sends on startup).
    if (typeof Shiny !== "undefined") {
      Shiny.addCustomMessageHandler("ca_slash_commands", function (data) {
        cmds = data || [];
      });
    }

    // Lazily create or return the dropdown element.
    function getDropdown() {
      if (dropEl) return dropEl;
      dropEl = document.createElement("ul");
      dropEl.id = "ca-slash-dropdown";
      dropEl.style.cssText = [
        "position:absolute", "z-index:9999", "background:var(--bs-body-bg,#fff)",
        "border:1px solid var(--bs-border-color,#dee2e6)",
        "border-radius:var(--bs-border-radius,0.375rem)",
        "box-shadow:0 4px 12px rgba(0,0,0,.15)", "list-style:none",
        "margin:0", "padding:4px 0", "min-width:220px", "max-width:380px",
        "max-height:240px", "overflow-y:auto", "display:none"
      ].join(";");
      document.body.appendChild(dropEl);
      return dropEl;
    }

    function hideDropdown() {
      var el = getDropdown();
      el.style.display = "none";
      el.innerHTML = "";
    }

    // Find the textarea inside the shinychat web component.
    function getChatTextarea() {
      var host = document.getElementById(chatId + "_user_input");
      if (!host) host = document.querySelector("shiny-chat-input");
      if (!host) return null;
      return host.querySelector("textarea") || host.querySelector("input[type=text]");
    }

    // Position the dropdown above the textarea.
    function positionDropdown(ta) {
      var el = getDropdown();
      var rect = ta.getBoundingClientRect();
      var scrollY = window.scrollY || document.documentElement.scrollTop;
      var scrollX = window.scrollX || document.documentElement.scrollLeft;
      el.style.left = (rect.left + scrollX) + "px";
      // Place above the textarea if there is room, otherwise below.
      var dropH = Math.min(el.scrollHeight || 240, 240);
      if (rect.top - dropH - 4 > 0) {
        el.style.top = (rect.top + scrollY - dropH - 4) + "px";
      } else {
        el.style.top = (rect.bottom + scrollY + 4) + "px";
      }
    }

    // Submit a selected command via shinychat update.
    function selectCommand(cmd, ta) {
      hideDropdown();
      var val = "/" + cmd.name + (cmd.has_args ? " " : "");
      // Use Shiny message to update the chat input (server-side mirrors).
      if (typeof Shiny !== "undefined" && Shiny.setInputValue) {
        Shiny.setInputValue("ca_slash_select", {
          value: val,
          submit: !cmd.has_args,
          focus: !!cmd.has_args
        }, { priority: "event" });
      }
    }

    function showDropdown(query, ta) {
      var q = query.slice(1).toLowerCase();    // strip leading "/"
      var matches = cmds.filter(function (c) {
        return c.name.toLowerCase().indexOf(q) === 0 ||
               (c.description || "").toLowerCase().indexOf(q) !== -1;
      }).slice(0, 10);

      if (!matches.length) { hideDropdown(); return; }

      var el = getDropdown();
      el.innerHTML = "";
      matches.forEach(function (cmd, i) {
        var li = document.createElement("li");
        li.style.cssText = "padding:6px 12px;cursor:pointer;display:flex;gap:8px;align-items:baseline;";
        li.innerHTML = '<span style="font-weight:600;font-family:monospace;white-space:nowrap">/' +
          escHtml(cmd.name) + '</span>' +
          '<span style="font-size:0.78rem;color:var(--bs-secondary-color,#666);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' +
          escHtml(cmd.description || "") + '</span>';
        li.addEventListener("mousedown", function (e) {
          e.preventDefault();   // don't blur the textarea
          selectCommand(cmd, ta);
        });
        li.addEventListener("mouseenter", function () {
          el.querySelectorAll("li").forEach(function (l) { l.style.background = ""; });
          li.style.background = "var(--bs-primary-bg-subtle,#cfe2ff)";
        });
        li.addEventListener("mouseleave", function () {
          li.style.background = "";
        });
        el.appendChild(li);
      });

      el.style.display = "block";
      positionDropdown(ta);
    }

    function escHtml(s) {
      return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
    }

    // Attach listeners once the DOM is ready.
    function attachListeners() {
      var ta = getChatTextarea();
      if (!ta) { setTimeout(attachListeners, 300); return; }

      ta.addEventListener("input", function () {
        var v = ta.value;
        if (v.startsWith("/") && v.length >= 1) {
          showDropdown(v, ta);
        } else {
          hideDropdown();
        }
      });

      // Keyboard navigation inside the dropdown.
      ta.addEventListener("keydown", function (e) {
        var el = getDropdown();
        if (el.style.display === "none") return;
        var items = el.querySelectorAll("li");
        var active = el.querySelector("li[data-active]");
        var idx = active ? Array.prototype.indexOf.call(items, active) : -1;
        if (e.key === "ArrowDown") {
          e.preventDefault();
          var next = (idx + 1) % items.length;
          items.forEach(function(l){l.removeAttribute("data-active"); l.style.background="";});
          items[next].setAttribute("data-active","1");
          items[next].style.background = "var(--bs-primary-bg-subtle,#cfe2ff)";
        } else if (e.key === "ArrowUp") {
          e.preventDefault();
          var prev = (idx - 1 + items.length) % items.length;
          items.forEach(function(l){l.removeAttribute("data-active"); l.style.background="";});
          items[prev].setAttribute("data-active","1");
          items[prev].style.background = "var(--bs-primary-bg-subtle,#cfe2ff)";
        } else if (e.key === "Enter" || e.key === "Tab") {
          var act = el.querySelector("li[data-active]");
          if (act) {
            e.preventDefault();
            // find command for this item
            var name = act.querySelector("span").textContent.slice(1); // strip "/"
            var cmd = cmds.find(function(c){ return c.name === name; });
            if (cmd) selectCommand(cmd, ta);
          } else if (e.key !== "Enter") {
            // Tab with no active item: just hide
            hideDropdown();
          }
        } else if (e.key === "Escape") {
          hideDropdown();
        }
      });

      document.addEventListener("click", function (e) {
        if (e.target !== ta && !getDropdown().contains(e.target)) hideDropdown();
      });
    }

    // Handle server-side ca_slash_select to fill/submit the input.
    if (typeof Shiny !== "undefined") {
      Shiny.addCustomMessageHandler("ca_slash_fill", function (data) {
        var ta = getChatTextarea();
        if (!ta) return;
        ta.value = data.value || "";
        ta.dispatchEvent(new Event("input", { bubbles: true }));
        if (data.focus) { ta.focus(); hideDropdown(); }
      });
    }

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", attachListeners);
    } else {
      attachListeners();
    }
  })();

})();
