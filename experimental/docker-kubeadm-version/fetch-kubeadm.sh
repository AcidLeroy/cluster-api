#!/bin/sh
# Reads kubeadm version from /var/lib/kubeadm-version/version, downloads that kubeadm binary from
# dl.k8s.io, and installs it to /usr/bin/kubeadm. Used for experimental testing with
# custom node images (e.g. workers joining with a different kubeadm version).
set -e

VERSION_FILE="/var/lib/kubeadm-version/version"
KUBEADM_INSTALL="/usr/bin/kubeadm"
BASE_URL="https://dl.k8s.io/release"

if [ ! -f "$VERSION_FILE" ]; then
	echo "No $VERSION_FILE, skipping kubeadm fetch"
	exit 0
fi

version=$(cat "$VERSION_FILE")
version=$(echo "$version" | tr -d '\n\r')
if [ -z "$version" ]; then
	echo "Empty version in $VERSION_FILE, skipping"
	exit 0
fi

# Ensure version has v prefix for URL
case "$version" in
	v*) ;;
	*) version="v$version";;
esac

arch=$(uname -m)
case "$arch" in
	x86_64) arch="amd64";;
	aarch64|arm64) arch="arm64";;
	*) echo "Unsupported arch: $arch"; exit 1;;
esac

url="${BASE_URL}/${version}/bin/linux/${arch}/kubeadm"
echo "Fetching kubeadm ${version} (${arch}) from ${url}"
tmp=$(mktemp -p /tmp kubeadm.XXXXXX)
curl -fLsS -o "$tmp" "$url" || { echo "Download failed"; rm -f "$tmp"; exit 1; }
chmod 755 "$tmp"
# Overwrite existing kubeadm (e.g. from kindest/node)
mv -f "$tmp" "$KUBEADM_INSTALL"
echo "Installed kubeadm to ${KUBEADM_INSTALL}"
/usr/bin/kubeadm version -o short 2>/dev/null || true
