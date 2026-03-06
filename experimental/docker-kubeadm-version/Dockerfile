# Experimental: kindest/node image with curl installed.
# For testing only. Not part of main CAPD/kind image flow.
# Build with: docker build --build-arg KUBEADM_VERSION=1.35.0 -t localhost:5001/node:v1.35.0 .
ARG KUBEADM_VERSION=1.35.0
FROM kindest/node:v${KUBEADM_VERSION}

# fetch-kubeadm.sh is injected via preKubeadmCommands at bootstrap time.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*
