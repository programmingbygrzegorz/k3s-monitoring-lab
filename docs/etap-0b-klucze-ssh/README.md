# Etap 0b – dostęp przez klucz SSH

Co powstaje: logowanie z Windowsa do każdej maszyny kluczem, po nazwie (`ssh k3s-master`).

Polecenia krok po kroku: [przewodnik, kroki 5–8](../00-przewodnik.md#etap-0b--dostęp-przez-klucz-ssh).

## Etap 0b w pigułce – zacznij tutaj

**Para kluczy zamiast hasła.** Klucz prywatny zostaje na Windowsie, publiczny wędruje na maszyny:

```
① Windows:   ssh-keygen → ~/.ssh/k3s-lab (prywatny, nigdy nie wysyłasz)
                          ~/.ssh/k3s-lab.pub (publiczny)
                  │
② Windows:   ~/.ssh/config – skróty: „k3s-master” = 192.168.180.51 + użytkownik + klucz
                  │
③ Maszyny:   klucz publiczny dopisany do ~/.ssh/authorized_keys na każdej z 5 maszyn
                  │
④ Test:      ssh k3s-master  → wchodzisz bez hasła
```

**Co powstało:**

| Gdzie | Plik | Po co |
|---|---|---|
| Windows | `~/.ssh/k3s-lab` | klucz prywatny – Twój „dowód tożsamości” |
| Windows | `~/.ssh/config` | nazwy zamiast adresów IP |
| Windows | `~/.ssh/known_hosts` | zapamiętane klucze hosta maszyn (ochrona przed podszyciem) |
| każda maszyna | `~/.ssh/authorized_keys` | lista kluczy, które mogą się logować |

Bez tego etapu Etap 1 wyłączyłby Ci dostęp: skrypt wyłącza logowanie hasłem przez SSH.

## Pliki w kolejności czytania

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-klucze-ssh.md](01-klucze-ssh.md) | teoria: klucz użytkownika i klucz hosta, `~/.ssh/config` |
| – | [problemy.md](problemy.md) | problemy z tego etapu |

Następny etap: [Etap 1 – przygotowanie systemu](../etap-1-przygotowanie-systemu/README.md).
