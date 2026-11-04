"""预览服务器：找不到的路径一律回落 index.html，避免随手贴错 URL 就 404。"""

import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

ROOT = os.path.dirname(os.path.abspath(__file__))


class PreviewHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        target = os.path.join(ROOT, path.lstrip("/"))
        if not os.path.exists(target) or os.path.isdir(target) and not os.path.exists(
            os.path.join(target, "index.html")
        ):
            self.path = "/index.html"
        return super().do_GET()

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 8787), PreviewHandler)
    print("serving on http://127.0.0.1:8787", flush=True)
    server.serve_forever()
