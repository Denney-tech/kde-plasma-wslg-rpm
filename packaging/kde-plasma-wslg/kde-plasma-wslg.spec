# Version is bumped by release-please (generic updater, see release-please-config.json).
# x-release-please-start-version
%global baseversion 1.0.0
# x-release-please-end-version

Name:           kde-plasma-wslg
Version:        %{baseversion}
Release:        1%{?dist}
Summary:        Nested KDE Plasma (Wayland) desktop, full-screen under WSLg, for RHEL 10 WSL

# The kwin patch this depends on derives from GPL-2.0-or-later KWin source; this glue is
# released under the same terms.
License:        GPL-2.0-or-later
URL:            https://github.com/Denney-tech/kde-plasma-wslg-rpm
BuildArch:      noarch

Source0:        plasma-wslg
Source1:        plasma-wslg-launch
Source2:        plasma-wslg.service
Source3:        kde-plasma-wslg.tmpfiles.conf
Source4:        kscreenlockerrc
Source5:        README.md
Source6:        LICENSE

# %%_userunitdir, %%_tmpfilesdir, %%tmpfiles_create, %%systemd_requires
BuildRequires:  systemd-rpm-macros

# The WSLg-patched compositor (kwin-*.wslgN carries Provides: kwin-wslg-patch).
Requires:       kwin-wslg-patch
Requires:       plasma-workspace
Requires:       plasma-desktop
Requires:       kscreenlocker
Requires:       wayland-utils
Requires:       dbus-daemon
Requires:       mesa-dri-drivers
%{?systemd_requires}

%description
Scripts, a systemd user service and system config to run a nested
KDE Plasma 6 Wayland session inside a WSLg window on a RHEL 10 WSL
distro. Rendering is CPU-only (llvmpipe); GPU compositing is not
possible under WSLg's Weston.

Start it with 'plasma-wslg start' (or 'systemctl --user start plasma-wslg').

Install kde-plasma-wslg-repo first so dnf pulls the patched kwin build this needs.

%prep
%autosetup -c -T
cp -p %{SOURCE5} %{SOURCE6} .

%build
# nothing to build

%install
install -Dm0755 %{SOURCE0} %{buildroot}%{_bindir}/plasma-wslg
install -Dm0755 %{SOURCE1} %{buildroot}%{_libexecdir}/%{name}/plasma-wslg-launch
install -Dm0644 %{SOURCE2} %{buildroot}%{_userunitdir}/plasma-wslg.service
install -Dm0644 %{SOURCE3} %{buildroot}%{_tmpfilesdir}/%{name}.conf
install -Dm0644 %{SOURCE4} %{buildroot}%{_sysconfdir}/xdg/kscreenlockerrc

%post
%tmpfiles_create %{_tmpfilesdir}/%{name}.conf
if [ "$1" -eq 1 ]; then
  echo "kde-plasma-wslg: run 'plasma-wslg start' to launch the desktop." >&2
fi

%files
%license LICENSE
%doc README.md
%{_bindir}/plasma-wslg
%dir %{_libexecdir}/%{name}
%{_libexecdir}/%{name}/plasma-wslg-launch
%{_userunitdir}/plasma-wslg.service
%{_tmpfilesdir}/%{name}.conf
%config(noreplace) %{_sysconfdir}/xdg/kscreenlockerrc

%changelog
* Sun Sep 06 2026 kde-plasma-wslg-rpm <kde-plasma-wslg-rpm@users.noreply.github.com> - 0.0.0-1
- See https://github.com/Denney-tech/kde-plasma-wslg-rpm/releases
