#!/usr/bin/env bash
# Apply this repo's kernel patches (patches/*.patch, in order) to a Linux source tree.
#   ./apply-patches.sh <kernel-tree>             apply; a patch already in the tree is skipped
#   ./apply-patches.sh --check <kernel-tree>     say what would happen, change nothing
#   ./apply-patches.sh --reverse <kernel-tree>   take the patches out again, newest first
# The patches are against Linux 6.18 (sound/hda/codecs/cirrus/cs420x.c) and build on each other, so the whole
# series is first tried on a copy of the files it touches: either all of it goes in, or the tree stays as it was.
# After applying, build and install the kernel your usual way; see README.md for the module options.
set -euo pipefail

mode=apply
case ${1:-} in
  --check) mode=check; shift ;;
  --reverse) mode=reverse; shift ;;
  -h | --help) sed -n '2,8p' "$0"; exit 0 ;;
esac
tree=${1:-}
[[ -n $tree && $# -eq 1 ]] || { sed -n '2,8p' "$0" >&2; exit 2; }
[[ -f $tree/Makefile && -d $tree/sound ]] || { echo "ERROR: $tree is not a kernel source tree" >&2; exit 1; }
tree=$(realpath "$tree")
here=$(dirname "$(realpath "$0")")
mapfile -t patches < <(printf '%s\n' "$here"/patches/*.patch | sort)
[[ -f ${patches[0]} ]] || { echo "ERROR: no patches in $here/patches" >&2; exit 1; }
command -v patch >/dev/null || { echo "ERROR: the 'patch' program is not installed" >&2; exit 1; }

version=$(sed -n 's/^VERSION = //p;s/^PATCHLEVEL = //p;s/^SUBLEVEL = //p' "$tree/Makefile" | paste -sd.)
echo "kernel tree: $tree (Linux $version)"

# Files the series touches, from the "+++ b/<path>" lines.
mapfile -t files < <(sed -n 's|^+++ b/\([^[:space:]]*\).*|\1|p' "${patches[@]}" | sort -u)
for f in "${files[@]}"; do
  [[ -f $tree/$f ]] && continue
  echo "ERROR: $f is missing in this tree: the patches are against Linux 6.18," >&2
  echo "       older kernels keep this driver in sound/pci/hda/patch_cirrus.c" >&2
  exit 1
done

applies() { patch -d "$1" -p1 --dry-run -s -f "${@:3}" <"$2" >/dev/null 2>&1; }
do_patch() { patch -d "$1" -p1 -s -f "${@:3}" <"$2"; }
copy_files() {   # copy_files <destination>: the touched files, with their paths
  local f
  for f in "${files[@]}"; do mkdir -p "$1/${f%/*}"; cp "$tree/$f" "$1/$f"; done
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=${#patches[@]}

# How many patches of the series are in the tree? A later patch rewrites lines of an earlier one, so a single
# patch cannot be tested on its own: find the largest k for which patches k..1 come out cleanly, one after
# the other, on a copy.
applied=0
for ((k = n; k > 0; k--)); do
  rm -rf "$tmp/probe"; copy_files "$tmp/probe"
  ok=1
  for ((i = k - 1; i >= 0; i--)); do
    if applies "$tmp/probe" "${patches[i]}" -R; then do_patch "$tmp/probe" "${patches[i]}" -R; else ok=0; break; fi
  done
  if (( ok )); then applied=$k; break; fi
done

if [[ $mode == reverse ]]; then
  for ((i = n - 1; i >= applied; i--)); do echo "absent   ${patches[i]##*/} (not in the tree, skipped)"; done
  for ((i = applied - 1; i >= 0; i--)); do
    do_patch "$tree" "${patches[i]}" -R
    echo "removed  ${patches[i]##*/}"
  done
  echo "done: ${files[*]}"
  exit 0
fi

# Rehearsal on a copy: nothing in the tree changes unless the rest of the series goes in.
copy_files "$tmp/try"
for ((i = applied; i < n; i++)); do
  if ! applies "$tmp/try" "${patches[i]}"; then
    echo "ERROR: ${patches[i]##*/} does not apply to Linux $version" >&2
    patch -d "$tmp/try" -p1 --dry-run -f <"${patches[i]}" 2>&1 | sed 's/^/       /' | head -12 >&2
    echo "nothing was changed in $tree" >&2
    exit 1
  fi
  do_patch "$tmp/try" "${patches[i]}"
done

for ((i = 0; i < applied; i++)); do echo "present      ${patches[i]##*/} (already applied, skipped)"; done
for ((i = applied; i < n; i++)); do
  if [[ $mode == check ]]; then
    echo "would apply  ${patches[i]##*/}"
  else
    do_patch "$tree" "${patches[i]}"
    echo "applied      ${patches[i]##*/}"
  fi
done
if [[ $mode == check ]]; then
  echo "check only: the tree was not changed"
else
  echo "done: ${files[*]}"
fi
