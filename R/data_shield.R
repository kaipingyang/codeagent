#' Data Shield --- pluggable strict data-safety valve (P0 core)
# Data Shield strategy specification (internal).
.new_shield_strategy <- function(type, ...) {
  structure(list(type = type, config = list(...)), class = "shield_strategy")
}

#' Configure strict protected-data metadata
#'
#' @description
#' Enable the automatically registered `DescribeData` tool. In the currently
#' implemented strict mode (`distributions = "off"`), it never returns rows,
#' histograms, quantiles, means, category counts, or real free-text examples.
#' `identifier`/`quasi` values are suppressed; `measure`/`open` columns may show
#' numeric/date min-max and low-cardinality labels whose support is at least
#' `k_anon` (labels are shown without counts).
#'
#' @param distributions `"off"` is implemented and is the safe default.
#'   `"on"` and `"dp"` are accepted as roadmap configuration but DescribeData
#'   returns an explicit not-implemented error instead of silently weakening
#'   privacy.
#' @param k_anon Minimum rows supporting a categorical label before it may be
#'   exposed; rarer labels become `<rare suppressed>`.
#' @param category_max Maximum distinct values for automatically treating a
#'   character column as categorical.
#' @param category_ratio Maximum `n_distinct / n_non_missing` ratio for automatic
#'   character-categorical treatment. Higher-cardinality text is marked
#'   `free_text` and no examples are returned.
#' @return A Data Shield strategy specification.
#' @examples
#' strict_metadata <- shield_describe(k_anon = 5)
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
#' @description
#' Create the core model-egress stage. Every wrapped tool still executes locally;
#' this stage controls only what its result may send back to the LLM.
#'
#' `row_cap` detects output shaped like a data.frame/tibble or a many-line
#' rectangular table. With `max_rows = 0` (recommended strict default), it keeps
#' **zero raw lines** and replaces the output with a shape/withheld notice.
#' Scalars, ordinary messages, model summaries, plots, and errors pass through.
#' `value_match` independently withholds high-entropy values previously indexed
#' by `DataShield$register_data()` (e.g. one subject id that is too short to
#' trigger the bulk row cap).
#'
#' @param detectors One or both of `"row_cap"` and `"value_match"`. Default:
#'   both, in that order.
#' @param max_rows Number of leading printed table lines to retain when
#'   `row_cap` triggers. `0` retains no raw line; values greater than zero
#'   deliberately expose that many leading lines and should only be used when
#'   the caller accepts that disclosure.
#' @param on_fail `"redact"` replaces unsafe output with a withheld notice;
#'   `"block"` discards it with a blocked notice. Neither mode asks a user;
#'   interactive `"ask"` is a later phase.
#' @return A Data Shield strategy specification.
#' @examples
#' strict <- shield_egress(max_rows = 0, on_fail = "redact")
#' no_value_index <- shield_egress(detectors = "row_cap", max_rows = 0)
#' @export
shield_egress <- function(detectors = c("row_cap", "value_match"), max_rows = 0L,
                          on_fail = c("redact", "block")) {
  detectors <- match.arg(detectors, c("row_cap", "value_match"), several.ok = TRUE)
  .new_shield_strategy(
    "egress", detectors = detectors, max_rows = as.integer(max_rows),
    on_fail = match.arg(on_fail))
}

.data_shield_asset_defaults <- function(kind) {
  switch(kind,
    dataset = list(prompt="schema", egress="scan"),
    spec = list(prompt="raw", egress="scan"),
    synthetic = list(prompt="raw", egress="scan"),
    document = list(prompt="scan", egress="scan"))
}

.data_shield_asset_policy <- function(name, kind, llm_access=NULL,
                                      scan_secrets=TRUE, reason=NULL,
                                      expires="session") {
  kinds <- c("dataset","spec","document","synthetic")
  kind <- match.arg(kind, kinds)
  if (!is.character(name) || length(name)!=1L || !nzchar(name))
    stop("`name` must be a non-empty character(1).",call.=FALSE)
  access <- .data_shield_asset_defaults(kind)
  if (!is.null(llm_access)) {
    if (!is.list(llm_access) || !all(names(llm_access) %in% c("prompt","egress")))
      stop("`llm_access` must be list(prompt=, egress=).",call.=FALSE)
    access[names(llm_access)] <- llm_access
  }
  allowed <- c("none","schema","scan","raw")
  if (any(!unlist(access,use.names=FALSE) %in% allowed))
    stop("Asset access must be none/schema/scan/raw.",call.=FALSE)
  if (any(unlist(access,use.names=FALSE)=="raw") &&
      (is.null(reason) || !is.character(reason) || length(reason)!=1L || !nzchar(reason)))
    stop("`reason` is required for raw asset access.",call.=FALSE)
  expiry <- if (identical(expires,"session") || is.null(expires)) Inf else {
    if (!inherits(expires,"POSIXt")) stop("`expires` must be 'session' or POSIXct.",call.=FALSE)
    as.numeric(expires)
  }
  list(name=name,kind=kind,llm_access=access,scan_secrets=isTRUE(scan_secrets),
       reason=reason %||% paste0("registered ",kind),expires=expiry)
}

.data_shield_asset_expired <- function(asset) {
  is.finite(asset$expires) && as.numeric(Sys.time()) > asset$expires
}

.data_shield_asset_text <- function(x) {
  if (is.character(x) && length(x)==1L && file.exists(x)) {
    size <- suppressWarnings(file.info(x)$size)
    n <- if (length(size)==1L && is.finite(size)) min(size,8192) else 8192
    probe <- tryCatch(readBin(x,"raw",n=n),error=function(e) raw())
    if (any(as.integer(probe)==0L))
      stop("Raw binary asset needs a dedicated trusted adapter.",call.=FALSE)
    return(paste(readLines(x,warn=FALSE),collapse="\n"))
  }
  if (is.character(x)) return(paste(x,collapse="\n"))
  paste(utils::capture.output(print(x)),collapse="\n")
}

.data_shield_default_regex_patterns <- function() {
  c(
    email = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
    phone = "(?:\\+?[0-9][0-9 .()\\-]{7,}[0-9])",
    api_token = "\\b(?:sk|ghp|dapi)[_-]?[A-Z0-9]{16,}\\b",
    identity_18 = "\\b[0-9]{17}[0-9X]\\b")
}

#' Configure regex-based egress scanning
#'
#' @description
#' Detect and redact/block common unregistered PII and secrets in tool output.
#' Default rules cover email, phone-like numbers, common API-token prefixes,
#' and 18-character identity-number shapes. Custom named PCRE patterns may be
#' added without introducing another state engine.
#'
#' @param patterns Optional named character vector of custom regular expressions
#'   using PCRE (Perl-Compatible Regular Expression) syntax. Example:
#'   `c(study_id = "STUDY-[0-9]+")`, where `study_id` names the rule and
#'   `[0-9]+` means one or more digits. With `include_defaults = TRUE`, custom
#'   rules are appended after the built-ins.
#' @param include_defaults Include built-in email, phone-like, common-token-prefix,
#'   and 18-character identity-number rules.
#' @param replacement Marker inserted once per merged matching span when
#'   `on_fail = "redact"`.
#' @param on_fail `"redact"` replaces only matching spans and preserves the rest
#'   of the tool result; `"block"` replaces the entire model-facing result.
#' @param ignore_case Apply case-insensitive PCRE matching to all rules.
#' @return A Data Shield scanner strategy specification.
#' @examples
#' pii <- shield_regex(on_fail = "redact")
#' study_ids <- shield_regex(
#'   patterns = c(study_id = "STUDY-[0-9]+"),
#'   include_defaults = FALSE,
#'   on_fail = "block"
#' )
#' @export
shield_regex <- function(patterns = NULL, include_defaults = TRUE,
                         replacement = "[REDACTED]",
                         on_fail = c("redact", "block"), ignore_case = TRUE) {
  defaults <- .data_shield_default_regex_patterns()
  if (!is.null(patterns)) {
    if (!is.character(patterns) || is.null(names(patterns)) || any(!nzchar(names(patterns))))
      stop("`patterns` must be a named character vector.", call. = FALSE)
  }
  resolved <- c(if (isTRUE(include_defaults)) defaults else character(), patterns %||% character())
  if (!length(resolved)) stop("At least one regex pattern is required.", call. = FALSE)
  fn <- .data_shield_regex_scanner(
    resolved, replacement = replacement,


    on_fail = match.arg(on_fail), ignore_case = ignore_case)
  .new_shield_strategy("scanner", name = "regex", fn = fn)
}
#' Configure per-tool/agent Data Shield policy
#'
#' @description
#' Override Shield handling by exact tool name or `*` glob. `scan` is the safe
#' default; `bypass` explicitly skips one Shield edge and is audited; `deny`
#' prevents execution (or blocks egress). Shield bypass never bypasses the
#' independent permission gate.
#'
#' @param default Default mode (`"scan"`).
#' @param rules Named list keyed by exact/glob tool names. Each rule may contain
#'   `execution`, `ingress`, and `egress` set to `scan`, `bypass`, or `deny`.
#' @return A Data Shield tool-policy strategy specification.
#' @examples
#' trusted_plot <- shield_tool_policy(rules = list(
#'   KMPlot = list(ingress = "scan", egress = "bypass"),
#'   DangerousExport = list(execution = "deny")
#' ))
#' @export
shield_tool_policy <- function(default = "scan", rules = list()) {
  default <- match.arg(default, c("scan"))
  if (!is.list(rules) || (length(rules) && (is.null(names(rules)) || any(!nzchar(names(rules))))))
    stop("`rules` must be a named list keyed by tool name/glob.", call.=FALSE)
  allowed <- c("scan", "bypass", "deny")
  normalized <- lapply(rules, function(rule) {
    if (!is.list(rule) || any(!names(rule) %in% c("execution","ingress","egress")))
      stop("Each tool rule may contain execution/ingress/egress.", call.=FALSE)
    if (any(!unlist(rule,use.names=FALSE) %in% allowed))
      stop("Tool policy values must be scan/bypass/deny.", call.=FALSE)
    utils::modifyList(list(execution=default,ingress=default,egress=default),rule)
  })
  .new_shield_strategy("tool_policy", default=default, rules=normalized)
}

#' Configure universal tool-call ingress scanning
#'
#' @description
#' Scan every tool's arguments in the central permission gate before execution.
#' Default rules target high-confidence data serialization, encoded output,
#' network exfiltration, shell display of data files, and direct previews of
#' registered protected dataset names. This is defense-in-depth; egress remains
#' the primary model-data boundary.
#'
#' @param langs Any of `"r"`, `"python"`, and `"bash"`; controls which
#'   language-specific default rules are included.
#' @param patterns Optional named regular expressions using PCRE
#'   (Perl-Compatible Regular Expression) syntax, appended after defaults.
#' @param include_defaults Include built-in serialization/encoding, network
#'   transfer, shell data-file display, and protected-name preview rules.
#' @param on_fail `"block"` rejects the tool call; `"ask"` forces the existing
#'   permission approval callback/UI (including the tool-call id).
#' @param ignore_case Apply case-insensitive matching.
#' @return A Data Shield ingress strategy specification.
#' @examples
#' strict_calls <- shield_ingress(on_fail = "block")
#' supervised <- shield_ingress(langs = c("r", "python", "bash"), on_fail = "ask")
#' @export
shield_ingress <- function(langs = c("r", "python", "bash"), patterns = NULL,
                           include_defaults = TRUE,
                           on_fail = c("block", "ask"), ignore_case = TRUE) {
  langs <- match.arg(tolower(langs), c("r", "python", "bash"), several.ok = TRUE)
  if (!is.null(patterns) &&
      (!is.character(patterns) || is.null(names(patterns)) || any(!nzchar(names(patterns)))))
    stop("`patterns` must be a named character vector.", call. = FALSE)
  defaults <- character()
  if (isTRUE(include_defaults) && "r" %in% langs) defaults <- c(defaults,
    r_serialize = "\\b(?:serialize|saveRDS|dput|jsonlite::toJSON|base64enc::base64encode|write\\.csv|write\\.table)\\s*\\(",
    r_network = "\\b(?:httr2?::(?:request|POST|PUT|PATCH)|curl::)\\b")
  if (isTRUE(include_defaults) && "python" %in% langs) defaults <- c(defaults,
    py_serialize = "\\b(?:pickle\\.dumps?|json\\.dumps?|base64\\.b64encode)\\s*\\(",
    py_network = "\\brequests\\.(?:post|put|patch)\\s*\\(",
    py_df_print = "\\bprint\\s*\\(\\s*(?:df|data|dataset)\\b")
  if (isTRUE(include_defaults) && "bash" %in% langs) defaults <- c(defaults,
    sh_upload = "\\bcurl\\b[^\\n]*(?:--data|-d\\s|--upload-file|-T\\s)|\\bwget\\b[^\\n]*--post-data",
    sh_data_print = "\\b(?:cat|head|tail)\\s+[^\\n;|]*(?:\\.csv|\\.parquet|\\.sas7bdat|\\.xlsx)\\b",
    sh_base64 = "\\bbase64\\s+")
  resolved <- c(defaults, patterns %||% character())
  if (!length(resolved)) stop("At least one ingress pattern is required.", call. = FALSE)
  fn <- .data_shield_ingress_scanner(
    resolved, on_fail = match.arg(on_fail), ignore_case = ignore_case)
  .new_shield_strategy("ingress", name = "ingress", fn = fn)
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
#' shared across chats. Instances are intentionally non-cloneable; create a new
#' object for an independent user/thread boundary.
#'
#' @examples
#' # Easy one-client declaration:
#' specs <- list(
#'   shield_describe(k_anon = 5),
#'   shield_egress(max_rows = 0),
#'   shield_regex(on_fail = "redact")
#' )
#'
#' # Explicit lifecycle for uploaded data / selected shared chats:
#' shield <- DataShield$new(strategies = specs)
#' shield$register_data(iris, name = "iris",
#'   sensitivity = c(Species = "measure"))
#' shield$coverage()
#'
#' @export
DataShield <- R6::R6Class(
  "DataShield",
  cloneable = FALSE,
  public = list(
    #' @description Create a Data Shield.
    #' @param max_rows Direct `row_cap` value when `strategies = NULL`: `0`
    #'   exposes no raw tabular line; positive values retain that many leading
    #'   printed lines.
    #' @param distributions Direct DescribeData policy. Strict `"off"` only is
    #'   implemented; `"on"`/`"dp"` fail explicitly.
    #' @param k_anon Minimum category support for exposing a label.
    #' @param category_max Maximum distinct character values treated as a category.
    #' @param category_ratio Maximum distinct/non-missing ratio for character
    #'   categorical treatment.
    #' @param audit_max Maximum in-memory non-sensitive decision events retained.
    #' @param strategies Optional ordered list from [shield_describe()],
    #'   [shield_egress()], [shield_regex()], [shield_ingress()], and
    #'   [shield_tool_policy()]. If supplied, only listed
    #'   strategies are enabled and list order controls egress execution order.
    initialize = function(max_rows = 0L, distributions = "off", k_anon = 5L,
                          category_max = 20L, category_ratio = 0.2,
                          audit_max = 1000L, strategies = NULL) {
      private$config <- list(
        max_rows = as.integer(max_rows),
        distributions = match.arg(distributions, c("off", "on", "dp")),
        k_anon = as.integer(k_anon), category_max = as.integer(category_max),
        category_ratio = as.numeric(category_ratio),
        detectors = c("row_cap", "value_match"), on_fail = "redact",
        describe_enabled = TRUE, egress_enabled = TRUE)
      private$datasets <- list()
      private$assets <- list()
      private$index <- new.env(parent = emptyenv())
      private$strategies <- list()
      private$egress_pipeline <- list()
      private$ingress_pipeline <- list()
      private$audit_log <- list()
      private$audit_max <- max(0L, as.integer(audit_max))
      private$tool_policy_config <- list(default="scan", rules=list())
      private$closed <- FALSE
      if (is.null(strategies)) {
        private$egress_pipeline[[1L]] <- list(
          type = "core", name = "egress",
          config = list(detectors = private$config$detectors,
                        max_rows = private$config$max_rows,
                        on_fail = private$config$on_fail))
      } else {
        private$config$describe_enabled <- FALSE
        private$config$egress_enabled <- FALSE
        for (strategy in strategies) private$apply_strategy(strategy)
      }
    },

    #' @description Register one protected data.frame.
    #' @param df A data.frame retained locally; rows are never emitted by
    #'   `DescribeData`.
    #' @param name Dataset name used by the model-facing `DescribeData` tool.
    #' @param sensitivity Optional named overrides: `identifier`, `quasi`,
    #'   `measure`, or `open`. Local heuristics classify unspecified columns.
    #' @param cols Optional explicit value-match columns. Default: columns
    #'   classified `identifier`/`quasi`.
    #' @param min_len,min_card Minimum value length and column cardinality for
    #'   deterministic value indexing (reduces low-entropy false positives).
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

    #' @description Register a typed data/document/spec asset and its LLM access policy.
    #' @param x Local asset value or path.
    #' @param name Unique asset name.
    #' @param kind `dataset`, `spec`, `document`, or `synthetic`.
    #' @param llm_access NULL for kind defaults, or list(prompt=, egress=) using
    #'   `none`, `schema`, `scan`, or `raw`.
    #' @param scan_secrets Keep baseline PII/secret regex active for raw access.
    #' @param reason Required when prompt or egress access is raw.
    #' @param expires `"session"` or POSIXct expiry.
    register_asset = function(x, name, kind,
                              llm_access = NULL, scan_secrets = TRUE,
                              reason = NULL, expires = "session") {
      private$assert_open()
      policy <- .data_shield_asset_policy(
        name=name, kind=kind, llm_access=llm_access,
        scan_secrets=scan_secrets, reason=reason, expires=expires)
      private$assets[[name]] <- c(list(value=x), policy)
      if (identical(kind, "dataset") && is.data.frame(x) &&
          (policy$llm_access$prompt %in% c("schema", "scan") ||
           identical(policy$llm_access$egress, "scan")))
        self$register_data(x, name=name)
      invisible(self)
    },

    #' @description Return non-sensitive policy metadata for one registered asset.
    asset_policy = function(name) {
      private$assert_open()
      asset <- private$assets[[name]]
      if (is.null(asset)) stop("Unknown Data Shield asset: ", name, call.=FALSE)
      asset[names(asset) != "value"]
    },

    #' @description Resolve effective Shield policy for one tool/agent name.
    tool_policy = function(tool_name) {
      private$assert_open()
      private$resolve_tool_policy(tool_name)
    },

    #' @description Return prompt-safe content according to an asset policy.
    prompt_content = function(name) {
      private$assert_open()
      asset <- private$asset(name)
      access <- asset$llm_access$prompt
      if (identical(access, "none")) stop("Asset prompt access is disabled.", call.=FALSE)
      if (identical(access, "schema")) {
        if (name %in% names(private$datasets)) return(self$describe(name))
        return(sprintf("Asset '%s': kind=%s (content suppressed)", name, asset$kind))
      }
      text <- .data_shield_asset_text(asset$value)
      if (identical(access, "scan"))
        return(self$scan_egress(text, context=list(edge="prompt", tool_name=paste0("asset:",name))))
      # raw bypasses row/value rules; optional baseline secret/PII scan remains.
      out <- private$scan_raw_secrets(text, asset, edge="prompt", tool_name=paste0("asset:",name))
      private$record_event(
        edge="prompt", tool_name=paste0("asset:",name), strategy="asset_policy",
        action="bypass", reason=asset$reason, match_count=0L, score=0)
      out
    },

    #' @description Tag one result with registered provenance for raw egress.
    trusted_result = function(value, source) {
      private$assert_open()
      asset <- private$asset(source)
      if (!identical(asset$llm_access$egress, "raw"))
        stop("Asset is not approved for raw egress: ", source, call.=FALSE)
      structure(list(value=value, source=source), class="DataShieldTrustedResult")
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

    #' @description Apply the ordered egress strategy pipeline to a tool result.
    #' @param result Tool return value.
    #' @param context Optional non-sensitive context (`tool_name`, `tool_call_id`).
    scan_egress = function(result, context = list()) {
      private$assert_open()
      tool_name <- context$tool_name %||% NA_character_
      policy <- private$resolve_tool_policy(tool_name)
      if (identical(policy$egress, "deny")) {
        private$record_event(
          edge=context$edge %||% "egress",tool_name=tool_name,
          tool_call_id=context$tool_call_id,strategy="tool_policy",action="deny",
          reason=paste0("tool rule: ",policy$matched_rule),match_count=0L,score=1)
        return("[data_shield] tool output denied by explicit tool policy.")
      }
      if (identical(policy$egress, "bypass")) {
        private$record_event(
          edge=context$edge %||% "egress",tool_name=tool_name,
          tool_call_id=context$tool_call_id,strategy="tool_policy",action="bypass",
          reason=paste0("trusted tool rule: ",policy$matched_rule),match_count=0L,score=0)
        if (inherits(result,"DataShieldTrustedResult")) return(.data_shield_asset_text(result$value))
        return(result)
      }
      if (inherits(result, "DataShieldTrustedResult")) {
        asset <- private$asset(result$source)
        text <- .data_shield_asset_text(result$value)
        out <- private$scan_raw_secrets(
          text, asset, edge=context$edge %||% "egress",
          tool_name=context$tool_name %||% paste0("asset:",result$source))
        private$record_event(
          edge=context$edge %||% "egress",
          tool_name=context$tool_name %||% paste0("asset:",result$source),
          tool_call_id=context$tool_call_id, strategy="asset_policy",
          action="bypass", reason=asset$reason, match_count=0L, score=0)
        return(out)
      }
      audit_fn <- function(strategy, action, reason, match_count=0L, score=0) {
        private$record_event(
          edge=context$edge %||% "egress", tool_name=context$tool_name,
          tool_call_id=context$tool_call_id, strategy=strategy, action=action,
          reason=reason, match_count=match_count, score=score)
      }
      output <- result
      for (stage in private$egress_pipeline) {
        if (identical(stage$type, "core")) {
          cfg <- stage$config
          output <- .data_shield_filter_result(
            output, max_rows = cfg$max_rows, index = private$index,
            detectors = cfg$detectors, on_fail = cfg$on_fail,
            audit_fn = audit_fn)
        } else if (identical(stage$type, "scanner")) {
          output <- .data_shield_apply_scanner(
            output, stage$fn, stage$name,
            context = c(list(shield=self),
                        if(is.null(context$edge)) c(context,list(edge="egress")) else context),
            audit_fn = audit_fn)
        }
      }
      output
    },

    #' @description Scan one tool request before execution.
    #' @param tool_name Model-facing tool name.
    #' @param input Named list of tool arguments.
    #' @param tool_call_id Optional non-sensitive tool-call identifier.
    #' @return List with action (`pass`, `block`, or `ask`), reason, matches and score.
    scan_ingress = function(tool_name, input, tool_call_id = NULL) {
      private$assert_open()
      policy <- private$resolve_tool_policy(tool_name)
      if (identical(policy$execution,"deny") || identical(policy$ingress,"deny")) {
        decision <- list(
          action="block", reason=paste0("Data Shield tool policy denied: ",policy$matched_rule),
          matches=policy$matched_rule, score=1)
        private$record_event(
          edge="ingress",tool_name=tool_name,tool_call_id=tool_call_id,
          strategy="tool_policy",action="deny",reason=decision$reason,
          match_count=1L,score=1)
        return(decision)
      }
      if (identical(policy$ingress,"bypass")) {
        private$record_event(
          edge="ingress",tool_name=tool_name,tool_call_id=tool_call_id,
          strategy="tool_policy",action="bypass",
          reason=paste0("trusted tool rule: ",policy$matched_rule),match_count=0L,score=0)
        return(list(action="pass",reason=NULL,matches=character(),score=0))
      }
      if (!length(private$ingress_pipeline))
        return(list(action="pass", reason=NULL, matches=character(), score=0))
      text <- .data_shield_flatten_tool_input(tool_name, input)
      context <- list(edge="ingress", tool_name=tool_name, tool_call_id=tool_call_id,
                      input=input, protected_names=names(private$datasets), shield=self)
      for (stage in private$ingress_pipeline) {
        decision <- tryCatch(
          .data_shield_validate_ingress_result(stage$fn(text, context), stage$name),
          error = function(e) list(
            action="block", reason=sprintf("scanner '%s' failed safely", stage$name),
            matches=character(), score=1))
        if (!identical(decision$action, "pass")) {
          private$record_event(
            edge="ingress", tool_name=tool_name, tool_call_id=tool_call_id,
            strategy=stage$name, action=decision$action,
            reason=decision$reason, match_count=length(decision$matches),
            score=decision$score)
          return(decision)
        }
      }
      list(action="pass", reason=NULL, matches=character(), score=0)
    },

    #' @description Add a custom scanner function to the end of the egress pipeline.
    add_scanner = function(name, fn) {
      private$assert_open()
      if (!is.character(name) || length(name) != 1L || !nzchar(name) || !is.function(fn))
        stop("`name` must be non-empty and `fn` must be a function.", call. = FALSE)
      private$egress_pipeline[[length(private$egress_pipeline) + 1L]] <-
        list(type = "scanner", name = name, fn = fn)
      invisible(self)
    },

    #' @description Return a copy of non-sensitive decision events.
    #' @param limit Optional number of most recent events.
    audit = function(limit = NULL) {
      events <- private$audit_log
      if (!is.null(limit)) events <- utils::tail(events, max(0L, as.integer(limit)))
      if (!length(events)) return(.data_shield_empty_audit())
      do.call(rbind, lapply(events, function(event) {
        data.frame(
          timestamp = as.POSIXct(event$timestamp, origin="1970-01-01", tz="UTC"),
          edge = event$edge, tool_name = event$tool_name,
          tool_call_id = event$tool_call_id, strategy = event$strategy,
          action = event$action, reason = event$reason,
          match_count = event$match_count, score = event$score,
          stringsAsFactors = FALSE)
      }))
    },

    #' @description Remove all in-memory audit events.
    clear_audit = function() {
      private$audit_log <- list()
      invisible(self)
    },

    #' @description Remove one dataset, or all datasets when name is NULL.
    clear = function(name = NULL) {
      private$assert_open()
      if (is.null(name)) {
        private$datasets <- list(); private$assets <- list()
      } else {
        private$datasets[[name]] <- NULL; private$assets[[name]] <- NULL
      }
      private$rebuild_index()
      invisible(self)
    },

    #' @description Clear sensitive state and close the shield.
    close = function() {
      if (!isTRUE(private$closed)) {
        private$datasets <- list()
        private$assets <- list()
        private$audit_log <- list()
        rm(list = ls(private$index, all.names = TRUE), envir = private$index)
        private$closed <- TRUE
      }
      invisible(NULL)
    },

    #' @description Summarise non-sensitive runtime coverage.
    coverage = function() {
      list(config = private$config, datasets = names(private$datasets),
           assets = names(private$assets),
           indexed_values = length(ls(private$index, all.names = TRUE)),
           egress_pipeline = vapply(private$egress_pipeline, `[[`, character(1), "name"),
           ingress_pipeline = vapply(private$ingress_pipeline, `[[`, character(1), "name"),
           audit_events = length(private$audit_log), audit_max = private$audit_max,
           tool_policy_default = private$tool_policy_config$default,
           tool_policy_rules = names(private$tool_policy_config$rules),
           closed = private$closed)
    }
  ),
  private = list(
    config = NULL,
    datasets = NULL,
    assets = NULL,
    index = NULL,
    strategies = NULL,
    egress_pipeline = NULL,
    ingress_pipeline = NULL,
    audit_log = NULL,
    audit_max = 1000L,
    tool_policy_config = NULL,
    closed = FALSE,

    assert_open = function() {
      if (isTRUE(private$closed)) stop("The DataShield is closed.", call. = FALSE)
    },
    record_event = function(edge, tool_name = NA_character_, tool_call_id = NA_character_,
                            strategy, action, reason, match_count = 0L, score = 0) {
      if (private$audit_max <= 0L) return(invisible(NULL))
      event <- list(
        timestamp = as.numeric(Sys.time()),
        edge = as.character(edge)[[1L]],
        tool_name = substr(as.character(tool_name %||% NA_character_)[[1L]], 1L, 100L),
        tool_call_id = substr(as.character(tool_call_id %||% NA_character_)[[1L]], 1L, 100L),
        strategy = substr(as.character(strategy)[[1L]], 1L, 100L),
        action = as.character(action)[[1L]],
        reason = substr(as.character(reason %||% "policy match")[[1L]], 1L, 200L),
        match_count = as.integer(match_count %||% 0L),
        score = as.numeric(score %||% 0))
      private$audit_log[[length(private$audit_log) + 1L]] <- event
      if (length(private$audit_log) > private$audit_max)
        private$audit_log <- utils::tail(private$audit_log, private$audit_max)
      invisible(NULL)
    },
    asset = function(name) {
      asset <- private$assets[[name]]
      if (is.null(asset)) stop("Unknown Data Shield asset: ", name, call.=FALSE)
      if (.data_shield_asset_expired(asset))
        stop("Data Shield asset policy expired: ", name, call.=FALSE)
      asset
    },
    resolve_tool_policy = function(tool_name) {
      default <- private$tool_policy_config$default %||% "scan"
      base <- list(execution=default, ingress=default, egress=default,
                   matched_rule=NA_character_)
      rules <- private$tool_policy_config$rules %||% list()
      if (!length(rules)) return(base)
      if (tool_name %in% names(rules))
        return(c(rules[[tool_name]], matched_rule=tool_name))
      for (pattern in names(rules)) {
        if (grepl("*",pattern,fixed=TRUE) && .hook_pattern_matches(pattern,tool_name))
          return(c(rules[[pattern]], matched_rule=pattern))
      }
      base
    },
    scan_raw_secrets = function(text, asset, edge, tool_name) {
      if (!isTRUE(asset$scan_secrets)) return(text)
      scanner <- .data_shield_regex_scanner(
        .data_shield_default_regex_patterns(), replacement="[REDACTED]",
        on_fail="redact", ignore_case=TRUE)
      result <- scanner(text, list(edge=edge, tool_name=tool_name))
      if (!isTRUE(result$valid)) {
        labels <- if (is.data.frame(result$spans) && "label" %in% names(result$spans))
          unique(unlist(strsplit(result$spans$label,"\\|",perl=TRUE))) else character()
        private$record_event(
          edge=edge, tool_name=tool_name, strategy="asset_secret_scan",
          action="redact", reason=paste0("raw asset secret/PII match: ",paste(labels,collapse=", ")),
          match_count=if(is.data.frame(result$spans))nrow(result$spans) else 0L,
          score=result$score)
      }
      result$sanitized
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
        private$egress_pipeline[[length(private$egress_pipeline) + 1L]] <- list(

          type = "core", name = "egress", config = cfg)
      } else if (identical(type, "scanner")) {
        private$config$egress_enabled <- TRUE
        private$egress_pipeline[[length(private$egress_pipeline) + 1L]] <- list(
          type = "scanner", name = cfg$name, fn = cfg$fn)
      } else if (identical(type, "ingress")) {
        private$ingress_pipeline[[length(private$ingress_pipeline) + 1L]] <- list(
          type = "scanner", name = cfg$name, fn = cfg$fn)
      } else if (identical(type, "tool_policy")) {
        private$tool_policy_config <- list(default=cfg$default, rules=cfg$rules)
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
    }
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

.data_shield_empty_audit <- function() {
  data.frame(
    timestamp=as.POSIXct(character(),tz="UTC"), edge=character(),
    tool_name=character(), tool_call_id=character(), strategy=character(),
    action=character(), reason=character(), match_count=integer(), score=double(),
    stringsAsFactors=FALSE)
}

# Build a pure regex scanner closure.
.data_shield_regex_scanner <- function(patterns, replacement, on_fail, ignore_case) {
  for (pattern in patterns)
    tryCatch(grepl(pattern, "", perl = TRUE, ignore.case = ignore_case),
             error = function(e) stop("Invalid shield regex: ", conditionMessage(e), call. = FALSE))
  force(patterns); force(replacement); force(on_fail); force(ignore_case)
  function(text, context) {
    spans <- .data_shield_regex_spans(text, patterns, ignore_case)
    if (!nrow(spans))
      return(list(sanitized = text, valid = TRUE, score = 0,
                  spans = spans, action = "pass"))
    labels <- unique(spans$label)
    sanitized <- if (identical(on_fail, "block")) {
      sprintf("[data_shield] output blocked by regex scanner (%s).",
              paste(labels, collapse = ", "))
    } else {
      .data_shield_redact_spans(text, spans, replacement)
    }
    list(sanitized = sanitized, valid = FALSE,
         score = min(1, nrow(spans) / 5), spans = spans, action = on_fail)
  }
}

.data_shield_regex_spans <- function(text, patterns, ignore_case = TRUE) {
  rows <- list()
  for (label in names(patterns)) {
    matches <- gregexpr(patterns[[label]], text, perl = TRUE,
                        ignore.case = ignore_case)[[1L]]
    lengths <- attr(matches, "match.length")
    keep <- matches > 0L & lengths > 0L
    if (any(keep)) {
      rows[[length(rows) + 1L]] <- data.frame(
        start = matches[keep], end = matches[keep] + lengths[keep] - 1L,
        label = label, stringsAsFactors = FALSE)
    }
  }
  if (!length(rows))
    return(data.frame(start=integer(), end=integer(), label=character()))
  spans <- do.call(rbind, rows)
  spans <- spans[order(spans$start, spans$end), , drop=FALSE]
  # Merge overlap so redaction never corrupts offsets; keep all reason labels.
  merged <- list()
  for (i in seq_len(nrow(spans))) {
    cur <- spans[i, , drop=FALSE]
    if (!length(merged) || cur$start > merged[[length(merged)]]$end) {
      merged[[length(merged) + 1L]] <- cur
    } else {
      last <- merged[[length(merged)]]
      last$end <- max(last$end, cur$end)
      last$label <- paste(unique(c(strsplit(last$label, "\\|", perl=TRUE)[[1L]],
                                   cur$label)), collapse="|")
      merged[[length(merged)]] <- last
    }
  }
  out <- do.call(rbind, merged); rownames(out) <- NULL; out
}

.data_shield_redact_spans <- function(text, spans, replacement = "[REDACTED]") {
  out <- text
  for (i in rev(seq_len(nrow(spans)))) {
    before <- if (spans$start[[i]] > 1L) substr(out, 1L, spans$start[[i]] - 1L) else ""
    after  <- if (spans$end[[i]] < nchar(out)) substr(out, spans$end[[i]] + 1L, nchar(out)) else ""
    out <- paste0(before, replacement, after)
  }
  out
}

.data_shield_validate_scanner_result <- function(result, original, name) {
  ok <- is.list(result) && is.character(result$sanitized) && length(result$sanitized) == 1L &&
    is.logical(result$valid) && length(result$valid) == 1L && !is.na(result$valid) &&
    is.numeric(result$score) && length(result$score) == 1L && !is.na(result$score) &&
    result$score >= 0 && result$score <= 1 &&
    is.character(result$action) && length(result$action) == 1L &&
    result$action %in% c("pass", "redact", "block")
  if (!isTRUE(ok)) stop("Scanner '", name, "' returned an invalid result.", call. = FALSE)
  result$spans <- result$spans %||% list()
  result
}

# Apply a custom scanner to the model-facing text of common tool result shapes.
# Scanner errors/invalid contracts fail closed.
.data_shield_apply_scanner <- function(result, scanner, name, context = list(),
                                       audit_fn = NULL) {
  kind <- "other"; text <- NULL
  if (isTRUE(tryCatch(S7::S7_inherits(result, ellmer::ContentToolResult),
                      error=function(e) FALSE))) {
    kind <- "content"; text <- tryCatch(as.character(result@value), error=function(e) NULL)
  } else if (is.character(result) && length(result) == 1L) {
    kind <- "character"; text <- result
  } else if (is.data.frame(result) || is.matrix(result)) {
    kind <- "tabular"
    text <- tryCatch(paste(utils::capture.output(print(result)), collapse="\n"),
                     error=function(e) NULL)
  }
  if (is.null(text)) return(result)
  scanned <- tryCatch(
    .data_shield_validate_scanner_result(scanner(text, context), text, name),
    error = function(e) list(
      sanitized = sprintf("[data_shield] output blocked: scanner '%s' failed safely.", name),
      valid = FALSE, score = 1, spans = list(), action = "block",
      .scanner_failed = TRUE))
  changed <- !isTRUE(scanned$valid) || !identical(scanned$sanitized, text)
  if (!changed) return(result)
  if (is.function(audit_fn)) {
    spans <- scanned$spans %||% list()
    match_count <- if (is.data.frame(spans)) nrow(spans) else length(spans)
    labels <- if (is.data.frame(spans) && "label" %in% names(spans))
      unique(unlist(strsplit(spans$label, "\\|", perl=TRUE))) else character()
    reason <- if (isTRUE(scanned$.scanner_failed)) "scanner failed safely" else
      paste0("scanner matched", if(length(labels)) paste0(": ",paste(labels,collapse=", ")) else "")
    audit_fn(name, scanned$action, reason, match_count, scanned$score)
  }
  if (identical(kind, "content")) { result@value <- scanned$sanitized; return(result) }
  scanned$sanitized
}

# Flatten arbitrary tool arguments to a local-only scan string; no value is sent
# anywhere by this operation.
.data_shield_flatten_tool_input <- function(tool_name, input) {
  walk <- function(x, path = "") {
    if (is.list(x)) {
      nms <- names(x) %||% rep("", length(x))
      return(unlist(Map(function(value, name) {
        next_path <- paste(c(path, name[nzchar(name)]), collapse=".")
        walk(value, next_path)
      }, x, nms), use.names=FALSE))
    }
    value <- tryCatch(paste(as.character(x), collapse=" "), error=function(e) "")
    paste0(path, if(nzchar(path)) "=" else "", value)
  }
  paste(c(paste0("tool=", tool_name), walk(input)), collapse="\n")
}

.data_shield_ingress_scanner <- function(patterns, on_fail, ignore_case) {
  for (pattern in patterns)
    tryCatch(grepl(pattern, "", perl=TRUE, ignore.case=ignore_case),
             error=function(e) stop("Invalid ingress regex: ",conditionMessage(e),call.=FALSE))
  force(patterns); force(on_fail); force(ignore_case)
  function(text, context) {
    resolved <- patterns
    protected <- context$protected_names %||% character()
    if (length(protected)) {
      escaped <- gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", protected)
      resolved <- c(resolved,
        protected_preview = paste0(
          "\\b(?:head|tail|print|dput|cat|View)\\s*\\(\\s*(?:",
          paste(escaped,collapse="|"), ")\\b"))
    }
    spans <- .data_shield_regex_spans(text, resolved, ignore_case)
    if (!nrow(spans))
      return(list(action="pass",reason=NULL,matches=character(),score=0,spans=spans))
    labels <- unique(unlist(strsplit(spans$label,"\\|",perl=TRUE)))
    list(action=on_fail,
         reason=paste0("Data Shield ingress matched: ",paste(labels,collapse=", ")),
         matches=labels, score=min(1,nrow(spans)/5), spans=spans)
  }
}

.data_shield_validate_ingress_result <- function(result, name) {
  ok <- is.list(result) && is.character(result$action) && length(result$action)==1L &&
    result$action %in% c("pass","block","ask") &&
    is.numeric(result$score) && length(result$score)==1L && !is.na(result$score) &&
    result$score >= 0 && result$score <= 1
  if (!isTRUE(ok)) stop("Ingress scanner '",name,"' returned an invalid result.",call.=FALSE)
  result$matches <- result$matches %||% character()
  result$reason <- result$reason %||% NULL
  result
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
                                      on_fail = "redact", audit_fn = NULL) {
  if (!is.character(text) || length(text) != 1L)
    return(list(text = text, changed = FALSE))
  if ("row_cap" %in% detectors) {
    capped <- .data_shield_row_cap(text, max_rows = max_rows)
    if (isTRUE(capped$capped)) {
      if (identical(on_fail, "block"))
        capped$text <- sub("output withheld", "output blocked", capped$text, fixed = TRUE)
      if (is.function(audit_fn))
        audit_fn("row_cap", on_fail, "bulk tabular output", capped$n_lines %||% 0L, 1)
      return(list(text = capped$text, changed = TRUE))
    }
  }
  if ("value_match" %in% detectors) {
    matched <- tryCatch(.data_shield_value_scan(text, index),
                        error = function(e) list(hit = FALSE))
    if (isTRUE(matched$hit)) {
      verb <- if (identical(on_fail, "block")) "blocked" else "withheld"
      if (is.function(audit_fn))
        audit_fn("value_match", on_fail, "protected value match", matched$n, min(1, matched$n / 5))
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
                                       on_fail = "redact", audit_fn = NULL) {
  process <- function(text) .data_shield_process_text(
    text, max_rows = max_rows, index = index,
    detectors = detectors, on_fail = on_fail, audit_fn = audit_fn)
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
  tool_name <- tryCatch(S7::prop(tool, "name"), error=function(e) NA_character_)
  wrapped <- function(...) shield$scan_egress(
    original(...), context=list(tool_name=tool_name))
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
