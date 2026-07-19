#!/usr/bin/env bash
# ============================================================================
# FlowBook Release Script
# Usage: ./scripts/release.sh [major|minor|patch]
#   - patch (default): 1.2.2 → 1.2.3
#   - minor:           1.2.2 → 1.3.0
#   - major:           1.2.2 → 2.0.0
#
# Does:
#   1. Bumps version in pubspec.yaml + assets/version.json
#   2. Builds release APK (all ABIs)
#   3. Commits & pushes to git
#   4. Creates a GitHub release with the APK attached
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ─── Parse version bump type ────────────────────────────────────────────────
BUMP="${1:-patch}"

# ─── Get current version ────────────────────────────────────────────────────
CURRENT_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
CURRENT_SEMVER="${CURRENT_VERSION%%+*}"
CURRENT_BUILD="${CURRENT_VERSION##*+}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_SEMVER"

case "$BUMP" in
  major)
    MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1)); PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Unknown bump type: $BUMP. Use major|minor|patch"
    exit 1
    ;;
esac

NEW_SEMVER="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_VERSION="${NEW_SEMVER}+${NEW_BUILD}"

echo "📦 Bumping version: $CURRENT_VERSION → $NEW_VERSION"

# ─── Update version files ───────────────────────────────────────────────────
sed -i '' "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
echo "$NEW_SEMVER" > assets/version.json
echo "   ✅ pubspec.yaml + assets/version.json"

# ─── Build release APK ──────────────────────────────────────────────────────
echo ""
echo "🔨 Building release APK..."
flutter build apk --release
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
echo "   ✅ APK built: $APK_PATH ($(du -sh "$APK_PATH" | cut -f1))"

# ─── Git commit & push ──────────────────────────────────────────────────────
echo ""
echo "📤 Committing & pushing..."
git add pubspec.yaml assets/version.json build/app/outputs/flutter-apk/app-release.apk
git commit -m "v${NEW_SEMVER}: release build"
git push origin main
echo "   ✅ Pushed to origin/main"

# ─── GitHub release ─────────────────────────────────────────────────────────
echo ""
echo "🚀 Creating GitHub release..."
gh release create "v${NEW_SEMVER}" \
  --title "v${NEW_SEMVER}" \
  --notes "Release v${NEW_SEMVER} (build ${NEW_BUILD})" \
  "$APK_PATH#FlowBook-v${NEW_SEMVER}.apk"
echo "   ✅ Release created: https://github.com/everancii/Flow-Book/releases/tag/v${NEW_SEMVER}"

echo ""
echo "🎉 Done! v${NEW_SEMVER} released."
