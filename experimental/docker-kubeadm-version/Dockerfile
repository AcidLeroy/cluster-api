# Experimental: kindest/node with /tmp/kubeadm-version and fetch script.
# For testing only. Not part of main CAPD/kind image flow.
# Build with: docker build --build-arg KUBEADM_VERSION=1.35.0 -t localhost:5001/node:v1.35.0 .
ARG KUBEADM_VERSION=1.35.0
FROM kindest/node:v${KUBEADM_VERSION}

# Dependencies for fetch-kubeadm.sh (downloads kubeadm binary via curl)
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

COPY fetch-kubeadm.sh /tmp/fetch-kubeadm.sh
RUN chmod +x /tmp/fetch-kubeadm.sh
