# KDE Plasma Wayland over WSLg (RHEL 10) — Investigation Handoff

## Goal

Run a full KDE Plasma Desktop session using Wayland over WSLg on a RHEL 10 WSL
distro, without xrdp, an external X server, or launching individual graphical
windows. Target launch command shape:

```bash
dbus-run-session -- startplasma-wayland
```

## Environment

- Windows host: WSL2, WSLg enabled, fully up to date (`wsl --update` confirmed
  no further updates available).
- Distro: RHEL 10 (`RHEL-10` in `wsl -d RHEL-10`).
- Plasma: `plasma-workspace-6.6.4-1.el10_2.x86_64`, `kwin` 6.6.4.
- No `kwin-x11` package exists for this Plasma version (KDE fully removed the
  X11 session in Plasma 6.8, June 2026; even before that, this RHEL build only
  ships the Wayland session) — **there is no X11-session fallback available**.
- GPU: no `/dev/dri` device present; only `/dev/dxg` (WSLg's virtual GPU
  device). Mesa/D3D12-Dozen driver stack presumably meant to bridge this to a
  normal DRI render node.
- WSLg's bundled Weston compositor is old (pre-v9-era per the version-bump PR
  discussed below) and does not implement several newer Wayland protocols.

## Root causes found and fixed (in order encountered)

1. **`/tmp/.X11-unix` missing sticky bit** → blocked Xwayland socket creation.
   Fixed by bind-mounting a tmpfs over it (the directory is otherwise a
   read-only bind-mount from WSLg's system distro):
   ```bash
   sudo mount -t tmpfs -o mode=1777 tmpfs /tmp/.X11-unix
   ```

2. **`XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir` is mode 0777** → D-Bus (and
   other libraries doing the same security check) reject world-writable
   runtime dirs; this was also the source of an apparent "another compositor
   is running" collision on `wayland-0`. Fixed by using a private runtime dir
   and pointing `WAYLAND_DISPLAY` at the real host socket by absolute path:
   ```bash
   mkdir -p /tmp/kde-runtime && chmod 0700 /tmp/kde-runtime
   export XDG_RUNTIME_DIR=/tmp/kde-runtime
   export WAYLAND_DISPLAY=/mnt/wslg/runtime-dir/wayland-0
   export XDG_SESSION_TYPE=wayland
   export QT_QPA_PLATFORM=wayland
   ```

3. **KWin's nested-Wayland backend hard-requires `wp_single_pixel_buffer_manager_v1`**
   from the host compositor, and WSLg's Weston fork doesn't implement that
   protocol (confirmed via `WAYLAND_DEBUG=1` trace: the protocol never
   appears in the advertised registry globals). KWin's `WaylandDisplay::initialize()`
   treated this as fatal and called `return false`, which propagates to a
   clean `exit(1)` — confirmed via gdb (`[Inferior 1 (process ...) exited
   with code 01]`, no crash, no coredump).

   - Checked `microsoft/wslg` issue
     [#1349](https://github.com/microsoft/wslg/issues/1349) and PR
     [`microsoft/weston-mirror#159`](https://github.com/microsoft/weston-mirror/pull/159):
     that PR only bumps **version metadata** (9.0.0 → 14.0.2 strings) and does
     **not** rebase the actual Weston source — confirmed via the PR's own
     description and GitHub Copilot's review summary. It would not fix this
     issue even if merged.
   - No `kwin-x11` package/session exists to fall back to.
   - No environment variable exists to bypass the check — confirmed by
     extracting `libkwin.so.6.6.4` and grepping every `getenv`-style string in
     it; the full ~45-entry env var surface has nothing related to
     single-pixel-buffer or shm fallback.
   - **Fix: patched and rebuilt `libkwin.so` locally** (see below).

## The patch (source: KDE upstream, tag `v6.6.4`)

### 1. `src/backends/wayland/wayland_display.cpp` — make the check non-fatal

In `WaylandDisplay::initialize()`, changed:
```cpp
if (!m_singlePixelManager) {
    qCWarning(KWIN_WAYLAND_BACKEND, "wp_single_pixel_buffer_manager_v1 isn't supported by the host compositor");
    return false;
}
```
to:
```cpp
if (!m_singlePixelManager) {
    qCWarning(KWIN_WAYLAND_BACKEND, "wp_single_pixel_buffer_manager_v1 isn't supported by the host compositor");
    // Not fatal, can live without it — falls back to wl_shm in WaylandOutput::present().
}
```

### 2. `src/backends/wayland/wayland_output.cpp` — add a `wl_shm` fallback

The only other place in the codebase that dereferences `singlePixelManager()`
is `WaylandOutput::present()`, which unconditionally created a 1×1
solid-black buffer via the single-pixel-buffer protocol with **no null
check** — meaning the startup-check fix alone would have traded a clean
failure for a null-pointer segfault on first frame. Added a `wl_shm`-based
fallback:

```cpp
#include <sys/mman.h>
#include <unistd.h>
#include <cstring>

namespace {
wl_buffer *createFallbackBlackBuffer(wl_shm *shm)
{
    if (!shm) {
        return nullptr;
    }
    constexpr int width = 1;
    constexpr int height = 1;
    constexpr int stride = width * 4;
    constexpr int size = stride * height;

    int fd = memfd_create("kwin-shm-fallback", MFD_CLOEXEC);
    if (fd < 0) {
        return nullptr;
    }
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return nullptr;
    }
    void *data = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        close(fd);
        return nullptr;
    }
    const uint32_t pixel = 0xFF000000; // ARGB8888, opaque black
    std::memcpy(data, &pixel, sizeof(pixel));
    munmap(data, size);

    wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    close(fd); // safe: libwayland dups the fd during request marshalling
    wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    return buffer;
}
}
```

And in `WaylandOutput::present()`, changed:
```cpp
if (!m_mapped) {
    // we only ever want a black background
    auto buffer = wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(m_backend->display()->singlePixelManager(), 0, 0, 0, 0xFFFFFFFF);
    m_surface->attachBuffer(buffer);
    m_mapped = true;
}
```
to:
```cpp
if (!m_mapped) {
    // we only ever want a black background
    wl_buffer *buffer = nullptr;
    if (auto mgr = m_backend->display()->singlePixelManager()) {
        buffer = wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(mgr, 0, 0, 0, 0xFFFFFFFF);
    } else {
        buffer = createFallbackBlackBuffer(m_backend->display()->shm());
    }
    if (buffer) {
        m_surface->attachBuffer(buffer);
    }
    m_mapped = true;
}
```

**This patch is untested beyond the manual build/run described below** — it
compiled cleanly and got kwin past its previous instant-exit, but has not
been reviewed by anyone besides this conversation. Treat the `memfd_create`/
`mmap`/`close-fd-early` sequence as the first suspect if anything looks wrong
around buffer/output handling later.

## Build process used

```bash
# Enable source repos (verify exact repo names for your subscription)
dnf repolist --all | grep -i source
sudo subscription-manager repos --enable rhel-10-for-x86_64-appstream-source-rpms
sudo subscription-manager repos --enable codeready-builder-for-rhel-10-x86_64-source-rpms

sudo dnf install -y rpmdevtools rpm-build
rpmdev-setuptree
dnf download --source kwin
rpm -ivh kwin-*.src.rpm
cd ~/rpmbuild/SPECS
sudo dnf builddep -y kwin.spec
rpmbuild -bp kwin.spec        # prep only: extract + apply RHEL patches

# --- edit the two files under ~/rpmbuild/BUILD/kwin-6.6.4/src/backends/wayland/ here ---

# Build using RHEL's own spec-defined cmake flags, skipping back over prep
# so it does NOT re-extract and wipe the edits:
rpmbuild -bc --short-circuit --nocheck kwin.spec

# Locate and swap in the rebuilt library
find ~/rpmbuild/BUILD/kwin-6.6.4 -name "libkwin.so*" -newer ~/rpmbuild/SPECS/kwin.spec
sudo cp /usr/lib64/libkwin.so.6.6.4 /usr/lib64/libkwin.so.6.6.4.orig   # backup
sudo cp <path-from-find> /usr/lib64/libkwin.so.6.6.4
sudo ldconfig
```

## Result of the patch

`kwin_wayland --xwayland` and the full `dbus-run-session -- startplasma-wayland`
now get **past** the previous instant `exit(1)`. Confirmed via foreground
test:
```
No backend specified, automatically choosing Wayland because WAYLAND_DISPLAY is set
Accepting client connections on sockets: QList("wayland-0")
kwin_wayland_backend: wp_single_pixel_buffer_manager_v1 isn't supported by the host compositor
kwin_wayland_backend: xdg_toplevel_icon_manager_v1 isn't supported by the host compositor
kwin_wayland_backend: zwp_keyboard_shortcuts_inhibit_manager_v1 isn't supported by the host compositor
kwin_core: Configured compositor not supported by Platform. Falling back to defaults
kwin_screencast: Failed to connect PipeWire context
```
All three "isn't supported" lines are now non-fatal warnings (the other two —
`xdg_toplevel_icon_manager_v1` and `zwp_keyboard_shortcuts_inhibit_manager_v1`
— were already non-fatal upstream; only `wp_single_pixel_buffer_manager_v1`
needed the patch).

The full `startplasma-wayland` launch proceeds through the entire session
bootstrap (Xwayland, xdg-desktop-portal, kded6, ksmserver, plasma_session,
kdeconnect, bluez, activity manager, login chime plays) — a major step past
every previous attempt.

## Current blocker: black screen after login chime

Session boots but shows only a black screen. Repeated, spammy errors
throughout the log point at graphics/rendering rather than session bootstrap:

```
MESA: error: ZINK: failed to choose pdev
libEGL warning: egl: failed to create dri2 screen
libEGL warning: failed to get driver name for fd -1
libEGL warning: MESA-LOADER: failed to retrieve device information
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
```

**Working theory:** no `/dev/dri/renderD128`-style node exists (only
`/dev/dxg`), so nothing in the session can get a working GL/Vulkan context —
Mesa's D3D12/Dozen bridge from `/dev/dxg` to a normal DRI render node does
not appear to be wired up on this system. The visible "black screen" may
literally be the solid-black fallback buffer our own patch created, with
nothing successfully rendering Plasma's UI on top of it (plasmashell needs a
working GL context for its QtQuick-based interface).

### Next diagnostic steps (not yet run)

```bash
ps aux | grep -E "plasmashell|kwin_wayland"   # is plasmashell running / crash-looping?
ls -la /dev/dri 2>&1                          # confirm no render node exists
rpm -qa | grep -iE "mesa|d3d12"               # check installed Mesa/D3D12 packages
```

Quick test — force pure software rendering to isolate the GPU path as the
cause:
```bash
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
dbus-run-session -- startplasma-wayland
```
If a real (if slow) desktop renders under forced software mode, that
confirms the GPU/DRI bridge as the actual remaining blocker, separate from
everything fixed so far.

## Full working launch command (once GPU issue is resolved or worked around)

```bash
sudo mount -t tmpfs -o mode=1777 tmpfs /tmp/.X11-unix
mkdir -p /tmp/kde-runtime && chmod 0700 /tmp/kde-runtime
export XDG_RUNTIME_DIR=/tmp/kde-runtime
export WAYLAND_DISPLAY=/mnt/wslg/runtime-dir/wayland-0
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
dbus-run-session -- startplasma-wayland
```

## Loose ends / things worth doing regardless of outcome

- File an upstream KDE bug (bugs.kde.org, product `kwin`) about the missing
  `wl_shm` fallback for `wp_single_pixel_buffer_manager_v1` — this affects
  anyone nesting KWin under any older/Weston-derived host compositor, not
  just WSLg.
- The `org.freedesktop.systemd1` activation-failure spam throughout every
  log is believed cosmetic/benign (well-known stub-activation behavior) and
  was deprioritized during this investigation — worth a final sanity check
  (`systemctl --user status`, confirm `[boot] systemd=true` in
  `/etc/wsl.conf`) once the GPU issue is resolved, but has not been the
  actual blocker at any point so far.
- `RealtimeKit`/`rtkit` missing — harmless, audio thread priority only.
