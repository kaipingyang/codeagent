# AskUserForm widgets

How each AskUserForm field type is drawn. The model only names the type
(`select`, `date`, ...); the host picks the widget with `form_widgets =`
on
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
/
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md).
A widget is `function(id, label, value, choices, field)` returning UI
whose value comes back as `input[[id]]` in the shape the native Shiny
control gives, so collection and validation (`.form_collect()`) do not
depend on it.
