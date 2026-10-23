#!/usr/bin/env python3
"""Development-only literal-loopback stand-in for Komari 1.6.0's three read
endpoints, for the opt-in Komari integration test. Synthetic nodes only; not a
Komari acceptance harness (Go's scripts/accept_komari.py runs the official
binary). Usage: fake-komari.py --ready-file ABS_PATH (the path must not exist)."""
import datetime, json, os, signal, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = 'synthetic-komari-admin-key-0001'
NODES = [
    {'id': 'd4c8d9a1-4ec5-4c1b-9b95-4c1c8f930b0d', 'name': 'Tokyo edge', 'public': True, 'cpu': 12.5, 'cores': 4,
     'ram': (3221225472, 8589934592), 'disk': (21474836480, 107374182400)},
    {'id': '7f0c1e2a-3b4d-4e5f-8a9b-0c1d2e3f4a5b', 'name': 'Frankfurt build', 'public': True, 'cpu': 63.0, 'cores': 16,
     'ram': (27917287424, 34359738368), 'disk': (751619276800, 1099511627776)},
    {'id': '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d', 'name': 'Home NAS', 'public': False, 'cpu': 4.0, 'cores': 2,
     'ram': (1073741824, 4294967296), 'disk': (7696581394432, 15393162788864)},
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        authed = self.headers.get('Authorization') == 'Bearer ' + KEY
        denied = {'status': 'error', 'message': 'Unauthorized'}
        if self.path == '/api/admin/client/list':
            # A raw array, with fields topo must discard.
            if not authed:
                return self.send(401, denied)
            return self.send(200, [{'uuid': n['id'], 'name': n['name'], 'token': 'agent-token', 'hidden': not n['public']} for n in NODES])
        if self.path == '/api/nodes':
            shown = [{'uuid': n['id'], 'name': n['name']} for n in NODES if n['public'] or authed]
            return self.send(200, {'status': 'success', 'message': '', 'data': shown})
        if self.path.startswith('/api/recent/'):
            node = next((n for n in NODES if n['id'] == self.path[len('/api/recent/'):]), None)
            if node is None:
                return self.send(200, {'status': 'success', 'message': '', 'data': []})
            if not node['public'] and not authed:
                return self.send(401, denied)
            now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
            return self.send(200, {'status': 'success', 'message': '', 'data': [{
                'uuid': node['id'], 'updated_at': now, 'cpu': {'usage': node['cpu'], 'cores': node['cores']},
                'ram': {'used': node['ram'][0], 'total': node['ram'][1]},
                'disk': {'used': node['disk'][0], 'total': node['disk'][1]}, 'message': ''}]})
        self.send(404, {'status': 'error', 'message': 'Not found'})


if __name__ == '__main__':
    ready = sys.argv[sys.argv.index('--ready-file') + 1]
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    with open(ready, 'x') as f:
        json.dump({'url': f'http://127.0.0.1:{server.server_address[1]}', 'key': KEY,
                   'nodes': [{'id': n['id'], 'name': n['name'], 'public': n['public']} for n in NODES]}, f)
    print(ready, flush=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        os.unlink(ready)
