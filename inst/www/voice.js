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

  function init() {
    // Voice button toggle
    $(document).on("click", "#ca_voice_btn", function () {
      if (isRecording) stopRecognition();
      else startRecognition();
    });

    // Local file upload is handled by shinychat's native attachment button
    // (chat_ui allow_attachments = TRUE). The old custom #ca_upload_local_btn /
    // #ca_file_hidden path was removed as a duplicate.
  }

  // Wait for jQuery (loaded by Shiny) to be available
  if (typeof $ !== "undefined") {
    $(document).ready(init);
  } else {
    document.addEventListener("DOMContentLoaded", function () {
      if (typeof $ !== "undefined") $(document).ready(init);
      else init();
    });
  }

})();
