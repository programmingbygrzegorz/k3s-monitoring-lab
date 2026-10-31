# Etap 0 – sieć i maszyny wirtualne – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## Adres maszyny zależny od Wi-Fi

- **Objaw:** maszyny w trybie *Bridged* dostają adresy z sieci domowej; po zmianie sieci Wi-Fi
  (inne miejsce, inny router) stałe adresy przestają pasować i klaster traci łączność.
- **Przyczyna:** Bridged wpina maszyny bezpośrednio w fizyczną sieć – adresacja zależy od routera.
- **Rozwiązanie:** sieć **NAT VMware (VMnet8)** – własna, stała podsieć wewnątrz komputera,
  niezależna od Wi-Fi. Maszyny wychodzą do internetu przez NAT, a adresy się nie zmieniają.
- **Wniosek:** w labie (i w chmurze – VPC) sieć projektuje się tak, żeby nie zależała od tego,
  gdzie akurat stoi sprzęt.

## Zła brama domyślna

- **Objaw:** po ustawieniu stałego IP brak internetu; `ping 8.8.8.8` nie odpowiada.
- **Przyczyna:** w VMnet8 `.1` to karta hosta (Windows), a bramą NAT i serwerem DNS jest **`.2`**.
  Intuicyjne „brama = .1” tu nie działa.
- **Diagnoza:** Windows: `ipconfig` (adres karty VMnet8); VMware: *Virtual Network Editor → NAT Settings*.
- **Wniosek:** nie zakładaj konwencji – sprawdź konfigurację konkretnej sieci.

## Ten sam MAC na kilku klonach

- **Objaw:** brama `.2` raz odpowiada, raz nie; maszyny „gubią” sieć na zmianę.
- **Przyczyna:** klony skopiowały adres MAC karty. Dwie karty z tym samym MAC w jednej sieci
  przejmują sobie nawzajem ruch.
- **Rozwiązanie:** VMware → *Network Adapter → Advanced → Generate* dla każdego klonu.
- **Wniosek:** klonowanie kopiuje *wszystko*, także to, co musi być unikalne.

## Wspólny machine-id i klucze SSH hosta

- **Objaw:** DHCP daje kilku klonom ten sam adres; `ssh` ostrzega o zmienionym kluczu hosta.
- **Przyczyna:** `/etc/machine-id` (z niego DHCP liczy identyfikator klienta) i klucze
  `/etc/ssh/ssh_host_*` zostały skopiowane z szablonu.
- **Diagnoza:** `cat /etc/machine-id` na każdym klonie – wartości muszą się różnić.
- **Rozwiązanie:** przed klonowaniem wyczyścić machine-id na szablonie (`truncate -s 0`), a na
  klonach wygenerować nowe: `systemd-machine-id-setup`, `ssh-keygen -A`. Automatycznie: rola
  `bootstrap` w Ansible wykrywa powtórzenia między maszynami.
- **Wniosek:** szablon trzeba „uogólnić” przed klonowaniem – w świecie Windows to `sysprep`,
  w chmurze robi to cloud-init przy pierwszym starcie.

## Wspólny klucz hosta wykryty dopiero po zbudowaniu klastra

- **Objaw:** `ssh k3s-master` z nowej maszyny pyta o klucz i dodaje: *This host key is known by
  the following other names/addresses* – ten sam klucz jest zapisany pod adresami innych maszyn.
- **Przyczyna:** przy ręcznej konfiguracji klonów pominięto `ssh-keygen -A` – master, dwa workery
  i `monitoring` miały klucz szablonu. Ansible tego nie zgłosił, bo miał `host_key_checking = False`.
- **Diagnoza:** porównanie odcisków wszystkich maszyn z jednego miejsca:
  ```bash
  for ip in 51 52 53 54 55; do ssh-keyscan -t ed25519 192.168.180.$ip 2>/dev/null | ssh-keygen -lf -; done
  ```
- **Rozwiązanie:**
  1. nowe klucze na klonach (master zachował swój):
     `ansible k3s-worker-1,k3s-worker-2,monitoring -b -K -m shell -a "rm -f /etc/ssh/ssh_host_* && ssh-keygen -A && systemctl restart ssh"`,
  2. stare wpisy usunięte z `known_hosts` (`ssh-keygen -R <nazwa lub adres>`) na każdym
     komputerze, z którego się łączysz,
  3. nowe odciski porównane z tym, co podaje sama maszyna
     (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, najlepiej w konsoli VMware), dopiero
     potem `yes`,
  4. w `ansible.cfg` włączone `host_key_checking = True` z `StrictHostKeyChecking=accept-new`.
- **Wniosek:** wyłączone zabezpieczenie nie tylko otwiera lukę, ale też **ukrywa błędy**.
  Ostrzeżenia SSH o kluczach czyta się, a nie odruchowo wpisuje `yes`.

## cloud-init przywraca stary adres i nazwę

- **Objaw:** po restarcie maszyna wraca do adresu z DHCP albo do nazwy szablonu.
- **Przyczyna:** cloud-init przy starcie generuje konfigurację sieci (`50-cloud-init.yaml`) i może
  ustawić nazwę hosta. Do tego zostały stare pliki Netplan, które wygrywają z nowym.
- **Rozwiązanie:** `network: {config: disabled}` i `preserve_hostname: true` w
  `/etc/cloud/cloud.cfg.d/`, stare pliki Netplan przeniesione, jeden plik `01-lab.yaml` z uprawnieniami `600`.
- **Wniosek:** gdy zmiana „sama się cofa”, coś ją nadpisuje przy starcie. Szukaj, kto zarządza plikiem.

## Zmienna pusta w nowej sesji

- **Objaw:** `sudo hostnamectl set-hostname $NAME` → *Too few arguments*.
- **Przyczyna:** zmienna ustawiona w poprzedniej sesji (lub ze spacją wokół `=`) – w nowej
  sesji jest pusta, więc polecenie dostaje o argument mniej.
- **Diagnoza:** `echo "$NAME"` przed użyciem.
- **Wniosek:** zmienne powłoki żyją tylko w bieżącej sesji. W skryptach – `set -u`, który
  przerywa przy pustej zmiennej.

## Instalacja z ISO trwa długo

- **Objaw:** Packer instaluje maszynę kilkanaście minut, a klon powstaje w sekundę.
- **Przyczyna:** Packer (`vmware-iso`) przechodzi pełną instalację systemu i aktualizacje.
- **Wniosek:** to cena powtarzalności – maszyna powstaje zawsze tak samo, z kodu. W praktyce
  Packerem buduje się raz *obraz* (szablon), a z niego szybko klonuje.
