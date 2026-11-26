from __future__ import annotations
import json, socket, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

class IPTVServer:
    def __init__(self, host="0.0.0.0", port=8765, playlist_file=None):
        self.playlist_file=Path(playlist_file).expanduser() if playlist_file else None
        owner=self
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                path=urlparse(self.path).path
                if path in ("/","/api/status"):
                    self._json({"name":"IPTV-СИЛА","status":"online","playlist":"/api/playlist"})
                elif path=="/api/playlist":
                    owner._playlist(self)
                else: self._json({"error":"Not found"},404)
            def _json(self,obj,status=200):
                body=json.dumps(obj,ensure_ascii=False).encode("utf-8")
                self.send_response(status); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Content-Length",str(len(body))); self.send_header("Access-Control-Allow-Origin","*"); self.end_headers(); self.wfile.write(body)
            def log_message(self,fmt,*args): print("[IPTV-СИЛА] "+(fmt%args))
        self.http=ThreadingHTTPServer((host,port),Handler)
        self.http.daemon_threads=True
        self.lan_ip=self._lan_ip()
        self.thread=None
    @staticmethod
    def _lan_ip():
        s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try: s.connect(("192.0.2.1",80)); return s.getsockname()[0]
        except OSError: return "127.0.0.1"
        finally: s.close()
    def _playlist(self,handler):
        if not self.playlist_file or not self.playlist_file.is_file():
            body=json.dumps({"error":"Укажи существующий M3U-файл в настройках сервера."},ensure_ascii=False).encode()
            handler.send_response(404); handler.send_header("Content-Type","application/json; charset=utf-8"); handler.send_header("Content-Length",str(len(body))); handler.end_headers(); handler.wfile.write(body); return
        data=self.playlist_file.read_bytes()
        handler.send_response(200); handler.send_header("Content-Type","application/vnd.apple.mpegurl; charset=utf-8"); handler.send_header("Content-Length",str(len(data))); handler.send_header("Access-Control-Allow-Origin","*"); handler.end_headers(); handler.wfile.write(data)
    def start(self):
        if self.thread and self.thread.is_alive(): return
        self.thread=threading.Thread(target=self.http.serve_forever,name="IPTV-SILA-HTTP",daemon=True); self.thread.start()
    def stop(self):
        if self.thread and self.thread.is_alive(): self.http.shutdown(); self.thread.join(timeout=3)
        self.http.server_close()
