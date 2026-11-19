// Point Prism's autoloader at the locally vendored grammars. Loaded right after
// prism-autoloader.min.js (see head_assets() in R/ui_panels.R).
if (window.Prism && Prism.plugins && Prism.plugins.autoloader) {
  Prism.plugins.autoloader.languages_path = 'codeagent-www/vendor/prism/components/';
}
