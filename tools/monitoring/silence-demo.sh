#!/bin/bash
# Poziom 7 ćwiczeń z monitoringu – wyciszenie (silence) przez API Alertmanagera, zrzuty i sprzątanie.
# Uruchom po alert-lifecycle.sh, gdy PodinfoDown jest w stanie firing.
# Tworzy wyciszenie na 1 h, robi zrzuty, wygasza je, przywraca 3 repliki podinfo i czeka,
# aż alerty Podinfo* znikną.
#
# Użycie (Git Bash na Windowsie, z katalogu repozytorium):
#   tools/monitoring/silence-demo.sh [katalog_na_zrzuty]
set -uo pipefail

OUT=${1:-docs/etap-3-monitoring/img}
P=${PROM_URL:-http://192.168.180.51:30090}
A=${AM_URL:-http://192.168.180.51:30093}
shot() { node tools/cdpshot.mjs "$OUT/$1" "$2" 1400 "${3:-760}" "${4:-4000}"; }
kube() { echo "\$ $*"; ssh -o BatchMode=yes k3s-master "$*"; }
state() {
  curl -s "$P/api/v1/alerts" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
    const a=JSON.parse(d).data.alerts.filter(x=>/Podinfo/.test(x.labels.alertname));
    console.log(a.map(x=>x.labels.alertname+"="+x.state).join(" ")||"brak")})'
}

mkdir -p "$OUT"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ); end=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
# Treść z pliku (--data-binary @plik): przekazana jako argument w Git Bash traci polskie znaki
body=$(mktemp); trap 'rm -f "$body"' EXIT
cat > "$body" <<EOF
{"matchers":[{"name":"alertname","value":"PodinfoDown","isRegex":false,"isEqual":true}],
 "startsAt":"$now","endsAt":"$end","createdBy":"${USER:-admin}","comment":"Ćwiczenie – podinfo celowo wyłączone"}
EOF
id=$(curl -s -X POST -H 'Content-Type: application/json; charset=utf-8' --data-binary @"$body" "$A/api/v2/silences" \
  | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(JSON.parse(d).silenceID))')
echo "wyciszenie $id"; sleep 3

shot 7-silences.png "$A/#/silences" 640
shot 7-alerts-bez-wyciszonych.png "$A/#/alerts" 700
shot 7-alerts-wyciszone.png "$A/#/alerts?silenced=true"
shot 7-silence-szczegoly.png "$A/#/silences/$id"
echo "Prometheus: $(state)   (wyciszenie działa w Alertmanagerze, Prometheus dalej widzi firing)"

# Sprzątanie: wygaszenie wyciszenia i przywrócenie aplikacji
curl -s -X DELETE "$A/api/v2/silence/$id" -o /dev/null -w "wygaszenie wyciszenia: HTTP %{http_code}\n"
kube kubectl -n demo scale deployment podinfo --replicas=3
kube kubectl -n demo rollout status deployment/podinfo --timeout=120s
T0=$(date +%s)
for _ in $(seq 1 30); do s=$(state); echo "t+$(( $(date +%s) - T0 ))s $s"; [ "$s" = "brak" ] && break; sleep 10; done

shot 7-po-sprzataniu.png "$P/alerts?search=podinfo" 520
shot 7-query-repliki-powrot.png "$P/query?g0.expr=kube_deployment_status_replicas_available%7Bnamespace%3D%22demo%22%7D&g0.tab=graph&g0.range_input=15m" 760 6000
echo "aktywne wyciszenia: $(curl -s "$A/api/v2/silences" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(JSON.parse(d).filter(s=>s.status.state==="active").length))')"
