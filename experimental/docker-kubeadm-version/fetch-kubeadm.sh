#!/bin/sh
# Reads kubeadm version from /tmp/kubeadm-version and prints it.
# Used for experimental testing with custom node images.
version=$(cat /tmp/kubeadm-version)
echo "fetching kubeadm version: $version"
