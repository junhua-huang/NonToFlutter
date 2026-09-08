"""Serve a fixed Flutter build under /nonto/ for the local control console."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class NontoHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        request_path = urlsplit(self.path).path
        if request_path == "/":
            self.send_response(302)
            self.send_header("Location", "/nonto/")
            self.end_headers()
            return
        if not request_path.startswith("/nonto/"):
            self.send_error(404)
            return
        relative = request_path.removeprefix("/nonto/")
        candidate = (Path(self.directory) / relative).resolve()
        root = Path(self.directory).resolve()
        if candidate != root and root not in candidate.parents:
            self.send_error(404)
            return
        if relative and candidate.is_file():
            self.path = "/" + relative
        else:
            self.path = "/index.html"
        super().do_GET()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    handler = lambda *values, **options: NontoHandler(*values, directory=str(root), **options)
    ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()
