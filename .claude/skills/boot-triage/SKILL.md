---
name: boot-triage
description: >-
  Run the title under a hard timeout, keep its log outside the checkout, call the run PASS, HANG, CRASH or
  EXIT, and turn the log and crashes.log into a ranked list of what stopped it: the crash report, the
  unimplemented import that trapped, D3D12.X methods that are not implemented, and GPU failures. Compares a
  run with the one before it. Use when the user says "run it", "does it boot", "why did it crash", "what do
  I fix next", "did that break anything", or after a change to the loader, leonida-hle or leonida-gpu.
---

# Boot triage

Every fix ends the same way: build, run, read the log, decide. This skill keeps that loop short and the
same every time. The method comes from the tester skill of
[Jakeschincariol/console-skill](https://github.com/Jakeschincariol/console-skill) (MIT, see
[LICENSE](LICENSE)), rewritten for this repository. Read [CLAUDE.md](../../../CLAUDE.md) first.

Its partner skills: [missing-imports](../missing-imports/SKILL.md) fixes what this one ranks,
[trace-import](../trace-import/SKILL.md) works out what the title expects when the log doesn't say, and
[renderdoc-gpu-debug](../renderdoc-gpu-debug/SKILL.md) takes over when it runs but the picture is wrong.

## Logs stay local

The run's log and `crashes.log` keep the title's last debug output, and crash reports name its code. They
stay on your PC, outside the checkout (the "Derived data stays outside the repository" rule), and never go
into a commit, issue or pull request. Share import names, `module+offset` addresses and counts, never the
logs.

## The state file

`%LOCALAPPDATA%\leonida\agent-state.md` is the memory between sessions, outside the checkout for the same
reason. Read it first and write back one line per run. It holds:

- the run command and the switches it was run with, copied and never rebuilt from memory;
- which build (`target\release` or `target\diag`);
- one line per run: date, what changed, verdict, run folder;
- the open stops, each with how many fixes were tried on it;
- the regression runs: the exact command and expected verdict of each milestone reached.

If it does not exist, create it. The game folder comes from `leonida.toml` (`leonida config` prints it;
`run-gta6.ps1` asks for it once).

## Without the game

The loader and HLE tests build their input with our own code, and are the first thing to run after a change
there:

```powershell
cargo test -p leonida-loader --locked
cargo test -p leonida-hle --locked
```

## One run

1. **Build.** `cargo build --profile diag -p leonida --features diagnostics` for the debugging aids
   (`LEONIDA_STACKS`, `LEONIDA_WATCH`, `LEONIDA_KEYS`, debug output), or `cargo build --release -p leonida`
   to check what players get. Never `cargo clean` to make sure.
2. **Bind first, without running.** `target\diag\leonida.exe run` stops after binding and prints
   `bound <image>: N hle, N host, N title, N missing` with a `missing dll!symbol` line for each. A new
   missing import here is cheaper to find than in a run.
3. **Run short, log to a new folder:**

   ```powershell
   $run = Join-Path $env:LOCALAPPDATA "leonida\runs\$(Get-Date -Format yyyyMMdd-HHmmss)"
   New-Item -ItemType Directory -Force $run | Out-Null
   $env:LEONIDA_LOG = 'info'
   $p = Start-Process target\diag\leonida.exe -PassThru -NoNewWindow -ArgumentList 'run', '--execute' `
       -RedirectStandardError "$run\stderr.log" -RedirectStandardOutput "$run\stdout.log"
   $null = $p.Handle
   if ($p.WaitForExit(120000)) { "exit $($p.ExitCode)" } else { taskkill /pid $p.Id /t /f | Out-Null; 'timeout' }
   ```

   Two minutes covers the loader, the intro and the menus; raise it only when chasing a later milestone,
   and set `LEONIDA_KEYS` (diag build) to get through the menus unattended. `$p.Handle` is read so
   PowerShell keeps the exit code. `taskkill /t` ends the whole process tree, so no game window is left.
4. **Give the verdict** (table below).
5. **Read only what matters**, not the whole log:

   ```powershell
   Get-Content "$run\stdout.log" -Tail 20
   Select-String -Path "$run\stderr.log" -Pattern 'ERROR|unimplemented import|not implemented|panicked' |
       Select-Object -First 40
   Get-Content (Join-Path $env:LOCALAPPDATA 'leonida\data\*\crashes.log') -Tail 80
   ```

   `crashes.log` is appended to by every build, in the title's folder under `%LOCALAPPDATA%\leonida\data`;
   take the entries with this run's time.
6. **Rank** (next section) and work the top item.
7. **Record** the line in the state file.

## Verdicts

| Verdict | When |
|---|---|
| PASS | the milestone being chased was reached (a log line, a picture, play) and nothing crashed before the timeout |
| HANG | the timeout came first and the milestone did not. `LEONIDA_STACKS=60,90` (diag) shows what every thread was waiting on |
| CRASH | a crash report in `crashes.log` for this run, an unimplemented import that trapped, a host GPU failure, or a negative exit code |
| EXIT | `title exited with <code>` before the milestone |

## Ranking

The first thing that went wrong usually caused the rest. In this order:

1. **An unimplemented import that trapped.** With the default `--unimplemented trap` the run logs it,
   writes `Leonida X: unimplemented import dll!symbol called` to `crashes.log`, and aborts. That
   import is the stop: [missing-imports](../missing-imports/SKILL.md).
2. **The crash report.** The faulting address as `module+offset`, the frames and the title's last lines of
   debug output, which often say what it checked (`crates/leonida-loader/src/crash.rs`). A breakpoint is
   usually the title's own assertion. Inside our code: a bug of ours. Inside the title's code with nothing
   missing before it: [trace-import](../trace-import/SKILL.md), starting from that address.
3. **Host GPU failures** in `crashes.log` (device removed, a pipeline the driver refused).
   `LEONIDA_D3D12_DRED=1` names the allocation and the commands in flight; `docs/fork-notes.md` lists the
   other GPU switches.
4. **`method not implemented`** warnings (`crates/leonida-gpu/src/object.rs`): the object, the slot and the
   caller. The method answered `E_NOTIMPL`, and the title may have gone on without it.
5. **Imports that returned 0** under `--unimplemented zero`: each is logged once. Use `zero` only to see how
   far the title gets past a trap, never as the fix.

## Comparing two runs

After a fix, set this run's ranked list next to the one before:

- The stop is gone: progress. Update the state file.
- A new stop after the old one: usually progress too, the title got further.
- A new stop earlier than the old one: the change broke something. Look at it before the next fix.

After any change to the loader, `leonida-hle` or `leonida-gpu`, run every regression run in the state
file. A milestone that passed before and fails now is the first thing to fix.

## Three strikes

Three fixes on the same stop that did not move it: stop guessing. Reread the state file and
`docs/fork-notes.md`, trace the address with [trace-import](../trace-import/SKILL.md), and if it is still
unclear, ask the user one specific question.

## Do not

- leave a process running: one run at a time, ended at the timeout;
- make a stop pass silently to get further: an approximation gets a `shortcut:` marker, a risky behaviour a
  `LEONIDA_*` switch that is off by default;
- clean the build or change a test to make a run pass;
- post a log, `crashes.log`, a `LEONIDA_CRASH_SAVE` file or a screenshot of the title anywhere.
