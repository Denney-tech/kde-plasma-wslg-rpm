# kde-plasma-wslg-rpm — thin wrappers around scripts/. See MAINTAINING.md.
PKGS := kde-plasma-wslg-repo kde-plasma-wslg kwin

.PHONY: help patch check specs srpm rpms lint clean

help:
	@printf 'targets:\n'
	@printf '  make patch    regenerate packaging/kwin/wslg-kwin-rail.patch from src/\n'
	@printf '  make check     verify the patch is current + all specs parse\n'
	@printf '  make srpm      build all .src.rpm into build/\n'
	@printf '  make rpms      build all binary RPMs into build/ (needs dnf builddep / root)\n'
	@printf '  make lint      pre-commit run --all-files (incl. manual hooks)\n'
	@printf '  make clean     remove build/\n'

patch:
	scripts/gen-patch.sh

check:
	scripts/gen-patch.sh --check
	scripts/check-specs.sh

specs: check

srpm:
	@for p in $(PKGS); do scripts/build-srpm.sh $$p; done

rpms:
	@for p in $(PKGS); do scripts/build-rpms.sh $$p; done

lint:
	pre-commit run --all-files
	pre-commit run --all-files --hook-stage manual

clean:
	rm -rf build
