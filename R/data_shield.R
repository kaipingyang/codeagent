#' Data Shield --- pluggable strict data-safety valve (P0 core)
# Data Shield strategy specification (internal).
.new_shield_strategy <- function(type, ...) {
  structure(list(type = type, config = list(...)), class = "shield_strategy")
}

#' Configure strict protected-data metadata
#'
#' @param distributions Distribution policy. Strict `"off"` is implemented;
#'   `"on"` and `"dp"` are reserved for later phases.
#' @param k_anon Minimum support before a categorical label may be exposed.
#' @param category_max Maximum distinct values for categorical treatment.
#' @param category_ratio Maximum distinct/row ratio for character categories.
#' @return A Data Shield strategy specification.
#' @export
shield_describe <- function(distributions = "off", k_anon = 5L,
                            category_max = 20L, category_ratio = 0.2) {
  .new_shield_strategy(
    "describe", distributions = match.arg(distributions, c("off", "on", "dp")),
    k_anon = as.integer(k_anon), category_max = as.integer(category_max),
    category_ratio = as.numeric(category_ratio))
}

#' Configure tool-result egress protection
#'
#' @param detectors Character vector. Implemented detectors are `"row_cap"`
#'   and `"value_match"`.
#' @param max_rows Rows retained from bulk tabular output (`0` = none).
#' @param on_fail Action label for withheld output. P0/P0.5 support
#'   `"redact"` and `"block"`; `"ask"` is reserved for a later phase.
#' @return A Data Shield strategy specification.
#' @export
shield_egress <- function(detectors = c("row_cap", "value_match"), max_rows = 0L,
                          on_fail = c("redact", "block")) {
  detectors <- match.arg(detectors, c("row_cap", "value_match"), several.ok = TRUE)
  .new_shield_strategy(
    "egress", detectors = detectors, max_rows = as.integer(max_rows),
    on_fail = match.arg(on_fail))
}

#' Stateful protected-data policy engine
#'
#' @description
#' R6 lifecycle owner for protected datasets, deterministic value indexes,
#' strategy configuration, tool wrapping, and strict `DescribeData` metadata.
#' Create one instance per Shiny session or thread; explicitly share an instance
#' only when those chat threads intentionally share the same protected data.
#'
#' `codeagent_client(data_shield = list(shield_*()))` is the declarative
#' convenience path and creates a private `DataShield` internally. Pass an
#' explicit `DataShield` instance when data must be registered dynamically or
#' shared across chats.
#'
#' @export
DataShield <- R6::R6Class(
  "DataShield",
  cloneable = FALSE,
  public = list(
    #' @description Create a Data Shield.
    #' @param max_rows,k_anon,category_max,category_ratio Direct defaults used
    #'   when `strategies` is NULL.
    #' @param distributions Direct strict metadata policy.
    #' @param strategies Optional list from [shield_describe()] and
    #'   [shield_egress()].
    initialize = function(max_rows = 0L, distributions = "off", k_anon = 5L,
                          category_max = 20L, category_ratio = 0.2,
                          strategies = NULL) {
      private$config <- list(
        max_rows = as.integer(max_rows),
        distributions = match.arg(distributions, c("off", "on", "dp")),
        k_anon = as.integer(k_anon), category_max = as.integer(category_max),
        category_ratio = as.numeric(category_ratio),
        detectors = c("row_cap", "value_match"), on_fail = "redact",
        describe_enabled = TRUE, egress_enabled = TRUE)
      private$datasets <- list()
      private$index <- new.env(parent = emptyenv())
      private$strategies <- list()
      private$closed <- FALSE
      if (!is.null(strategies)) {
        private$config$describe_enabled <- FALSE
        private$config$egress_enabled <- FALSE
        for (strategy in strategies) private$apply_strategy(strategy)
      }
    },

    #' @description Register one protected data.frame.
    #' @param df A data.frame.
    #' @param name Dataset name used by `DescribeData`.
    #' @param sensitivity Optional named identifier/quasi/measure/open overrides.
    #' @param cols Optional explicit columns to value-index.
    #' @param min_len,min_card High-entropy index thresholds.
    register_data = function(df, name = NULL, sensitivity = NULL, cols = NULL,
                             min_len = 3L, min_card = 8L) {
      private$assert_open()
      if (!is.data.frame(df)) stop("`df` must be a data.frame.", call. = FALSE)
      if (is.null(name)) name <- paste0("dataset_", length(private$datasets) + 1L)
      if (!is.character(name) || length(name) != 1L || !nzchar(name))
        stop("`name` must be a non-empty character(1).", call. = FALSE)
      sensitivity <- .data_shield_classify_columns(df, sensitivity)
      index_cols <- cols %||%
        names(sensitivity)[sensitivity %in% c("identifier", "quasi")]
      idx <- .data_shield_build_value_index(
        df, cols = index_cols, min_len = min_len, min_card = min_card)
      private$datasets[[name]] <- list(
        name = name, data = df, sensitivity = sensitivity,
        index = idx, index_columns = index_cols)
      private$rebuild_index()
      invisible(length(ls(idx, all.names = TRUE)))
    },

    #' @description Install/refresh this shield on an ellmer Chat.
    install = function(chat) {
      private$assert_open()
      if (!inherits(chat, "Chat"))
        stop("`chat` must be an ellmer Chat.", call. = FALSE)
      attr(chat, "codeagent_data_shield") <- self
      if (isTRUE(private$config$describe_enabled))
        .data_shield_register_describe_tool(chat, self)
      tools <- tryCatch(chat$get_tools(), error = function(e) list())
      if (length(tools)) {
        wrapped <- lapply(tools, function(tool) .data_shield_wrap_tool(tool, self))
        tryCatch(chat$set_tools(wrapped), error = function(e) NULL)
      }
      invisible(chat)
    },

    #' @description Return strict safe metadata for a registered dataset.
    describe = function(name = NULL) {
      private$assert_open()
      if (!isTRUE(private$config$describe_enabled))
        return("[Error] DescribeData strategy is not enabled.")
      if (!length(private$datasets)) return("No protected datasets are registered.")
      if (is.null(name) || !nzchar(name)) {
        if (length(private$datasets) != 1L)
          return(paste0("Protected datasets: ", paste(names(private$datasets), collapse = ", "),
                        ". Call again with data_name."))
        name <- names(private$datasets)[[1L]]
      }
      dataset <- private$datasets[[name]]
      if (is.null(dataset))
        return(sprintf("[Error] Protected dataset '%s' is not registered.", name))
      if (!identical(private$config$distributions, "off"))
        return("[Error] Distribution modes 'on'/'dp' are planned but not implemented; use strict 'off'.")
      .data_shield_describe(dataset, private$config)
    },

    #' @description Apply the egress pipeline to a tool result.
    scan_egress = function(result) {
      private$assert_open()
      if (!isTRUE(private$config$egress_enabled)) return(result)
      .data_shield_filter_result(
        result,
        max_rows = private$config$max_rows,
        index = private$index,
        detectors = private$config$detectors,
        on_fail = private$config$on_fail)
    },

    #' @description Remove one dataset, or all datasets when name is NULL.
    clear = function(name = NULL) {
      private$assert_open()
      if (is.null(name)) private$datasets <- list() else private$datasets[[name]] <- NULL
      private$rebuild_index()
      invisible(self)
    },

    #' @description Clear sensitive state and close the shield.
    close = function() {
      if (!isTRUE(private$closed)) {
        private$datasets <- list()
        rm(list = ls(private$index, all.names = TRUE), envir = private$index)
        private$closed <- TRUE
      }
      invisible(NULL)
    },

    #' @description Summarise non-sensitive runtime coverage.
    coverage = function() {
      list(config = private$config, datasets = names(private$datasets),
           indexed_values = length(ls(private$index, all.names = TRUE)),
           closed = private$closed)
    }
  ),
  private = list(
    config = NULL,
    datasets = NULL,
    index = NULL,
    strategies = NULL,
    closed = FALSE,

    assert_open = function() {
      if (isTRUE(private$closed)) stop("The DataShield is closed.", call. = FALSE)
    },
    apply_strategy = function(strategy) {
      if (!inherits(strategy, "shield_strategy"))
        stop("Every strategy must come from a shield_*() constructor.", call. = FALSE)
      type <- strategy$type
      cfg <- strategy$config
      private$strategies[[length(private$strategies) + 1L]] <- strategy
      if (identical(type, "describe")) {
        private$config$describe_enabled <- TRUE
        private$config[names(cfg)] <- cfg
      } else if (identical(type, "egress")) {
        private$config$egress_enabled <- TRUE
        private$config[names(cfg)] <- cfg
      } else {
        stop("Unknown Data Shield strategy: ", type, call. = FALSE)
      }
    },
    rebuild_index = function() {
      rm(list = ls(private$index, all.names = TRUE), envir = private$index)
      for (dataset in private$datasets) {
        keys <- ls(dataset$index, all.names = TRUE)
        for (key in keys) assign(key, TRUE, envir = private$index)
      }
      invisible(length(ls(private$index, all.names = TRUE)))
    },
    get_index = function() private$index,
    get_config = function() private$config
  )
)

# Resolve NULL / strategy-list / explicit DataShield to one R6 engine.
#' @keywords internal
.data_shield_resolve <- function(x) {
  if (is.null(x)) return(NULL)
  if (inherits(x, "DataShield")) return(x)
  if (is.list(x) && all(vapply(x, inherits, logical(1), "shield_strategy")))
    return(DataShield$new(strategies = x))
  stop("`data_shield` must be NULL, list(shield_*()), or a DataShield instance.",
       call. = FALSE)
}

# Does `text` look like a bulk row-level data dump (vs a scalar/message/summary)?
# Heuristic (v0, to be threat-tested): TRUE when the output has a data.frame /
# tibble print signature, OR is a rectangular table with more than `max_rows`
# data rows. Deliberately conservative -- errs toward FALSE (pass) so harmless
# output is never blocked; small/targeted leaks are value_match's job (P0.5).
.data_shield_is_bulk_tabular <- function(text, max_rows = 10L) {
  if (!is.character(text) || length(text) != 1L || !nzchar(text)) return(FALSE)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  if (length(lines) <= max_rows + 1L) return(FALSE)   # too short to be a bulk dump

  # tibble / data.frame print signatures
  if (any(grepl("^#\\s*A tibble:\\s*[0-9,]+\\s*[x\u00d7]\\s*[0-9]+", lines))) return(TRUE)
  if (any(grepl("\\[[0-9,]+ rows? x [0-9]+ columns?\\]", lines)))            return(TRUE)

  # Rectangular: majority of the (non-blank) lines have >= 2 columns separated
  # by runs of whitespace or by commas, AND column count is consistent-ish.
  nb <- lines[nzchar(trimws(lines))]
  if (length(nb) <= max_rows + 1L) return(FALSE)
  ncols <- vapply(nb, function(l) {
    ws  <- length(strsplit(trimws(l), "\\s{2,}|\\t")[[1L]])
    csv <- length(strsplit(l, ",", fixed = TRUE)[[1L]])
    max(ws, csv)
  }, integer(1))
  multi <- mean(ncols >= 2L) >= 0.7            # >=70% of rows are multi-column
  bulk  <- sum(ncols >= 2L) > max_rows          # more than max_rows such rows
  isTRUE(multi && bulk)
}

# Row-cap a single tool-result text: if it looks like a bulk data dump, replace
# it with a shape summary (optionally keeping the first `max_rows` lines).
# `max_rows = 0` => shape-only. Returns list(text, capped, n_lines).
.data_shield_row_cap <- function(text, max_rows = 0L) {
  if (!.data_shield_is_bulk_tabular(text, max_rows = max(max_rows, 1L)))
    return(list(text = text, capped = FALSE))
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  n     <- length(lines)
  head_lines <- if (max_rows > 0L) paste(utils::head(lines, max_rows), collapse = "\n") else ""
  note <- sprintf(
    "[data_shield] tabular output withheld: %d lines look like row-level data.%s",
    n,
    if (max_rows > 0L) sprintf(" First %d line(s) shown; rest omitted.", max_rows) else
      " Use a schema/summary tool instead of dumping rows.")
  list(text = if (nzchar(head_lines)) paste0(head_lines, "\n", note) else note,
       capped = TRUE, n_lines = n)
}

# ---------------------------------------------------------------------------
# P0 wiring: wrap every tool so its result passes through the egress row-cap.
# on_tool_result is a read-only notification in ellmer (cannot rewrite the
# result), so we wrap the tool functions themselves (universal: native / btw /
# MCP / host tools). Off unless a client sets `data_shield`.
# ---------------------------------------------------------------------------

# Apply the egress row-cap to a single tool return value (edge 2). Handles the
# three shapes a tool can return: an ellmer ContentToolResult, a raw data.frame/
# matrix, or a character string. Everything else passes through untouched.
#' @keywords internal
# Run configured egress detectors on model-facing text.
#' @keywords internal
.data_shield_process_text <- function(text, max_rows = 0L, index = NULL,
                                      detectors = c("row_cap", "value_match"),
                                      on_fail = "redact") {
  if (!is.character(text) || length(text) != 1L)
    return(list(text = text, changed = FALSE))
  if ("row_cap" %in% detectors) {
    capped <- .data_shield_row_cap(text, max_rows = max_rows)
    if (isTRUE(capped$capped)) return(list(text = capped$text, changed = TRUE))
  }
  if ("value_match" %in% detectors) {
    matched <- tryCatch(.data_shield_value_scan(text, index),
                        error = function(e) list(hit = FALSE))
    if (isTRUE(matched$hit)) {
      verb <- if (identical(on_fail, "block")) "blocked" else "withheld"
      return(list(
        text = sprintf("[data_shield] output %s: contains %d protected data value(s).",
                       verb, matched$n),
        changed = TRUE))
    }
  }
  list(text = text, changed = FALSE)
}

.data_shield_filter_result <- function(result, max_rows = 0L, index = NULL,
                                       detectors = c("row_cap", "value_match"),
                                       on_fail = "redact") {
  process <- function(text) .data_shield_process_text(
    text, max_rows = max_rows, index = index,
    detectors = detectors, on_fail = on_fail)
  if (isTRUE(tryCatch(S7::S7_inherits(result, ellmer::ContentToolResult),
                      error = function(e) FALSE))) {
    value <- tryCatch(as.character(result@value), error = function(e) NULL)
    if (is.character(value) && length(value) == 1L) {
      filtered <- process(value)
      if (isTRUE(filtered$changed)) result@value <- filtered$text
    }
    return(result)
  }
  if (is.data.frame(result) || is.matrix(result)) {
    text <- tryCatch(paste(utils::capture.output(print(result)), collapse = "\n"),
                     error = function(e) "")
    filtered <- process(text)
    if (isTRUE(filtered$changed)) return(filtered$text)
    return(result)
  }
  if (is.character(result) && length(result) == 1L) {
    filtered <- process(result)
    if (isTRUE(filtered$changed)) return(filtered$text)
  }
  result
}

# Wrap one ToolDef in place. Re-wrapping for a new DataShield unwraps to the
# original function first, avoiding nested cross-session filters.
#' @keywords internal
.data_shield_wrap_tool <- function(tool, shield) {
  current <- tryCatch(S7::S7_data(tool), error = function(e) NULL)
  if (!is.function(current)) return(tool)
  if (identical(attr(current, "data_shield_state"), shield)) return(tool)
  original <- attr(current, "data_shield_original") %||% current
  wrapped <- function(...) shield$scan_egress(original(...))
  attr(wrapped, "data_shield_wrapped") <- TRUE
  attr(wrapped, "data_shield_original") <- original
  attr(wrapped, "data_shield_state") <- shield
  tryCatch({ S7::S7_data(tool) <- wrapped }, error = function(e) NULL)
  tool
}

# ---------------------------------------------------------------------------
# P0.5: value_match --- deterministic detection of *registered* protected
# values in egress text. Catches targeted single-value leaks the shape-based
# row-cap lets through (e.g. printing one subject's name/id). We index only
# HIGH-ENTROPY values (unique, long enough, high-cardinality columns, non
# small-int) so common/categorical values don't cause false positives -- those
# are the describe layer's job. Token-hash matching (v0); delimited/multi-word
# values are a known gap (Aho-Corasick is a later enhancement).
# ---------------------------------------------------------------------------

# Normalise a value/token for matching: casefold + canonical numeric form.
#' @keywords internal
.data_shield_normalize <- function(x) {
  x   <- tolower(as.character(x))
  num <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(num) & nzchar(x), format(num, scientific = FALSE, trim = TRUE), x)
}

# Build a value index (hash set env) from a data.frame's sensitive columns.
#' @keywords internal
.data_shield_build_value_index <- function(df, cols = names(df),
                                           min_len = 3L, min_card = 8L) {
  set <- new.env(parent = emptyenv())
  n <- 0L
  for (cn in intersect(cols, names(df))) {
    v <- df[[cn]]
    if (is.null(v)) next
    vals <- unique(v[!is.na(v)])
    if (length(vals) < min_card) next                     # low-cardinality -> skip
    ch <- as.character(vals)
    ch <- ch[nchar(ch) >= min_len]                        # too short -> skip
    ch <- ch[!grepl("^[0-9]{1,2}$", ch)]                  # pure small int -> skip
    for (x in .data_shield_normalize(ch)) {
      assign(x, TRUE, envir = set); n <- n + 1L
    }
  }
  attr(set, "n") <- n
  set
}

# Scan text for indexed protected values (token-hash, v0).
#' @keywords internal
.data_shield_value_scan <- function(text, index) {
  if (!is.environment(index) || !is.character(text) || length(text) != 1L)
    return(list(hit = FALSE, n = 0L, values = character(0)))
  toks <- unique(strsplit(text, "[^[:alnum:].]+", perl = TRUE)[[1L]])
  toks <- gsub("^\\.+|\\.+$", "", toks)                 # strip edge dots (keep 3.14)
  toks <- toks[nchar(toks) >= 3L]
  if (!length(toks)) return(list(hit = FALSE, n = 0L, values = character(0)))
  norm <- .data_shield_normalize(toks)
  hit  <- norm[vapply(norm, function(t) exists(t, envir = index, inherits = FALSE),
                      logical(1))]
  list(hit = length(hit) > 0L, n = length(hit), values = unique(hit))
}

# Classify columns locally (never sent to the model). Overrides remain the
# authority; heuristics deliberately err toward more restrictive classes.
#' @keywords internal
.data_shield_classify_columns <- function(df, sensitivity = NULL) {
  out <- stats::setNames(rep("measure", ncol(df)), names(df))
  nms <- tolower(names(df))
  id_pat <- "(^|_)(id|identifier|subjid|subject|patient|name|email|phone|ssn|mrn|address)(_|$)"
  quasi_pat <- "(^|_)(age|sex|gender|race|ethnic|site|country|region|zip|postal|birth|dob)(_|$)"
  out[grepl(id_pat, nms, perl = TRUE)] <- "identifier"
  out[grepl(quasi_pat, nms, perl = TRUE)] <- "quasi"
  for (i in seq_along(df)) {
    x <- df[[i]]
    if (inherits(x, c("Date", "POSIXt")) && identical(out[[i]], "measure"))
      out[[i]] <- "quasi"
    if ((is.character(x) || is.factor(x)) && identical(out[[i]], "measure")) {
      vals <- unique(x[!is.na(x)])
      if (length(vals) >= 8L && length(vals) / max(1L, nrow(df)) >= 0.8)
        out[[i]] <- "identifier"
    }
  }
  if (!is.null(sensitivity)) {
    sensitivity <- unlist(sensitivity, use.names = TRUE)
    if (is.null(names(sensitivity)) || any(!names(sensitivity) %in% names(df)))
      stop("`sensitivity` must be named by columns in `df`.", call. = FALSE)
    allowed <- c("identifier", "quasi", "measure", "open")
    if (any(!sensitivity %in% allowed))
      stop("Sensitivity must be identifier/quasi/measure/open.", call. = FALSE)
    out[names(sensitivity)] <- sensitivity
  }
  out
}

.data_shield_type <- function(x) {
  if (inherits(x, "Date")) return("Date")
  if (inherits(x, "POSIXt")) return("datetime")
  if (is.ordered(x)) return("ordered factor")
  if (is.factor(x)) return("factor")
  class(x)[[1L]] %||% typeof(x)
}

.data_shield_range <- function(x) {
  if (!length(x) || all(is.na(x))) return(NULL)
  r <- tryCatch(range(x, na.rm = TRUE), error = function(e) NULL)
  if (is.null(r) || length(r) != 2L) return(NULL)
  if (inherits(x, "Date")) return(format(r, "%Y-%m-%d"))
  if (inherits(x, "POSIXt")) return(format(r, "%Y-%m-%d %H:%M:%S %Z"))
  format(r, scientific = FALSE, trim = TRUE)
}

# Strict schema for one registered dataset: no distributions/counts/examples.
#' @keywords internal
.data_shield_describe <- function(dataset, config) {
  df <- dataset$data
  sensitivity <- dataset$sensitivity
  k <- config$k_anon %||% 5L
  category_max <- config$category_max %||% 20L
  category_ratio <- config$category_ratio %||% 0.2
  lines <- sprintf("Protected dataset '%s': %d rows x %d columns",
                   dataset$name, nrow(df), ncol(df))
  for (cn in names(df)) {
    x <- df[[cn]]
    sens <- sensitivity[[cn]] %||% "identifier"
    typ <- .data_shield_type(x)
    fields <- c(sprintf("type=%s", typ), sprintf("sensitivity=%s", sens),
                sprintf("missing=%s", if (anyNA(x)) "yes" else "no"))
    if (sens %in% c("measure", "open")) {
      if (is.numeric(x) || inherits(x, c("Date", "POSIXt"))) {
        r <- .data_shield_range(x)
        if (!is.null(r)) fields <- c(fields, sprintf("range=[%s, %s]", r[[1L]], r[[2L]]))
      } else if (is.logical(x)) {
        fields <- c(fields, "labels=[FALSE, TRUE]")
      } else if (is.factor(x) || is.character(x)) {
        vals <- as.character(x[!is.na(x)])
        tab <- table(vals)
        ratio <- length(tab) / max(1L, length(vals))
        categorical <- is.factor(x) ||
          (length(tab) <= category_max && ratio <= category_ratio)
        if (categorical) {
          safe <- names(tab)[tab >= k]
          labels <- safe
          if (any(tab < k)) labels <- c(labels, "<rare suppressed>")
          if (length(labels))
            fields <- c(fields, sprintf("labels=[%s]", paste(labels, collapse = ", ")))
        } else {
          fields <- c(fields, "format=free_text")
        }
      }
    } else {
      fields <- c(fields, "values=suppressed")
    }
    lines <- c(lines, sprintf("- %s: %s", cn, paste(fields, collapse = "; ")))
  }
  paste(lines, collapse = "\n")
}

# Build/register the strict DescribeData tool (internal; lifecycle belongs to R6).
.data_shield_make_describe_tool <- function(shield) {
  ellmer::tool(
    function(data_name = NULL) shield$describe(data_name),
    name = "DescribeData",
    description = paste0(
      "Describe a registered protected data.frame without returning raw rows. ",
      "Strict mode returns schema, sensitivity, missing presence, safe numeric/date ranges, ",
      "and k-supported low-cardinality labels; never distributions, counts, or free-text examples."),
    arguments = list(
      data_name = ellmer::type_string(
        "Registered protected dataset name. Optional when exactly one exists.",
        required = FALSE)),
    annotations = ellmer::tool_annotations(
      title = "DescribeData", read_only_hint = TRUE,
      destructive_hint = FALSE, open_world_hint = FALSE))
}

.data_shield_register_describe_tool <- function(chat, shield) {
  names_now <- vapply(tryCatch(chat$get_tools(), error = function(e) list()),
    function(tool) tryCatch(S7::prop(tool, "name"), error = function(e) ""),
    character(1))
  if (!"DescribeData" %in% names_now)
    chat$register_tool(.data_shield_make_describe_tool(shield))
  invisible(chat)
}
