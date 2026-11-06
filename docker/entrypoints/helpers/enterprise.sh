#!/bin/sh

# Brings enterprise/ into the app at boot, from the official tag in VERSION_CW, when the
# edition asks for it. The image itself ships without enterprise/: it is fetched, checked
# against the hash pinned when the image was built, and only then put where Rails looks.
#
#   enterprise.sh ensure          run by every entrypoint before anything boots Rails
#   enterprise.sh lock <out_dir>  build time: download the official tree, write the lock
#   enterprise.sh tree-hash <dir> the hash both sides agree on, for one enterprise/ tree
#
# The hash covers the tree, not the tarball: one sha256 per regular file, in a stable
# order, hashed again. GitHub does not promise byte-stable archives, so hashing the
# download would break on a recompression that changed nothing that runs.
#
# `ensure` does nothing unless CW_EDITION=ee. With it, a missing lock, a lock for another
# version, a download that fails and a tree that does not match the lock all stop the boot
# with a message saying which. Booting without enterprise/ instead would quietly turn an
# Enterprise installation into a Community one: custom roles fall back to the plain agent
# role, SAML sign-in goes away, and nothing on screen says why. A container that refuses to
# start is the louder and safer failure. CW_EDITION=ce boots without it, on purpose.
#
# Settings, all optional:
#   CW_ENTERPRISE_CACHE_DIR      where verified trees are kept, one directory per version
#                                and hash. Defaults to storage/.cw-enterprise, which the
#                                stock composes already mount as a volume shared by the
#                                web and worker containers, so a restart or a recreate on
#                                the same version needs no network.
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
    if [ -n "$(find "$name" ! -type d ! -type f -print | head -n 1)" ]; then
      echo "unexpected non-regular file under $name" >&2
      exit 1
    fi
    find "$name" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      sha256_line "$file"
    done | sha256_of_stdin
  )
}

lock_value() {
  sed -n "s/^$1=//p" "$LOCK_FILE" | head -n 1
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

# Puts a verified tree in place of $TARGET. Copied rather than linked, so Rails, Zeitwerk
# and bootsnap see plain files under the app root, exactly as in a checkout. The bootsnap
# cache goes with it: it was built, if at all, for a tree that is no longer there.
install_tree() {
  src=$1
  rm -rf "$TARGET.incoming"
  cp -R "$src" "$TARGET.incoming"
  rm -rf "$TARGET"
  mv "$TARGET.incoming" "$TARGET"
  rm -rf "$APP_ROOT/tmp/cache/bootsnap"
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

  [ -f "$LOCK_FILE" ] || fail "this image has no $LOCK_FILE, so there is no hash to check enterprise/ against"
  version=$(tr -d '[:space:]' < "$APP_ROOT/VERSION_CW")
  locked_version=$(lock_value version)
  pinned=$(lock_value sha256)
  [ -n "$pinned" ] || fail "$LOCK_FILE has no sha256"
  [ "$locked_version" = "$version" ] || fail "$LOCK_FILE pins v$locked_version, but this image is v$version"

  if [ -d "$TARGET" ] && [ "$(tree_hash "$TARGET" 2>/dev/null || true)" = "$pinned" ]; then
    log "enterprise/ v$version already in place"
    exit 0
  fi

  cache_root=${CW_ENTERPRISE_CACHE_DIR:-$APP_ROOT/storage/.cw-enterprise}
  mkdir -p "$cache_root" || fail "cannot create the cache directory $cache_root"
  entry="$cache_root/$version-$pinned"

  if [ -d "$entry/enterprise" ]; then
    if [ "$(tree_hash "$entry/enterprise" 2>/dev/null || true)" = "$pinned" ]; then
      log "using cached enterprise/ v$version from $entry"
      install_tree "$entry/enterprise"
      log "enterprise/ v$version installed"
      exit 0
    fi
    log "cached enterprise/ in $entry does not match the pinned hash; downloading it again"
    rm -rf "$entry"
  fi

  work=$(mktemp -d "$cache_root/.incoming.XXXXXX")
  if ! download_tree "$version" "$work"; then
    rm -rf "$work"
    fail "could not download enterprise/ for v$version (network, or a source without that tag). Not starting: set CW_EDITION=ce to run without Enterprise on purpose"
  fi
  actual=$(tree_hash "$work/enterprise" 2>/dev/null || true)
  if [ "$actual" != "$pinned" ]; then
    rm -rf "$work"
    fail "downloaded enterprise/ for v$version hashes to ${actual:-nothing}, the image pins $pinned. Not starting"
  fi

  # A rename is atomic, and refuses an existing non-empty target: when the web and worker
  # containers race on a shared cache, one entry wins and the other run is discarded.
  if ! ruby -e 'File.rename(ARGV[0], ARGV[1])' "$work" "$entry" 2>/dev/null; then
    rm -rf "$work"
  fi
  [ "$(tree_hash "$entry/enterprise" 2>/dev/null || true)" = "$pinned" ] || fail "cache entry $entry is not usable"

  install_tree "$entry/enterprise"
  log "enterprise/ v$version downloaded, verified and installed"
}

command=${1:-}
[ "$#" -gt 0 ] && shift
case "$command" in
  ensure) cmd_ensure "$@" ;;
  lock) cmd_lock "$@" ;;
  tree-hash) cmd_tree_hash "$@" ;;
  *) fail "usage: enterprise.sh ensure | lock <out_dir> | tree-hash <enterprise_dir>" ;;
esac
