# Experimental: CAPD images for kubeadm fetch testing

**Experimental only.** This Dockerfile builds node images for testing (e.g. with CAPD). The image does **not**
bake in `fetch-kubeadm.sh`; instead, the CAPD quick-start `KubeadmConfigTemplate` injects
`/run/cluster-api/kubeadm-version/fetch-kubeadm.sh` via `files`, and runs setup via `preKubeadmCommands` before `kubeadm join`.

The image only ensures `curl` and `ca-certificates` are available. Base image is `kindest/node`; the version is
passed at build time.

## Build

From this directory, pass the Kubernetes version via `--build-arg` and tag as `localhost:5001/node:v<version>`:

```bash
# Example: build for 1.34 and push
docker build --build-arg KUBEADM_VERSION=1.34.0 -t localhost:5001/node:v1.34.0 .
docker push localhost:5001/node:v1.34.0

# Example: build for 1.35 and push
docker build --build-arg KUBEADM_VERSION=1.35.0 -t localhost:5001/node:v1.35.0 .
docker push localhost:5001/node:v1.35.0
```

## Verify

```bash
docker run --rm localhost:5001/node:v1.34.0 sh -c 'command -v curl && command -v kubeadm'
docker run --rm localhost:5001/node:v1.35.0 sh -c 'command -v curl && command -v kubeadm'
```
