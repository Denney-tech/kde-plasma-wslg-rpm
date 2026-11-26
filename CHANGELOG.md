# Changelog

## [1.1.1](https://github.com/Denney-tech/kde-plasma-wslg-rpm/compare/v1.1.0...v1.1.1) (2026-11-26)


### Bug Fixes

* **ci:** 3-way merge kwin overlay sources on rebase ([#8](https://github.com/Denney-tech/kde-plasma-wslg-rpm/issues/8)) ([9cde01c](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/9cde01c69031010afb9c5ac0f2c5ec145a4a94ed))
* **ci:** don't hard-code the kwin version in the libkwin strings check ([4a81ab7](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/4a81ab7aebc7ed61d691ce264d6f9290f086eeba))
* **kwin:** rebase WSLg overlay onto kwin 6.7.5 ([d51e7a1](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/d51e7a1cbb1638ad7f7d286d664551a9f118f074))
* restore kwin dist-git pin to epel10.3 (01bd7b8) ([1d824a2](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/1d824a2fddc378f7b32ac7071922483615e952f2))
* track epel10.3 (RHEL 10.3) ([47b2715](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/47b2715228ed275e18330f671151802aba6fadd1))

## [1.1.0](https://github.com/Denney-tech/kde-plasma-wslg-rpm/compare/v1.0.0...v1.1.0) (2026-09-15)


### Features

* automate kwin dist-git tracking and a RHEL 10 minor-version watch ([7351b59](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/7351b592f097aebefb1e51db0f042b811fa88b1e))


### Bug Fixes

* make the kwin spec overlay immune to routine EPEL churn ([9902418](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/9902418113557a7f7d780a998c1c197bddb5b8e7))

## 1.0.0 (2026-09-07)


### Features

* build and release scripts ([1ad602c](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/1ad602c5a349f48d87347ecb3b70a23f146f4f0c))
* kde-plasma-wslg desktop package ([234518d](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/234518dd82360a7521a4bce6656ed89cf81d3d00))
* kde-plasma-wslg-repo package ([2016fbd](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/2016fbdaec35418abe3fcd6fe55f86d431952020))
* kwin WSLg RAIL patch and EPEL dist-git spec overlay ([3de4010](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/3de4010d42421465b0678fd29e6d486d4ee85b86))


### Bug Fixes

* CI install-test globbing, rpmlint filters, and spec description width ([e65ddea](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/e65ddea08895a188e799baaac27a036bd83374d9))
* cut the release build from release-please, not an `on: release` handler ([5fd0e5e](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/5fd0e5e0a952e45fd0a8f81fa9784171f70cd5fa))
* shellcheck findings in gen-patch.sh and the release workflow ([865b320](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/865b3205adedd3dd5903cc783941c62ac8f01bc0))
* verify the systemd unit after install, not standalone ([8a518f1](https://github.com/Denney-tech/kde-plasma-wslg-rpm/commit/8a518f1e3c118a18407047087566cb06f525e74b))

## Changelog

All notable changes to this project are documented here. This file is maintained by
[release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/) — do not edit it by hand.
