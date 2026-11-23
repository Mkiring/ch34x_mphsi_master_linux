#!/usr/bin/env bash
# Build a source-only DKMS package from an upstream source tree.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
package_root=$(cd -- "$script_dir/.." && pwd)
source_dir=$package_root
output_dir=$package_root/build

usage() {
    cat <<'EOF'
Usage: scripts/build-deb.sh [--source-dir DIR] [--output-dir DIR]

Build ch34x-mphsi-master-dkms. By default, use the repository as both the
packaging and driver source, and put build products in ./build.
EOF
}

while (($#)); do
    case "$1" in
        --source-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            source_dir=$2
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            output_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

source_dir=$(realpath -- "$source_dir")
output_dir=$(realpath -m -- "$output_dir")

[[ -f $source_dir/driver/Makefile ]] || {
    printf 'Driver source not found: %s/driver/Makefile\n' "$source_dir" >&2
    exit 1
}

upstream_version=$(sed -nE 's/^V([0-9]+([.][0-9]+)*) - .*/\1/p' \
    "$source_dir/driver/ch34x_mphsi_master_usb.c" | head -n 1)
: "${upstream_version:=1.7}"
if [[ ! $upstream_version =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    printf 'Invalid upstream version: %s\n' "$upstream_version" >&2
    exit 1
fi

if commit_date=$(git -C "$source_dir" log -1 --format=%cs 2>/dev/null); then
    upstream_commit=$(git -C "$source_dir" rev-parse HEAD)
else
    commit_date=$(date -u +%F)
    upstream_commit=unknown
fi

short_commit=${upstream_commit:0:12}
version="$upstream_version+git${commit_date//-/}.${short_commit}"
if ! dpkg --validate-version "$version" >/dev/null; then
    printf 'Invalid Debian version: %s\n' "$version" >&2
    exit 1
fi

staging_dir=$(mktemp -d "$output_dir.tmp.XXXXXX")
cleanup() {
    rm -rf -- "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$staging_dir/source/debian" "$output_dir"
cp -a "$package_root/debian/." "$staging_dir/source/debian/"
cp -a "$package_root/dkms.conf" "$staging_dir/source/"
cp -a "$source_dir/README.md" "$source_dir/README_EN.md" "$staging_dir/source/"
mkdir -p "$staging_dir/source/driver"
cp -a "$source_dir/driver/Makefile" "$staging_dir/source/driver/"
find "$source_dir/driver" -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' \) \
    -exec cp -a -t "$staging_dir/source/driver" -- {} +

# The upstream date and commit keep package versions ordered between syncs.
# A new version is required because DKMS does not replace an existing one.
maintainer=$(dpkg-parsechangelog -l"$staging_dir/source/debian/changelog" -SMaintainer)
timestamp=$(LC_ALL=C date -u --date="$commit_date" '+%a, %d %b %Y 00:00:00 +0000')
cat > "$staging_dir/source/debian/changelog" <<EOF
ch34x-mphsi-master-dkms ($version) stable; urgency=medium

  * Import upstream driver V$upstream_version at $upstream_commit.
  * Build and install the driver through DKMS.

 -- $maintainer  $timestamp
EOF

# dpkg-buildpackage writes metadata next to the source tree. Keep all outputs
# in build/ rather than the parent of the checkout.
(
    cd "$staging_dir/source"
    DEB_BUILD_OPTIONS=noautodbgsym dpkg-buildpackage -us -uc -b \
        --buildinfo-file="$staging_dir/package.buildinfo" \
        --changes-file="$staging_dir/package.changes"
)

deb=$(find "$staging_dir" -maxdepth 1 -type f -name '*_all.deb' -print -quit)
[[ -n $deb ]] || { printf 'The build did not produce a deb package.\n' >&2; exit 1; }
mv -- "$deb" "$output_dir/"
mv -- "$staging_dir/package.buildinfo" "$staging_dir/package.changes" "$output_dir/"

if [[ ${RUN_LINTIAN:-1} == 1 ]]; then
    lintian "$output_dir/$(basename -- "$deb")"
fi

printf '\nBuilt package: %s\n' "$output_dir/$(basename -- "$deb")"
printf 'PACKAGE_VERSION=%s\n' "$version"
printf 'UPSTREAM_COMMIT=%s\n' "$upstream_commit"
