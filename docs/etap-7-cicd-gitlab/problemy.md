# Etap 7 – CI/CD – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## packer validate: Missing plugins (github.com/hashicorp/vmware)

- **Objaw:** `packer validate` kończy się `Error: Missing plugins … github.com/hashicorp/vmware >= 1.1.0 …
  Did you run packer init for this project?`, choć ten sam przepis zbudował wcześniej worker-3.
- **Przyczyna:** pluginy Packera leżą osobno (`%APPDATA%\packer.d\plugins`), nie w repozytorium. Po miesiącu
  (aktualizacja Packera, czyszczenie katalogu) pluginu już nie było.
- **Diagnoza:** sam komunikat – nazwa pluginu i wersja z bloku `required_plugins` w `k3s-node.pkr.hcl`.
- **Rozwiązanie:** 🪟 `packer init .` w folderze `packer` – pobiera brakujące pluginy, potem `validate` → valid.
- **Wniosek:** `packer init` to odpowiednik `terraform init` / `ansible-galaxy install` – uruchamiaj go
  zawsze na nowym komputerze i po aktualizacji Packera.

## ssh gitlab: user@192.168.180.56: Permission denied (publickey)

- **Objaw:** po dopisaniu `Host gitlab` + `HostName 192.168.180.56` do `~/.ssh/config` połączenie
  odrzucone, a w komunikacie użytkownik **`user`** (nazwa konta Windows), nie `grzegorz`.
- **Przyczyna:** wspólne ustawienia (`User grzegorz`, `IdentityFile ~/.ssh/k3s-lab`, `IdentitiesOnly yes`)
  są w osobnym bloku `Host k3s-master … monitoring 192.168.180.*`. Wzorzec `Host` jest porównywany
  z nazwą **wpisaną w poleceniu** (`gitlab`), nie z `HostName` – więc `192.168.180.*` nie pasował.
- **Diagnoza:** nazwa użytkownika w komunikacie błędu; `ssh -G gitlab | findstr /b "user identityfile"`
  pokazuje ustawienia, które SSH naprawdę wybrał.
- **Rozwiązanie:** dopisać `gitlab` do linii `Host k3s-master k3s-worker-1 … monitoring gitlab 192.168.180.*`.
- **Wniosek:** nowa maszyna = dwa miejsca w `~/.ssh/config`: adres i grupa ze wspólnymi ustawieniami.
