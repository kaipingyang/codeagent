# Extract the plain-text portion from a user-input value

shinychat delivers `input$chat_user_input` as either a character scalar
(attachments off) or a contents list whose first element is the typed
text (attachments on). Return that text as a single string, or `""` when
there is none (empty list, NULL, attachment-only). Never errors.

## Usage

``` r
.user_input_text(x)
```
