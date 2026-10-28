# 2. Instalacja klastra k3s

## Węzeł sterujący

```bash
sudo ./scripts/01-install-master.sh
```

Na końcu skrypt wyświetli **token**. Wpisz go jako `K3S_TOKEN` w pliku `lab.env` na obu workerach.

Co ustawia skrypt:

| Parametr | Po co |
|---|---|
| `--node-ip`, `--advertise-address` | węzeł przedstawia się stałym adresem IP |
| `--flannel-iface` | ruch między podami idzie właściwym interfejsem |
| `--node-taint ...:NoSchedule` | na masterze nie uruchamiają się zwykłe aplikacje |

## Workery

```bash
sudo ./scripts/02-install-worker.sh 192.168.1.52   # na k3s-worker-1
sudo ./scripts/02-install-worker.sh 192.168.1.53   # na k3s-worker-2
```

## Kontrola

```bash
sudo ./scripts/03-post-install.sh
```

Oczekiwany wynik:

```
NAME           STATUS   ROLES                  ...
k3s-master     Ready    control-plane,master   ...
k3s-worker-1   Ready    worker                 ...
k3s-worker-2   Ready    worker                 ...
```

## kubectl i k9s na własnym komputerze

```bash
./scripts/get-kubeconfig.sh <użytkownik-ssh>
export KUBECONFIG=~/.kube/k3s-lab.kubeconfig
kubectl get nodes
k9s
```

## Najczęstsze problemy

- **Worker nie dołącza:** sprawdź `K3S_TOKEN`, łączność z `MASTER_IP:6443` i logi `sudo journalctl -u k3s-agent -f`.
- **Pody na różnych węzłach się nie komunikują:** zła nazwa interfejsu w `IFACE` – sprawdź `ip a`.
- **Węzeł w stanie NotReady:** `kubectl describe node <nazwa>` – sekcja *Conditions* i *Events*.
