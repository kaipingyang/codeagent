---
name: loop
description: Run a skill or task periodically (e.g. /loop 5m /verify)
argument-hint: "<interval> <task>"
---

Set up a periodic task loop. The request was: $ARGUMENTS

Parse the request to determine:
1. **Interval** -- How often to repeat (e.g. "5m", "1h", "30s")
2. **Task** -- What to do each iteration (e.g. run /verify, check tests, monitor a file)

Then:
- Acknowledge the loop configuration
- Run the task once immediately to verify it works
- Describe how to stop the loop (type "stop" or close the session)

Note: The loop runs within this session. If the model context fills up, /compact will be called automatically.
