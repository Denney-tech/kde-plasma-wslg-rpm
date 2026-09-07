# gpu/ — Mesa d3d12 + Dozen

## Result (2026-09-06): the driver works; the desktop can't use it

Built Mesa 25.2.7 with `-Dgallium-drivers=llvmpipe,d3d12` +
`-Dvulkan-drivers=swrast,microsoft-experimental` (Dozen). It **works** — GPU-accelerated
GL/Vulkan through `/dev/dxg` on this host's RTX 5070 Ti:

```
$ eglinfo -p surfaceless   (MESA_LOADER_DRIVER_OVERRIDE=d3d12)
OpenGL core profile renderer: D3D12 (NVIDIA GeForce RTX 5070 Ti)
OpenGL core profile version:  4.6 (Core Profile) Mesa 25.2.7
OpenGL ES profile version:    OpenGL ES 3.1
```
(full output: `d3d12-proof.txt`; Dozen loads too — dzn's "not a conformant Vulkan
implementation" banner appears, i.e. it initialised.)

**But the nested KDE Plasma desktop still falls back to `llvmpipe` / QPainter, and cannot
be made to use the GPU.** This is architectural, not a missing package:

- KWin's nested Wayland backend only has an **`EGL_PLATFORM_GBM`** code path
  (`src/backends/wayland/wayland_egl_backend.cpp:289`): it needs a **gbm device from a
  `/dev/dri` render node** *and* a **DRM device that it learns from the host's
  `zwp_linux_dmabuf` `main_device` event** (`wayland_backend.cpp:440`).
- WSLg has **neither**: `dxgkrnl` is not a DRM driver (`/dev/dri` does not exist, only
  `/dev/dxg`; `CONFIG_DRM_VIRTIO_GPU` is off), and WSLg's Weston 9 advertises **only
  `wl_shm`** — no `zwp_linux_dmabuf`, no `wl_drm`.
- So `m_backend->drmDevice()` is null → KWin's EGL backend can't initialise → QPainter.
- Even if it could: every buffer that crosses a process boundary here **must be `wl_shm`
  (CPU memory)** — client→KWin (KWin's QPainter backend only accepts shm clients) and
  KWin→Weston (the phase-1 patch hands Weston shm buffers because that's all it supports).
  GPU rendering would mean a GPU→CPU readback on every frame, which negates the win for a
  desktop workload.

Mesa's `d3d12` driver talks to `/dev/dxg` directly via `libdxcore.so`; it does **not**
create a `/dev/dri` node, so it can't paper over the gap.

**Conclusion:** GPU-accelerated *desktop compositing* is not possible under the current
WSLg. Phase 1's llvmpipe + QPainter + software-QtQuick setup is the ceiling for the desktop.

### Where the d3d12 build IS still worth having

Standalone GL/Vulkan/compute apps run *inside* the WSL distro (Blender, wine games, GL/Vulkan
dev, ML frameworks that want GL/Vulkan not just CUDA) get real GPU. WSL already gave CUDA +
NVENC; this adds OpenGL 4.6 + Vulkan (Dozen). Same build works on an Intel iGPU host — the
D3D12 layer abstracts the vendor. That's the case for still packaging it in `../rpm/`.

### What would unblock the desktop (not us)

- WSLg shipping a Weston with `zwp_linux_dmabuf` + a `/dev/dri` render node
  (`microsoft/wslg` — their Weston fork is effectively frozen), or
- a `dxgkrnl` DRM/virtio-gpu shim exposing `/dev/dri/renderD128` (kernel side), or
- a KWin patch adding a surfaceless/shm EGL path to the nested backend **and** a way to
  allocate GPU buffers without gbm — large, and still readback-bound.

## Build recipe (reproducible)

```bash
cd ~/projects/kde-plasma-wslg-gpu-rpm/gpu

# DirectX-Headers (not packaged for RHEL) — build to a local prefix
git clone --branch v1.615.0 --depth 1 https://github.com/microsoft/DirectX-Headers src/DirectX-Headers
cd src/DirectX-Headers
meson setup build --prefix="$PWD/../../prefix" -Dbuild-test=false -Dbuildtype=release
ninja -C build install
cd ../..

# Mesa (tarball from the SRPM: rpmbuild/SOURCES/mesa-25.2.7.tar.xz)
tar xf rpmbuild/SOURCES/mesa-25.2.7.tar.xz -C src
cd src/mesa-25.2.7
PKG_CONFIG_PATH=../../prefix/lib64/pkgconfig \
meson setup build-lean --prefix="$PWD/../../prefix" --libdir=lib64 -Dbuildtype=release \
  -Dplatforms=x11,wayland \
  -Dgallium-drivers=llvmpipe,d3d12 -Dvulkan-drivers=swrast,microsoft-experimental \
  -Degl=enabled -Dgbm=enabled -Dglx=dri -Dglvnd=enabled \
  -Dgles1=enabled -Dgles2=enabled -Dopengl=true -Dllvm=enabled -Dshared-llvm=enabled \
  -Dgallium-va=disabled -Dgallium-vdpau=disabled -Dgallium-d3d12-video=disabled \
  -Dvideo-codecs= -Dvalgrind=disabled -Dbuild-tests=false -Dmicrosoft-clc=disabled -Dintel-rt=disabled
ninja -C build-lean install     # -> ../../prefix/{lib64/dri/d3d12_dri.so, lib64/libvulkan_dzn.so, share/vulkan/icd.d/dzn_icd.x86_64.json}
```

Build deps installed this session: `meson ninja-build llvm-devel clang-devel spirv-tools-devel
spirv-headers-devel glslang python3-mako python3-pyyaml python3-pycparser libdrm-devel
wayland-devel wayland-protocols-devel libX11/xcb/Xext/Xfixes/Xdamage/Xrandr/Xxf86vm/xshmfence-devel
libxml2-devel expat-devel zlib-ng-devel libzstd-devel libselinux-devel elfutils-libelf-devel
libglvnd-devel vulkan-headers`. LTO is already disabled in the RHEL mesa spec, so no OOM risk.

Runtime env to select d3d12 (from `../prefix`):
```
LD_LIBRARY_PATH=…/prefix/lib64  LIBGL_DRIVERS_PATH=…/prefix/lib64/dri
__EGL_VENDOR_LIBRARY_FILENAMES=…/prefix/share/glvnd/egl_vendor.d/50_mesa.json
MESA_LOADER_DRIVER_OVERRIDE=d3d12  GALLIUM_DRIVER=d3d12
VK_ICD_FILENAMES=…/prefix/share/vulkan/icd.d/dzn_icd.x86_64.json
```
`/usr/lib/wsl/lib` (has `libdxcore.so`) is already on the loader path via
`/etc/ld.so.conf.d/ld.wsl.conf`.

For proper RPMs (`../rpm/`): rebuild the RHEL `mesa` SRPM (`rpmbuild/SPECS/mesa.spec`) —
the spec already fully supports d3d12/dzn, it's just gated `%if !0%{?rhel}`. Force
`%global with_d3d12 1` and add `BuildRequires: pkgconfig(DirectX-Headers)` (package
DirectX-Headers first, or `--force-fallback-for=DirectX-Headers`).
