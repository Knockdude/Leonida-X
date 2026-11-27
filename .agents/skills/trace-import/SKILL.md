---
name: trace-import
description: >-
  Work out what the title expects from an import, a D3D12.X method or a crash address: its callers, the
  arguments it passes, what it does with the result, and write the finding down with a label for how it is
  known (observed, measured, inferred, unknown). Use when the user asks "what does the game do with X",
  "what does this import have to return", "who calls this", "what is at module+0x...", or before writing an
  implementation whose behaviour is not documented.
---

# Trace an import

Tracing means following the title from something concrete (an import, a method slot, a crash address) to
the code that uses it, and leaving a written trail. The method and the labels come from the `re-trace` and
`re-start` skills of [tanepiper/game-frame](https://github.com/tanepiper/game-frame) (CC0), rewritten for
this repository. Read [CLAUDE.md](../../../CLAUDE.md) first: nothing of the title goes into the
repository, and that includes disassembly, decompiled pseudocode and memory dumps.

## Label every claim

Write each finding with its evidence and one label:

| Label | Means |
|---|---|
| observed | read in the executable, a crash report or a log line: name where, as `module+offset` |
| measured | produced by running: a run of the title, a test, a count over every shader, with the inputs |
| inferred | follows from observed or measured facts, with the reasoning written next to it |
| unknown | not settled; say what would settle it |

A claim with no label is a guess, and CLAUDE.md asks for it to be called one. In code, behaviour built on
an inferred fact that approximates the console gets a `shortcut:` comment.

## 0. Has it been done?

The import, method or address may already be measured. Search before opening the executable:

```bash
grep -rn "XUserAddAsync" docs/ crates/ | head
```

`docs/fork-notes.md` is the measurement log; `docs/architecture.md` says which crate owns what. The
implementations in `crates/leonida-hle/src/modules/` often carry what was learned in their comments.

## 1. Find the way in

Work outward from something concrete. None of these write inside the checkout.

| Starting from | Where to look |
|---|---|
| an import | `leonida inspect <image> --imports` (is it imported, from which DLL); `leonida census --missing` (how many images use it) |
| an import that trapped | `crashes.log`: `Leonida X: unimplemented import dll!symbol called`. Run under a debugger and the trap breaks at the call, with the title's arguments in rcx, rdx, r8 and r9 |
| a D3D12.X method | the `method not implemented` warning (`crates/leonida-gpu/src/object.rs`): object kind, slot offset and the caller as `+offset` |
| a crash | the crash report (`crates/leonida-loader/src/crash.rs`): the faulting `module+offset`, the frames and the title's last debug output |
| a value that changes | `LEONIDA_WATCH=<rva>,...` (diag build) logs a title u32 each time it changes |
| where threads wait | `LEONIDA_STACKS=20,60` (diag build) prints every thread's stack at those seconds |

## 2. Read the call site

Open the address in a disassembler (Ghidra, x64dbg or IDA, your own install) and note:

- the arguments: Win64 passes the first four in rcx, rdx, r8 and r9 (xmm0 to xmm3 for floats), the rest
  on the stack; which are constants, which point at the caller's locals;
- what happens to the result: tested against what, and where each branch goes. A branch to `int3` is the
  title treating that result as impossible, and a wrong answer there ends the run with a breakpoint;
- the out parameters it reads afterwards: those are what the implementation must fill in;
- the callers above, up to a loop, a vtable slot or a thread entry. A code path is not proof that it runs;
  a trap, a crash report or a `LEONIDA_WATCH` line shows that it does.

A function's name does not tell you its argument order or meaning: read the public reference page and the
call site, and say which one each fact comes from.

## 3. Measure when it matters

When the exact value matters (a size, a flag word, a slot), confirm it by running: a breakpoint at the
call under a debugger, `LEONIDA_WATCH`, or a test in the crate that builds the same input with our own
code. That turns observed into measured. `LEONIDA_CRASH_SAVE` writes title memory to the cache folder on a
crash; that file is game data and stays there.

## 4. Write it down

Add what was measured to `docs/fork-notes.md`, or extend the comment on the implementation: what the
title calls, from where (`module+offset`, with the build), with which arguments, what it does with the
result, and what is still open. Describe the code in prose and tables; never paste disassembly or
pseudocode. Every claim carries its label.

## Pitfalls

- A small function may be inlined into each caller, so a "missing" function is often inside its caller.
- A call through a register after loading the import's address does not show as a direct call; count
  call sites as a lower bound.
- Two subsystems may share a helper with different meanings for its arguments. Name it by what it does,
  not by the first place it was seen.
- Never round a constant: write it as the file has it.
