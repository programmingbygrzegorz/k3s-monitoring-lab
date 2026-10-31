# Etap 0b – klucze SSH – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## Polecenie wpisane na złej maszynie

- **Objaw:** `ssh k3s-master` pyta o hasło, choć klucz jest skonfigurowany.
- **Przyczyna:** polecenie wpisane w terminalu Linuxa (np. już na masterze), a klucz i
  `~/.ssh/config` są na Windowsie.
- **Wniosek:** zawsze patrz na znak zachęty. Dlatego przewodnik oznacza każdy krok 🪟 / 🖥️ / 🐧.

## Windows nie ma `ssh-copy-id`

- **Rozwiązanie:** `type klucz.pub | ssh user@host "cat >> ~/.ssh/authorized_keys"` – to samo,
  co robi `ssh-copy-id`, rozpisane ręcznie.
- **Wniosek:** warto wiedzieć, co narzędzie robi pod spodem – wtedy da się je zastąpić.
