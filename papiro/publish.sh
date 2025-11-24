#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  echo "Usage: $0 [-t <version_type>] [-f]"
  echo "  -t: Version type (patch, minor, major)"
  echo "  -f: Publish to Ansible Galaxy (default: false)"
  exit 1
}

VERSION_TYPE="alpha"
PUBLISH="false"

while getopts "t:f" opt; do
  case $opt in
    t)
      VERSION_TYPE="${OPTARG}"
      ;;
    f)
      PUBLISH="true"
      ;;
    *)
      print_usage
      exit 1
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_VERSION=$(sed -n 's/version: //p' "$SCRIPT_DIR/infra/galaxy.yml")
CURRENT_VERSION_PARTS=(${CURRENT_VERSION//./ })
CURRENT_VERSION_MAJOR=${CURRENT_VERSION_PARTS[0]}
CURRENT_VERSION_MINOR=${CURRENT_VERSION_PARTS[1]}
CURRENT_VERSION_PATCH_PARTS=(${CURRENT_VERSION_PARTS[2]//-/ })
CURRENT_VERSION_PATCH=${CURRENT_VERSION_PATCH_PARTS[0]}
CURRENT_VERSION_ALPHA=${CURRENT_VERSION_PARTS[3]:-0}

NEW_VERSION_MAJOR=$CURRENT_VERSION_MAJOR
NEW_VERSION_MINOR=$CURRENT_VERSION_MINOR
NEW_VERSION_PATCH=$CURRENT_VERSION_PATCH
NEW_VERSION_ALPHA=$CURRENT_VERSION_ALPHA

case $VERSION_TYPE in
  alpha)
    NEW_VERSION_ALPHA=$((CURRENT_VERSION_ALPHA + 1))
    ;;
  patch)
    NEW_VERSION_PATCH=$((CURRENT_VERSION_PATCH + 1))
    NEW_VERSION_ALPHA=0
    ;;
  minor)
    NEW_VERSION_MINOR=$((CURRENT_VERSION_MINOR + 1))
    NEW_VERSION_PATCH=0
    NEW_VERSION_ALPHA=0
    ;;
  major)
    NEW_VERSION_MAJOR=$((CURRENT_VERSION_MAJOR + 1))
    NEW_VERSION_MINOR=0
    NEW_VERSION_PATCH=0
    NEW_VERSION_ALPHA=0
    ;;
  *)
    echo "Invalid version type: $VERSION_TYPE"
    exit 1
  esac

NEW_VERSION="$NEW_VERSION_MAJOR.$NEW_VERSION_MINOR.$NEW_VERSION_PATCH"

if [ $NEW_VERSION_ALPHA -gt 0 ]; then
  NEW_VERSION="$NEW_VERSION-alpha.$NEW_VERSION_ALPHA"
fi

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

if [ $PUBLISH == "false" ]; then
  echo "[Publish] Skipping publishing collection..."
  exit 0
fi

echo "[Publish] Publishing collection..."
ansible-galaxy collection publish "$SCRIPT_DIR/dist/papiro-infra-$NEW_VERSION.tar.gz" --api-key "$ANSIBLE_GALAXY_API_KEY"