# Problemy administratora – metoda i problemy ogólne

Ten dokument zbiera **prawdziwe problemy**, które pojawiły się przy budowie tego laboratorium,
pogrupowane według etapów. Przy każdym: objaw, przyczyna, jak to zdiagnozować, jak naprawić
i czego uczy. Większość z nich spotkasz też w pracy – na serwerach, w chmurze, w automatyzacji.

Krótka ściągawka objaw → rozwiązanie jest w [przewodniku](00-przewodnik.md#najczęstsze-problemy).
Tutaj jest szerszy kontekst.

## Jak diagnozować – metoda ogólna

1. **Przeczytaj cały komunikat błędu**, nie tylko ostatnią linię. Ansible i systemd zwykle mówią
   wprost, co jest nie tak (`Timeout waiting for privilege escalation prompt`,
   `couldn't resolve module`).
2. **Ustal, gdzie jesteś.** Połowa zagadek to polecenie wpisane na złej maszynie. Patrz na znak
   zachęty: `PS C:\...>` to Windows, `user@nazwa:~$` to Linux – i *który* Linux.
3. **Sprawdź stan, nie zakładaj go.** `ip a`, `hostnamectl`, `cat plik`, `sudo --version`,
   `ansible-galaxy collection list` – jedno polecenie rozstrzyga, zamiast zgadywać.
4. **Zmieniaj jedną rzecz naraz** i sprawdzaj efekt.
5. **Miej punkt powrotu.** Snapshot przed każdym większym krokiem kosztuje sekundy.
6. **Zapisz rozwiązanie** – w kodzie (komentarz), w dokumentacji albo w tabeli problemów.

---

## Problemy według etapów

| Etap | Problemy |
|---|---|
| Etap 0 – sieć i maszyny wirtualne | [Adres maszyny zależny od Wi-Fi](etap-0-maszyny-wirtualne/problemy.md#adres-maszyny-zależny-od-wi-fi)<br>[Zła brama domyślna](etap-0-maszyny-wirtualne/problemy.md#zła-brama-domyślna)<br>[Ten sam MAC na kilku klonach](etap-0-maszyny-wirtualne/problemy.md#ten-sam-mac-na-kilku-klonach)<br>[Wspólny machine-id i klucze SSH hosta](etap-0-maszyny-wirtualne/problemy.md#wspólny-machine-id-i-klucze-ssh-hosta)<br>[Wspólny klucz hosta wykryty dopiero po zbudowaniu klastra](etap-0-maszyny-wirtualne/problemy.md#wspólny-klucz-hosta-wykryty-dopiero-po-zbudowaniu-klastra)<br>[cloud-init przywraca stary adres i nazwę](etap-0-maszyny-wirtualne/problemy.md#cloud-init-przywraca-stary-adres-i-nazwę)<br>[Zmienna pusta w nowej sesji](etap-0-maszyny-wirtualne/problemy.md#zmienna-pusta-w-nowej-sesji)<br>[Instalacja z ISO trwa długo](etap-0-maszyny-wirtualne/problemy.md#instalacja-z-iso-trwa-długo) |
| Etap 0b – klucze SSH | [Polecenie wpisane na złej maszynie](etap-0b-klucze-ssh/problemy.md#polecenie-wpisane-na-złej-maszynie)<br>[Windows nie ma ssh-copy-id](etap-0b-klucze-ssh/problemy.md#windows-nie-ma-ssh-copy-id) |
| Etap 1 – przygotowanie systemu | [PasswordAuthentication no nie działa](etap-1-przygotowanie-systemu/problemy.md#passwordauthentication-no-nie-działa)<br>[Skrypt bez prawa wykonywania](etap-1-przygotowanie-systemu/problemy.md#skrypt-bez-prawa-wykonywania)<br>[Duplikaty po ponownym uruchomieniu](etap-1-przygotowanie-systemu/problemy.md#duplikaty-po-ponownym-uruchomieniu) |
| Etap 2 – klaster k3s przez Ansible | [Ansible nie może przejść na roota (sudo-rs)](etap-2-k3s-ansible/problemy.md#ansible-nie-może-przejść-na-roota-sudo-rs)<br>[Ansible nie działa na Windowsie](etap-2-k3s-ansible/problemy.md#ansible-nie-działa-na-windowsie)<br>[ansible-lint nie widzi modułów](etap-2-k3s-ansible/problemy.md#ansible-lint-nie-widzi-modułów)<br>[Zmienna z inventory ignorowana](etap-2-k3s-ansible/problemy.md#zmienna-z-inventory-ignorowana)<br>[Cudzysłowy i dzielenie argumentów](etap-2-k3s-ansible/problemy.md#cudzysłowy-i-dzielenie-argumentów) |
| Etap 3 – monitoring w klastrze | [kubectl działa, a Helm nie widzi klastra](etap-3-monitoring/problemy.md#kubectl-działa-a-helm-nie-widzi-klastra)<br>[ErrImagePull przez chwilowy błąd DNS](etap-3-monitoring/problemy.md#errimagepull-przez-chwilowy-błąd-dns)<br>[AlertmanagerFailedToSendAlerts zaraz po instalacji](etap-3-monitoring/problemy.md#alertmanagerfailedtosendalerts-zaraz-po-instalacji) |

---

## Bezpieczeństwo i repozytorium

### Sekrety i prywatne dane poza gitem

- **Problem:** hasła (Grafana, sudo w Packerze), adresy własnej sieci, prywatne notatki łatwo
  wypchnąć do publicznego repozytorium.
- **Rozwiązanie:** w repo tylko wzory (`lab.env.example`, `inventory.ini.example`,
  `*.pkrvars.hcl.example`), prawdziwe pliki w `.gitignore`; prywatne pliki lokalnie w
  `.git/info/exclude`.
- **Gdy już trafiło do gita:** usunięcie pliku w nowym commicie **nie wystarcza** – zostaje w
  historii. Trzeba przepisać historię i wykonać `git push --force`, a hasło i tak uznać za ujawnione
  i zmienić.

### CI nie działa

- **Objaw:** GitHub Actions nie uruchamia się (blokada rozliczeń konta).
- **Rozwiązanie:** te same kontrole lokalnie: `ansible-lint`, `yamllint`, `shellcheck`.
- **Wniosek:** automatyczne kontrole to wygoda, nie jedyna linia obrony – trzeba umieć je
  uruchomić ręcznie.

## Środowisko pracy

### Awaria komputera w trakcie pracy

- **Objaw:** komputer wyłączył się podczas robienia snapshotów.
- **Skutek:** maszyny przetrwały; po ponownym uruchomieniu sprawdzono ich stan i działano dalej.
- **Wniosek:** snapshoty i dokumentacja każdego kroku sprawiają, że awaria kosztuje minuty,
  a nie odbudowę od zera. To ta sama idea co kopie zapasowe i *runbooki* w produkcji.

## Co powiedzieć na rozmowie

> „Przy budowie laboratorium najwięcej czasu zajęły nie instalacje, tylko diagnozowanie:
> zduplikowane MAC i machine-id po klonowaniu, cloud-init cofający konfigurację sieci, kolejność
> plików drop-in w sshd, pierwszeństwo zmiennych w Ansible i sudo-rs w nowym Ubuntu, którego
> Ansible nie obsługiwał. Każdy problem rozwiązywałem od sprawdzenia faktycznego stanu, a
> rozwiązanie zapisywałem w kodzie i dokumentacji, żeby nie wróciło.”
