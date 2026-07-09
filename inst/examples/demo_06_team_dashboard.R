#!/usr/bin/env Rscript
# inst/examples/demo_06_team_dashboard.R
#
# Demo: the live multi-agent team-board dashboard (team_dashboard()).
#
# team_dashboard() is a STANDALONE Shiny app (separate from codeagent_app) that
# monitors a shared task board in real time: a task table coloured by status, a
# done/total progress bar, and the inter-agent message log. It refreshes
# event-driven via board_watch() (the watcher package), falling back to polling.
#
# Run from the package root:
#   Rscript inst/examples/demo_06_team_dashboard.R
# Or in RStudio / Positron:
#   source("inst/examples/demo_06_team_dashboard.R")
#
# This demo seeds a small dependency DAG on a board (no LLM needed) so you can
# see the dashboard immediately. For a LIVE run with real agents, see the
# commented "Option B" block at the bottom.

readRenviron(".Renviron")
devtools::load_all(quiet = TRUE)

# ---------------------------------------------------------------------------
# Option A (default): seed a demo board so the dashboard has content to show.
# ---------------------------------------------------------------------------
db <- file.path(tempdir(), "codeagent_demo_board.sqlite")
unlink(db)
board_create(db)

# A little DAG: "seed data" and "run report" both depend on "build schema".
a <- board_add_task(db, "build schema")
b <- board_add_task(db, "seed data",  blocked_by = a)
d <- board_add_task(db, "run report", blocked_by = c(a, b))

# Fake some progress so the board isn't all-pending: claim + complete task A,
# then claim B (as if a worker is running it) and post a coordinator message.
board_claim(db, "worker-1")                    # claims A (only unblocked task)
board_complete(db, a, "schema.sql created")    # A done -> B becomes claimable
board_send_message(db, "worker-1", "completed task #1 (build schema)", "coordinator")
board_claim(db, "worker-2")                    # claims B (now unblocked)

cat("Seeded demo board at: ", db, "\n", sep = "")
cat("Launching team_dashboard() -- 1 done, 1 running, 1 pending.\n")
cat("Press Ctrl-C to stop.\n\n")

team_dashboard(db, title = "codeagent \u2014 team board (demo)")

# ---------------------------------------------------------------------------
# Option B (live): run a real team in the background and watch it fill in.
# Uncomment to try (needs CODEAGENT_BASE_URL / MODEL / API_KEY in .Renviron).
# ---------------------------------------------------------------------------
# live_db <- file.path(tempdir(), "codeagent_live_board.sqlite"); unlink(live_db)
# bg <- callr::r_bg(function(db) {
#   codeagent::team_coordinate(
#     tasks      = c("write a haiku about R", "write a haiku about Shiny",
#                    "combine both haiku into one poem"),
#     blocked_by = list(integer(0), integer(0), c(1L, 2L)),  # 3 waits for 1 + 2
#     permission_mode = "bypass", db_path = db)
# }, args = list(db = live_db))
# team_dashboard(live_db, title = "codeagent \u2014 live team board")
