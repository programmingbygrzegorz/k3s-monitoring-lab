# 7. Nowa maszyna z Packera

Zamiast klonować szablon i poprawiać każdy klon ręcznie (machine-id, klucze SSH, MAC, nazwa, IP),
Packer instaluje maszynę **od zera z ISO** – bez klikania, od razu z właściwą konfiguracją.
Przykład: dodatkowy węzeł `k3s-worker-3`.

## Co robi przepis

Pliki w `packer/`:

| Plik | Rola |
|---|---|
| `k3s-node.pkr.hcl` | przepis: maszyna w VMware Workstation, sieć NAT, kroki po instalacji |
| `user-data.pkrtpl.yaml` | autoinstall Ubuntu: użytkownik, stały IP, nazwa hosta, pakiety |
| `k3s-worker-3.pkrvars.hcl.example` | parametry maszyny (nazwa, IP, MAC, RAM, ISO) |
| `secrets.pkrvars.hcl.example` | użytkownik i hasło |

Przebieg `packer build`:

1. Packer tworzy maszynę w VMware i uruchamia instalator z ISO.
2. Wpisuje w menu startowym polecenie `autoinstall` z adresem swojego serwera HTTP, z którego
   instalator pobiera `user-data`.
3. Ubuntu instaluje się samo: użytkownik, OpenSSH, `open-vm-tools`, `git`, **stały IP od razu**,
   cloud-init bez zmian nazwy i sieci.
4. Po restarcie Packer łączy się przez SSH pod stałym adresem, dopisuje maszyny labu do
   `/etc/hosts` i klonuje repozytorium do `~/k3s-monitoring-lab`.
5. Wyłącza maszynę – gotowa leży w `output_directory`.

Świeża instalacja ma własny machine-id i klucze SSH, a MAC jest ustawiony w przepisie –
żadnych poprawek po klonowaniu.

## Przygotowanie

```powershell
winget install Hashicorp.Packer      # potem nowe okno PowerShell
cd k3s-monitoring-lab\packer
copy k3s-worker-3.pkrvars.hcl.example k3s-worker-3.pkrvars.hcl
copy secrets.pkrvars.hcl.example secrets.pkrvars.hcl
```

W `k3s-worker-3.pkrvars.hcl` uzupełnij ścieżkę do ISO, sumę kontrolną
(`Get-FileHash plik.iso`), adresy i `output_directory`. MAC musi być unikalny i z puli VMware
dla adresów statycznych: `00:50:56:00:00:00` – `00:50:56:3F:FF:FF`.

W `secrets.pkrvars.hcl` wpisz użytkownika, hasło i jego hash. Hash wygenerujesz na dowolnej
maszynie labu:

```bash
openssl passwd -6
```

Oba pliki `.pkrvars.hcl` są w `.gitignore`. Hasło nie może zawierać apostrofu `'`.

## Budowa

```powershell
packer init .
packer validate "-var-file=k3s-worker-3.pkrvars.hcl" "-var-file=secrets.pkrvars.hcl" .
packer build "-var-file=k3s-worker-3.pkrvars.hcl" "-var-file=secrets.pkrvars.hcl" .
```

- W PowerShell argumenty `-var-file=...` muszą być w cudzysłowie – bez tego PowerShell 5.1 rozbija
  je na kropce i Packer pokazuje tylko pomoc (`Usage: packer build`).
- Trwa to ok. 15–30 minut. **Nie klikaj w okno maszyny** – Packer wpisuje na nim polecenia.
- Przy pierwszym uruchomieniu Zapora Windows może zapytać o dostęp dla Packera – zezwól w sieciach
  prywatnych, inaczej instalator nie pobierze `user-data`.
- Na etapie `Waiting for SSH to become available...` Packer czeka na koniec instalacji – to normalne.

## Po budowie

1. VMware: **File → Open** → `k3s-worker-3.vmx` z `output_directory` i uruchom maszynę.
2. Sprawdź: `hostname`, `ip a`, `ping -c 3 k3s-master`.
3. Na pozostałych maszynach dopisz nowy węzeł do `/etc/hosts` i ustaw `WORKER3_IP` w `lab.env`
   (patrz [docs/02](02-instalacja-k3s.md)).
4. Dalej jak z każdym workerem: `00-prepare-node.sh k3s-worker-3`, potem `02-install-worker.sh`.

## Najczęstsze problemy

- **Instalator pokazuje zwykły kreator zamiast instalować sam:** `boot_command` nie trafił
  w menu GRUB. Zwiększ `boot_wait` (np. `10s`) i uruchom ponownie.
- **Packer wisi na `Waiting for SSH`:** sprawdź w oknie maszyny, czy instalacja się skończyła
  i czy maszyna ma adres z przepisu (`ip a`). Jeśli instalator nie pobrał `user-data`, sprawdź
  zaporę Windows.
- **`output_directory` already exists:** usuń folder po nieudanej próbie albo wybierz inny.
