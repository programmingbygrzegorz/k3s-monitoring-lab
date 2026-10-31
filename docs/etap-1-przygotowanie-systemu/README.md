# Etap 1 – przygotowanie systemu

Co powstaje: `/etc/hosts`, aktualizacje, wyłączony swap, SSH tylko kluczem i firewall na każdej maszynie.

Polecenia krok po kroku: [przewodnik, kroki 9–14](../00-przewodnik.md#etap-1--przygotowanie-systemu).
Skrypt: [scripts/00-prepare-node.sh](../../scripts/00-prepare-node.sh).

## Etap 1 w pigułce – zacznij tutaj

**Jeden skrypt, uruchomiony na każdej maszynie osobno.** Ustawienia (adresy, sieć
administratora) czyta z pliku `lab.env`:

```
① Ty:      ssh -t k3s-master "cd ~/k3s-monitoring-lab && sudo ./scripts/00-prepare-node.sh k3s-master"
                │   (to samo dla worker-1, worker-2, worker-3, monitoring)
② Skrypt:  ├── hostname i /etc/hosts  → maszyny znają się po nazwach
           ├── aktualizacje pakietów
           ├── swap wyłączony          → wymaganie Kubernetesa
           ├── SSH tylko kluczem       → tylko gdy klucz już jest (inaczej byś się zablokował)
           └── firewall ufw            → otwarte tylko potrzebne porty
                │
③ Test:    hostname; systemctl is-active ufw; swapon --show  → snapshot „czysty-system”
```

**Co jest otwarte w firewallu (ufw)** – reszta ruchu przychodzącego jest blokowana:

| Port / źródło | Na których maszynach | Po co |
|---|---|---|
| 22 z sieci administratora | wszystkie | SSH |
| wszystko z innych węzłów k3s | węzły k3s | komunikacja w klastrze |
| `10.42.0.0/16`, `10.43.0.0/16` | węzły k3s | sieć podów i usług k3s |
| 6443 z sieci administratora | węzły k3s | API Kubernetesa (kubectl) |
| 80, 443 | węzły k3s | Ingress (strony WWW w klastrze) |
| 30000–32767 z sieci administratora i z `monitoring` | węzły k3s | NodePorty – stąd Prometheus `:30090`, Grafana `:30300` |
| 3000, 3001 z sieci administratora | tylko `monitoring` | Grafana i Uptime Kuma z Etapu 4 |

W Etapie 2 to samo robi rola Ansible `common` – skrypt pokazuje, co dzieje się pod spodem.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-skrypt-prepare-node.md](01-skrypt-prepare-node.md) | co robi każda część skryptu |
| – | [problemy.md](problemy.md) | problemy z tego etapu: sshd, uprawnienia, duplikaty |

Następny etap: [Etap 2 – klaster k3s przez Ansible](../etap-2-k3s-ansible/README.md).
