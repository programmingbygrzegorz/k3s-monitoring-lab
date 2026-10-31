# Etap 0 – sieć i maszyny wirtualne

Co powstaje: sieć NAT w VMware, szablon Ubuntu i klony ze stałymi adresami. Jedną maszynę
(`k3s-worker-3`) budujesz z kodu Packerem.

Polecenia krok po kroku: [przewodnik, kroki 1–4](../00-przewodnik.md#etap-0--sieć-i-maszyny-wirtualne).

| Kolejność | Plik | Co w nim jest |
|---|---|---|
| 1 | [01-maszyny-wirtualne.md](01-maszyny-wirtualne.md) | sieć VMnet8, szablon, klonowanie, stałe adresy |
| 2 | [02-packer.md](02-packer.md) | nowa maszyna z ISO, zbudowana z kodu |
| – | [problemy.md](problemy.md) | problemy z tego etapu: sieć, klonowanie, Packer |

Następny etap: [Etap 0b – klucze SSH](../etap-0b-klucze-ssh/README.md).
