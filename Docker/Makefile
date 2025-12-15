# Makefile for building and running the gem5 dev container

# Image configuration
IMAGE_NAME ?= nugget-ae
IMAGE_TAG  ?= latest
IMAGE      := $(IMAGE_NAME):$(IMAGE_TAG)
DOCKERFILE ?= Dockerfile

# Host user info (used to match UID/GID inside container)
UID := $(shell id -u)
GID := $(shell id -g)

# Directory on host to mount as /workdir inside the container
# Default: current directory
WORKDIR ?= $(PWD)

# Default number of cores to use inside container
NUM_CORES_TO_USE ?= 1

.PHONY: image
image:
	@echo "Checking if Docker image $(IMAGE) exists..."
	@if ! docker image inspect $(IMAGE) >/dev/null 2>&1; then \
		echo "Image $(IMAGE) not found. Building..."; \
		docker build \
		  --build-arg UID=$(UID) \
		  --build-arg GID=$(GID) \
		  -t $(IMAGE) \
		  -f $(DOCKERFILE) . ; \
	else \
		echo "Image $(IMAGE) already exists. Skipping build."; \
	fi

.PHONY: run
run: image
	@echo "Starting container from $(IMAGE) with $(WORKDIR) mounted to /workdir..."
	@echo "NUM_CORES_TO_USE=$(NUM_CORES_TO_USE)"
	docker run --rm -it \
		--cap-add=PERFMON --cap-add=SYS_ADMIN --cap-add=SYS_PTRACE \
		--security-opt seccomp=unconfined \
		-e NUM_CORES_TO_USE=$(NUM_CORES_TO_USE) \
		-v $(WORKDIR):/workdir \
		$(IMAGE)

.PHONY: clean-image
clean-image:
	@echo "Removing image $(IMAGE) if it exists..."
	@docker image rm $(IMAGE) 2>/dev/null || echo "Image $(IMAGE) not present."
