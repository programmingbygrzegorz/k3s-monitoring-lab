"""hello-lab – mała aplikacja WWW do ćwiczeń z budowania obrazu (Etap 4).

Tylko biblioteka standardowa Pythona, więc obraz nie potrzebuje pip ani pakietów.
Adresy:
  /         strona z wersją i nazwą poda (kontenera)
  /healthz  "ok" – do HEALTHCHECK w Dockerze i sond w Kubernetesie
  /api      to samo co / w formacie JSON
Ustawienia przez zmienne środowiskowe: APP_VERSION (wpisywana przy budowie), APP_COLOR, PORT.
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")
COLOR = os.environ.get("APP_COLOR", "#2b6cb0")
PORT = int(os.environ.get("PORT", "8080"))
HOSTNAME = socket.gethostname()

PAGE = """<!doctype html>
<html lang="pl"><head><meta charset="utf-8"><title>hello-lab</title></head>
<body style="font-family:sans-serif;background:{color};color:#fff;text-align:center;padding-top:15vh">
<h1>Witaj z hello-lab</h1>
<p>wersja: <b>{version}</b></p>
<p>kontener / pod: <b>{host}</b></p>
</body></html>
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_body(200, "text/plain", "ok\n")
        elif self.path == "/api":
            data = {"app": "hello-lab", "version": VERSION, "host": HOSTNAME}
            self.send_body(200, "application/json", json.dumps(data) + "\n")
        elif self.path == "/":
            self.send_body(200, "text/html; charset=utf-8",
                           PAGE.format(color=COLOR, version=VERSION, host=HOSTNAME))
        else:
            self.send_body(404, "text/plain", "nie ma takiej strony\n")

    def send_body(self, code, content_type, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    print(f"hello-lab {VERSION} słucha na porcie {PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
