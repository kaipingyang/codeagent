# Suppress R CMD check NOTEs for symbols injected by other packages' macros:
#   await -- provided inside coro::async() generators (not a normal function)
#   yield -- provided inside coro::async_generator() bodies
utils::globalVariables(c("await", "task", "yield"))
