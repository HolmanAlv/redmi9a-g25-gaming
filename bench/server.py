#!/usr/bin/env python3
"""Serve bench.html to the phone (via adb reverse) and store each POSTed phase in OUT/<profile>.jsonl."""
import http.server
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(sys.argv[1]).resolve()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self):
        rec = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(OUT / f"{rec['profile']}.jsonl", "a") as f:
            f.write(json.dumps(rec) + "\n")
        if rec["phase"] not in ("sustained_tick", "ram_step"):
            print(rec["profile"], rec["phase"], flush=True)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


# Localhost only: the phone reaches it through `adb reverse`, nothing on the LAN does.
http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
