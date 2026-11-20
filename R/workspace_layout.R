#' @title Workspace layout engine
#' @description Pure functions over the right-panel workspace layout: each
#'   returns a new layout, none reads the clock or the session. A layout is
#'   `list(tabs, active, seen, next_id)`: `tabs` in strip order (pinned first),
#'   `active` the shown tab id or `NULL`, `seen` tab ids from least to most
#'   recently viewed (eviction order), `next_id` the counter for tab ids.
#'   A tab is `list(id, kind, content_id, title, pinned)`; `(kind, content_id)`
#'   is its content identity.
#' @name workspace_layout
#' @keywords internal
NULL

.ws_layout <- function() {
  list(tabs = list(), active = NULL, seen = character(0), next_id = 1L)
}

.ws_ids <- function(layout) vapply(layout$tabs, `[[`, "", "id")

.ws_index <- function(layout, id) {
  if (!is.character(id) || length(id) != 1L) return(NA_integer_)
  match(id, .ws_ids(layout))
}

.ws_find <- function(layout, kind, content_id) {
  for (t in layout$tabs)
    if (identical(t$kind, kind) && identical(t$content_id, content_id)) return(t$id)
  NULL
}

.ws_focus <- function(layout, id) {
  if (is.na(.ws_index(layout, id))) return(layout)
  layout$active <- id
  layout$seen <- c(setdiff(layout$seen, id), id)
  layout
}

# Pinned tabs first, each group in its current order.
.ws_sort <- function(layout) {
  pinned <- vapply(layout$tabs, function(t) isTRUE(t$pinned), NA)
  layout$tabs <- c(layout$tabs[pinned], layout$tabs[!pinned])
  layout
}

.ws_open <- function(layout, kind, content_id, title = NULL, pinned = FALSE,
                     reveal = TRUE, max_tabs = Inf) {
  hit <- .ws_find(layout, kind, content_id)
  if (!is.null(hit)) return(if (isTRUE(reveal)) .ws_focus(layout, hit) else layout)
  id <- paste0("t_", layout$next_id)
  layout$next_id <- layout$next_id + 1L
  layout$tabs[[length(layout$tabs) + 1L]] <- list(
    id = id, kind = kind, content_id = content_id,
    title = title %||% content_id, pinned = isTRUE(pinned))
  layout <- .ws_sort(layout)
  if (isTRUE(reveal) || is.null(layout$active)) layout <- .ws_focus(layout, id)
  else layout$seen <- c(id, layout$seen)   # opened in the background: first to go
  .ws_evict(layout, max_tabs, keep = id)
}

# Close least recently viewed unpinned tabs until at most max_tabs remain.
.ws_evict <- function(layout, max_tabs = Inf, keep = NULL) {
  while (length(layout$tabs) > max_tabs) {
    unpinned <- .ws_ids(layout)[!vapply(layout$tabs, function(t) isTRUE(t$pinned), NA)]
    order <- c(layout$seen[layout$seen %in% unpinned], setdiff(unpinned, layout$seen))
    victim <- setdiff(order, keep)
    if (!length(victim)) break
    layout <- .ws_close(layout, victim[[1L]])
  }
  layout
}

.ws_close <- function(layout, id) {
  i <- .ws_index(layout, id)
  if (is.na(i) || isTRUE(layout$tabs[[i]]$pinned)) return(layout)
  layout$tabs <- layout$tabs[-i]
  layout$seen <- setdiff(layout$seen, id)
  if (identical(layout$active, id)) {
    layout$active <- NULL
    if (length(layout$tabs)) {
      pinned <- vapply(layout$tabs, function(t) isTRUE(t$pinned), NA)
      next_i <- if (all(pinned)) 1L else min(i, length(layout$tabs))
      layout <- .ws_focus(layout, layout$tabs[[next_i]]$id)
    }
  }
  layout
}

.ws_close_others <- function(layout, id) {
  if (is.na(.ws_index(layout, id))) return(layout)
  for (other in setdiff(.ws_ids(layout), id)) layout <- .ws_close(layout, other)
  .ws_focus(layout, id)
}

.ws_pin <- function(layout, id, pinned = TRUE) {
  i <- .ws_index(layout, id)
  if (is.na(i)) return(layout)
  layout$tabs[[i]]$pinned <- isTRUE(pinned)
  .ws_sort(layout)
}

# A layout read back from a session log: keep only well-formed tabs.
.ws_validate <- function(x) {
  out <- .ws_layout()
  if (!is.list(x)) return(out)
  ok <- function(v) is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)
  seen_ids <- character(0)
  for (t in x$tabs %||% list()) {
    if (!is.list(t) || !ok(t$id) || !ok(t$kind) || !ok(t$content_id) ||
        t$id %in% seen_ids) next
    seen_ids <- c(seen_ids, t$id)
    out$tabs[[length(out$tabs) + 1L]] <- list(
      id = t$id, kind = t$kind, content_id = t$content_id,
      title = if (ok(t$title)) t$title else t$content_id, pinned = isTRUE(t$pinned))
  }
  out <- .ws_sort(out)
  ids <- .ws_ids(out)
  seen <- as.character(unlist(x$seen %||% character(0)))
  out$seen <- seen[seen %in% ids]
  nums <- suppressWarnings(as.integer(sub("^t_", "", ids)))
  nid <- suppressWarnings(as.integer(x$next_id))
  out$next_id <- max(max(c(0L, nums[!is.na(nums)])) + 1L,
                     if (length(nid) == 1L && !is.na(nid)) nid else 1L)
  act <- x$active
  if (ok(act) && act %in% ids) out <- .ws_focus(out, act)
  else if (length(ids)) out <- .ws_focus(out, ids[[1L]])
  out
}
