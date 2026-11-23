#!/usr/bin/env bash
# Install a local deb, migrating an older manually-added DKMS source first.
set -euo pipefail

package=ch34x-mphsi-master-dkms
module=ch34x_mphsi_master

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    sudo=()
elif command -v sudo >/dev/null 2>&1; then
    sudo=(sudo)
else
    printf 'Run this script as root, or install sudo.\n' >&2
    exit 1
fi

if [[ $# -ne 1 ]]; then
    printf 'Usage: scripts/install-deb.sh PATH_TO_DEB\n' >&2
    exit 2
fi

deb=$(realpath -- "$1")
[[ -f $deb ]] || { printf 'No such package: %s\n' "$deb" >&2; exit 1; }
[[ $(dpkg-deb -f "$deb" Package) == "$package" ]] || {
    printf 'Unexpected package in %s\n' "$deb" >&2
    exit 1
}
version=$(dpkg-deb -f "$deb" Version)

# A previously hand-added V1.7 entry cannot be managed by the new deb's
# maintainer scripts. Remove only that DKMS registration, not the loaded module.
if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' &&
    dkms status -m "$module" -v V1.7 2>/dev/null | grep -q .; then
    printf 'Migrating the manually-added DKMS source %s/V1.7...\n' "$module"
    "${sudo[@]}" dkms remove -m "$module" -v V1.7 --all
fi

# apt resolves dependencies. A failed install must abort this script.
"${sudo[@]}" apt-get update
"${sudo[@]}" apt-get install --yes "$deb"

# DKMS installs a module for the running kernel but does not necessarily load
# it immediately. Load only after the package installation has succeeded.
if [[ -d /lib/modules/$(uname -r) ]]; then
    "${sudo[@]}" modprobe "$module" || true
fi

printf '\nInstalled %s %s\n' "$package" "$version"
dkms status -m "$module" -v "$version" || true
