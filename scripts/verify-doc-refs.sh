#!/usr/bin/env bash
# verify-doc-refs.sh — Check for stale documentation references
#
# Usage: ./scripts/verify-doc-refs.sh
# Returns: 0 if no stale refs found, 1 otherwise

set -euo pipefail

echo "=== Checking for stale documentation references ==="
echo ""

ERRORS=0

# Check for references to deleted/redirected docs (excluding PLAN.md which has historical context)
echo "Checking for active references to docs/NIX-PATTERNS.md (excluding PLAN.md and archive context)..."
STALE_NIX=$(grep -rn "docs/NIX-PATTERNS\.md" --include="*.md" --include="*.nix" . 2>/dev/null | grep -v "^Binary" | grep -v "PLAN.md" | grep -v "docs/patterns/index.md" | grep -v "docs/archive/" || true)
if [ -n "$STALE_NIX" ]; then
    echo "$STALE_NIX"
    echo "  ⚠ Found active references to docs/NIX-PATTERNS.md (should use docs/patterns/)"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✓ No stale references found"
fi

echo ""
echo "Checking for active references to docs/STAGES.md (excluding PLAN.md)..."
STALE_STAGES=$(grep -rn "docs/STAGES\.md" --include="*.md" --include="*.nix" . 2>/dev/null | grep -v "^Binary" | grep -v "PLAN.md" || true)
if [ -n "$STALE_STAGES" ]; then
    echo "$STALE_STAGES"
    echo "  ⚠ Found active references to docs/STAGES.md (should use docs/roadmap/)"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✓ No stale references found"
fi

echo ""
echo "=== Summary ==="
if [ $ERRORS -eq 0 ]; then
    echo "All checks passed ✓"
    exit 0
else
    echo "Found $ERRORS issue(s) — see above"
    exit 1
fi
