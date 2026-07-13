# Request: system Protobuf for the R otelsdk package (OpenTelemetry SDK)

**To:** IT / Platform team **From:** *(your name)* **Environment:**
Posit Workbench, Ubuntu 22.04 (jammy), R on this server **Priority:**
Low (blocks an optional observability feature, no production impact)

## Summary

I cannot install the R package **`otelsdk`** (the OpenTelemetry SDK
backend) on this server. The **`otel`** package (the pure-R API)
installs fine; only the SDK — which carries native code — fails. This
blocks local end-to-end testing of an optional OpenTelemetry tracing
feature. It does **not** affect any production system.

## Root cause

`otelsdk` bundles the OpenTelemetry C++ library, whose build requires
**Protobuf** (compiler + development headers), which is not present on
this machine.

Building from source fails at the CMake configuration step:

    -- Could NOT find Protobuf (missing: Protobuf_LIBRARIES Protobuf_INCLUDE_DIR)
    CMake Error at CMakeLists.txt:350 (find_package):
      Could not find a package configuration file provided by "Protobuf"
      (ProtobufConfig.cmake / protobuf-config.cmake)

`cmake`, `gcc`, and `g++` are available; only Protobuf is missing.

## What I already tried (all failed)

| Channel                                                       | Result                                                            |
| ------------------------------------------------------------- | ----------------------------------------------------------------- |
| Source build (`cloud.r-project.org`)                          | Fails — missing system Protobuf (above)                           |
| Posit Package Manager binary (jammy)                          | Installs but fails to load — runtime `libprotobuf.so` not present |
| r-lib prebuilt binaries (`github.com/r-lib/otelsdk/releases`) | No installable package index found                                |
| `r-universe` (`r-lib.r-universe.dev`)                         | No compatible Linux binary available                              |

## What I’m requesting

Either of the following would unblock it:

1.  **Install the system Protobuf packages** (preferred), e.g. on Ubuntu
    22.04:
    
    ``` bash
    sudo apt-get update
    sudo apt-get install -y protobuf-compiler libprotobuf-dev
    ```
    
    After that, `install.packages("otelsdk")` should build from source.

2.  **Or** provide a prebuilt `otelsdk` binary compatible with this R
    version / platform, with the Protobuf runtime library available on
    the loader path.

## Impact if not actioned

Low. The affected feature (OpenTelemetry trace export) is optional and
guarded — the application runs normally without it; only live
tracing/observability export is unavailable on this specific server. No
other functionality is affected.

## References

  - otel (API, pure R): <https://cran.r-project.org/package=otel>
  - otelsdk (SDK, native): <https://cran.r-project.org/package=otelsdk>
