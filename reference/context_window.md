# Dynamic context-window resolution

Resolves a model's context window and the auto-compaction threshold
dynamically, instead of hard-coding 200K. Aligned with Claude Code's
public auto-compaction behaviour (compaction triggers a fixed buffer
below the model's effective context window).

Resolution order for the raw window (highest priority first):

1.  `CODEAGENT_MAX_CONTEXT_TOKENS` env override

2.  `[1m]` suffix in the model name -\> 1,000,000

3.  Known-model capability table / provider-reported value (\>= 100K
    trusted)

4.  `.MODEL_CONTEXT_WINDOW_DEFAULT` (200K)
