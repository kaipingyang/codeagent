# Patch codeagent\_client() to use btw file tools (Path A)

Call this once after loading codeagent to enable btw file tools
globally. Modifies `.register_all_tools()` behaviour for subsequent
`codeagent_client()` calls.

## Usage

``` r
enable_btw_file_tools()
```

## Details

    library(codeagent)
    source(system.file("pathA/tools_btw_files.R", package = "codeagent"))
    enable_btw_file_tools()   # opt in
    client <- codeagent_client(chat)
