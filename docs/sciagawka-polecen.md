# Ściągawka poleceń

Polecenia omawiane w trakcie budowy labu, zebrane w jednym miejscu i pogrupowane tematycznie.
Przy każdym: co robi i gdzie jest opisane dokładniej. Plik jest uzupełniany na bieżąco.

Oznaczenia: 🪟 Windows (PowerShell / Git Bash), 🐧 maszyna Linux przez SSH.
`k` = `kubectl` (alias z [ćwiczeń z kubectl](etap-2-k3s-ansible/05-cwiczenia-kubectl.md#skrót-k-zamiast-kubectl-opcjonalnie)).

## Spis treści

1. [Linux – tekst i pliki](#linux--tekst-i-pliki)
2. [Linux – użytkownicy i grupy](#linux--użytkownicy-i-grupy)
3. [kubectl – oglądanie](#kubectl--oglądanie)
4. [kubectl – tworzenie, zmiany, usuwanie](#kubectl--tworzenie-zmiany-usuwanie)
5. [kubectl – wdrożenia i wersje](#kubectl--wdrożenia-i-wersje)
6. [kubectl – diagnoza](#kubectl--diagnoza)
7. [kubectl – konta i tokeny](#kubectl--konta-i-tokeny)
8. [Helm](#helm)
9. [Docker i rejestr](#docker-i-rejestr)
10. [Ansible (ad-hoc)](#ansible-ad-hoc)
11. [Git](#git)

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

Problem z tym związany: `permission denied … docker.sock` – sesja otwarta przed dodaniem do grupy.

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
| `k -n NS get endpoints NAZWA` | do których podów Service kieruje ruch |
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
| `k delete -f plik.yaml` | usuwa obiekty opisane w pliku |
| `k delete namespace NS` | usuwa namespace **ze wszystkim w środku** |
| `k -n NS delete all --all` | czyści typowe obiekty, namespace zostaje |
| `k -n NS delete pod NAZWA` | usuwa pod (Deployment postawi nowy) |
| `k -n NS scale deployment web --replicas=4` | zmienia liczbę kopii |
| `k -n NS expose deployment web --port=80 --type=NodePort` | tworzy Service do Deploymentu |

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
| `helm get values NAZWA -n NS` | ustawienia podane przez Ciebie (`-a` – wszystkie) |
| `helm rollback NAZWA 1 -n NS` | powrót do rewizji 1 |
| `helm uninstall NAZWA -n NS` | usuwa release |

Teoria: [Helm](etap-3-monitoring/03-teoria-kubernetes-helm.md).

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

Kolejność przy własnym obrazie: **build → push → `k apply`** (raz na każdą wersję obrazu).
Szczegóły: [własny obraz](etap-4-monitoring-zewnetrzny/02-wlasny-obraz.md).

## Ansible (ad-hoc)

🐧 Na `monitoring`, w `~/k3s-monitoring-lab/ansible`.

| Polecenie | Co robi |
|---|---|
| `ansible k3s_cluster -b -m file -a "path=PLIK state=absent"` | usuwa plik na wszystkich węzłach k3s (`-b` – jako root) |
| `ansible k3s_server -b -m systemd -a "name=k3s state=restarted"` | restart k3s na masterze |
| `ansible k3s_agents -b -f 1 -m systemd -a "name=k3s-agent state=restarted"` | restart agentów po jednym węźle (`-f 1`) |
| `ansible k3s-worker-1 -b -m shell -a "polecenie"` | dowolne polecenie na jednej maszynie |

Teoria: [Ansible](etap-2-k3s-ansible/01-teoria-ansible.md).

## Git

| Polecenie | Co robi |
|---|---|
| `git clone https://github.com/pnowy/kubernetes-course.git ~/kubernetes-course` | pobiera repozytorium |
| `git pull` | dociąga zmiany |
| `git diff` | co zmieniłeś w plikach |
| `git checkout .` | cofa niezapisane zmiany we wszystkich plikach |
