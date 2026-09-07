# KDE Plasma (Wayland) over WSLg on RHEL 10 — SOLVED

---
## Side task: move THIS Claude Code session to `~/projects/kde-plasma-wslg`

**Why:** the user wants to keep working in this conversation from a VS Code window opened on
the `~/projects/kde-plasma-wslg` workspace. Claude Code stores each session's transcript under
a per-directory folder (`~/.claude/projects/<slug>/`, slug = cwd with `/`→`-`). This session
was launched in `/home/user`, so its transcript is `~/.claude/projects/-home-user/0740027d-2a79-4b57-b1b6-1f7bb35ead7e.jsonl`.
A VS Code window opened on `~/projects/kde-plasma-wslg` looks at the slug
`-home-user-projects-kde-plasma-wslg`, which has no history — hence "not carried over".
(The picker even records this: *"filtered from /resume: recorded cwd is a different directory
with the same project slug"*.)

**Fix — one command, run it in THIS session (must be idle, not mid-turn):**

```
/cwd ~/projects/kde-plasma-wslg
```

`/cwd` changes the session's working directory **and relocates the transcript** to the new
project folder (`transcript_relocated`). It will prompt to trust the new directory (accept)
and save it to local settings; it also re-homes CLAUDE.md / skills / plugins / MCP for that dir.

**Then, to pick it up in a fresh VS Code window:**
1. In this window run `/cwd ~/projects/kde-plasma-wslg`.
2. Close this session / VS Code window (so it isn't "live" — otherwise a resume elsewhere
   *"starts a copy"*).
3. Open VS Code on `~/projects/kde-plasma-wslg` (or `Claude Code: Open in New Window`).
4. In the Claude Code panel there, pick this conversation from the history list — or run
   `claude --resume` in that window's terminal (the bundled binary is at
   `~/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude`),
   or use the `Claude Code: Reopen Closed Session` command.

**Manual fallback** (if you'd rather not use `/cwd`, or it's unavailable): with no live
session running, move the transcript yourself —
```
mkdir -p ~/.claude/projects/-home-user-projects-kde-plasma-wslg
mv ~/.claude/projects/-home-user/0740027d-2a79-4b57-b1b6-1f7bb35ead7e.jsonl \
   ~/.claude/projects/-home-user/0740027d.backup.jsonl \
   ~/.claude/projects/-home-user-projects-kde-plasma-wslg/
```
then `claude --resume` from the new directory.

**Not the answer here:** `/teleport` (pulls a *cloud* session to a local terminal) and
`--cloud` / `claude.ai/code` (new cloud-sandbox sessions with no access to this WSL box).

---

> **Consolidated:** everything now lives in `~/projects/kde-plasma-wslg/`
> (`README.md` = how-to, `NOTES.md` = this file, `rpmbuild/` = the build tree with
> `~/rpmbuild` symlinked to it, `dist/` `patch/` `srpm/` `screenshots/`). The launcher
> moved to `~/.local/bin/plasma-wslg.sh`. `~/kwin-wslg-patch/` no longer exists — its
> contents are the top-level files + `patch/` + `dist/` in the project.

## Status: working

`dbus-run-session -- startplasma-wayland` (via `~/plasma-wslg.sh`) now brings up a full
KDE Plasma desktop — wallpaper, panel, clock, system tray, working tooltips — nested in a
WSLg window, **with zero user interaction and no freeze**. Confirmed by Windows-side
screenshots at t+45s and t+65s (`~/final-noint.png`, `~/final-noint2.png`;
also `~/v10-realsession.png` maximized). Rendering is CPU-only (llvmpipe); no GPU.

## What was wrong (all fixed)

Continuation of `~/Downloads/wslg-kde-plasma-handoff.md`. A prior web session patched
`libkwin.so` past KWin's instant `exit(1)` on the missing `wp_single_pixel_buffer_manager_v1`
and hit a black screen. This session found the black screen was **five** stacked problems:

1. **Mesa tried Zink→Dozen→`/dev/dxg` and failed** (`ZINK: failed to choose pdev`, the EGL
   error flood). RHEL's `mesa-25.2.7-4.el10` ships no `d3d12_dri.so` / no `dzn_icd.json`, so
   there is no GPU path at all. Fix: force llvmpipe (env in `plasma-wslg.sh`).
2. **KWin's OpenGL compositor can't init nested on WSLg's ancient Weston** (no
   `zwp_linux_dmabuf`/`wl_drm`) — always falls back to QPainter. Accept it: `KWIN_COMPOSE=Q`.
3. **KWin's QPainter compositor only composites `wl_shm` client buffers.** plasmashell uses
   `wayland-egl` → invisible. Fix: `QT_QUICK_BACKEND=software` (whole session). QWidget apps
   like kwrite already use shm — that was the diagnostic tell.
4. **The session auto-locked** (big clock, no panel = the lock greeter, which respawns).
   Fix: `~/.config/kscreenlockerrc` `[Daemon] Autolock=false / LockOnResume=false`.
5. **WSLg's `weston-rdprail` (Weston 9.0.0) doesn't stream a nested KWin toplevel's contents
   to the RDP client**, so the window stayed black even though KWin composited every frame
   and got presentation feedback back. Two distinct sub-bugs, both fixed in a new
   `libkwin.so` patch (details below):
   - it can't scale a 1×1 background buffer with `wp_viewport` for a RAIL window
     (`weston.log`: "surface width/height doesn't match with buffer");
   - it never streams **subsurface** content of a RAIL window (KWin paints the desktop into
     a subsurface on top of the black toplevel) — only re-grabs the whole window on a
     Windows-side resize.

Also: use `XDG_RUNTIME_DIR=/run/user/1000` (0700, has pipewire) — the handoff's "runtime dir
is 0777" issue is only `/mnt/wslg/runtime-dir`; the `/tmp/kde-runtime` hack is unnecessary.
`/tmp/.X11-unix` sticky-tmpfs mount is still needed. Read kwin/plasmashell logs with
`journalctl -b _COMM=kwin_wayland` (`QT_LOGGING_RULES` is ignored by this build).

## The libkwin patch (on top of the prior single-pixel-buffer patch)

Full diff vs pristine v6.6.4: `~/wslg-kwin-rail.patch`. Patched sources and the built `.so`:
`~/kwin-wslg-patch/`. Touches `src/backends/wayland/{wayland_display,wayland_output,wayland_layer}.{cpp,h}`:

- **`wayland_display`**: detect `weston_rdprail_shell` in the registry → `hasRdpRailShell()`.
  Everything below is gated on it (no behaviour change for normal nested KWin).
- **`wayland_layer`**: for the **Primary** layer under rdprail, set `m_directToOutput` — its
  rendered buffer is handed to `WaylandOutput::attachContentBuffer()` (which attaches it to
  the **toplevel** `wl_surface`) instead of to a subsurface. The subsurface stays created
  but never gets a buffer. This is the key fix — the desktop is now on the surface
  weston-rdprail actually streams.
- **`wayland_output`**:
  - `createFallbackBlackBuffer()` takes `width,height` (was hard 1×1). Under rdprail the
    toplevel gets a real full-size black `wl_shm` buffer until the primary layer's first
    frame arrives, and the `wp_viewport` destination is kept 1:1 with it (fixes the
    "doesn't match with buffer" rejection).
  - `attachContentBuffer()` — new; primary layer's frames land here.
  - a 1 Hz heartbeat `QTimer` (`m_rdpRailHeartbeatTimer`) that force-repaints the primary
    layer, because weston-rdprail stops streaming a static window (`rdp_rail_idle_handler`
    in `weston.log`). Real input/animation schedules its own repaints; this only matters
    when the desktop is idle. One software recomposite/second — negligible.

### Rebuild procedure (the handoff's `rpmbuild -bc` also works but is slower / can OOM on LTO)

```bash
cd ~/rpmbuild/BUILD/kwin-6.6.4/redhat-linux-build
# RPM_ARCH etc. are required by the redhat-package-notes gcc spec when building outside rpmbuild:
env RPM_ARCH=x86_64 RPM_PACKAGE_NAME=kwin RPM_PACKAGE_VERSION=6.6.4 RPM_PACKAGE_RELEASE=2.el10_2 \
    gmake kwin -j6
sudo cp bin/libkwin.so.6.6.4 /usr/lib64/libkwin.so.6.6.4
sudo ldconfig
readlink /usr/lib64/libkwin.so.6   # MUST be libkwin.so.6.6.4
```

**Gotcha:** keep backup copies of `libkwin.so*` OUT of `/usr/lib64` (they carry the
`libkwin.so.6` soname and `ldconfig` will point the symlink at a backup). The stock lib is
saved at `/usr/local/lib/kwin-backups/libkwin.so.6.6.4.orig`.

## Protecting it

`dnf versionlock` is set on `kwin kwin-libs kwin-common` (done this session) — a `dnf update`
can't revert the patched `libkwin.so` (it lives in `kwin-libs`).

## Full-screen output — `kwin_wayland_wrapper` shim (installed + verified)

`startplasma-wayland` runs `kwin_wayland_wrapper --xwayland` with no size → nested KWin
defaults to a 1024x768 window under the Windows taskbar. `kwin_wayland_wrapper` forwards
all its args to `kwin_wayland`, so `/usr/bin/kwin_wayland_wrapper` is now a shell shim
(`~/kwin-wslg-patch/kwin_wayland_wrapper.shim`; real binary at `.bin`) that appends
`--width/--height` (from `wayland-info`, currently 2560x1440) **and `--fullscreen true`**.
Verified: full-screen Plasma desktop covering the Windows taskbar, panel fully visible,
zero interaction (`~/service-test.png`). `KWIN_WSLG_NO_FULLSCREEN=1` → windowed instead.
Alt+Tab (Windows) switches away; right-Ctrl releases the pointer grab.

## systemd user service (installed + verified)

`~/.config/systemd/user/plasma-wslg.service` — `Type=exec`, `ExecStart=~/plasma-wslg.sh`,
**no `[Install]` section** so it is `static` (manual only, as asked):

```bash
desktop.sh start | stop | status         # ~/.local/bin/desktop.sh wrapper
systemctl --user start  plasma-wslg       # (equivalent raw command)
journalctl  --user -u   plasma-wslg -f    # logs -> journal, no terminal spam
```

Confirmed running full-screen with the whole session in its cgroup (602 tasks, ~790 MB).

### `systemctl --user` glitch fixed this session
All the `pkill -9 dbus*` during testing left `systemd --user`'s private socket stale →
`systemctl --user` printed "Failed to connect to user scope bus via local transport:
Connection refused" (D-Bus path still worked). Fixed with
`busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1
org.freedesktop.systemd1.Manager Reexecute`. Shouldn't recur in normal use.

## Remaining polish (optional, not done)

- `/tmp/.X11-unix` needs to be a writable sticky dir for Xwayland's socket; `plasma-wslg.sh`
  does `sudo mount -t tmpfs -o mode=1777` (passwordless sudo is configured). A `[boot]
  command=` in `/etc/wsl.conf` would move that out of the script.
- Move `plasma-wslg.sh`'s env into `~/.config/plasma-workspace/env/*.sh`.

## Phase 2 (final) → `~/projects/kde-plasma-wslg-gpu-rpm/`

**GPU: built + tested; desktop cannot use it (WSLg-architectural).** Built Mesa 25.2.7 with
`d3d12` + `dzn` (Dozen) — works: `eglinfo` shows `D3D12 (NVIDIA GeForce RTX 5070 Ti)`, GL 4.6,
Vulkan loads. But KWin's nested Wayland backend hard-requires `EGL_PLATFORM_GBM` (a `/dev/dri`
render node) + a DRM device from the host's `zwp_linux_dmabuf`; WSLg has neither (`dxgkrnl`
isn't a DRM driver; Weston 9 advertises only `wl_shm`). Every cross-process buffer must be
CPU `wl_shm`. So the desktop stays on llvmpipe/QPainter (phase-1 setup = the ceiling). The
d3d12 build is still worth packaging for **standalone GL/Vulkan/compute apps** in the distro
(works on Intel hosts too). Full detail + reproducible recipe: `gpu/README.md`.

**RPM packaging (`rpm/`): DONE — installed + verified on this host.**
- `kwin{,-libs,-common}-6.6.4-3.el10.wslg1` — RHEL kwin SRPM + `Patch1000: wslg-kwin-rail.patch`
  + wrapper shim folded into `%install` (real binary → `kwin_wayland_wrapper.bin`),
  `Requires: wayland-utils`, `Release: 3%{?dist}.wslg1` (sorts above stock `2.el10_2` →
  clean `dnf` upgrade, no downgrade). Stripped 9.3 MB libkwin (vs the 274 MB hand-built
  debug one). `rpm -V` clean. `dnf versionlock` on `6.6.4-3.el10.wslg1`.
- `kde-plasma-wslg-1.0` noarch — `/usr/bin/plasma-wslg` (start/stop/status),
  `/usr/libexec/kde-plasma-wslg/plasma-wslg-launch`, `/usr/lib/systemd/user/plasma-wslg.service`,
  `/usr/lib/tmpfiles.d/kde-plasma-wslg.conf` (`/tmp/.X11-unix` 1777), `/etc/xdg/kscreenlockerrc`.
- The hand-installed overrides in `~/.local/bin` + `~/.config` were removed; the packaged
  versions are now live. `plasma-wslg start` → full-screen Plasma verified (`rpm/pkg-desktop.png`).
- Redeploy to another RHEL-10 WSL distro = copy 4 RPMs + `dnf install` + `versionlock`.
d3d12 `mesa` SRPM rebuild: skipped (desktop can't use GPU). See `rpm/README.md`.

## Loose ends worth doing regardless

- File the KWin bug: nested Wayland backend is unusable under weston-rdprail (RAIL) —
  needs the toplevel-surface / full-size-background handling this patch adds.
- File / check the WSLg bug: weston-rdprail doesn't stream subsurface content of RAIL windows.
- `~/kde-test/` holds all the scratch scripts and the numbered screenshot series (v6–v10).
