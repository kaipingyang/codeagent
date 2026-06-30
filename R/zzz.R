# Suppress R CMD check NOTEs for symbols injected by other packages' macros:
#   await -- provided inside coro::async() generators (not a normal function)
utils::globalVariables(c("await"))
