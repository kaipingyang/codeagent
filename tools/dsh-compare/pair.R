# Pair DSH screenshots from one run with codeagent screenshots from another.
#   Rscript tools/dsh-compare/pair.R dsh=baseline ca=step1 label="codeagent: dsh"
args <- commandArgs(trailingOnly = TRUE)
opt <- list(dsh = "baseline", ca = "latest", label = "codeagent")
for (a in args) { kv <- strsplit(a, "=", fixed = TRUE)[[1]]; opt[[kv[1]]] <- paste(kv[-1], collapse = "=") }
here <- normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))
d_dir <- file.path(here, "out", opt$dsh); c_dir <- file.path(here, "out", opt$ca)
for (cf in list.files(c_dir, "-ca\\.png$", full.names = TRUE)) {
  df <- file.path(d_dir, sub("-ca\\.png$", "-dsh.png", basename(cf)))
  if (!file.exists(df)) next
  lab <- function(f, t) magick::image_annotate(magick::image_read(f), t, size = 18,
    color = "#d33", boxcolor = "#ffffffcc", location = "+8+8")
  a <- lab(df, "DSH"); b <- lab(cf, opt$label)
  sep <- magick::image_blank(12, magick::image_info(a)$height, "#888")
  out <- file.path(c_dir, sub("-ca\\.png$", "-pair.png", basename(cf)))
  magick::image_write(magick::image_append(c(a, sep, b)), out)
  cat("pair:", basename(out), "\n")
}
