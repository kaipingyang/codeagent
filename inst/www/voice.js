/* codeagent voice.js — Web Speech API voice input for chat */

(function () {
  "use strict";

  var recognition = null;
  var isRecording  = false;

  function getStatusEl() { return document.getElementById("ca-speech-status"); }
  function getVoiceBtn() { return document.getElementById("ca_voice_btn"); }

  function setStatus(text, active) {
    var el  = getStatusEl();
    var btn = getVoiceBtn();
    if (el)  el.textContent = text || "";
    if (btn) {
      if (active) btn.classList.add("is-recording");
      else        btn.classList.remove("is-recording");
    }
  }

  function stopRecognition() {
    isRecording = false;
    if (recognition) { try { recognition.stop(); } catch (e) {} recognition = null; }
    setStatus("", false);
  }

  function startRecognition() {
    var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      setStatus("Speech recognition requires Chrome/Edge.", false);
      return;
    }
    recognition               = new SR();
    recognition.lang          = document.documentElement.lang || navigator.language || "en-US";
    recognition.interimResults = true;
    recognition.continuous    = false;

    recognition.onstart = function () {
      isRecording = true;
      setStatus("Listening…", true);
    };

    recognition.onresult = function (e) {
      var finalText = "", interimText = "";
      for (var i = e.resultIndex; i < e.results.length; i++) {
        var t = (e.results[i][0] && e.results[i][0].transcript) || "";
        if (e.results[i].isFinal) finalText += t;
        else interimText += t;
      }
      var text = (finalText || interimText).trim();
      if (!text) return;
      // Use Shiny message so server can update_chat_user_input (proper binding)
      if (typeof Shiny !== "undefined") {
        Shiny.setInputValue("ca_voice_text",
          { text: text, final: !!finalText, ts: Date.now() },
          { priority: "event" });
      }
      if (finalText) setStatus("Voice text added.", false);
    };

    recognition.onerror = function (e) {
      setStatus(e && e.error ? ("Speech error: " + e.error) : "Speech recognition failed.", false);
      recognition = null;
      isRecording = false;
    };

    recognition.onend = function () {
      var el = getStatusEl();
      if (el && el.textContent === "Listening…") setStatus("", false);
      recognition = null;
      isRecording = false;
    };

    recognition.start();
  }

  // Button click toggle
  document.addEventListener("click", function (e) {
    if (!e.target.closest("#ca_voice_btn")) return;
    if (isRecording) stopRecognition();
    else startRecognition();
  });

  // Local file: icon button -> hidden <input type=file>
  document.addEventListener("click", function (e) {
    if (!e.target.closest("#ca_upload_local_btn")) return;
    var fi = document.getElementById("ca_file_hidden");
    if (fi) fi.click();
  });

  document.addEventListener("DOMContentLoaded", function () {
    var fi = document.getElementById("ca_file_hidden");
    if (!fi) return;
    fi.addEventListener("change", function (e) {
      if (!e.target.files.length) return;
      var names = Array.from(e.target.files).map(function (f) { return f.name; }).join(", ");
      if (typeof Shiny !== "undefined") {
        Shiny.setInputValue("ca_uploaded_files",
          { names: names, ts: Date.now() }, { priority: "event" });
      }
      e.target.value = "";
    });
  });
})();
