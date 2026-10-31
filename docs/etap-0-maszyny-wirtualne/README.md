# Etap 0 – sieć i maszyny wirtualne

Co powstaje: sieć NAT w VMware, szablon Ubuntu i klony ze stałymi adresami. Jedną maszynę
(`k3s-worker-3`) budujesz z kodu Packerem.

Polecenia krok po kroku: [przewodnik, kroki 1–4](../00-przewodnik.md#etap-0--sieć-i-maszyny-wirtualne).

## Etap 0 w pigułce – zacznij tutaj

**Jedna maszyna wzorcowa, z niej kopie.** Zamiast instalować Ubuntu pięć razy, instalujesz je
raz, a potem klonujesz:

```
① VMware:   sieć NAT VMnet8 (192.168.180.0/24, brama .2) – adresy nie zależą od Wi-Fi
                 │
② Szablon:  ubuntu-template – Ubuntu + OpenSSH, wyczyszczony machine-id, snapshot „czysty”
                 │  Manage → Clone
③ Klony:    każdy dostaje własną tożsamość: nowy machine-id i klucze hosta SSH,
            nazwę (hostname) i stały adres IP
                 │
④ Packer:   k3s-worker-3 zbudowany z kodu, z ISO – bez klikania (wersja „jak w firmie”)
```

**Co powstało – 5 maszyn:**

| Maszyna | Adres | Rola (od Etapu 2) |
|---|---|---|
| `k3s-master` | `192.168.180.51` | sterowanie klastrem |
| `k3s-worker-1` | `192.168.180.52` | uruchamia pody |
| `k3s-worker-2` | `192.168.180.53` | uruchamia pody |
| `k3s-worker-3` | `192.168.180.55` | uruchamia pody, zbudowany Packerem |
| `monitoring` | `192.168.180.54` | Ansible, później monitoring zewnętrzny |

Dlaczego tożsamość trzeba zmienić: klon to kopia 1:1 – bez zmian wszystkie maszyny miałyby ten
sam machine-id (konflikty adresów DHCP) i te same klucze hosta SSH.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-maszyny-wirtualne.md](01-maszyny-wirtualne.md) | sieć VMnet8, szablon, klonowanie, stałe adresy |
| 2 | [02-packer.md](02-packer.md) | nowa maszyna z ISO, zbudowana z kodu |
| – | [problemy.md](problemy.md) | problemy z tego etapu: sieć, klonowanie, Packer |

Następny etap: [Etap 0b – klucze SSH](../etap-0b-klucze-ssh/README.md).
