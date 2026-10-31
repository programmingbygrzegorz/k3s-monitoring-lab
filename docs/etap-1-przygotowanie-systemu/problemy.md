# Etap 1 – przygotowanie systemu – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## `PasswordAuthentication no` nie działa

- **Objaw:** po wyłączeniu logowania hasłem SSH dalej je przyjmuje.
- **Przyczyna:** pliki w `/etc/ssh/sshd_config.d/` są czytane **alfabetycznie**, a dla większości
  opcji **wygrywa pierwsza** wartość. Ubuntu ma `50-cloud-init.conf` z `PasswordAuthentication yes`,
  więc nasz `99-lab.conf` przegrywał.
- **Diagnoza:** `sudo sshd -T | grep passwordauthentication` – efektywna konfiguracja.
  Test: `ssh -o PubkeyAuthentication=no host` ma dać `Permission denied (publickey)`.
- **Rozwiązanie:** plik `01-lab.conf` – czytany przed `50-cloud-init.conf`.
- **Wniosek:** przy plikach typu *drop-in* kolejność ma znaczenie, a reguła „pierwsza czy ostatnia
  wygrywa” różni się między programami. Sprawdzaj konfigurację efektywną, nie tylko plik.

## Skrypt bez prawa wykonywania

- **Objaw:** `sudo: cannot execute ...: Permission denied`.
- **Przyczyna:** pliki zapisane na Windowsie trafiły do gita bez bitu wykonywania.
- **Rozwiązanie:** `git update-index --chmod=+x scripts/*.sh` i commit (tryb `100755`).
- **Wniosek:** Windows nie zna uprawnień uniksowych – przy pracy między systemami trzeba
  je ustawiać w gicie jawnie.

## Duplikaty po ponownym uruchomieniu

- **Objaw:** w `/etc/hosts` te same maszyny po kilka razy.
- **Przyczyna:** skrypt dopisywał wpisy bez sprawdzania, czy już są; później Ansible dodał
  własny blok obok wpisów skryptu.
- **Rozwiązanie:** skrypt najpierw usuwa stare wpisy, a rola `common` usuwa wpisy skryptu
  przed zapisaniem swojego bloku (`blockinfile`). Próba na sucho (`--check --diff`) pokazała
  problem, zanim cokolwiek się zmieniło.
- **Wniosek:** **idempotentność** – uruchomienie drugi raz nie może psuć. Przy przejściu
  ze skryptów na Ansible trzeba posprzątać po starym sposobie.
