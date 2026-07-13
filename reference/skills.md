# Skill System

Progressive skill loading for codeagent. Uses btw as the discovery and
loading backend. Skill format: `<name>/SKILL.md` directories
(btw-compatible).

Discovery order (later overrides earlier):

1.  codeagent built-ins (inst/skills/)

2.  Other attached R packages with inst/skills/

3.  btw built-in skills

4.  btw user dirs (\~/.config/btw/skills/, \~/.btw/skills/)

5.  .btw/skills/, .agents/skills/ (btw project dirs)

6.  .claude/skills/ (Claude Code compat)

7.  .codex/skills/ (Codex compat)

User-global custom skills: use \~/.btw/skills/ (btw native).
Project-local custom skills: use .btw/skills/ (btw native).
