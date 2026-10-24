"""Serves the web build so you can play in a browser on this PC, or on a
phone on the same Wi-Fi. Run:  python tools/play_web.py   (Ctrl+C to stop)"""
import functools
import http.server
import os
import socket
import socketserver

PORT = 8060
WEB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


def lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))  # sends nothing; just picks the Wi-Fi address
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")  # always load the newest build
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if not os.path.exists(os.path.join(WEB, "index.html")):
        raise SystemExit('No web build yet: export the "Web" preset to build/web first.')
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), functools.partial(Handler, directory=WEB)) as httpd:
        print("O Mago! Dhaka! is being served.")
        print(f"  On this PC:               http://localhost:{PORT}")
        print(f"  On a phone (same Wi-Fi):  http://{lan_ip()}:{PORT}")
        print("Press Ctrl+C to stop.")
        httpd.serve_forever()
