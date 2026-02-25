# Experimental: Docker images with kubeadm version files

**Experimental only.** These Dockerfiles build node images for testing (e.g. with CAPD) that include:

- `/tmp/kubeadm-version` – file containing the kubeadm version (e.g. `1.34.0` or `1.35.0`)
- `/tmp/fetch-kubeadm.sh` – script that reads that file and prints: `fetching kubeadm version: <version>`

Base images: `kindest/node:v1.34.0` and `kindest/node:v1.35.0`.

## Build

From this directory:

```bash
# Build and tag as 1.34-kubeadm-version
docker build -f Dockerfile.1.34 -t 1.34-kubeadm-version .

# Build and tag as 1.35-kubeadm-version
docker build -f Dockerfile.1.35 -t 1.35-kubeadm-version .
```

## Verify

```bash
docker run --rm 1.34-kubeadm-version cat /tmp/kubeadm-version
# 1.34.0

docker run --rm 1.34-kubeadm-version /tmp/fetch-kubeadm.sh
# fetching kubeadm version: 1.34.0

docker run --rm 1.35-kubeadm-version /tmp/fetch-kubeadm.sh
# fetching kubeadm version: 1.35.0
```
