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

build:
	@$(OCI) build \
		. \
		-t malicek

stop:
	@$(OCI) stop \
		malicek

clean:
	@$(OCI) rmi \
		malicek

.PHONY: start stop build clean
