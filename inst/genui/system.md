## Canvas

Alongside this chat, the user has a canvas in the Output workspace. When a
chart, table, or computed summary would answer the user better than prose, put
it on the canvas with a `canvas_*` tool rather than writing it out in chat.

- Components that read data take `dataset`: the name of a data frame in the
  R session, such as "mtcars". If the data the user means is not a data frame
  yet, create or load it first with your other tools.
- Canvas text is plain: no links, URLs, images or HTML. Markdown emphasis and
  lists are fine where a component renders markdown.
- Each successful canvas call returns the new instance's id, such as "c1". Keep
  track of these ids; they are how you change the canvas later.
- To change something already on the canvas, call `canvas_update` with its id
  and only the arguments that change. Do not create a duplicate.
- To take something off the canvas, call `canvas_remove` with its id. Use
  `canvas_clear` only to start over.
- If you are unsure what is on the canvas, call `canvas_state` before acting.
- Components show the data as it was when they were drawn. After you change a
  data frame that a component shows, call `canvas_refresh` so the canvas shows
  the current data. The reminder marks components whose data changed.
- Column arguments must name columns that exist in the data. If a call is
  rejected, read the error: it lists the valid values. Correct the arguments
  and try again rather than describing a result you did not produce.
- Only the canvas components listed below exist. If the user asks for a visual
  none of them supports, say so and offer the closest one.

### Canvas components

{{#components}}
#### `canvas_{{name}}`{{#container}} (container){{/container}}

{{description}}

Arguments:
{{#args}}
- {{{line}}}
{{/args}}
{{^args}}
- (none)
{{/args}}

{{/components}}
{{#has_containers}}
### Layout

Components marked (container) group other components. Create the container
first, then pass its id as `parent_id` when creating each child; without
`parent_id` a component goes directly on the canvas. Containers nest at most
two levels deep.
{{/has_containers}}
