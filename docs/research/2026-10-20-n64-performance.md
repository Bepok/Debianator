# N64 performance research

Date: 2026-10-20. Status: closed; parallel-n64 measured and shipped (see "parallel-n64" below). Found during Task 5 of [`../plans/2026-10-19-n64-psp.md`](../plans/2026-10-19-n64-psp.md).
Context: [`../specs/2026-10-19-n64-psp-design.md`](../specs/2026-10-19-n64-psp-design.md).

## Summary

mupen64plus-next with GLideN64 (GLES2) is **GPU-bound** on the Mali-400 MP2 (Mesa lima). Mario Kart 64 reaches about
45 fps of 60 with the core's threaded renderer, 30 without it; Super Smash Bros. reaches 24 fps and then goes black in
its menus. The audio crackles at any speed below real time, because the core only makes samples as fast as it
emulates. 2D menu graphics show horizontal gaps through letters.

- **GPU-bound, measured.** Capping the GPU at 240 MHz instead of 384 MHz drops Mario Kart from about 45 to about
  27 fps (x1.67 for x1.6 of clock). When RetroArch's main thread waits, it waits in `poll()` on an
  `anon_inode:sync_file`: Mesa's swap throttle waiting for the previous frame's GPU fence. Neither CPU thread is
  saturated (about 50 % and 31 % of a core with the threaded renderer); the system is about 80 % idle.
- **Why the GPU is slow: GLideN64's GLES2 shaders.** On GLES2 GLideN64 compiles only its "Accurate" combiner, which
  filters textures in the shader (4 dependent fetches per sample, up to 8 per pixel) and does texture wrap, clamp and
  atlas math per fragment. LOD emulation adds more. (Read from the pinned source; the per-pixel cost on lima is not
  measured.)
- **Why the picture breaks: FP16.** lima runs every fragment shader in FP16; `highp` is accepted and ignored, and Mesa
  defines `GL_FRAGMENT_PRECISION_HIGH` anyway, so GLideN64's `mediump` fallback never triggers. The Accurate path's
  `floor`/`mod` and `(tc + 0.5) / texSize` math rounds to the wrong texel at FP16, which skips or doubles whole texel
  rows: the gaps in the Mario Kart menu letters. (Strong inference from code and docs, not tested on the device.)
- **Smash black screen: cause unknown.** This core build logs nothing (`LOG_NONE`, shader checks only under
  `GL_DEBUG`) and lima skips a draw whose shader fails to compile, printing to stderr only. Candidates: the FP16 noise
  hash collapsing (as in GLideN64 #2837), the texture precision above, or lima compile failures.
- **Other firmware avoids GLideN64 on this class of hardware**, even on stronger chips (RK3326, Cortex-A35 with a
  Mali-G31): standalone mupen64plus with Rice (AmberELEC, ROCKNIX, ArkOS) or libretro parallel-n64 with glide64
  (Knulli). RetroPie switches Mario Kart to gles2n64 on Pi 0-3 because it "runs faster". The one firmware on this
  exact SoC, spruceOS on the Miyoo A30, does use a GLideN64 fork, but with the CPU at 1.344-1.512 GHz and presumably
  the vendor Mali driver.

Decision (owner, 2026-10-20): stop tuning GLideN64 and build **libretro parallel-n64** next, platform
`classic_armv7_a7` (the SNES Classic target; its Allwinner R16 is an A33 sibling with the same Mali-400 MP2), and
compare it on the same games. Its gln64 and glide64 renderers sample textures straight from varyings with hardware
filtering, so they should be lighter on the GPU and get lima's FP24 texture path. That is from reading their code;
no Mali-400 report was found either way.

## Measurements

All on GA36 V1.0, image `v1.0.0-40-g9aa1ba5`, Mesa 25.0.7 lima, RetroArch 1.20.0 (Debian), core at `6752836`,
CPU 1.2 GHz (performance governor while RetroArch runs), GPU 384 MHz.

| Change from the shipped options                 | Mario Kart 64      | Notes                                       |
|-------------------------------------------------|--------------------|---------------------------------------------|
| none (vsync on)                                  | 30.03 fps          | audio crackles, ALSA keeps underrunning     |
| `video_vsync = false`                            | 30.25 fps          | no effect                                   |
| + `mupen64plus-ThreadedRenderer = True`          | about 45 fps       | audio better, still crackles                |
| + `mupen64plus-virefresh = 1500`                 | about 45 (40 menus)| no gain                                     |
| + `mupen64plus-FrameDuping = True`               | about 45 fps       | no gain                                     |
| + GPU `max_freq` 240 MHz                         | about 27 fps       | the GPU-bound test                          |

Super Smash Bros.: 24 fps, crackling audio; after the intro the screen goes solid colour, then black, with
`EnableFBEmulation` False and True. RetroArch RSS 176-213 MB, about 260 MB available, no OOM. No lima errors in the
kernel log.

The fps counter counts `video_cb` calls. The core yields once per emulated VI and calls `video_cb` on a GLideN64 swap
(or a duped frame with FrameDuping), so full speed reads about 60 with FrameDuping on. Mario Kart draws 30 frames/s
on a real N64, so the counter alone is ambiguous with FrameDuping off; the crackling audio and FrameDuping's 45 settle
that it runs below real time.

## parallel-n64

Upstream `6f23339`, `platform=classic_armv7_a7`, dynarec, 320x240. The platform's `-fwhole-program` with `-flto` hides
every `retro_*` symbol under GCC 14 (a 95 KB core with no exports), so the build drops it
(`apps/parallel-n64/patches`).

| Renderer, accuracy | Mario Kart 64      | Super Smash Bros.                                  |
|--------------------|--------------------|----------------------------------------------------|
| glide64, veryhigh  | 21-24 fps, clean   | not tried                                          |
| gln64, low         | about 48 fps, clean| 30-35 fps, menus correct, one core at 100 %        |

gln64 at low ships. It is CPU-bound, not GPU-bound: Smash keeps the emulation thread at 100 % of a core, and
`parallel-n64-virefresh = 1500` gained only about 2 fps (not kept). Audio still crackles below full speed.

## Ruled out

- **Vsync / page-flip quantisation.** With `video_vsync = false`, RetroArch 1.20's KMS context drops a frame rather
  than wait for a pending flip (default `video_max_swapchain_images = 3`, Mesa GBM has 4 buffers). Never set it to 2:
  that forces a blocking flip wait every frame.
- **Audio pacing.** The ALSA buffer stays nearly empty and restarts after each underrun, so audio never blocks the
  loop. No audio setting can fix a lasting deficit: rate control bends pitch by 0.5 % at most.
- **Memory.** About 260 MB available while playing.
- **GPU clock scaling.** Pinned at 384 MHz during play. Note that lima sets `simple_ondemand` to upthreshold 30,
  downdifferential 5 (`drivers/gpu/drm/lima/lima_devfreq.c`), so "pinned at max" alone only means more than 30 %
  busy; the 240 MHz cap is what proves the GPU limit.
- **`video_threaded`, `video_hard_sync`.** Threaded video is forced off for HW-rendered cores; hard sync needs GLES 3.
- **CPU above 1.2 GHz.** Needs new OPPs and voltage on mainline; rejected for the same reason as in
  [`2026-10-20-doom-performance.md`](2026-10-20-doom-performance.md) ("CPU at 1.344 GHz").

## Not tried (GLideN64), in case parallel-n64 fails

- `mupen64plus-EnableInaccurateTextureCoordinates = True` ("fast but less accurate shaders, can help with low-end
  GPUs"): normalised coordinates and hardware filtering. Should confirm the FP16 cause of the streaks and cut fragment
  cost.
- `mupen64plus-EnableLODEmulation = False`: drops the LOD math from the shaders.
- `mupen64plus-CorrectTexrectCoords = Force`, `EnableNativeResFactor = 1`, `EnableTexCoordBounds = True`: the known
  Mario Kart menu texrect-line bug class (GLideN64 #2506).
- Smash: `MESA_GLSL=nopfrag` (fragment path vs geometry), `MESA_GLSL=errors MESA_DEBUG=1 LIMA_DEBUG=shaderdb` with
  RetroArch's stderr captured (lima compile failures).

## Diagnostics that work on this board

Over the USB console (`scripts/board-run.sh`), no strace or perf needed:

- Which fd a thread waits on: read `/proc/PID/task/TID/syscall` (armhf `poll` is 168, `ppoll` 336/414), read the
  first `pollfd` from `/proc/PID/mem` at the address in arg0, `readlink /proc/PID/fd/FD`. `sync_file` = GPU fence,
  `/dev/snd/pcmC0D0p` = audio, `/dev/dri/card1` = page flip.
- GPU-bound or not: `echo 240000000 > /sys/class/devfreq/1c40000.gpu/max_freq` while playing and compare fps; restore
  with `384000000`.
- GPU job rate: `gp`, `pp0`, `pp1` lines of `/proc/interrupts`.
- Not available: dynamic debug (lima's busy-% message), lima debugfs or fdinfo stats.
- GLES2 extensions: there is no `es2_info` on the image; a 30-line surfaceless EGL probe (`dlopen` libEGL, platform
  `EGL_PLATFORM_SURFACELESS_MESA`) cross-built with `./build.sh run arm-linux-gnueabihf-gcc` prints them without DRM
  master.

## Sources

- Mesa lima limitations (FP16 fragment shaders, `highp` ignored): https://docs.mesa3d.org/drivers/lima.html
- Mesa defines `GL_FRAGMENT_PRECISION_HIGH` for every GLES context: `src/compiler/glsl/glcpp/glcpp-parse.y` at
  `mesa-25.0.7`; swap throttle on the previous fence: `src/gallium/frontends/dri/dri_drawable.c`,
  `src/gallium/drivers/lima/lima_fence.c`.
- Possibly relevant open Mesa issue (texcoord varyings dropped to FP16 since 25.0):
  https://gitlab.freedesktop.org/mesa/mesa/-/issues/12702
- GLideN64 GLES2 Accurate combiner: `GLideN64/src/Graphics/OpenGLContext/GLSL/glsl_CombinerProgramBuilderAccurate.cpp`
  in the pinned core; FP16 precedent https://github.com/gonetz/GLideN64/issues/2837 ; Mario Kart menu texrect lines
  https://github.com/gonetz/GLideN64/issues/2506 ; GLES2 on lima https://github.com/gonetz/GLideN64/issues/2903
- RetroArch KMS flip handling: `gfx/drivers_context/drm_ctx.c` at `v1.20.0`.
- Other firmware: AmberELEC `es_systems.cfg` and `mupen64plus-RG351P.cfg`; ROCKNIX mupen64plus-sa RK3326 config;
  Knulli `es_systems_n64.cfg`; ArkOS wiki "Emulators and Ports information"; RetroPie `scriptmodules/emulators/mupen64plus.sh`;
  spruceOS `Emu/N64/config.json` and `spruce/scripts/platform/A30.cfg`.
- parallel-n64 `classic_armv7_a7` target and GLES2 plugins: https://github.com/libretro/parallel-n64 (`Makefile`,
  `Makefile.common`); purpose: https://docs.libretro.com/library/parallel_n64/
