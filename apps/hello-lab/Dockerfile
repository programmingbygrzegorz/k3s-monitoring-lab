# Obraz aplikacji hello-lab – wersja końcowa z ćwiczeń (docs/etap-4-monitoring-zewnetrzny/03-cwiczenia-obraz.md).
# Budowanie (w katalogu apps/hello-lab):
#   docker build --build-arg APP_VERSION=1.0 -t hello-lab:1.0 .

# 1. Obraz bazowy: Debian z Pythonem, wersja "slim" bez narzędzi do kompilacji (~120 MB zamiast ~1 GB).
FROM python:3.14-slim

# 2. Wersja podawana przy budowie (--build-arg) i zapisana w obrazie jako zmienna środowiskowa.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1

# 3. Katalog roboczy – kolejne polecenia i aplikacja działają w /app.
WORKDIR /app

# 4. Zwykły użytkownik zamiast root. Ta warstwa jest PRZED kopiowaniem kodu,
#    więc zmiana app.py nie powoduje ponownego tworzenia użytkownika (cache).
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app

# 5. Kod aplikacji – zmienia się najczęściej, dlatego na końcu.
COPY app.py .

USER 10001

# 6. Dokumentacja: aplikacja słucha na 8080 (EXPOSE niczego nie otwiera).
EXPOSE 8080

# 7. Docker sprawdza co 30 s, czy aplikacja odpowiada (stan "healthy" w docker ps).
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz')"]

# 8. Polecenie startowe (forma JSON – Python dostaje sygnały, docker stop działa od razu).
CMD ["python", "app.py"]
