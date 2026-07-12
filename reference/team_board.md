# Shared Task Board (multi-agent coordination)

A SQLite-backed task board that multiple agent workers (running in
separate `mirai` daemon processes) can share to claim and complete work,
plus a simple message log for inter-agent communication. Mirrors Claude
Code's team coordination (TeamCreate / shared board / auto-claim /
SendMessage).

Why SQLite, not the in-memory `.task_store` (`tools_task.R`): that store
lives in one R process's memory and is invisible to mirai daemons. A
SQLite file is shared across processes, and a claim is a single atomic
`UPDATE ... WHERE owner IS NULL` so two workers never grab the same
task.
