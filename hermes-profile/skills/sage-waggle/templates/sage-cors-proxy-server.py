#!/usr/bin/env python3
"""
Sage CORS proxy + static server (stdlib only).

Browsers block direct fetch() to data.sagecontinuum.org over CORS (esp. file://).
This serves the HTML in the same directory AND proxies the Sage query API, adding
CORS headers so a browser page can pull live data.

    python3 sage-cors-proxy-server.py
    # then open  http://localhost:8899/<your-page>.html?proxy=1
    # page should POST to /sage-proxy instead of the public API when ?proxy=1

No dependencies. Copy into a viz project and adjust PORT/SAGE if needed.
"""
import http.server, socketserver, urllib.request, json, os, webbrowser

PORT = int(os.environ.get("PORT", "8899"))
SAGE = "https://data.sagecontinuum.org/api/v1/query"
HERE = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=HERE, **k)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_POST(self):
        if self.path.rstrip("/") != "/sage-proxy":
            self.send_error(404); return
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            req = urllib.request.Request(SAGE, data=body,
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=25) as r:
                data = r.read()
            self.send_response(200); self._cors()
            self.send_header("Content-Type", "application/x-ndjson")
            self.end_headers(); self.wfile.write(data)
        except Exception as e:
            self.send_response(502); self._cors(); self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def log_message(self, format, *args):  # quiet
        pass


if __name__ == "__main__":
    url = f"http://localhost:{PORT}/"
    print(f"Sage proxy server on {url} (Ctrl-C to stop)")
    try:
        webbrowser.open(url)
    except Exception:
        pass
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped.")
