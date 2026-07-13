# Install the codeagent CLI

Installs the `codeagent` CLI script (powered by Rapp) to a directory on
your PATH. After installation, run `codeagent run "prompt"`, `codeagent
app`, `codeagent skills list`, etc.

## Usage

``` r
install_codeagent_cli(destdir = NULL)
```

## Arguments

  - destdir:
    
    Character or NULL. Destination directory. NULL uses `~/.local/bin`
    (Linux/macOS) or `~/bin` as fallback.

## Value

Character. Path(s) to installed script(s), invisibly.
