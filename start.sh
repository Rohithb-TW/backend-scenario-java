#!/bin/bash
# =============================================================
# Petclinic — One-command startup
#
# Usage:
#   bash start.sh              → start everything
#   bash start.sh stop         → stop everything cleanly
#   bash start.sh status       → show what's running
#   bash start.sh errors       → generate 4xx/5xx traffic spike
#   bash start.sh load         → run pool-exhaustion load test
#   bash start.sh demo         → full scenario: healthy → break → fix → verify
# =============================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBS_DIR="$PROJECT_DIR/observability"
APP_LOG="$PROJECT_DIR/app.log"
APP_PID="$PROJECT_DIR/app.pid"
PROM_PID="$OBS_DIR/prometheus.pid"
PROM_LOG="$OBS_DIR/prometheus.log"
TRAFFIC_PID="$OBS_DIR/traffic.pid"
GRAFANA_URL="http://localhost:3000"
PROMETHEUS_URL="http://localhost:9090"
APP_BASE="http://localhost:9966/petclinic"
APP_METRICS="$APP_BASE/actuator/prometheus"
DASH_UID="petclinic-obs-v1"

# ── Colours ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${NC}"; }
sent()  { echo -e "${CYAN}[SENT]${NC}  $*"; }

wait_for() {
  local url=$1 label=$2 max=${3:-60} tries=0
  info "Waiting for $label..."
  until curl -sf "$url" >/dev/null 2>&1; do
    tries=$((tries+1))
    [ $tries -gt $max ] && error "$label did not start after ${max}s. Check logs."
    [ $((tries % 15)) -eq 0 ] && info "  Still waiting... (${tries}s)"
    printf '.'; sleep 1
  done
  echo; info "$label ready ✅"
}

# ── Import / refresh dashboard helper ─────────────────────────
import_dashboard() {
  DS_UID=$(curl -sf "$GRAFANA_URL/api/datasources/name/Prometheus" \
    -u admin:admin \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || true)
  [ -z "$DS_UID" ] && { warn "Cannot get datasource UID — skipping dashboard import"; return; }

  PATCHED=$(python3 - <<PYEOF
import json
with open('$OBS_DIR/grafana-dashboard.json') as f:
    dash = json.load(f)
for panel in dash.get('panels', []):
    ds = panel.get('datasource')
    if isinstance(ds, dict): ds['uid'] = '$DS_UID'
    for t in panel.get('targets', []):
        tds = t.get('datasource')
        if isinstance(tds, dict): tds['uid'] = '$DS_UID'
dash.pop('__inputs', None)
dash.pop('__requires', None)
dash['id'] = None
print(json.dumps({"dashboard": dash, "overwrite": True, "folderId": 0}))
PYEOF
)
  RESP=$(curl -sf -X POST "$GRAFANA_URL/api/dashboards/import" \
    -H "Content-Type: application/json" \
    -u admin:admin \
    -d "$PATCHED" 2>&1 || true)

  DASH_URL=$(echo "$RESP" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('importedUrl') or '/d/$DASH_UID')" \
    2>/dev/null || echo "/d/$DASH_UID")
  info "Dashboard imported ✅ → $GRAFANA_URL$DASH_URL"
  echo "$GRAFANA_URL$DASH_URL" > "$OBS_DIR/dashboard.url"
}

# ─────────────────────────────────────────────────────────────
# MODE: stop
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "stop" ]; then
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║          Petclinic — Stopping All Services            ║"
  echo "╚═══════════════════════════════════════════════════════╝"

  [ -f "$TRAFFIC_PID" ] && {
    kill "$(cat "$TRAFFIC_PID")" 2>/dev/null && info "Traffic generator stopped" || warn "Already stopped"
    rm -f "$TRAFFIC_PID"
  }
  [ -f "$APP_PID" ] && {
    kill "$(cat "$APP_PID")" 2>/dev/null && info "App stopped" || warn "Already stopped"
    rm -f "$APP_PID"
  }
  [ -f "$PROM_PID" ] && {
    kill "$(cat "$PROM_PID")" 2>/dev/null && info "Prometheus stopped" || warn "Already stopped"
    rm -f "$PROM_PID"
  }
  brew services stop grafana 2>/dev/null && info "Grafana stopped" || true
  info "All services stopped ✅"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# MODE: status
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "status" ]; then
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║              Petclinic — Service Status               ║"
  echo "╠═══════════════════════════════════════════════════════╣"
  curl -sf "$APP_METRICS" >/dev/null 2>&1 \
    && printf "║  %-52s ║\n" "App          : ✅ running → $APP_BASE" \
    || printf "║  %-52s ║\n" "App          : ❌ not running"
  curl -sf "$PROMETHEUS_URL/-/ready" >/dev/null 2>&1 \
    && printf "║  %-52s ║\n" "Prometheus   : ✅ running → $PROMETHEUS_URL" \
    || printf "║  %-52s ║\n" "Prometheus   : ❌ not running"
  curl -sf "$GRAFANA_URL/api/health" >/dev/null 2>&1 \
    && printf "║  %-52s ║\n" "Grafana      : ✅ running → $GRAFANA_URL" \
    || printf "║  %-52s ║\n" "Grafana      : ❌ not running"
  [ -f "$TRAFFIC_PID" ] && kill -0 "$(cat "$TRAFFIC_PID")" 2>/dev/null \
    && printf "║  %-52s ║\n" "Traffic gen  : ✅ running (PID $(cat "$TRAFFIC_PID"))" \
    || printf "║  %-52s ║\n" "Traffic gen  : ❌ not running"

  # Pool metrics snapshot
  if curl -sf "$APP_METRICS" >/dev/null 2>&1; then
    PMAX=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_max" | awk '{print $2}')
    PIDLE=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_idle" | awk '{print $2}')
    PACTIVE=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_active" | awk '{print $2}')
    PPEND=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_pending" | awk '{print $2}')
    echo "╠═══════════════════════════════════════════════════════╣"
    printf "║  %-52s ║\n" "Pool max     : $PMAX"
    printf "║  %-52s ║\n" "Pool idle    : $PIDLE"
    printf "║  %-52s ║\n" "Pool active  : $PACTIVE"
    printf "║  %-52s ║\n" "Pool pending : $PPEND"
  fi
  echo "╚═══════════════════════════════════════════════════════╝"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# MODE: errors  — generate realistic 4xx error traffic
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "errors" ]; then
  curl -sf "$APP_METRICS" >/dev/null 2>&1 || error "App not running. Run: bash start.sh"
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║        Petclinic — Error Traffic Generator            ║"
  echo "╚═══════════════════════════════════════════════════════╝"
  info "Firing 5 bursts of 4xx errors (400 + 404)..."
  info "Watch the Error Rate panel in Grafana in ~15s"
  for i in $(seq 1 5); do
    info "Burst $i/5"
    # 404s — non-existent resources
    for id in 99991 99992 99993 99994; do
      sent "404 → GET /api/owners/$id"
      curl -sf -o /dev/null -w "       HTTP %{http_code}\n" "$APP_BASE/api/owners/$id" || true
    done
    # 400s — invalid POST bodies
    sent "400 → POST /api/owners (empty body)"
    curl -sf -o /dev/null -w "       HTTP %{http_code}\n" \
      -X POST "$APP_BASE/api/owners" -H "Content-Type: application/json" -d '{}' || true
    sent "400 → POST /api/vets (invalid body)"
    curl -sf -o /dev/null -w "       HTTP %{http_code}\n" \
      -X POST "$APP_BASE/api/vets" -H "Content-Type: application/json" -d '{"bad":"data"}' || true
    sent "400 → POST /api/pettypes (empty name)"
    curl -sf -o /dev/null -w "       HTTP %{http_code}\n" \
      -X POST "$APP_BASE/api/pettypes" -H "Content-Type: application/json" -d '{"name":""}' || true
    # Mix in 200s so error rate shows as ratio
    for ep in owners vets pettypes; do
      curl -sf -o /dev/null "$APP_BASE/api/$ep" &
    done
    wait; sleep 1
  done
  DASH_URL=$(cat "$OBS_DIR/dashboard.url" 2>/dev/null || echo "$GRAFANA_URL/d/$DASH_UID")
  info "Done ✅ — check Error Rate panel: $DASH_URL"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# MODE: load  — pool exhaustion load test (RCA scenario)
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "load" ]; then
  curl -sf "$APP_METRICS" >/dev/null 2>&1 || error "App not running. Run: bash start.sh"
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║        Petclinic — Pool Exhaustion Load Test          ║"
  echo "╚═══════════════════════════════════════════════════════╝"

  # Capture before metrics
  info "Capturing pre-load pool state..."
  BEFORE_MAX=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_max" | awk '{print $2}')
  BEFORE_ACQ=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_acquire_seconds_max" | awk '{print $2}')
  info "Pool max        : $BEFORE_MAX"
  info "Acquire max (s) : $BEFORE_ACQ"

  info "Running: 20 threads × 50 requests = 1000 concurrent hits..."
  START_TIME=$(date +%s)
  for i in {1..20}; do
    (
      for j in {1..50}; do
        curl -s -o /dev/null "$APP_BASE/api/owners"
      done
    ) &
  done
  wait
  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))

  info "Load test complete in ${ELAPSED}s"
  info "Capturing post-load pool state..."
  AFTER_ACQ=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_acquire_seconds_max" | awk '{print $2}')
  AFTER_TIMEOUT=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_timeout_total" | awk '{print $2}')
  AFTER_PENDING=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_pending" | awk '{print $2}')
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║              Load Test Results                        ║"
  echo "╠═══════════════════════════════════════════════════════╣"
  printf "║  %-52s ║\n" "Duration             : ${ELAPSED}s"
  printf "║  %-52s ║\n" "Pool size (max)      : $BEFORE_MAX connections"
  printf "║  %-52s ║\n" "Acquire time before  : ${BEFORE_ACQ}s"
  printf "║  %-52s ║\n" "Acquire time after   : ${AFTER_ACQ}s"
  printf "║  %-52s ║\n" "Timeouts             : $AFTER_TIMEOUT"
  printf "║  %-52s ║\n" "Pending (now)        : $AFTER_PENDING"
  echo "╚═══════════════════════════════════════════════════════╝"
  DASH_URL=$(cat "$OBS_DIR/dashboard.url" 2>/dev/null || echo "$GRAFANA_URL/d/$DASH_UID")
  info "Check P95 Latency panel: $DASH_URL"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# MODE: demo  — full scenario: healthy → break → fix → verify
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "demo" ]; then
  curl -sf "$APP_METRICS" >/dev/null 2>&1 \
    || error "App not running. Run 'bash start.sh' first."
  curl -sf "$GRAFANA_URL/api/health" >/dev/null 2>&1 \
    || error "Grafana not running. Run 'bash start.sh' first."

  PROPS="$PROJECT_DIR/src/main/resources/application.properties"
  DASH_URL=$(cat "$OBS_DIR/dashboard.url" 2>/dev/null || echo "$GRAFANA_URL/d/$DASH_UID")

  pause() {
    local secs=$1 msg=$2
    echo ""
    warn "⏳ $msg — waiting ${secs}s for dashboard to update..."
    for i in $(seq "$secs" -1 1); do
      printf "\r   ${YELLOW}%2ds remaining...${NC}" "$i"; sleep 1
    done
    echo ""
  }

  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║       Petclinic — Full Observability Demo             ║"
  echo "║   Phase 1: Healthy  →  Phase 2: Break  →  Phase 3: Fix║"
  echo "╠═══════════════════════════════════════════════════════╣"
  printf "║  %-52s ║\n" "Dashboard: $DASH_URL"
  echo "╚═══════════════════════════════════════════════════════╝"
  info "Open the dashboard now → $DASH_URL"
  pause 10 "Phase 1 starting — system is healthy"

  # ── PHASE 1: Healthy baseline ────────────────────────────────
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║  🟢  PHASE 1 — Healthy System                         ║"
  echo "╚═══════════════════════════════════════════════════════╝"
  info "Pool config: max=20, min-idle=10"
  info "Generating normal traffic for 30s..."

  # Traffic loop for 30s
  END=$(($(date +%s) + 30))
  while [ "$(date +%s)" -lt "$END" ]; do
    for ep in owners vets pettypes specialties; do
      curl -sf -o /dev/null "$APP_BASE/api/$ep" &
    done
    sleep 1
  done
  wait

  # Capture healthy metrics
  H_MAX=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_max" | awk '{print $2}')
  H_ACQ=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_acquire_seconds_max" | awk '{print $2}')
  H_COUNT=$(curl -s "$APP_METRICS" | grep "^http_server_requests_seconds_count.*owners" | grep -v bucket | awk '{print $2}' | head -1)
  info "✅ Healthy — pool.max=$H_MAX  acquire.max=${H_ACQ}s  requests=$H_COUNT"
  pause 20 "Phase 1 complete — observe the Request Rate and P95 Latency panels"

  # ── PHASE 2: Inject fault ────────────────────────────────────
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║  🔴  PHASE 2 — Injecting Fault (pool-size → 1)        ║"
  echo "╚═══════════════════════════════════════════════════════╝"
  warn "Reducing HikariCP pool to maximum-pool-size=1..."

  # Write faulty config
  python3 - <<PYEOF
import re
with open('$PROPS') as f:
    content = f.read()
# Remove existing hikari pool size lines if present
content = re.sub(r'spring\.datasource\.hikari\.maximum-pool-size=\d+\n', '', content)
content = re.sub(r'spring\.datasource\.hikari\.minimum-idle=\d+\n', '', content)
content = re.sub(r'spring\.datasource\.hikari\.connection-timeout=\d+\n', '', content)
# Append fault config
content += '\n# DEMO FAULT — pool reduced to 1\n'
content += 'spring.datasource.hikari.maximum-pool-size=1\n'
content += 'spring.datasource.hikari.minimum-idle=1\n'
content += 'spring.datasource.hikari.connection-timeout=1000\n'
with open('$PROPS', 'w') as f:
    f.write(content)
print('Fault config written')
PYEOF

  # Restart app with faulty config
  info "Restarting app with faulty pool config..."
  [ -f "$TRAFFIC_PID" ] && kill "$(cat "$TRAFFIC_PID")" 2>/dev/null || true
  lsof -ti:9966 | xargs kill -9 2>/dev/null || true; sleep 2
  cd "$PROJECT_DIR"
  nohup ./mvnw spring-boot:run > "$APP_LOG" 2>&1 &
  echo $! > "$APP_PID"
  wait_for "$APP_METRICS" "App (faulty config)" 120
  FAULT_MAX=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_max" | awk '{print $2}')
  warn "Pool confirmed at max=$FAULT_MAX ← FAULT ACTIVE"

  # Run load test against faulty app
  info "Running load test: 20 threads × 50 requests..."
  FAULT_START=$(date +%s)
  for i in {1..20}; do
    ( for j in {1..50}; do curl -s -o /dev/null "$APP_BASE/api/owners"; done ) &
  done
  wait
  FAULT_END=$(date +%s)
  FAULT_ELAPSED=$((FAULT_END - FAULT_START))

  FAULT_ACQ=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_acquire_seconds_max" | awk '{print $2}')
  FAULT_SUM=$(curl -s "$APP_METRICS" | grep "^http_server_requests_seconds_sum.*owners" | grep -v bucket | awk '{print $2}' | head -1)
  FAULT_CNT=$(curl -s "$APP_METRICS" | grep "^http_server_requests_seconds_count.*owners" | grep -v bucket | awk '{print $2}' | head -1)

  warn "🔴 FAULTY — pool.max=$FAULT_MAX  acquire.max=${FAULT_ACQ}s  load_test=${FAULT_ELAPSED}s"
  pause 25 "Phase 2 complete — observe the P95 Latency spike in the dashboard"

  # ── PHASE 3: Fix ─────────────────────────────────────────────
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║  🟢  PHASE 3 — Remediating (pool-size → 20)           ║"
  echo "╚═══════════════════════════════════════════════════════╝"
  info "Restoring HikariCP pool to maximum-pool-size=20..."

  # Write fixed config
  python3 - <<PYEOF
import re
with open('$PROPS') as f:
    content = f.read()
# Remove fault lines
content = re.sub(r'# DEMO FAULT.*\n', '', content)
content = re.sub(r'spring\.datasource\.hikari\.maximum-pool-size=\d+\n', '', content)
content = re.sub(r'spring\.datasource\.hikari\.minimum-idle=\d+\n', '', content)
content = re.sub(r'spring\.datasource\.hikari\.connection-timeout=\d+\n', '', content)
# Append correct config
content += '\n# HikariCP pool — remediated\n'
content += 'spring.datasource.hikari.maximum-pool-size=20\n'
content += 'spring.datasource.hikari.minimum-idle=10\n'
content += 'spring.datasource.hikari.connection-timeout=30000\n'
with open('$PROPS', 'w') as f:
    f.write(content)
print('Fixed config written')
PYEOF

  # Restart with fixed config
  info "Restarting app with fixed pool config..."
  lsof -ti:9966 | xargs kill -9 2>/dev/null || true; sleep 2
  nohup ./mvnw spring-boot:run > "$APP_LOG" 2>&1 &
  echo $! > "$APP_PID"
  wait_for "$APP_METRICS" "App (fixed config)" 120
  FIX_MAX=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_max" | awk '{print $2}')
  info "Pool confirmed at max=$FIX_MAX ✅"

  # Re-run identical load test
  info "Re-running identical load test: 20 threads × 50 requests..."
  FIX_START=$(date +%s)
  for i in {1..20}; do
    ( for j in {1..50}; do curl -s -o /dev/null "$APP_BASE/api/owners"; done ) &
  done
  wait
  FIX_END=$(date +%s)
  FIX_ELAPSED=$((FIX_END - FIX_START))
  FIX_ACQ=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_acquire_seconds_max" | awk '{print $2}')

  # Restart traffic generator
  (
    while true; do
      for ep in "$APP_BASE/api/owners" "$APP_BASE/api/vets" "$APP_BASE/api/pettypes" "$APP_BASE/api/specialties"; do
        curl -sf -o /dev/null "$ep" &
      done
      sleep 2
    done
  ) &
  echo $! > "$TRAFFIC_PID"
  info "Traffic generator restarted ✅"

  # Re-import dashboard with fresh datasource UID
  import_dashboard

  pause 20 "Phase 3 complete — observe recovery in the dashboard"

  # ── Final comparison report ──────────────────────────────────
  echo ""
  echo "╔═══════════════════════════════════════════════════════╗"
  echo "║              📊  Demo Complete — Before vs After       ║"
  echo "╠═══════════════════════════════════════════════════╤═══╣"
  printf "║  %-38s │ %-10s │ %-10s ║\n" "Metric" "FAULTY" "FIXED"
  echo "╠═══════════════════════════════════════════════════╪═══╣"
  printf "║  %-38s │ %-10s │ %-10s ║\n" "Pool max connections"       "$FAULT_MAX"         "$FIX_MAX"
  printf "║  %-38s │ %-10s │ %-10s ║\n" "Max connection acquire time" "${FAULT_ACQ}s"      "${FIX_ACQ}s"
  printf "║  %-38s │ %-10s │ %-10s ║\n" "Load test duration (1000 req)" "${FAULT_ELAPSED}s" "${FIX_ELAPSED}s"
  echo "╠═══════════════════════════════════════════════════╧═══╣"
  printf "║  %-52s ║\n" "Dashboard: $DASH_URL"
  echo "╚═══════════════════════════════════════════════════════╝"
  open "$DASH_URL" 2>/dev/null || true
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# MODE: start (default)
# ─────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║         Petclinic — One-Command Startup               ║"
echo "║  App · Prometheus · Grafana · Traffic · Dashboard     ║"
echo "╚═══════════════════════════════════════════════════════╝"

# ── Prerequisites ─────────────────────────────────────────────
step "Checking Prerequisites"
command -v java       >/dev/null 2>&1 || error "Java not found.      Fix: brew install --cask temurin@21"
command -v prometheus >/dev/null 2>&1 || error "Prometheus not found. Fix: brew install prometheus"
command -v brew       >/dev/null 2>&1 || error "Homebrew not found.  See: https://brew.sh"
brew list grafana     >/dev/null 2>&1 || error "Grafana not found.   Fix: brew install grafana"
command -v python3    >/dev/null 2>&1 || error "Python3 not found.   Fix: brew install python3"
info "Java       : $(java -version 2>&1 | head -1)"
info "Prometheus : $(prometheus --version 2>&1 | head -1)"
info "All prerequisites met ✅"

# ── Step 1: Spring Boot App ───────────────────────────────────
step "Step 1 — Starting Spring Boot App"
lsof -ti:9966 | xargs kill -9 2>/dev/null || true; sleep 1
cd "$PROJECT_DIR"
nohup ./mvnw spring-boot:run > "$APP_LOG" 2>&1 &
echo $! > "$APP_PID"
info "App PID: $(cat "$APP_PID") — logs: app.log"
wait_for "$APP_METRICS" "Spring Boot App" 120
info "App → $APP_BASE"

# Confirm pool config
POOL_MAX=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_max" | awk '{print $2}')
POOL_MIN=$(curl -s "$APP_METRICS" | grep "^hikaricp_connections_min" | awk '{print $2}')
info "HikariCP pool: max=$POOL_MAX  min-idle=$POOL_MIN"

# ── Step 2: Prometheus ────────────────────────────────────────
step "Step 2 — Starting Prometheus"
lsof -ti:9090 | xargs kill -9 2>/dev/null || true; sleep 1
mkdir -p "$OBS_DIR/prometheus-data"
nohup prometheus \
  --config.file="$OBS_DIR/prometheus.yml" \
  --storage.tsdb.path="$OBS_DIR/prometheus-data" \
  > "$PROM_LOG" 2>&1 &
echo $! > "$PROM_PID"
wait_for "$PROMETHEUS_URL/-/ready" "Prometheus" 30

# Wait for first successful scrape of petclinic
info "Waiting for Prometheus to scrape petclinic target..."
tries=0
until curl -sf "$PROMETHEUS_URL/api/v1/targets" | python3 -c "
import sys,json
d=json.load(sys.stdin)
up=any(t.get('health')=='up' for t in d.get('data',{}).get('activeTargets',[]) if 'petclinic' in t.get('labels',{}).get('job',''))
sys.exit(0 if up else 1)" 2>/dev/null; do
  tries=$((tries+1)); [ $tries -gt 20 ] && warn "Target not yet UP — check $PROMETHEUS_URL/targets" && break
  printf '.'; sleep 1
done
echo; info "Prometheus scraping petclinic ✅ → $PROMETHEUS_URL/targets"

# ── Step 3: Grafana ───────────────────────────────────────────
step "Step 3 — Starting Grafana"
brew services start grafana >/dev/null 2>&1 || true
wait_for "$GRAFANA_URL/api/health" "Grafana" 60

# ── Step 4: Datasource ────────────────────────────────────────
step "Step 4 — Provisioning Prometheus Datasource"
DS_RESP=$(curl -sf -X POST "$GRAFANA_URL/api/datasources" \
  -H "Content-Type: application/json" -u admin:admin \
  -d '{"name":"Prometheus","type":"prometheus","url":"'"$PROMETHEUS_URL"'","access":"proxy","isDefault":true}' \
  2>&1 || true)
echo "$DS_RESP" | grep -qiE '"id"|already exists|conflict' \
  && info "Datasource ready ✅" || warn "Datasource response: $DS_RESP"

# ── Step 5: Dashboard ─────────────────────────────────────────
step "Step 5 — Importing Grafana Dashboard"
import_dashboard
DASH_URL=$(cat "$OBS_DIR/dashboard.url" 2>/dev/null || echo "$GRAFANA_URL/d/$DASH_UID")

# ── Step 6: Continuous traffic generator ─────────────────────
step "Step 6 — Starting Continuous Traffic Generator"
[ -f "$TRAFFIC_PID" ] && kill "$(cat "$TRAFFIC_PID")" 2>/dev/null || true; rm -f "$TRAFFIC_PID"
(
  while true; do
    for ep in \
      "$APP_BASE/api/owners" \
      "$APP_BASE/api/vets" \
      "$APP_BASE/api/pettypes" \
      "$APP_BASE/api/specialties"; do
      curl -sf -o /dev/null "$ep" &
    done
    sleep 2
  done
) &
echo $! > "$TRAFFIC_PID"
info "Traffic generator started (PID $(cat "$TRAFFIC_PID")) ✅"
info "Hitting 4 endpoints every 2s — live data in all panels"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║              ✅  Everything is Running                 ║"
echo "╠═══════════════════════════════════════════════════════╣"
printf "║  %-52s ║\n" "App          : $APP_BASE"
printf "║  %-52s ║\n" "Swagger UI   : $APP_BASE/swagger-ui.html"
printf "║  %-52s ║\n" "Metrics      : $APP_METRICS"
printf "║  %-52s ║\n" "Prometheus   : $PROMETHEUS_URL/targets"
printf "║  %-52s ║\n" "Grafana      : $GRAFANA_URL"
printf "║  %-52s ║\n" "Dashboard    : $DASH_URL"
echo "╠═══════════════════════════════════════════════════════╣"
printf "║  %-52s ║\n" "HikariCP     : max=$POOL_MAX  min-idle=$POOL_MIN"
printf "║  %-52s ║\n" "App log      : app.log"
printf "║  %-52s ║\n" "Prom log     : observability/prometheus.log"
echo "╠═══════════════════════════════════════════════════════╣"
echo "║  Commands:                                            ║"
printf "║  %-52s ║\n" "  bash start.sh stop     → stop everything"
printf "║  %-52s ║\n" "  bash start.sh status   → service health"
printf "║  %-52s ║\n" "  bash start.sh errors   → generate 4xx spike"
printf "║  %-52s ║\n" "  bash start.sh load     → pool exhaustion test"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# Auto-open dashboard in browser
open "$DASH_URL" 2>/dev/null || true
