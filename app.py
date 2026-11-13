import json
import os
import socket
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

ENV = os.getenv("APP_ENV", "unknown")
VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("APP_PORT", "8000"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        routes = {
            "/health": {"status": "OK"},
            "/version": {"version": VERSION},
            "/environment": {"environment": ENV, "host": socket.gethostname()},
        }
        body = routes.get(self.path.rstrip("/"))
        code = 200 if body else 404
        data = json.dumps(body or {"error": "not found"}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        # log JSON ke stdout, dibaca lewat: docker logs <container>
        print(json.dumps({
            "time": datetime.now().isoformat(timespec="seconds"),
            "env": ENV,
            "version": VERSION,
            "request": fmt % args,
        }), flush=True)


print(f"demo-app {VERSION} ({ENV}) listen di port {PORT}", flush=True)
HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
