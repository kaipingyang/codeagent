# Data Shield: identifier variants and identifier shapes.
#
# The value-match index holds each protected value exactly as registered
# (normalized: lower case, numbers canonical), and the scanner looks tokens of
# the text up in it. That misses the same identifier written another way --
# "BGB 001 0007", "BGB0010007", "bgb_001_0007", "BGB-1-7" for an indexed
# "BGB-001-0007" -- and every identifier that was never registered (another
# study, an unloaded subject, one the model made up).
#
# Two additions, built from IDENTIFIER columns when a dataset is registered
# with `id_variants = TRUE` (the default) and consulted by value_match:
#   * variant keys  -- each indexed identifier that contains a letter and is
#     long enough is also stored as "c:<alnum only>" and (multi-part ones)
#     "z:<parts, leading zeros dropped, joined by |>". The scanner joins runs
#     of adjacent words (separated by a short run of spaces / - _ / . en dash)
#     that contain a letter, and looks their keys up. Purely numeric ids get
#     no variants: their variants are indistinguishable from decimals and
#     counts ("54.3", "1 2").
#   * shape patterns -- an identifier column whose values share one or two
#     character shapes (letters -> A, digits -> 9, punctuation kept) and a
#     literal letter prefix becomes a regex such as `BGB-[0-9]{3}-[0-9]{4}`,
#     which matches identifiers of that form whether registered or not.

.DATA_SHIELD_VARIANT_MIN <- 6L     # alnum characters an id needs for variant keys
.DATA_SHIELD_SHAPE_SHARE <- 0.9    # share of values the 1-2 dominant shapes must cover
.DATA_SHIELD_MAX_ID_PARTS <- 12L   # hard cap on parts per identifier window
# What may sit between the parts of one identifier: spaces (incl. no-break),
# hyphen, en dash, underscore, slash, dot.
.DATA_SHIELD_SEP_RUN <- "[[:space:]\u00a0\u2013_/.-]{1,3}"

# Variant keys for many values at once (character vector -> character vector
# of keys, unnamed). `gate = TRUE` (indexing) keeps only ids that contain a
# letter and have enough alphanumerics. Vectorised. PURE.
.ds_variant_keys <- function(x, gate = TRUE) {
  low <- tolower(as.character(x))
  concat <- gsub("[^[:alnum:]]", "", low, perl = TRUE)
  zform <- gsub("[^[:alnum:]]+", "|", low, perl = TRUE)
  zform <- gsub("^\\||\\|$", "", zform, perl = TRUE)
  zform <- gsub("(^|\\|)0+(?=[0-9]+(\\||$))", "\\1", zform, perl = TRUE)
  multi <- grepl("|", zform, fixed = TRUE)
  keep <- nzchar(concat)
  if (isTRUE(gate))
    keep <- keep & nchar(concat) >= .DATA_SHIELD_VARIANT_MIN & grepl("[a-z]", concat)
  c(paste0("c:", concat[keep]), paste0("z:", zform[keep & multi]))
}

# Number of alphanumeric parts of each value. PURE.
.ds_n_parts <- function(x) {
  n <- lengths(regmatches(x, gregexpr("[[:alnum:]]+", x, perl = TRUE)))
  as.integer(n)
}

.ds_drop_zeros <- function(seg) {
  num <- grepl("^[0-9]+$", seg)
  seg[num] <- sub("^0+(?=.)", "", seg[num], perl = TRUE)
  seg
}

# Character shape of a value: letters -> A, digits -> 9, anything else kept.
.ds_shape <- function(x) {
  s <- gsub("[[:alpha:]]", "A", x, perl = TRUE)
  gsub("[[:digit:]]", "9", s, perl = TRUE)
}

# Regex for one shape after a literal prefix.
.ds_shape_regex <- function(shape, prefix) {
  rest <- substring(shape, nchar(prefix) + 1L)
  runs <- regmatches(rest, gregexpr("A+|9+|[^A9]+", rest, perl = TRUE))[[1L]]
  body <- vapply(runs, function(r) {
    ch <- substr(r, 1L, 1L)
    if (ch == "A") sprintf("[[:alpha:]]{%d}", nchar(r))
    else if (ch == "9") sprintf("[0-9]{%d}", nchar(r))
    else .data_shield_escape_regex(r)
  }, character(1L))
  paste0("(?i)(?<![[:alnum:]])", .data_shield_escape_regex(prefix),
         paste(body, collapse = ""), "(?![[:alnum:]])")
}

# Longest prefix shared by every value (vectorised over values, looped over
# character positions only).
.ds_common_prefix <- function(v) {
  n <- min(nchar(v))
  k <- 0L
  while (k < n) {
    ch <- substr(v, k + 1L, k + 1L)
    if (any(ch != ch[1L])) break
    k <- k + 1L
  }
  substr(v[1L], 1L, k)
}

# Infer identifier-shape regexes from one identifier column. NULL when the
# column has no dominant shape or no literal letter prefix (too generic).
.ds_shape_patterns <- function(values, min_card = 8L) {
  vals <- unique(as.character(values[!is.na(values)]))
  vals <- vals[nzchar(vals)]
  if (length(vals) < min_card) return(NULL)
  shapes <- .ds_shape(vals)
  tab <- sort(table(shapes), decreasing = TRUE)
  top <- names(tab)[seq_len(min(2L, length(tab)))]
  if (sum(tab[top]) / length(vals) < .DATA_SHIELD_SHAPE_SHARE) return(NULL)
  out <- character(0)
  for (sh in top) {
    if (nchar(sh) < .DATA_SHIELD_VARIANT_MIN ||
        lengths(regmatches(sh, gregexpr("9", sh, fixed = TRUE))) < 2L) next
    # The literal prefix stops at the first digit: digits vary between ids.
    pre <- .ds_common_prefix(vals[shapes == sh])
    pre <- regmatches(pre, regexpr("^[^0-9]*", pre))
    if (lengths(regmatches(pre, gregexpr("[[:alpha:]]", pre))) < 2L) next
    out <- c(out, .ds_shape_regex(sh, pre))
  }
  if (!length(out)) return(NULL)
  unique(out)
}

# Build the variant / shape side tables for one dataset's identifier columns.
# Variant keys count toward `max_values` like the exact index. PURE.
.ds_build_id_tables <- function(df, id_cols, min_len = 3L, min_card = 8L,
                                max_values = Inf) {
  keys <- character(0)
  max_parts <- 1L
  for (cn in intersect(id_cols, names(df))) {
    vals <- unique(as.character(df[[cn]][!is.na(df[[cn]])]))
    if (length(vals) < min_card) next
    vals <- vals[nchar(vals) >= min_len]
    k <- .ds_variant_keys(vals)
    if (!length(k)) next
    kept <- vals[grepl("[[:alpha:]]", vals) &
                   nchar(gsub("[^[:alnum:]]", "", vals)) >= .DATA_SHIELD_VARIANT_MIN]
    max_parts <- max(max_parts, .ds_n_parts(kept))
    keys <- c(keys, k)
  }
  keys <- unique(keys)
  if (length(keys) > max_values) {
    warning("Data Shield: ", length(keys), " identifier variant keys exceed ",
            "max_index_values (", max_values, "); keeping the first ", max_values,
            ".", call. = FALSE)
    keys <- keys[seq_len(max_values)]
  }
  shapes <- unlist(lapply(intersect(id_cols, names(df)), function(cn)
    .ds_shape_patterns(df[[cn]], min_card = min_card)), use.names = FALSE)
  list(variants = keys,
       max_segments = as.integer(min(max_parts, .DATA_SHIELD_MAX_ID_PARTS)),
       shapes = unique(as.character(shapes)))
}

# Spans of the text that are variants of indexed identifiers or match an
# identifier shape. Returns the raw substrings (for redaction). Vectorised
# over windows of adjacent words: for each window length every start position
# is keyed at once and looked up in the hashed variant environment. Windows
# without a letter are skipped (variants all contain one). PURE.
.ds_id_spans <- function(text, index) {
  variants <- attr(index, "variants")
  shapes <- attr(index, "shapes") %||% character(0)
  spans <- character(0)
  if (is.environment(variants) && length(ls(variants, all.names = TRUE)) &&
      grepl("[[:alpha:]]", text, perl = TRUE)) {
    max_seg <- max(1L, min(as.integer(attr(index, "max_segments") %||% 1L),
                           .DATA_SHIELD_MAX_ID_PARTS))
    m <- gregexpr("[[:alnum:]]+", text, perl = TRUE)[[1L]]
    if (m[1L] > 0L) {
      starts <- as.integer(m)
      ends <- starts + attr(m, "match.length") - 1L
      words <- tolower(substring(text, starts, ends))
      zwords <- .ds_drop_zeros(words)
      letter <- grepl("[a-z]", words)
      n <- length(words)
      gaps <- if (n > 1L) substring(text, ends[-n] + 1L, starts[-1L] - 1L) else character(0)
      broken <- c(!grepl(paste0("^", .DATA_SHIELD_SEP_RUN, "$"), gaps, perl = TRUE), TRUE)
      cbroken <- c(0L, cumsum(broken))
      cletter <- c(0L, cumsum(letter))
      found <- function(keys) {
        !is.na(unlist(mget(keys, envir = variants, ifnotfound = NA), use.names = FALSE))
      }
      cat_key <- words
      z_key <- zwords
      for (len in seq_len(min(n, max_seg))) {
        idx <- seq_len(n - len + 1L)
        if (len > 1L) {
          cat_key <- paste0(cat_key[idx], words[idx + len - 1L])
          z_key <- paste(z_key[idx], zwords[idx + len - 1L], sep = "|")
          ok <- (cbroken[idx + len - 1L] - cbroken[idx]) == 0L
        } else {
          ok <- rep(TRUE, length(idx))
        }
        ok <- ok & (cletter[idx + len] - cletter[idx]) > 0L
        if (!any(ok)) next
        w <- which(ok)
        hit <- found(paste0("c:", cat_key[w]))
        if (len > 1L) hit <- hit | found(paste0("z:", z_key[w]))
        if (any(hit)) {
          w <- w[hit]
          spans <- c(spans, substring(text, starts[w], ends[w + len - 1L]))
        }
      }
    }
  }
  for (p in shapes) {
    hits <- regmatches(text, gregexpr(p, text, perl = TRUE))[[1L]]
    spans <- c(spans, hits)
  }
  unique(spans[nzchar(spans)])
}

# Merge one dataset's side tables into the live index attributes.
.ds_merge_id_tables <- function(index, tables) {
  live <- attr(index, "variants")
  if (!is.environment(live)) {
    live <- new.env(hash = TRUE, parent = emptyenv())
    attr(index, "variants") <- live
  }
  if (length(tables$variants))
    list2env(stats::setNames(as.list(rep(TRUE, length(tables$variants))), tables$variants),
             envir = live)
  attr(index, "max_segments") <- max(as.integer(attr(index, "max_segments") %||% 1L),
                                     tables$max_segments %||% 1L)
  attr(index, "shapes") <- unique(c(attr(index, "shapes"), tables$shapes))
  invisible(index)
}

# Drop all side tables (rebuild / close).
.ds_reset_id_tables <- function(index) {
  attr(index, "variants") <- new.env(hash = TRUE, parent = emptyenv())
  attr(index, "max_segments") <- 1L
  attr(index, "shapes") <- character(0)
  invisible(index)
}
