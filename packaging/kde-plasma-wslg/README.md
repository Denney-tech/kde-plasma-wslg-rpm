# kde-plasma-wslg

A full KDE Plasma 6 Wayland desktop, full-screen in a WSLg window, on a RHEL 10 WSL distro.
CPU rendering (llvmpipe) — GPU compositing is not possible under WSLg (Weston 9 has no
dmabuf, no `/dev/dri`).

## Requires the patched `kwin`

This package depends on `kwin-wslg-patch` — EPEL's `kwin` rebuilt with the WSLg
nested-Wayland RAIL fixes and the `kwin_wayland_wrapper` sizing shim. Stock `kwin` gives a
black window under WSLg. Install the `kde-plasma-wslg-repo` package first: its dnf repo has
`priority=1`, so the patched `kwin` always wins over a stock update and is never silently
reverted (no `versionlock` needed).

## Use

```bash
plasma-wslg start        # or: systemctl --user start plasma-wslg
plasma-wslg stop
plasma-wslg status
journalctl --user -u plasma-wslg -f
```

- Comes up full-screen over the whole Windows display. **Alt+Tab** (Windows) switches away;
  **right Ctrl** releases the mouse-pointer grab.
- Normal window instead of full-screen: add `Environment=KWIN_WSLG_NO_FULLSCREEN=1`
  in a `systemctl --user edit plasma-wslg` drop-in.
- The unit is `static` — it won't auto-start and can't be `enable`d. To auto-start it, add
  an `[Install]` / `WantedBy=default.target` drop-in and `enable`.

## What it installs

| path | |
|---|---|
| `/usr/bin/plasma-wslg` | start/stop/status wrapper |
| `/usr/libexec/kde-plasma-wslg/plasma-wslg-launch` | the session launcher (llvmpipe + QPainter + software QtQuick env) |
| `/usr/lib/systemd/user/plasma-wslg.service` | the user unit |
| `/usr/lib/tmpfiles.d/kde-plasma-wslg.conf` | makes `/tmp/.X11-unix` writable+sticky for Xwayland |
| `/etc/xdg/kscreenlockerrc` | disables the screen locker system-wide (the WSLg session has no real greeter) |

## Migrating from a hand-installed setup

If you followed the pre-package instructions, remove the local copies so the packaged ones
take effect:

```bash
systemctl --user stop plasma-wslg
rm -f ~/.local/bin/plasma-wslg.sh ~/.local/bin/desktop.sh ~/.config/systemd/user/plasma-wslg.service
rm -f ~/.config/kscreenlockerrc         # now provided system-wide
systemctl --user daemon-reload
sudo dnf versionlock delete kwin kwin-libs kwin-common   # if you had set one
```
