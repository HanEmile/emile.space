#!/usr/bin/env python3
"""
Mini static file server with clean URLs.

If a request has no file extension (e.g. /about) and no exact match exists,
it tries appending .html (e.g. serves about.html). Requests for files that
already exist as-is (style.css, image.png, about.html, ...) are served
untouched.

Usage:
    python3 clean_url_server.py [port] [directory]

Defaults: port=8000, directory=current working directory
"""

import sys
import os
import functools
import http.server


class CleanURLHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        translated = super().translate_path(path)

        # Exact match (file or directory) -> serve as-is.
        if os.path.exists(translated):
            return translated

        # No extension and no exact match -> try appending .html.
        _, ext = os.path.splitext(translated)
        if not ext:
            candidate = translated + ".html"
            if os.path.isfile(candidate):
                return candidate

        return translated


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    directory = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

    handler = functools.partial(CleanURLHandler, directory=directory)
    with http.server.ThreadingHTTPServer(("", port), handler) as httpd:
        print(f"Serving {directory!r} at http://localhost:{port}/ "
              f"(extension-less URLs resolve to .html)")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down.")


if __name__ == "__main__":
    main()
