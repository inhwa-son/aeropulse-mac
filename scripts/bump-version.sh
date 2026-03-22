#!/usr/bin/env bash
set -euo pipefail

# AeroPulse Version Bumper
# Usage: ./scripts/bump-version.sh [major|minor|patch]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Project.swift"
BUMP_TYPE="${1:-patch}"

CURRENT_VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_FILE" | sed 's/.*"\([0-9.]*\)".*/\1/')
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION' "$PROJECT_FILE" | sed 's/.*"\([0-9]*\)".*/\1/')

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Usage: $0 [major|minor|patch]" >&2
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "==> Bumping version: $CURRENT_VERSION (build $CURRENT_BUILD) → $NEW_VERSION (build $NEW_BUILD)"

# Update Project.swift
sed -i '' "s/\"MARKETING_VERSION\": \"$CURRENT_VERSION\"/\"MARKETING_VERSION\": \"$NEW_VERSION\"/" "$PROJECT_FILE"
sed -i '' "s/\"CURRENT_PROJECT_VERSION\": \"$CURRENT_BUILD\"/\"CURRENT_PROJECT_VERSION\": \"$NEW_BUILD\"/" "$PROJECT_FILE"

# Also update the Info.plist entries in Project.swift
sed -i '' "s/\"CFBundleShortVersionString\": \"$CURRENT_VERSION\"/\"CFBundleShortVersionString\": \"$NEW_VERSION\"/" "$PROJECT_FILE"
sed -i '' "s/\"CFBundleVersion\": \"$CURRENT_BUILD\"/\"CFBundleVersion\": \"$NEW_BUILD\"/" "$PROJECT_FILE"

echo "==> Updated Project.swift"
echo "    MARKETING_VERSION: $NEW_VERSION"
echo "    CURRENT_PROJECT_VERSION: $NEW_BUILD"
echo ""
echo "Next steps:"
echo "  git add Project.swift"
echo "  git commit -m \"Bump version to $NEW_VERSION (build $NEW_BUILD)\""
echo "  git tag v$NEW_VERSION"
echo "  git push && git push --tags"
