#!/bin/bash
# Zrzut "terminala" z tekstu: wynik poleceń (plik .txt) -> HTML w stylu terminala -> PNG przez tools/cdpshot.mjs (Edge headless).
# Tak powstały zrzuty w ćwiczeniach z kubectl (docs/etap-2-k3s-ansible/img/).
#
# Użycie: tools/terminal-shot.sh <wynik.png> "<tytuł okna>" <plik.txt> [plik.txt...]
# Tekst zbierz np. tak (Git Bash na Windowsie):
#   { echo 'grzegorz@k3s-master:~$ kubectl get nodes'; ssh k3s-master kubectl get nodes; } > nodes.txt
#   tools/terminal-shot.sh docs/etap-2-k3s-ansible/img/1-wezly.png "Poziom 1 – węzły" nodes.txt
# Wiersze z promptem (user@host:~$) są pogrubione, stany Running/Ready na zielono, błędy na czerwono.
set -euo pipefail

[ $# -ge 3 ] || { echo "Użycie: $0 <wynik.png> \"<tytuł>\" <plik.txt>..." >&2; exit 2; }
out=$1; title=$2; shift 2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Sklejenie plików i usunięcie pustych linii na końcu
txt=$tmp/in.txt; : > "$txt"
for f in "$@"; do cat "$f" >> "$txt"; echo >> "$txt"; done
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$txt"

# Rozmiar okna z liczby i długości linii (ok. 7,8 px na znak, 19 px na linię, maks. 1400 px szerokości)
maxw=1400; cpl=$(( (maxw - 48) * 10 / 78 ))
lines=$(awk -v c=$cpl '{n=length($0); r=(n==0)?1:int((n+c-1)/c); s+=r} END{print s}' "$txt")
longest=$(awk '{if(length($0)>m)m=length($0)} END{print m+0}' "$txt")
w=$(( longest * 78 / 10 + 60 )); [ $w -gt $maxw ] && w=$maxw; [ $w -lt 640 ] && w=640
h=$(( lines * 19 + 78 ))

# Escapowanie HTML i kolorowanie
body=$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$txt" \
  | sed -E -e 's#^([a-z0-9_-]+@[a-z0-9-]+:~\$)(.*)$#<span class="p">\1</span><span class="c">\2</span>#' \
    -e 's#\b(Running|Ready|Completed|successfully rolled out|unchanged|created|evicted|drained|uncordoned|exposed|scaled|rolled back|Started|Pulled|Welcome to nginx!)\b#<span class="ok">\1</span>#g' \
    -e 's#\b(ContainerCreating|Pending|SchedulingDisabled|cordoned|Killing|Pulling|Waiting)\b#<span class="wa">\1</span>#g' \
    -e 's#\b(ImagePullBackOff|ErrImagePull|CrashLoopBackOff|OOMKilled|Warning|Failed|NotFound|not found)\b#<span class="er">\1</span>#g' \
    -e 's#^(\+.*)$#<span class="ok">\1</span>#' -e 's#^(-[^-].*)$#<span class="er">\1</span>#')

cat > "$tmp/shot.html" <<EOF
<!doctype html><meta charset="utf-8"><style>
body{margin:0;background:#1e1f24;font:14px/19px Consolas,"Cascadia Mono",monospace;color:#d4d4d4}
.bar{height:32px;background:#2d2f36;display:flex;align-items:center;padding:0 14px;gap:8px;font:13px "Segoe UI",sans-serif;color:#aab}
.d{width:12px;height:12px;border-radius:50%}.t{margin-left:10px}
pre{margin:0;padding:14px 18px;white-space:pre-wrap;word-break:break-all}
.p{color:#6ad46a;font-weight:bold}.c{color:#fff;font-weight:bold}.ok{color:#6ad46a}.wa{color:#e5c07b}.er{color:#f07178}
</style><div class="bar"><span class="d" style="background:#ff5f57"></span><span class="d" style="background:#febc2e"></span><span class="d" style="background:#28c840"></span><span class="t">$title</span></div><pre>$body</pre>
EOF

# Zrzut przez cdpshot.mjs – samo `msedge --screenshot` w nowym Edge kończy się od razu i nic nie zapisuje.
# Adres file:// potrzebuje ścieżki w formie C:/... (cygpath z Git Bash).
to_win() { command -v cygpath >/dev/null && cygpath -w "$1" || echo "$1"; }
mkdir -p "$(dirname "$out")"
node "$(dirname "$0")/cdpshot.mjs" "$out" "file:///$(to_win "$tmp/shot.html" | tr '\\' '/')" $w $h 1000 >/dev/null
echo "$out ${w}x${h}"
