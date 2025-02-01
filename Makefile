# Init initializes the repo for development.
init:
	git submodule update --init --recursive
.PHONY: init

# Slightly cursed way that we setup a dev version of this locally on NixOS.
dev/install:
	zig build -Dcpu=baseline -Doptimize=ReleaseFast
	if [ -f "/etc/NIXOS" ]; then patchelf --set-rpath "${LD_LIBRARY_PATH}" zig-out/bin/ghostty; fi
	mkdir -p ${HOME}/bin
	cp zig-out/bin/ghostty ${HOME}/bin/devtty
.PHONY: dev/install

# glad updates the GLAD loader. To use this, place the generated glad.zip
# in this directory next to the Makefile, remove vendor/glad and run this target.
#
# Generator: https://gen.glad.sh/
glad: vendor/glad
.PHONY: glad

vendor/glad: vendor/glad/include/glad/gl.h vendor/glad/include/glad/glad.h

vendor/glad/include/glad/gl.h: glad.zip
	rm -rf vendor/glad
	mkdir -p vendor/glad
	unzip glad.zip -dvendor/glad
	find vendor/glad -type f -exec touch '{}' +

vendor/glad/include/glad/glad.h: vendor/glad/include/glad/gl.h
	@echo "#include <glad/gl.h>" > $@
