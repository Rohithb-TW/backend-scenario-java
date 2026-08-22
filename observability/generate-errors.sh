#!/bin/bash
# =============================================================
# Petclinic — Error Traffic Generator
# Generates a mix of 404s and 400s alongside normal 200 traffic
# so the Grafana Error Rate panel shows non-zero values.
#
# Usage:
#   bash observability/generate-errors.sh          # run once (burst)
#   bash observability/generate-errors.sh loop     # run continuously
# =============================================================

BASE="http://localhost:9966/petclinic"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
sent() { echo -e "${CYAN}[SENT]${NC}  $*"; }

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║       Petclinic — Error Traffic Generator             ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

fire_errors() {
  # ── 404s — request owners/vets/pets that don't exist ────────
  sent "404 → GET /api/owners/99999"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/owners/99999"

  sent "404 → GET /api/vets/99999"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/vets/99999"

  sent "404 → GET /api/pets/99999"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/pets/99999"

  sent "404 → GET /api/specialties/99999"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/specialties/99999"

  # ── 400s — malformed POST bodies ────────────────────────────
  sent "400 → POST /api/owners (empty body)"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" \
    -X POST "$BASE/api/owners" \
    -H "Content-Type: application/json" \
    -d '{}'

  sent "400 → POST /api/vets (missing required fields)"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" \
    -X POST "$BASE/api/vets" \
    -H "Content-Type: application/json" \
    -d '{"invalid":"data"}'

  sent "400 → POST /api/pettypes (empty name)"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" \
    -X POST "$BASE/api/pettypes" \
    -H "Content-Type: application/json" \
    -d '{"name":""}'

  # ── Mix in normal 200s so error rate shows as a ratio ───────
  sent "200 → GET /api/owners"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/owners"

  sent "200 → GET /api/vets"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/vets"

  sent "200 → GET /api/pettypes"
  curl -s -o /dev/null -w "  → HTTP %{http_code}\n" "$BASE/api/pettypes"
}

if [ "${1:-}" = "loop" ]; then
  info "Running continuously (Ctrl+C to stop)..."
  info "Error rate will show ~40-50% in Grafana"
  echo ""
  while true; do
    fire_errors
    echo ""
    sleep 3
  done
else
  info "Running one burst of errors..."
  info "Refresh Grafana in ~15s to see the spike"
  echo ""
  # Fire 5 bursts for a visible spike
  for i in $(seq 1 5); do
    info "Burst $i/5"
    fire_errors
    sleep 1
  done
  echo ""
  info "Done! Check the Error Rate panel in Grafana ✅"
  info "Dashboard: http://localhost:3000/d/petclinic-obs-v1"
fi
