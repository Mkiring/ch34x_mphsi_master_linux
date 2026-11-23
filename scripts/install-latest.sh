#!/usr/bin/env bash
# Install the latest upstream-synced deb on Ubuntu/Debian.
set -euo pipefail

repository=${CH34X_REPOSITORY:-Mkiring/ch34x_mphsi_master_linux}
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    sudo=()
elif command -v sudo >/dev/null 2>&1; then
    sudo=(sudo)
else
    printf 'Run this script as root, or install sudo.\n' >&2
    exit 1
fi

work_dir=$(mktemp -d)
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

release_url="https://github.com/$repository/releases/latest"
download_url=$(curl --fail --location --silent --show-error --max-time 60 \
    --output /dev/null --write-out '%{url_effective}' "$release_url")
tag=${download_url##*/}
if [[ ! $tag =~ ^dkms-[0-9A-Za-z.+~:-]+$ ]]; then
    printf 'No DKMS release found at %s\n' "$release_url" >&2
    exit 1
fi

asset_base="https://github.com/$repository/releases/download/$tag"
package="ch34x-mphsi-master-dkms_${tag#dkms-}_all.deb"

# A hand-added V1.7 registration predates this package and must be removed
# before the package manager can own that DKMS source.
if ! dpkg-query -W -f='${Status}' ch34x-mphsi-master-dkms 2>/dev/null |
    grep -qx 'install ok installed' &&
    dkms status -m ch34x_mphsi_master -v V1.7 2>/dev/null | grep -q .; then
    printf 'Migrating the manually-added DKMS source ch34x_mphsi_master/V1.7...\n'
    "${sudo[@]}" dkms remove -m ch34x_mphsi_master -v V1.7 --all
fi

curl --fail --location --silent --show-error --max-time 120 \
    --remote-name --output-dir "$work_dir" "$asset_base/$package"
curl --fail --location --silent --show-error --max-time 60 \
    --remote-name --output-dir "$work_dir" "$asset_base/SHA256SUMS"
(cd "$work_dir" && sha256sum -c --ignore-missing SHA256SUMS)

"${sudo[@]}" apt-get update
"${sudo[@]}" apt-get install --yes "$work_dir/$package"
"${sudo[@]}" modprobe ch34x_mphsi_master || true
