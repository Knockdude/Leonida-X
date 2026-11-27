# Guide for coding agents

The rules for this repository are in [CLAUDE.md](CLAUDE.md). Read it before changing anything: its hard rules
(no game data, derived data outside the repository, text files only, offline by design) apply to every agent,
whatever it is called.

## Skills

Step-by-step guides for common work, in the Agent Skills format. Each `SKILL.md` reads on its own, so an agent
that does not load skill folders can open the one it needs.

The same files are in `.claude/skills/` (where Claude Code looks) and `.agents/skills/` (where other agents
look). Edit both copies in the same commit.

| Skill | Use it to |
|---|---|
| [boot-triage](.claude/skills/boot-triage/SKILL.md) | run the title under a timeout, call the run PASS, HANG, CRASH or EXIT, and rank what stopped it |
| [missing-imports](.claude/skills/missing-imports/SKILL.md) | find which imports and D3D12.X methods are missing, and where each fix goes |
| [trace-import](.claude/skills/trace-import/SKILL.md) | work out what the title expects from an import or a crash address, with every claim labelled observed, measured, inferred or unknown |
| [renderdoc-gpu-debug](.claude/skills/renderdoc-gpu-debug/SKILL.md) | read a wrong picture: a frame shot first, a RenderDoc capture when that is not enough |
| [systematic-debugging](.claude/skills/systematic-debugging/SKILL.md) | find the root cause of a bug before fixing it |
| [tdd](.claude/skills/tdd/SKILL.md) | write the test first, then the code |
