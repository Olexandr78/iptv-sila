from __future__ import annotations

import json
import os
import re
import socket
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
WEB = ROOT / "web"
CONFIG = ROOT / "config.json"
DEFAULT_CONFIG = {"playlist_url": "", "playlist_file": "playlist.m3u", "port": 8765}


def config():
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
        return {**DEFAULT_CONFIG, **data}
    except (OSError, json.JSONDecodeError):
        return DEFAULT_CONFIG.copy()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/config":
            self.send_json({"playlist_url": config()["playlist_url"]})
            return
        if path == "/api/playlist":
            self.serve_playlist()
            return
        super().do_GET()

    def send_json(self, value, status=200):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def serve_playlist(self):
        cfg = config()
        url = cfg.get("playlist_url", "").strip()
        if url:
            import urllib.request
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "IPTV-SILA/1.0"})
                with urllib.request.urlopen(req, timeout=15) as response:
                    data = response.read(8 * 1024 * 1024)
            except Exception as exc:
                self.send_json({"error": f"Не удалось загрузить плейлист: {exc}"}, 502)
                return
        else:
            file = ROOT / cfg.get("playlist_file", "playlist.m3u")
            if not file.is_file():
                self.send_json({"error": "Добавь playlist.m3u рядом с server.py или укажи playlist_url в config.json."}, 404)
                return
            data = file.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "audio/x-mpegurl; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("[IPTV-SILA] " + (fmt % args))


def lan_ip():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


if __name__ == "__main__":
    port = int(os.environ.get("IPTV_PORT", config()["port"]))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print("\nIPTV-SILA запущен!")
    print(f"Этот компьютер: http://127.0.0.1:{port}")
    print(f"Телефоны и другие ПК в одной Wi-Fi сети: http://{lan_ip()}:{port}")
    print("Остановка: Ctrl+C\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nСервер остановлен.")
    finally:
        server.server_close()
