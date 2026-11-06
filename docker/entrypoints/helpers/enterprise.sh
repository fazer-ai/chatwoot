#!/bin/sh

# Brings enterprise/ into the app at boot, from the official tag in VERSION_CW, when the
# edition asks for it. The image itself ships without the tree: /app/enterprise is a symlink
# into storage/.cw-enterprise/<version>-<hash>/enterprise, made at build time, and it dangles
# until this helper has put a verified tree there. A dangling link does not exist as far as
# Rails is concerned (ChatwootApp.enterprise? asks Pathname#exist?, which follows it), so an
# image without the tree boots as Community.
#
#   enterprise.sh ensure          run by every entrypoint before anything boots Rails
#   enterprise.sh lock <out_dir>  build time: download the official tree, write the lock
#   enterprise.sh tree-hash <dir> the hash both sides agree on, for one enterprise/ tree
#
# The hash covers the tree, not the tarball: one sha256 per regular file, in a stable
# order, hashed again. GitHub does not promise byte-stable archives, so hashing the
# download would break on a recompression that changed nothing that runs.
#
# `ensure` only ever writes under storage/.cw-enterprise, so /app itself can be read-only.
# It does nothing unless CW_EDITION=ee. With it, a missing lock, a lock for another version,
# a download that fails and a tree that does not match the lock all stop the boot with a
# message saying which. Booting without enterprise/ instead would quietly turn an Enterprise
# installation into a Community one: custom roles fall back to the plain agent role, SAML
# sign-in goes away, and nothing on screen says why. A container that refuses to start is
# the louder and safer failure. CW_EDITION=ce boots without it, on purpose.
#
# storage/ is the volume the stock composes already share between the web and worker
# containers, so a restart or a recreate on the same version needs no network, and the
# entry for one version never changes under a container running another one.
#
# Settings, both optional:
#   CW_ENTERPRISE_SOURCE_URL     a mirror of the official tarball for the tag. The tree is
#                                checked against the same pinned hash, wherever it came from.
#   CW_ENTERPRISE_FETCH_RETRIES  download attempts after the first one (default 3).

set -eu
# So a download cut halfway fails as a download, not as a tree that hashes wrong.
# shellcheck disable=SC3040 # busybox ash and bash have it; a shell without it skips it
(set -o pipefail) 2>/dev/null && set -o pipefail

APP_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
LOCK_FILE="$APP_ROOT/.enterprise_lock"
TARGET="$APP_ROOT/enterprise"
CACHE_ROOT="$APP_ROOT/storage/.cw-enterprise"

log() {
  echo "[enterprise] $*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d ' ' -f 1
  else
    shasum -a 256 | cut -d ' ' -f 1
  fi
}

sha256_line() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi
}

# Prints the tree hash of an enterprise/ directory. Paths are taken relative to its
# parent, so the same tree hashes the same wherever it was extracted.
tree_hash() {
  dir=$1
  [ -d "$dir" ] || return 1
  parent=$(dirname "$dir")
  name=$(basename "$dir")
  (
    cd "$parent"
    # Anything that is neither a directory nor a regular file (a symlink, above all) could
    # point outside the tree, and the hash would not cover what it points to.
    if [ -n "$(find "$name/" ! -type d ! -type f -print | head -n 1)" ]; then
      echo "unexpected non-regular file under $name" >&2
      exit 1
    fi
    find "$name/" -type f -print | sed 's|//*|/|g' | LC_ALL=C sort | while IFS= read -r file; do
      sha256_line "$file"
    done | sha256_of_stdin
  )
}

intact() {
  [ "$(tree_hash "$1" 2>/dev/null || true)" = "$PINNED" ]
}

# Reads the lock into VERSION and PINNED, and refuses one that does not belong to this image.
read_lock() {
  [ -f "$LOCK_FILE" ] || fail "this image has no $LOCK_FILE, so there is no hash to check enterprise/ against"
  VERSION=$(tr -d '[:space:]' < "$APP_ROOT/VERSION_CW")
  locked_version=$(sed -n 's/^version=//p' "$LOCK_FILE" | head -n 1)
  PINNED=$(sed -n 's/^sha256=//p' "$LOCK_FILE" | head -n 1)
  [ -n "$PINNED" ] || fail "$LOCK_FILE has no sha256"
  [ "$locked_version" = "$VERSION" ] || fail "$LOCK_FILE pins v$locked_version, but this image is v$VERSION"
  ENTRY="$CACHE_ROOT/$VERSION-$PINNED"
}

# Downloads the official tarball for a version and extracts only enterprise/ from it, into
# <dest>/enterprise. Streams straight into tar, so the rest of the repository never lands
# on disk.
download_tree() {
  version=$1
  dest=$2
  url=${CW_ENTERPRISE_SOURCE_URL:-https://codeload.github.com/chatwoot/chatwoot/tar.gz/refs/tags/v$version}
  retries=${CW_ENTERPRISE_FETCH_RETRIES:-3}
  top="chatwoot-$version"

  log "downloading enterprise/ for v$version from $url"
  mkdir -p "$dest/extract"
  if ! curl --fail --silent --show-error --location \
    --connect-timeout 15 --max-time 600 \
    --retry "$retries" --retry-delay 2 --retry-all-errors \
    "$url" | tar -xzf - -C "$dest/extract" "$top/enterprise"; then
    return 1
  fi
  [ -d "$dest/extract/$top/enterprise" ] || return 1
  mv "$dest/extract/$top/enterprise" "$dest/enterprise"
  rm -rf "$dest/extract"
}

cmd_tree_hash() {
  [ "$#" -eq 1 ] || fail "usage: enterprise.sh tree-hash <enterprise_dir>"
  tree_hash "$1" || fail "could not hash $1"
}

cmd_lock() {
  [ "$#" -eq 1 ] || fail "usage: enterprise.sh lock <out_dir>"
  out=$1
  version=$(tr -d '[:space:]' < "$APP_ROOT/VERSION_CW")
  [ -n "$version" ] || fail "VERSION_CW is empty"
  mkdir -p "$out"
  download_tree "$version" "$out" || fail "download of v$version failed"
  sha=$(tree_hash "$out/enterprise") || fail "could not hash the official tree"
  printf 'version=%s\nsha256=%s\n' "$version" "$sha" > "$out/enterprise_lock"
  log "pinned v$version at $sha"
}

# The tree has to be where the image's link points, verified, before Rails boots.
check_target() {
  intact "$TARGET" || fail "$TARGET does not lead to the verified tree in $ENTRY"
}

cmd_ensure() {
  edition=${CW_EDITION:-}
  if [ "$edition" != "ee" ]; then
    log "edition '${edition:-unset}': not fetching enterprise/"
    exit 0
  fi
  # ChatwootApp.enterprise? is false whenever DISABLE_ENTERPRISE is set, to any value.
  if [ -n "${DISABLE_ENTERPRISE+set}" ]; then
    log "DISABLE_ENTERPRISE is set: not fetching enterprise/"
    exit 0
  fi

  read_lock
  # Checking and filling the cache happen under one lock on it, which the web and worker
  # containers share: a second run waits, then finds the entry the first one made.
  mkdir -p "$CACHE_ROOT" || fail "cannot create $CACHE_ROOT"
  ruby -e 'File.open(ARGV.shift, File::RDWR | File::CREAT, 0o644) { |f| f.flock(File::LOCK_EX); exit(system(*ARGV) ? 0 : 1) }' \
    "$CACHE_ROOT/.lock" "$0" ensure-locked
}

cmd_ensure_locked() {
  read_lock
  if intact "$ENTRY/enterprise"; then
    check_target
    log "enterprise/ v$VERSION in place from $ENTRY"
    exit 0
  fi
  if [ -e "$ENTRY" ]; then
    log "cached enterprise/ in $ENTRY does not match the pinned hash; downloading it again"
    rm -rf "$ENTRY"
  fi

  work=$(mktemp -d "$CACHE_ROOT/.incoming.XXXXXX")
  if ! download_tree "$VERSION" "$work"; then
    rm -rf "$work"
    fail "could not download enterprise/ for v$VERSION (network, or a source without that tag). Not starting: set CW_EDITION=ce to run without Enterprise on purpose"
  fi
  actual=$(tree_hash "$work/enterprise" 2>/dev/null || true)
  if [ "$actual" != "$PINNED" ]; then
    rm -rf "$work"
    fail "downloaded enterprise/ for v$VERSION hashes to ${actual:-nothing}, the image pins $PINNED. Not starting"
  fi
  mv "$work" "$ENTRY"
  check_target
  log "enterprise/ v$VERSION downloaded, verified and installed"
}

command=${1:-}
[ "$#" -gt 0 ] && shift
case "$command" in
  ensure) cmd_ensure "$@" ;;
  ensure-locked) cmd_ensure_locked "$@" ;;
  lock) cmd_lock "$@" ;;
  tree-hash) cmd_tree_hash "$@" ;;
  *) fail "usage: enterprise.sh ensure | lock <out_dir> | tree-hash <enterprise_dir>" ;;
esac
