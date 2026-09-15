# x-release-please-start-version
%global baseversion 1.1.0
# x-release-please-end-version

Name:           kde-plasma-wslg-repo
Version:        %{baseversion}
Release:        1%{?dist}
Summary:        kde-plasma-wslg-rpm dnf repository configuration and GPG key

License:        GPL-2.0-or-later
URL:            https://github.com/Denney-tech/kde-plasma-wslg-rpm
BuildArch:      noarch

Source0:        kde-plasma-wslg-rpm.repo
Source1:        RPM-GPG-KEY-kde-plasma-wslg
Source2:        LICENSE

# priority= handling in the .repo file
Requires:       dnf-plugins-core

%description
Drops the kde-plasma-wslg-rpm dnf repository definition (hosted on
GitHub Pages) and its signing key. The repository has priority=1 so
dnf serves its patched kwin regardless of a newer stock version,
which makes 'dnf upgrade' the entire update path for the WSLg desktop.

Install this first, then 'dnf install kde-plasma-wslg'.

%prep
%autosetup -c -T
cp -p %{SOURCE2} .

%build
# nothing to build

%install
install -Dm0644 %{SOURCE0} %{buildroot}%{_sysconfdir}/yum.repos.d/kde-plasma-wslg-rpm.repo
install -Dm0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-kde-plasma-wslg

%files
%license LICENSE
%config(noreplace) %{_sysconfdir}/yum.repos.d/kde-plasma-wslg-rpm.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-kde-plasma-wslg

%changelog
* Sun Sep 06 2026 kde-plasma-wslg-rpm <kde-plasma-wslg-rpm@users.noreply.github.com> - 0.0.0-1
- See https://github.com/Denney-tech/kde-plasma-wslg-rpm/releases
