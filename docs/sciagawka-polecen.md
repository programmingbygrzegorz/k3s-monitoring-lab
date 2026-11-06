# Ściągawka poleceń

Polecenia omawiane w trakcie budowy labu, zebrane w jednym miejscu i pogrupowane tematycznie.
Przy każdym: co robi i gdzie jest opisane dokładniej. Plik jest uzupełniany na bieżąco.

Oznaczenia: 🪟 Windows (PowerShell / Git Bash), 🐧 maszyna Linux przez SSH.
`k` = `kubectl` (alias z [ćwiczeń z kubectl](etap-2-k3s-ansible/05-cwiczenia-kubectl.md#skrót-k-zamiast-kubectl-opcjonalnie)).

## Spis treści

1. [Linux – tekst i pliki](#linux--tekst-i-pliki)
2. [Linux – użytkownicy i grupy](#linux--użytkownicy-i-grupy)
3. [Linux – logi](#linux--logi)
4. [Linux – dyski i miejsce](#linux--dyski-i-miejsce)
5. [Linux – usługi, procesy i harmonogram](#linux--usługi-procesy-i-harmonogram)
6. [nginx](#nginx)
7. [PostgreSQL](#postgresql)
8. [MariaDB / MySQL](#mariadb--mysql)
9. [kubectl – oglądanie](#kubectl--oglądanie)
10. [kubectl – tworzenie, zmiany, usuwanie](#kubectl--tworzenie-zmiany-usuwanie)
11. [kubectl – wdrożenia i wersje](#kubectl--wdrożenia-i-wersje)
12. [kubectl – diagnoza](#kubectl--diagnoza)
13. [kubectl – konta i tokeny](#kubectl--konta-i-tokeny)
14. [Helm](#helm)
15. [Docker i rejestr](#docker-i-rejestr)
16. [DNS, certyfikaty i HTTPS](#dns-certyfikaty-i-https)
17. [Ansible (ad-hoc)](#ansible-ad-hoc)
18. [Sieć, firewall i maszyny VMware](#sieć-firewall-i-maszyny-vmware)
19. [Git](#git)

## Linux – tekst i pliki

| Polecenie | Co robi |
|---|---|
| `grep WZORZEC plik` | linie pliku, w których jest wzorzec |
| `polecenie \| grep WZORZEC` | filtruje wynik innego polecenia (`\|` – przekazanie wyniku dalej) |
| `grep -i error` | bez rozróżniania wielkości liter |
| `grep -v Running` | odwrotnie – linie, w których **nie ma** wzorca |
| `grep -n`, `-c`, `-w` | numer linii / liczba pasujących linii / tylko całe słowo |
| `grep -rn "image: app:" .` | szuka w całym katalogu z podkatalogami, z numerami linii |
| `grep -rl "image: app:" .` | tylko nazwy plików, w których jest wzorzec |
| `grep -A 5 Events` / `-B 3` / `-C 3` | dodatkowo 5 linii po / 3 przed / 3 wokół |
| `grep -E "Error\|BackOff"` | kilka wzorców naraz (lub) |
| `grep -v -E "^#\|^$" plik` | plik konfiguracyjny bez komentarzy i pustych linii (`^` początek, `$` koniec linii) |
| `sed -i 's#stare#nowe#' plik` | zamienia tekst w pliku na miejscu (`-i`); `#` to separator zamiast `/` |
| `sed -i 's#a#b#' $(grep -rl "a" .)` | zamiana tylko w plikach, które `grep` znalazł |
| `cat`, `ls`, `cd`, `rm -rf katalog` | wyświetl plik, lista plików, zmiana katalogu, usuń katalog z zawartością (bez kosza!) |
| `curl --cacert ca.crt https://adres` | zapytanie HTTPS z zaufaniem do własnego CA |

Szczegóły grep: wyjaśnienie z rozmowy 03.11.2026 (przełączniki, wyrażenia regularne, cudzysłowy).

## Linux – użytkownicy i grupy

| Polecenie | Co robi |
|---|---|
| `id`, `groups` | Twoje konto i grupy **tej sesji** (grupy ustalane są przy logowaniu) |
| `sudo usermod -aG docker $USER` | dopisuje konto do grupy `docker` (`-a` dopisz, bez niego konto wypada z innych grup) |
| `sudo gpasswd -d grzegorz docker` | wypisuje konto z grupy |
| `sudo groupdel docker` | usuwa grupę |
| `exit`, potem `ssh monitoring` | ponowne logowanie – nowe grupy zaczynają działać |
| `ls -l /var/run/docker.sock` | uprawnienia pliku (`srw-rw---- root docker` – tylko root i grupa docker) |

| `sudo adduser --disabled-password --gecos "Anna Nowak" anna` | nowe konto bez hasła (logowanie tylko kluczem) |
| `sudo groupadd devops` | nowa grupa |
| `sudo chown root:devops katalog`, `sudo chmod 2770 katalog` | wspólny katalog zespołu; `2` = setgid – nowe pliki dostają grupę katalogu |
| `sudo -u anna polecenie` | uruchamia polecenie jako inny użytkownik (test uprawnień) |
| `sudo -l -U anna` | co `anna` może robić przez `sudo` |
| `getent group sudo`, `grep anna /etc/passwd` | członkowie grupy, wpis konta |
| `sudo usermod -L anna`, `sudo passwd -S anna` | blokada konta, stan hasła (`L` = zablokowane) |

Problem z tym związany: `permission denied … docker.sock` – sesja otwarta przed dodaniem do grupy.
Ćwiczenia: [codzienna praca administratora Linuxa](etap-1-przygotowanie-systemu/02-cwiczenia-admin-linux.md).

## Linux – logi

| Polecenie | Co robi |
|---|---|
| `grep 'Invalid user' /var/log/auth.log` | nieudane próby logowania SSH (nieistniejące konta) |
| `grep -oE 'from [0-9.]+' … \| sort \| uniq -c \| sort -nr` | ile razy wystąpił każdy adres, najczęstsze na górze |
| `zgrep wzorzec /var/log/auth.log*` | `grep` także w starych, spakowanych logach (`.gz`) |
| `loginctl list-sessions`, `who` | bieżące sesje (`last` w Ubuntu 26.04 zastąpiło `wtmpdb last`) |
| `journalctl -b -p err` | błędy i gorsze od ostatniego uruchomienia |
| `journalctl -u ssh --since "1 hour ago"` | logi jednej usługi z ostatniej godziny |
| `journalctl -u licznik -f` | logi usługi na żywo (Ctrl+C kończy) |
| `journalctl --list-boots`, `journalctl -b -1` | lista uruchomień, logi poprzedniego uruchomienia |
| `journalctl --disk-usage`, `sudo journalctl --vacuum-size=200M` | ile zajmuje dziennik, przycięcie go |
| `sudo dmesg -T \| tail`, `journalctl -k` | komunikaty jądra (dyski, sieć, OOM) |
| `sudo sshd -T \| grep passwordauthentication` | ostateczna konfiguracja SSH po złożeniu wszystkich plików |

## Linux – dyski i miejsce

| Polecenie | Co robi |
|---|---|
| `lsblk`, `df -h`, `blkid` | dyski i partycje, zajęte miejsce, UUID systemu plików |
| `sudo pvs`, `sudo vgs`, `sudo lvs` | LVM: dyski fizyczne, pule, wolumeny |
| `sudo pvcreate /dev/sdb`, `sudo vgextend ubuntu-vg /dev/sdb` | nowy dysk do puli LVM |
| `sudo lvcreate -n data -L 5G ubuntu-vg`, `sudo mkfs.ext4 /dev/ubuntu-vg/data` | nowy wolumen i system plików |
| `sudo lvextend -r -L +3G /dev/ubuntu-vg/ubuntu-lv` | powiększa wolumen **i** system plików w trakcie pracy |
| `UUID=…  /data  ext4  defaults  0  2` w `/etc/fstab`, `sudo mount -a` | montowanie na stałe i test bez restartu |
| `sudo findmnt --verify` | sprawdza `fstab` (błąd = system nie wstanie) |
| `sudo du -xh --max-depth=1 / \| sort -h` | które katalogi zajmują najwięcej (bez innych dysków) |
| `sudo find / -xdev -type f -size +500M` | największe pliki |
| `sudo lsof +L1` | pliki usunięte, ale wciąż otwarte – „usunąłem, a miejsca nie ma” |
| `sudo truncate -s 0 /proc/PID/fd/N` | zwalnia miejsce po takim pliku bez zabijania procesu |

## Linux – usługi, procesy i harmonogram

| Polecenie | Co robi |
|---|---|
| `systemctl status usługa`, `systemctl is-active / is-enabled` | stan usługi |
| `sudo systemctl daemon-reload` | wczytuje zmienione pliki `.service` |
| `sudo systemctl enable --now usługa` | start teraz i przy każdym uruchomieniu systemu |
| `sudo systemctl reset-failed usługa` | kasuje licznik po `Start request repeated too quickly` |
| `systemctl show -p NRestarts -p MainPID usługa` | ile razy wznowiona, aktualny PID |
| `uptime`, `top` (`P`, `M`, `1`, `q`), `htop` | obciążenie, procesy na żywo |
| `ps aux --sort=-%cpu \| head`, `ps -o pid,user,lstart,cmd -p PID` | najbardziej obciążające procesy, kto i kiedy uruchomił |
| `kill PID`, `kill -9 PID`, `pkill nazwa` | łagodne zakończenie / siłą / wszystkie po nazwie |
| `sudo crontab -l`, `sudo crontab -e`, `sudo crontab -r` | zadania crona roota: pokaż / edytuj / usuń wszystkie |
| `grep CRON /var/log/syslog` | kiedy cron uruchomił zadania |
| `sudo logrotate -d plik`, `sudo logrotate -f plik` | rotacja logów: próba bez zmian / wymuszenie |
| `systemctl list-timers` | zadania uruchamiane przez systemd (np. `logrotate.timer`) |
| `find katalog -name "*.gz" -mtime +7 -delete` | usuwa pliki starsze niż 7 pełnych dób (rotacja kopii) |
| `setsid nohup polecenie >/dev/null 2>&1 </dev/null &` | proces w tle odłączony od sesji (SSH nie czeka na niego) |

## nginx

| Polecenie | Co robi |
|---|---|
| `sudo nginx -t` | test konfiguracji – **zawsze** przed reload |
| `sudo nginx -t && sudo systemctl reload nginx` | wczytanie zmian bez przerwy (przy błędzie zostaje stara konfiguracja) |
| `sudo nginx -T \| grep -E 'server_name\|listen'` | pełna, złożona konfiguracja – co nginx naprawdę wczytał |
| `sudo ln -s /etc/nginx/sites-available/X /etc/nginx/sites-enabled/` | włączenie strony (wirtualnego hosta) |
| `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: sklep.lab' localhost/` | sam kod odpowiedzi wybranej strony |
| `curl --resolve sklep.lab:443:127.0.0.1 https://sklep.lab` | test nazwy bez DNS (także HTTPS) |
| `curl -v … 2>&1 \| grep Trying` | na jaki adres naprawdę łączy się `curl` (IPv4 czy IPv6) |
| `sudo tail -f /var/log/nginx/error.log` | przyczyny 403, 404, 502, 504, 413 |
| `awk '{print $9}' access.log \| sort \| uniq -c \| sort -nr` | ile odpowiedzi każdego kodu |
| `awk '{print $1}' access.log \| sort \| uniq -c \| sort -nr` | najaktywniejsze adresy klientów |
| `namei -l /var/www/strona/index.html` | prawa każdego katalogu w ścieżce (403 przez uprawnienia) |
| `sudo ss -tlnp 'sport = :80'` | kto zajmuje port 80 |
| `sudo htpasswd -c /etc/nginx/.htpasswd user` | plik haseł do `auth_basic` |
| `openssl x509 -in cert.crt -noout -enddate -checkend 2592000` | data ważności; kod 1, gdy wygasa w ciągu 30 dni |
| `echo \| openssl s_client -connect IP:443 -servername nazwa \| openssl x509 -noout -subject -enddate` | certyfikat, który serwer naprawdę wysyła |

Ćwiczenia: [40 typowych problemów](etap-1-przygotowanie-systemu/04-cwiczenia-nginx-bazy.md).

## PostgreSQL

| Polecenie | Co robi |
|---|---|
| `sudo -u postgres psql` | konsola administratora bazy |
| `pg_lsclusters`, `systemctl status postgresql@18-main` | czy klaster naprawdę działa (`postgresql.service` to tylko parasol) |
| `psql -h localhost -U app sklep` | logowanie hasłem przez TCP (bez `-h` – `peer` przez gniazdo) |
| `\l`, `\du`, `\dt`, `\di+`, `\q` (w `psql`) | bazy, role, tabele, indeksy z rozmiarem, wyjście |
| `pg_hba.conf` + `sudo systemctl reload postgresql` | kto, skąd i jak może się łączyć |
| `listen_addresses = '*'` w `conf.d/` + restart | nasłuch nie tylko na localhost |
| `select * from pg_stat_activity;` | kto jest połączony i co robi |
| `pg_blocking_pids(pid)`, `pg_terminate_backend(pid)` | kto kogo blokuje, zakończenie sesji |
| `sudo -u postgres pg_dump -Fc baza -f plik.dump` | kopia bazy (format do `pg_restore`) |
| `pg_restore -l plik.dump`, `pg_restore -d baza -t tabela plik.dump` | spis kopii, odtworzenie jednej tabeli |
| `EXPLAIN ANALYZE select …` | plan i czas zapytania (`Seq Scan` = czyta całą tabelę) |
| `select pg_size_pretty(pg_database_size('baza'));` | rozmiar bazy |
| `/var/log/postgresql/postgresql-18-main.log` | log bazy – przyczyny błędów logowania i startu |

## MariaDB / MySQL

| Polecenie | Co robi |
|---|---|
| `sudo mariadb` | konsola jako root (przez `unix_socket`, bez hasła) |
| `mariadb -h 127.0.0.1 -u blog -p blog` | logowanie przez TCP (`-h localhost` = gniazdo Unix) |
| `CREATE USER 'blog'@'192.168.180.%' IDENTIFIED BY '…';` | konto = nazwa **i** skąd się łączy |
| `GRANT ALL ON blog.* TO 'blog'@'localhost';`, `SHOW GRANTS FOR …` | uprawnienia |
| `ALTER USER 'blog'@'localhost' IDENTIFIED BY '…';` | nowe hasło |
| `bind-address` w `/etc/mysql/mariadb.conf.d/50-server.cnf` | na jakim adresie słucha serwer |
| `sudo mariadb-dump --single-transaction baza > kopia.sql` | kopia bez blokowania tabel |
| `sudo mariadb baza < kopia.sql` | odtworzenie |
| `mariadb-admin ping`, `journalctl -u mariadb` | czy działa; dziennik (m.in. nieudane logowania) |

## kubectl – oglądanie

| Polecenie | Co robi |
|---|---|
| `k get nodes -o wide` | węzły z IP i wersją |
| `k get ns` | lista namespace'ów |
| `k get pods -A` | pody ze wszystkich namespace'ów (`-A`) |
| `k -n NS get pods -o wide` | pody w namespace NS, z węzłem i IP |
| `k -n NS get all` | typowe obiekty: pody, Service, Deploymenty, ReplicaSety |
| `k -n NS get all,cm,secret,pvc` | to samo plus ConfigMapy, Secrety, dyski (`all` ich nie obejmuje) |
| `k get all -A` | obiekty ze wszystkich namespace'ów |
| `k api-resources --namespaced -o name \| xargs -n1 k -n NS get --ignore-not-found --show-kind` | naprawdę wszystko w namespace |
| `k -n NS get svc` | Service: typ (ClusterIP / NodePort), porty `80:30400` |
| `k -n NS get endpoints NAZWA` | do których podów Service kieruje ruch (od k8s 1.33 ostrzeżenie „deprecated” – działa dalej) |
| `k -n NS get endpointslices` | nowsza wersja tego samego: adresy podów za każdym Service (skrót `eps`) |
| `k -n NS get rs` | ReplicaSety (stare wersje z `0` podów) |
| `k get pods --show-labels`, `-l app=web` | etykiety / filtrowanie po etykiecie |
| `k get deploy`, `po`, `svc`, `rs`, `ns`, `no`, `cm`, `pvc`, `ing` | skróty nazw: deployment, pod, service, replicaset, namespace, node, configmap, persistentvolumeclaim, ingress |
| `k api-resources` | wszystkie rodzaje obiektów; kolumna `SHORTNAMES` – dozwolone skróty |

Teoria obiektów: [teoria Kubernetesa](etap-3-monitoring/03-teoria-kubernetes-helm.md).

## kubectl – tworzenie, zmiany, usuwanie

| Polecenie | Co robi |
|---|---|
| `k apply -f plik.yaml` | tworzy albo aktualizuje obiekty opisane w pliku |
| `k diff -f plik.yaml` | co by się zmieniło – bez zmiany |
| `k apply --dry-run=server -f plik.yaml` | pełna walidacja przez API server (nieznane pola, zgodność selektora), nic nie zapisuje; `--dry-run=client` łapie tylko składnię |
| `k create deployment NAZWA --image=OBRAZ --replicas=3 --port=9898 --dry-run=client -o yaml > plik.yaml` | szkielet Deploymentu do pliku – nic nie tworzy w klastrze |
| `k create service nodeport NAZWA --tcp=9898:9898 --node-port=30898 --dry-run=client -o yaml` | szkielet Service'u NodePort |
| `k explain deployment.spec.selector` | dokumentacja pola: typ (`<[]…>` = lista, `<map…>` = słownik) i opis; `--recursive` = całe drzewo |
| `k delete -f plik.yaml` | usuwa obiekty opisane w pliku |
| `k delete namespace NS` | usuwa namespace **ze wszystkim w środku** |
| `k -n NS delete all --all` | czyści typowe obiekty, namespace zostaje |
| `k -n NS delete pod NAZWA` | usuwa pod (Deployment postawi nowy) |
| `k -n NS scale deployment web --replicas=4` | zmienia liczbę kopii |
| `k -n NS expose deployment web --port=80 --type=NodePort` | tworzy Service do Deploymentu: nazwa i selector skopiowane z Deploymentu; bez `--type` = ClusterIP; `--target-port` gdy kontener słucha na innym porcie; `--dry-run=client -o yaml` pokaże YAML |

⚠️ `delete` nie ma kosza ani pytania „czy na pewno” – najpierw `get`, potem `delete`, i sprawdź `-n`.

## kubectl – wdrożenia i wersje

| Polecenie | Co robi |
|---|---|
| `k -n NS set image deployment/web nginx=nginx:1.27` | nowy obraz → nowy ReplicaSet, aktualizacja krocząca |
| `k -n NS rollout status deployment/web` | czy aktualizacja się skończyła |
| `k -n NS rollout history deployment/web` | historia wersji |
| `k -n NS rollout undo deployment/web` | powrót do poprzedniej wersji |
| `k -n NS rollout restart deployment/web` | restart podów (np. po zmianie ConfigMap w zmiennych) |
| `k drain WĘZEŁ --ignore-daemonsets --delete-emptydir-data` | wyprowadza pody z węzła przed konserwacją |
| `k uncordon WĘZEŁ` | wpuszcza pody z powrotem |

## kubectl – diagnoza

| Polecenie | Co robi |
|---|---|
| `k -n NS describe pod NAZWA` | szczegóły poda; na dole **Events** – przyczyna błędu |
| `k -n NS get events --sort-by=.lastTimestamp` | co się działo, od najstarszych |
| `k -n NS logs NAZWA --tail=20` | ostatnie linie logu |
| `k -n NS exec NAZWA -- sh -c '…'` | polecenie wewnątrz kontenera |
| `k -n NS exec -it NAZWA -- bash` | wejście do kontenera (`-i` wejście z klawiatury, `-t` terminal); wyjście: `exit` albo Ctrl+D |
| `k exec -it NAZWA -c KONTENER -- sh` | gdy pod ma kilka kontenerów; `sh`, gdy w obrazie nie ma `bash` |
| `k get pods -A \| grep -v Running` | pody, które nie działają |
| `k exec toolbox -- cat /etc/resolv.conf` | jaki DNS i jakie domeny dopisuje pod (`search …svc.cluster.local`) |
| `k exec toolbox -- getent hosts USŁUGA.NAMESPACE` | nazwa Service → IP (DNS klastra); `nslookup`/`dig` w obrazie `pnowy/toolbox` kończą się błędem |
| `k exec toolbox -- curl -s http://USŁUGA.NAMESPACE:PORT/` | połączenie z usługą po nazwie |
| `k get ingress -A` | wszystkie Ingressy: klasa, hosty, adresy węzłów |
| `k describe ingress NAZWA -n NS` | reguły host → ścieżka → Service:port i **adresy podów za nim**; zdarzenia na dole |
| `k get ingress NAZWA -n NS -o yaml` | pełna definicja (to, co w pliku, plus pola dodane przez klaster) |
| `kubectl create ingress NAZWA -n NS --class=traefik --rule="host/*=service:port"` | nowy Ingress jednym poleceniem (`/*` = Prefix); `--dry-run=client -o yaml` wypisze YAML zamiast tworzyć |
| `kubectl apply -f plik.yaml` / `kubectl edit ingress NAZWA -n NS` | zmiana reguł z pliku (lepiej – zostaje w gicie) albo na żywo w edytorze |
| `kubectl delete ingress NAZWA -n NS` | usuwa tylko regułę – Service i pody działają dalej |
| `k get ingressclass` | kontrolery Ingress w klastrze; `(default)` = używany, gdy Ingress nie poda klasy |
| `curl -H "Host: podinfo.lab.local" http://192.168.180.52/` | test Ingressa bez wpisu w DNS/hosts: dowolny węzeł (Traefik słucha na .51–.55), nazwa w nagłówku `Host`. Na Windowsie w PowerShell 5.1 pisz `curl.exe` |
| `curl -s http://192.168.180.52:9100/metrics \| grep ^node_load` | surowe metryki node-exportera z węzła (port 9100, ok. 860 metryk `node_…`) – to samo, co co 30 s zbiera Prometheus |
| `k -n kube-system get svc kube-dns` | adres DNS klastra (CoreDNS, `10.43.0.10`) |

Typowe błędy (ImagePullBackOff, CrashLoopBackOff…):
[typowe awarie Kubernetesa](etap-5-scenariusze-awarii/02-typowe-awarie-kubernetesa.md).
`ImagePullBackOff` + `repository does not exist` = obrazu nie zbudowano albo nie wysłano do rejestru.

## kubectl – konta i tokeny

| Polecenie | Co robi |
|---|---|
| `k create token headlamp -n headlamp --duration=24h` | token logowania do Headlampa (bez `--duration` – 1 h) |
| `… --duration=1440h` | około 2 miesięcy (`--duration` przyjmuje h, m, s – nie dni) |
| `… -o jsonpath='{.status.expirationTimestamp}'` | sama data wygaśnięcia zamiast tokenu |
| `k get clusterrolebinding headlamp-admin` | jakie uprawnienia ma konto |

Szczegóły: [Headlamp – logowanie tokenem](etap-6-gui/01-headlamp.md#logowanie-tokenem).

## Helm

| Polecenie | Co robi |
|---|---|
| `helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/` | dodaje katalog chartów |
| `helm repo update` | odświeża spis wersji |
| `helm search repo headlamp/headlamp --versions` | dostępne wersje |
| `helm show values headlamp/headlamp --version 0.46.0` | wszystkie ustawienia charta z opisem |
| `helm install NAZWA repo/chart --version X -n NS --create-namespace` | instalacja |
| `helm upgrade NAZWA repo/chart --version X -n NS --reuse-values --set klucz=wartość` | zmiana ustawień, z zachowaniem poprzednich |
| `helm upgrade --install … -f values.yaml` | instaluje albo aktualizuje z pliku values (lepsza praktyka niż `--set`) |
| `helm list -A` | wszystkie release'y i ich rewizje |
| `helm list -A -a` | to samo, razem z release'ami nieudanymi i w trakcie (`failed`, `pending-…`) |
| `helm history NAZWA -n NS` | historia jednego release'u: rewizje, daty, status, wersja chartu, opis zmiany. Bez `-n` Helm szuka w `default` → `Error: release: not found` (np. `helm history monitoring -n monitoring`) |
| `helm list -A --no-headers \| while read n ns rest; do echo "== $n ($ns)"; helm history "$n" -n "$ns"; done` | historia **wszystkich** release'ów naraz (Helm nie ma `history -A`, więc pętla po liście) |
| `helm get values NAZWA -n NS` | ustawienia podane przez Ciebie (`-a` – wszystkie) |
| `helm get values NAZWA -n NS --revision 1` | ustawienia z konkretnej rewizji – porównanie z bieżącą pokazuje, co zmienił upgrade |
| `helm rollback NAZWA 1 -n NS` | powrót do rewizji 1 |
| `helm uninstall NAZWA -n NS` | usuwa release |
| `helm create NAZWA` | szkielet własnego chartu: `Chart.yaml`, `values.yaml`, `templates/` z przykładami |
| `rm -rf NAZWA/templates/*` | czyści przykładowe szablony z `helm create`, katalog `templates/` zostaje na własne pliki |
| `helm template NAZWA ./katalog` | pokazuje gotowe YAML-e z szablonów, niczego nie instaluje |

Teoria: [Helm](etap-3-monitoring/03-teoria-kubernetes-helm.md). Wszystkie polecenia i przełączniki:
oficjalna ściągawka Helma (po angielsku) – [helm.sh/docs/intro/cheatsheet](https://helm.sh/docs/intro/cheatsheet/).

## Docker i rejestr

Na maszynie `monitoring` (192.168.180.54), rejestr labu: `192.168.180.54:5000`.

| Polecenie | Co robi |
|---|---|
| `docker build -t 192.168.180.54:5000/app:1.0.0 .` | buduje obraz z `Dockerfile` w bieżącym katalogu (kropka!) i nadaje nazwę z adresem rejestru |
| `docker push 192.168.180.54:5000/app:1.0.0` | wysyła obraz do rejestru – stamtąd pobierają go węzły k3s |
| `curl --cacert ~/rejestr-certs/ca.crt https://192.168.180.54:5000/v2/app/tags/list` | jakie wersje obrazu są w rejestrze |
| `docker ps -a`, `docker images`, `docker volume ls` | kontenery, obrazy, wolumeny |
| `docker rm -f NAZWA` | zatrzymuje i usuwa kontener |
| `docker image prune -a -f` | usuwa nieużywane obrazy |
| `docker save OBRAZ:TAG -o plik.tar` | kopia obrazu ze wszystkimi warstwami do pliku – niezależna od rejestru |
| `docker load -i plik.tar` | przywraca obraz z pliku do lokalnego Dockera (potem `docker push`) |
| `curl --cacert ca.crt https://REJESTR:5000/v2/_catalog` | lista obrazów w rejestrze; `/v2/NAZWA/tags/list` – tagi jednego obrazu |
| `docker exec KONTENER POLECENIE` | uruchamia jedno polecenie w działającym kontenerze, np. `docker exec rejestr ls -l /certs` |
| `docker inspect KONTENER --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'` | co jest podpięte do kontenera z zewnątrz (`-v`) i skąd |
| 🐧 węzeł k3s: `sudo k3s crictl images` / `sudo k3s crictl rmi OBRAZ:TAG` | obrazy w containerd na węźle / usunięcie obrazu z cache węzła (na węzłach k3s nie ma Dockera) |
| `set -a && source lab.env && set +a` | wczytaj zmienne z pliku do bieżącej powłoki i eksportuj je (widzi je np. `envsubst`) |
| `umask 077` | nowe pliki w tej powłoce od razu z uprawnieniami `600` (różnica z `chmod`: działa przed utworzeniem pliku) |
| `envsubst '${A} ${B}' < wzor.yaml > /tmp/gotowy.yaml` | wstaw wartości tylko tych zmiennych w luki `${…}`; wzór zostaje bez zmian |
| `helm -n NS get values RELEASE` | ustawienia, które podałeś przy ostatnim wdrożeniu (bez domyślnych chartu) |
| `kubectl -n NS get secret NAZWA -o jsonpath='{.data.PLIK}' \| base64 -d` | odczytaj plik z Secretu (dla `.gz` dodaj `\| gunzip`) |
| `kubectl -n NS get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IMAGE:.status.containerStatuses[0].imageID` | który obraz (digest) naprawdę działa w każdym podzie |
| `-v ~/katalog/plik.crt:/certs/plik.crt:ro` | podpięcie **pojedynczego pliku** tylko do odczytu – kontener nie widzi reszty katalogu |
| `docker compose up -d` | uruchamia wszystkie usługi z `docker-compose.yml` w tle (zmienne bierze z `.env` obok) |
| `docker compose ps` / `docker compose logs -f USŁUGA` | stan kontenerów z tego pliku / logi jednej usługi na żywo |
| `docker compose rm -sf USŁUGA` | zatrzymuje (`-s`) i bez pytania (`-f`) usuwa kontener jednej usługi; wolumen zostaje |
| `docker volume rm monitoring-vm_uptime-kuma-data` | usuwa wolumen z danymi (nieodwracalne – np. pusta baza przed zmianą wersji) |
| `cut -d= -f1 .env` | same nazwy zmiennych z pliku, bez wartości (sprawdzenie pliku z hasłem bez wypisywania hasła) |

Kolejność przy własnym obrazie: **build → push → `k apply`** (raz na każdą wersję obrazu).
Szczegóły: [własny obraz](etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md).

## DNS, certyfikaty i HTTPS

| Polecenie | Co robi |
|---|---|
| 🪟 `nslookup NAZWA` / `Resolve-DnsName NAZWA` | jaki IP ma nazwa i który serwer DNS odpowiedział |
| 🪟 `ping NAZWA` | szybki test, czy Windows zna nazwę (np. z pliku `hosts`) |
| `NAZWA.192.168.180.51.nip.io` | nip.io – nazwa, która sama zwraca IP zapisany w środku; bez wpisu w `hosts` |
| `openssl genrsa -out ca.key 4096` | klucz prywatny (tu: dla CA); `chmod 600` |
| `openssl req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=…" -out ca.crt` | certyfikat własnego CA |
| `openssl req -new -key tls.key -subj "/CN=NAZWA" -out X.csr` | wniosek o certyfikat serwera (CSR) |
| `openssl x509 -req -in X.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -sha256 -extfile X.ext -out tls.crt` | CA podpisuje certyfikat; w `X.ext` `subjectAltName=DNS:NAZWA` |
| `openssl x509 -in tls.crt -noout -subject -issuer -dates -ext subjectAltName` | dla kogo, kto podpisał, ważność, nazwy |
| `openssl verify -CAfile ca.crt tls.crt` | czy certyfikat jest podpisany przez to CA |
| `openssl x509 -in tls.crt -noout -pubkey \| sha256sum` i `openssl pkey -in tls.key -pubout \| sha256sum` | czy klucz pasuje do certyfikatu – skróty muszą być identyczne |
| `kubectl create secret tls NAZWA --cert=tls.crt --key=tls.key -n NS` | certyfikat i klucz do klastra; Ingress wskazuje go w `tls.secretName` |
| `curl --cacert ca.crt https://…` / `curl -k https://…` | HTTPS z zaufaniem do własnego CA / bez sprawdzania certyfikatu |
| 🪟 `Import-Certificate -FilePath ca.crt -CertStoreLocation Cert:\CurrentUser\Root` | Windows ufa CA labu (tylko Twoje konto) |
| 🪟 `curl.exe --ssl-no-revoke https://…` | pomija sprawdzanie unieważnienia (`CRYPT_E_NO_REVOCATION_CHECK` przy własnym CA) |

Ćwiczenia: [Ingress, nip.io i HTTPS](etap-3-monitoring/13-cwiczenia-ingress.md).

## Ansible (ad-hoc)

🐧 Na `monitoring`, w `~/k3s-monitoring-lab/ansible`.

| Polecenie | Co robi |
|---|---|
| `ansible k3s_cluster -b -m file -a "path=PLIK state=absent"` | usuwa plik na wszystkich węzłach k3s (`-b` – jako root) |
| `ansible k3s_server -b -m systemd -a "name=k3s state=restarted"` | restart k3s na masterze |
| `ansible k3s_agents -b -f 1 -m systemd -a "name=k3s-agent state=restarted"` | restart agentów po jednym węźle (`-f 1`) |
| `ansible k3s-worker-1 -b -m shell -a "polecenie"` | dowolne polecenie na jednej maszynie |
| `ansible-playbook site.yml --syntax-check` | tylko składnia YAML i playbooka, nic nie łączy się z maszynami |
| `ansible-lint roles/common` | dobre praktyki w roli (instalacja: `pipx install ansible-lint`) |
| `ansible-playbook playbooks/prepare.yml --limit k3s-master --check --diff` | „na sucho”: co by się zmieniło na jednej maszynie, bez zmieniania |

Teoria: [Ansible](etap-2-k3s-ansible/01-teoria-ansible.md).

## Sieć, firewall i maszyny VMware

| Polecenie | Co robi |
|---|---|
| 🐧 `nc -zv -w 3 192.168.180.51 6443` | czy port TCP jest otwarty; timeout zwykle = firewall po drodze |
| 🐧 `sudo ufw status numbered` | reguły ufw z numerami (do `sudo ufw delete NUMER`) |
| 🐧 `sudo ufw allow from 192.168.180.54 to any port 6443 proto tcp` | wpuść jeden adres na jeden port (ręcznie – potem to samo w Ansible) |
| 🪟 `Get-Process vmware-vmx` | działające maszyny VMware (jeden proces na maszynę) |
| 🪟 `Get-ChildItem "FOLDER_MASZYNY" -Filter *.lck` | blokady plików maszyny; po awarii hosta mogą zostać |
| 🪟 `resmon` | Monitor zasobów → Procesor → Skojarzone dojścia: który proces trzyma plik |

Opis awarii: [blokady .lck](etap-4-monitoring-zewnetrzny/problemy.md#vmware-cannot-open-the-disk--pozostałe-blokady-lck).

**Diagnoza zawieszenia hosta** (🪟 PowerShell, sam odczyt):

| Polecenie | Co robi |
|---|---|
| `Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=(Get-Date).AddDays(-30)}` | nieczyste wyłączenia z 30 dni (41 – start po awarii, 6008 – „poprzednie zamknięcie było nieoczekiwane”) |
| `Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=(Get-Date '2026-11-05 19:30'); EndTime=(Get-Date '2026-11-05 20:30')}` | błędy i ostrzeżenia z okna czasu wokół awarii |
| `Get-ChildItem C:WindowsMinidump` | zrzuty po niebieskim ekranie; pusto = zawieszenie, nie BSOD |
| `Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'}` | błędy sprzętu zgłoszone przez procesor/pamięć/PCIe |
| `Get-CimInstance Win32_OperatingSystem | Select TotalVisibleMemorySize, FreePhysicalMemory` | RAM całkowity i wolny (w KB) |
| `Select-String -Path "…k3s-masterk3s-master.vmx" -Pattern '^memsize|^numvcpus'` | ile RAM i procesorów dostała maszyna VMware |
| `Select-String -Path "…k3s-mastermware-2.log" -Pattern '^2026-11-05T19:'` | wpisy z logu VMware z danej godziny (**czas w UTC**, w Polsce zimą +1 h) |
| `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` | `True` = działa Hyper-V, VMware pracuje na nim (tryb ULM) |
| `(Get-ItemProperty 'HKLM:HARDWAREDESCRIPTIONSystemCentralProcessor ').'Update Revision'` | wersja mikrokodu procesora (bajty od tyłu: `41 1 0 0` = 0x129) |
| `Get-CimInstance Win32_BIOS | Select SMBIOSBIOSVersion, ReleaseDate` | wersja i data BIOS-u |

Opis: [host zawiesza się razem z maszynami](etap-0-maszyny-wirtualne/problemy.md#host-zawiesza-się-razem-z-maszynami).

## Git

| Polecenie | Co robi |
|---|---|
| `git clone https://github.com/pnowy/kubernetes-course.git ~/kubernetes-course` | pobiera repozytorium |
| `git pull` | dociąga zmiany |
| `git diff` | co zmieniłeś w plikach |
| `git checkout .` | cofa niezapisane zmiany we wszystkich plikach |
