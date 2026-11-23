#!/usr/bin/env bash
# Compile the sources from a built deb without installing or loading a module.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Usage: scripts/verify-deb.sh PATH_TO_DEB\n' >&2
    exit 2
fi

deb=$(realpath -- "$1")
work_dir=$(mktemp -d)
cleanup() {
    local status=$?
    if ((status != 0)); then
        find "$work_dir" -name make.log -type f -exec sh -c \
            'for log; do printf "\n%s:\n" "$log"; cat "$log"; done' sh {} +
    fi
    rm -rf -- "$work_dir"
    return "$status"
}
trap cleanup EXIT

package=$(dpkg-deb -f "$deb" Package)
version=$(dpkg-deb -f "$deb" Version)
source_name=ch34x_mphsi_master
source_dir=$work_dir/usr/src/$source_name-$version

dpkg-deb -x "$deb" "$work_dir"
mkdir -p "$work_dir/dkms"
[[ -f $source_dir/dkms.conf ]] || {
    printf 'Missing DKMS configuration in %s\n' "$deb" >&2
    exit 1
}
[[ $(find "$source_dir" -type f | wc -l) -ge 7 ]] || {
    printf 'The package does not contain the expected driver sources.\n' >&2
    exit 1
}
if find "$source_dir/driver" -type f \
    ! -name '*.c' ! -name '*.h' ! -name Makefile | grep -q .; then
    printf 'Unexpected build products in the packaged driver sources.\n' >&2
    exit 1
fi

kernel_version=${KERNEL_VERSION:-$(uname -r)}
dkms add --sourcetree "$work_dir/usr/src" \
    --dkmstree "$work_dir/dkms" -m "$source_name" -v "$version"
dkms build --dkmstree "$work_dir/dkms" -m "$source_name" -v "$version" \
    -k "$kernel_version"

printf 'Verified source compilation for kernel %s: %s %s\n' \
    "$kernel_version" "$package" "$version"
