#!/bin/bash
# Poziom 6 ćwiczeń z monitoringu – "narodziny alertu", automatycznie i ze zrzutami.
# Skaluje podinfo do 0, co 10 s sprawdza stan alertów w Prometheusie i robi zrzuty:
# PodinfoDown pending -> firing -> alert w Alertmanagerze. Repliki przywraca silence-demo.sh
# (albo ręcznie: kubectl -n demo scale deployment podinfo --replicas=3).
#
# Użycie (Git Bash na Windowsie, z katalogu repozytorium, ssh k3s-master działa kluczem):
#   tools/monitoring/alert-lifecycle.sh [katalog_na_zrzuty]
set -uo pipefail

OUT=${1:-docs/etap-3-monitoring/img}
P=${PROM_URL:-http://192.168.180.51:30090}
A=${AM_URL:-http://192.168.180.51:30093}
shot() { node tools/cdpshot.mjs "$OUT/$1" "$2" 1400 760 "${3:-4000}"; }
kube() { echo "\$ $*"; ssh -o BatchMode=yes k3s-master "$*"; }
# Stan alertów Podinfo* z API Prometheusa, np. "PodinfoDown=pending"
state() {
  curl -s "$P/api/v1/alerts" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
    const a=JSON.parse(d).data.alerts.filter(x=>/Podinfo/.test(x.labels.alertname));
    console.log(a.map(x=>x.labels.alertname+"="+x.state).join(" ")||"brak")})'
}

mkdir -p "$OUT"
kube kubectl -n demo get deploy podinfo
T0=$(date +%s); echo "start $(date +%T)"
kube kubectl -n demo scale deployment podinfo --replicas=0

pending=0; firing=0; in_am=0; degraded=0
for _ in $(seq 1 60); do
  s=$(state); echo "t+$(( $(date +%s) - T0 ))s $s"
  if [ $pending = 0 ] && grep -q "PodinfoDown=pending" <<<"$s"; then pending=1; shot 6-alert-pending.png "$P/alerts?search=podinfo"; fi
  if [ $firing = 0 ] && grep -q "PodinfoDown=firing" <<<"$s"; then firing=1; shot 6-alert-firing.png "$P/alerts?search=podinfo"; fi
  if [ $firing = 1 ] && [ $in_am = 0 ] && curl -s "$A/api/v2/alerts?filter=alertname%3D%22PodinfoDown%22" | grep -q PodinfoDown; then
    in_am=1; shot 6-alertmanager-podinfo.png "$A/#/alerts"
  fi
  grep -q "PodinfoDegraded=firing" <<<"$s" && degraded=1
  [ $in_am = 1 ] && [ $degraded = 1 ] && break
  sleep 10
done

shot 6-query-repliki.png "$P/query?g0.expr=kube_deployment_status_replicas_available%7Bnamespace%3D%22demo%22%7D&g0.tab=graph&g0.range_input=15m" 6000
echo "koniec $(date +%T) – podinfo ma 0 replik; dalej: tools/monitoring/silence-demo.sh"
