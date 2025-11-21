#!/usr/bin/env bash
set -euo pipefail

VERSION_TYPE="${1:-patch}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_VERSION=$(sed -n 's/version: //p' "$SCRIPT_DIR/infra/galaxy.yml")
CURRENT_VERSION_PARTS=(${CURRENT_VERSION//./ })
CURRENT_VERSION_MAJOR=${CURRENT_VERSION_PARTS[0]}
CURRENT_VERSION_MINOR=${CURRENT_VERSION_PARTS[1]}
CURRENT_VERSION_PATCH=${CURRENT_VERSION_PARTS[2]}

NEW_VERSION_MAJOR=$CURRENT_VERSION_MAJOR
NEW_VERSION_MINOR=$CURRENT_VERSION_MINOR
NEW_VERSION_PATCH=$CURRENT_VERSION_PATCH

case $VERSION_TYPE in
  patch)
    NEW_VERSION_PATCH=$((CURRENT_VERSION_PATCH + 1))
    ;;
  minor)
    NEW_VERSION_MINOR=$((CURRENT_VERSION_MINOR + 1))
    NEW_VERSION_PATCH=0
    ;;
  major)
    NEW_VERSION_MAJOR=$((CURRENT_VERSION_MAJOR + 1))
    NEW_VERSION_MINOR=0
    NEW_VERSION_PATCH=0
    ;;
  *)
    echo "Invalid version type: $VERSION_TYPE"
    exit 1
  esac

NEW_VERSION="$NEW_VERSION_MAJOR.$NEW_VERSION_MINOR.$NEW_VERSION_PATCH"

set_version() {
    perl -i -pe"s/version: .*/version: $1/" "$SCRIPT_DIR/infra/galaxy.yml"
}

catch_error() {
    set_version $CURRENT_VERSION
    exit 1
}

trap 'catch_error' ERR

echo "[Publish] Updating version from $CURRENT_VERSION to $NEW_VERSION"
set_version $NEW_VERSION

echo "[Publish] Building collection..."
ansible-galaxy collection build "$SCRIPT_DIR/infra" --output-path "$SCRIPT_DIR/dist" --force

echo "[Publish] Publishing collection..."
ansible-galaxy collection publish "$SCRIPT_DIR/dist/papiro-infra-$NEW_VERSION.tar.gz" --api-key "$ANSIBLE_GALAXY_API_KEY"