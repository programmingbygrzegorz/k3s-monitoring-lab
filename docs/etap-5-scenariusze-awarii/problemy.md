# Etap 5 – scenariusze awarii – problemy

Prawdziwe problemy, które pojawiły się w tym etapie: objaw, przyczyna, diagnoza, rozwiązanie i wniosek.
Ogólna metoda diagnozowania i problemy niezwiązane z jednym etapem: [problemy ogólne](../problemy-ogolne.md).

## Error: flags cannot be placed before plugin name: -n

- **Objaw (10.11.2026):** `kubectl -n chaos describle pod chaos-oom-…` → `Error: flags cannot be placed before plugin name: -n`.
- **Przyczyna:** literówka `describle` zamiast `describe`. Kubectl nie zna takiego polecenia, więc uznaje je
  za zewnętrzną wtyczkę (plugin), a przed nazwą wtyczki nie wolno podawać opcji.
- **Rozwiązanie:** poprawić słowo na `describe`.
- **Wniosek:** dziwny komunikat o „pluginie” zwykle oznacza literówkę w nazwie polecenia.

## kubectl top pod pokazuje zupełnie inne pody

- **Objaw (10.11.2026):** `kubectl top pod` zamiast poda `chaos-oom-…` pokazał 5 podów `nginx-deployment-…`.
- **Przyczyna:** brak `-n chaos` – bez `-n` kubectl zawsze używa namespace'u `default`.
- **Rozwiązanie:** `kubectl top pod -n chaos`.
- **Wniosek:** gdy „podu nie ma” albo widać nie te pody – najpierw sprawdź `-n`.

## kubectl top: Metrics not available for pod

- **Objaw (10.11.2026):** `kubectl top pod -n chaos` → `error: Metrics not available for pod chaos/chaos-oom-…, age: 17m53s`.
- **Przyczyna:** pod był w `CrashLoopBackOff` – kontener żyje 1–2 s między restartami, a metrics-server
  zbiera dane co kilkanaście sekund i nie zdąży go zmierzyć.
- **Rozwiązanie:** najpierw naprawić pod; po ok. minucie od startu `top` pokazuje zużycie.
- **Wniosek:** brak metryk to objaw, nie przyczyna – sprawdź `get pods` i `describe`.
