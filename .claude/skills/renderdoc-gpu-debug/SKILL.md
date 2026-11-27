---
name: renderdoc-gpu-debug
description: >-
  Read GPU frames of a Leonida X run: a frame shot (LEONIDA_SHOT) first, a RenderDoc capture
  (LEONIDA_RENDERDOC) read through rdc-cli when a shot is not enough. Pipeline state at a draw, bound
  resources, shaders, pixel history, render targets exported as PNG, and the difference between two
  captures. Use when a picture is wrong (black, missing, washed out, garbage), or when the user mentions
  RenderDoc, an .rdc file, a frame shot, a draw, a render target or pixel history. Not for frame timings.
---

# GPU frame debugging

The RenderDoc part reads captures with [rdc-cli](https://github.com/BANANASJIM/rdc-cli), a command line
over RenderDoc's Python API. It is adapted from
[rudybear/renderdoc-skill](https://github.com/rudybear/renderdoc-skill) (MIT, see [LICENSE](LICENSE)),
rewritten for this repository. Read [CLAUDE.md](../../../CLAUDE.md) first: its hard rules apply to
everything here.

## Captures and shots are game data

A RenderDoc capture holds the title's shaders, textures and buffers; a frame shot's `snap-*.png` and an
exported render target show its pictures, and `events.txt` names its shaders. None of it goes into a
commit, an issue, a pull request or a test fixture, and none of it is written inside the checkout. The
defaults already keep them out: shots under `%LOCALAPPDATA%\leonida\shots`, captures under the
temporary folder. In a pull request, describe what was seen in words and numbers: the draw, the state
that was wrong, the value read back.

## First: a frame shot

The layer can take a frame apart itself, with no outside tool on the device (`crates/leonida-gpu/src/shot.rs`).
RenderDoc wraps the host device and hooks the process: the notes in that file record a run that ended
ten seconds in under a wrapped device, and while RenderDoc is loaded the driver's pipeline library is
neither read nor written, so the run is not the one players get. Try a shot before a capture.

```powershell
powershell -ExecutionPolicy Bypass -File .\shot-run.ps1 -Keys '30:Enter,35:Enter' -ShotAt '300,600'
```

`-Keys` (`LEONIDA_KEYS`) presses keys at those seconds to get from the menus into play, `-ShotAt`
(`LEONIDA_SHOT_AT`) names the frames, counted from the first frame of 500 draws or more. Each
`shot-<frame>` folder has:

- `events.txt`: every draw, dispatch, copy and submission in order, with its shaders, targets and states;
- `stamps.txt`: the card's clock before each of those commands;
- `snap-*.png` and `snaps.txt`: what a texture held when it left a written state, the picture each pass
  left;
- `info.txt`, and `done` when everything is written.

Open a `snap-*.png` with the Read tool to see it. Walk the snaps in order to find the first pass whose
picture is wrong; its line in `events.txt` names the draw, the shaders and the targets.

## Then, if needed: a RenderDoc capture

### Set up once

1. Install RenderDoc from [renderdoc.org](https://renderdoc.org), and Python 3 of the version its
   `renderdoc.pyd` was built for.
2. `pip install rdc-cli`. It is a tool on your PC, not part of this repository (which holds no Python).
3. Set `RENDERDOC_PYTHON_PATH` to the folder with `renderdoc.pyd` and `renderdoc.dll` (for the
   installer, `C:\Program Files\RenderDoc`).
4. Run `rdc doctor`. Every check must pass.

### Capture from a run

The run loads RenderDoc itself and asks it for one frame (`crates/leonida-gpu/src/renderdoc.rs`), so
`rdc capture` is not needed:

| Variable | Means |
|---|---|
| `LEONIDA_RENDERDOC` | the full path of `renderdoc.dll`. A bare name is refused, so neither the current folder nor the title's is searched |
| `LEONIDA_RENDERDOC_AT` | the frame to capture, counted in presents after the first frame of 500 draws or more (150 by default) |
| `LEONIDA_RENDERDOC_OUT` | the capture file names (by default `leonida_rdc\frame` under the temporary folder) |

```powershell
$env:LEONIDA_RENDERDOC = 'C:\Program Files\RenderDoc\renderdoc.dll'
$env:LEONIDA_RENDERDOC_AT = '300'
$env:LEONIDA_KEYS = '30:Enter,35:Enter'
target\release\leonida.exe run --execute
```

The API captured is host D3D12: the title's D3D12.X calls go through `leonida-gpu` to the PC driver,
and its shaders are DXIL from `leonida-shader`. Close overlays that hook D3D12 (RivaTuner, OBS game
capture, FPS counters) before a capture; they hook the same device RenderDoc wraps.

### Read it

Every session is open, work, close. A daemon left open keeps GPU memory.

```bash
rdc open "$TEMP/leonida_rdc/frame_capture.rdc"
rdc info --json              # API, GPU, driver, resolution
rdc stats --json             # passes, the largest draws and resources
rdc passes
rdc draws --limit 20
rdc close
```

Then, at the draw that matters (its event id, EID):

| Question | Command |
|---|---|
| What state is the pipeline in? | `rdc pipeline EID rs --json` (also `vs`, `ps`, `om`, `ia`, `ds`) |
| What is bound? | `rdc bindings EID --json` |
| Which shader runs, and what does it read? | `rdc shader EID ps --reflect --json`, `rdc shader EID ps --constants --json` |
| What does the shader say? | `rdc shader EID ps --targets`, then `rdc shader EID ps --target <one of them>` |
| What did the target hold after it? | `rdc rt EID -o "$TEMP/leonida_rdc/rt.png"`, then open the PNG with the Read tool |
| Which draws wrote this pixel? | `rdc pixel X Y EID --json` |
| How did the shader compute it? | `rdc debug pixel EID X Y --trace` |
| What changed between two runs? | `rdc diff a.rdc b.rdc --draws --json`, `rdc diff a.rdc b.rdc --framebuffer --json` |

`rdc --help` and `rdc <command> --help` list every command. Keep output small: `--limit` on lists, one
pipeline section at a time, `-q` for lists of ids. A full `rdc pipeline EID --json` is hundreds of lines
and a pixel trace can be a thousand.

## What a wrong picture usually is here

Check these in order before suspecting the driver:

1. **The translated shader.** A program that does not translate drops its draws (TODO R-7):
   `leonida translate --list` names them. A value that goes wrong inside a shader that did translate is
   a rule of `leonida-shader`; a debugged pixel shows where.
2. **The descriptors and root signature.** An empty or wrong binding points at
   `crates/leonida-gpu/src/descriptor.rs`, `root.rs` or `signature.rs`.
3. **Formats and layouts.** Scrambled with the right colours is tiling or detiling
   (`crates/leonida-formats`, `crates/leonida-gpu/src/tiles.rs`); the right shape with wrong colours is a
   format or an sRGB view.
4. **The state.** Culling, depth, blend and viewport from `rdc pipeline EID rs` and `om`.
5. **Something missing.** A `method not implemented` warning in the run's log (`object.rs`), or a
   pipeline creation method that is not implemented (`device.rs`), means the title went without it.

Write the finding with how it was seen: the shot and its line, or the EID and the state or value read,
and whether it was observed or inferred.

## Not for timings

A RenderDoc replay runs each draw alone on a wrapped device; its durations are not the game's. For time,
use `stamps.txt` of a shot, the card meter, or a measured run (`measure-gta6.ps1`), as "Measuring" in
CLAUDE.md says.
