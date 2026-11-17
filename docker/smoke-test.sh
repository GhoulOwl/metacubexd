#!/usr/bin/env bash
set -euo pipefail

image=${1:?Usage: smoke-test.sh IMAGE}
name="metacubexd-smoke-${RANDOM}-${RANDOM}"
data_dir=$(mktemp -d)
cleanup() {
  result=$?
  if (( result != 0 )); then
    docker logs "$name" 2>&1 || true
  fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$data_dir"
  exit "$result"
}
trap cleanup EXIT

# No real subscription or third-party proxy is required for this startup test.
cat > "$data_dir/active.yaml" <<'YAML'
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: false
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
YAML

docker run -d --name "$name" \
  -e CONTROL_TOKEN=ci-control-token \
  -e CLASH_SECRET=ci-clash-secret \
  -p 127.0.0.1::8080 -p 127.0.0.1::9090 -p 127.0.0.1::7890 \
  -v "$data_dir:/data" "$image" >/dev/null
panel_port=$(docker port "$name" 8080/tcp | awk -F: '{print $NF}')
api_port=$(docker port "$name" 9090/tcp | awk -F: '{print $NF}')
proxy_port=$(docker port "$name" 7890/tcp | awk -F: '{print $NF}')

ready=false
for ((attempt = 0; attempt < 60; attempt++)); do
  if curl --fail --silent --max-time 2 "http://127.0.0.1:$panel_port/api/control/health" >/dev/null &&
     curl --fail --silent --max-time 2 -H 'Authorization: Bearer ci-clash-secret' \
       "http://127.0.0.1:$api_port/version" >/dev/null; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  echo 'Panel or Mihomo did not become ready within 120 seconds.' >&2
  exit 1
fi

curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$panel_port/" > "$data_dir/panel.html"
grep -qi '<html' "$data_dir/panel.html"
status=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
  "http://127.0.0.1:$panel_port/api/control/kernel/status")
[[ "$status" == 401 ]]
curl --fail --silent --show-error --max-time 10 -H 'Authorization: Bearer ci-control-token' \
  "http://127.0.0.1:$panel_port/api/control/kernel/status" > "$data_dir/status.json"
jq -e '.status == "running"' "$data_dir/status.json" >/dev/null
docker exec "$name" node -e \
  'const s=require("node:net").connect(7890,"127.0.0.1",()=>s.end());s.setTimeout(5000,()=>process.exit(1));s.on("error",()=>process.exit(1))'
docker exec "$name" /usr/local/bin/mihomo -v
printf 'Startup checks passed: panel=%s, API=%s, proxy=%s\n' "$panel_port" "$api_port" "$proxy_port"
