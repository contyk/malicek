OCI ?= podman

all:
	@echo Call start, stop, build or clean explicitly.

start:
	@$(OCI) run \
		--rm \
		--name malicek \
		--detach \
		--publish 3000 \
		--volume .:/malicek \
		malicek

debug:
	@$(OCI) run \
		--rm \
		-it \
		--name malicek \
		--publish 3000 \
		--volume .:/malicek \
		--entrypoint /bin/sh \
		malicek

build:
	@$(OCI) build \
		. \
		-t malicek

stop:
	@$(OCI) stop \
		--time 0 \
		malicek

clean:
	@$(OCI) rmi \
		malicek

.PHONY: start stop debug build clean
