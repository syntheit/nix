"""Private NanoMDM-netns HTTP to Deus Unix-socket DDM transport.

The bridge has no secrets, DNS, proxy support, or published port. NanoMDM and
Deus authenticate request and response bodies with their own HMAC keys.
"""

import http.client
import os
import re
import socket
import stat
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http import HTTPStatus


LISTEN = ("127.0.0.1", 9992)
SOCKET = "/run/ddm-private/socket"
MAX_DDM_BODY = 1 << 20
MAX_RECEIPT_BODY = 2048
MAX_RESPONSE_BODY = 1 << 20
DECLARATION = re.compile(
    r"/declaration/(?:activation|configuration|asset|management)/"
    r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z"
)
# stdlib's default header parser accepts 100 lines of 64 KiB each. This is a
# single-purpose process, so constrain its private parser limits as well as
# checking the aggregate size after parsing.
http.client._MAXLINE = 4096
http.client._MAXHEADERS = 32


def allowed_request(method, path):
    if method == "GET":
        return path in ("/tokens", "/declaration-items") or bool(
            DECLARATION.fullmatch(path)
        )
    return (method, path) in (
        ("PUT", "/status"),
        ("POST", "/v1/command-receipts"),
    )


def check_socket(path=SOCKET):
    directory = os.path.dirname(path)
    if os.path.realpath(directory) != directory:
        raise RuntimeError("DDM socket directory must not contain symlinks")
    dir_info = os.lstat(directory)
    socket_info = os.lstat(path)
    uid = os.geteuid()
    if (
        not stat.S_ISDIR(dir_info.st_mode)
        or stat.S_IMODE(dir_info.st_mode) != 0o700
        or dir_info.st_uid != uid
        or not stat.S_ISSOCK(socket_info.st_mode)
        or stat.S_IMODE(socket_info.st_mode) != 0o600
        or socket_info.st_uid != uid
    ):
        raise RuntimeError("DDM socket ownership or mode does not match bridge UID")


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, socket_path):
        super().__init__("localhost", timeout=5)
        self.socket_path = socket_path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.socket_path)


class BoundedHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler):
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(address, handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "ddm-bridge"
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, fmt, *args):
        # Never log paths, enrollment IDs, bodies, or signed headers.
        pass

    def handle_one_request(self):
        try:
            self.raw_requestline = self.rfile.readline(2049)
            if len(self.raw_requestline) > 2048:
                self.requestline = ""
                self.request_version = ""
                self.command = ""
                self.send_error(HTTPStatus.REQUEST_URI_TOO_LONG)
                return
            if not self.raw_requestline:
                self.close_connection = True
                return
            if not self.parse_request():
                return
            method = getattr(self, "do_" + self.command, None)
            if method is None:
                self._reject(405)
                return
            method()
            self.wfile.flush()
        except TimeoutError:
            self.close_connection = True

    def do_GET(self):
        self.forward()

    def do_PUT(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def _reject(self, status):
        self.send_response(status)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        self.end_headers()
        self.close_connection = True

    def _single_header(self, name):
        values = self.headers.get_all(name, [])
        if len(values) != 1 or not values[0]:
            return None
        # Avoid ever reflecting control characters into the upstream request.
        if not all(32 <= ord(c) <= 126 for c in values[0]):
            return None
        return values[0]

    def forward(self):
        path = self.path
        request_parts = self.requestline.split(" ")
        if (
            len(request_parts) != 3
            or request_parts[1] != path
            or len(path) > 256
            or len(self.headers) > 32
            or sum(len(k) + len(v) for k, v in self.headers.items()) > 8192
            or self._single_header("Host")
            != f"127.0.0.1:{self.server.server_address[1]}"
        ):
            self._reject(400)
            return
        if not allowed_request(self.command, path):
            self._reject(404)
            return
        if self.headers.get_all("Transfer-Encoding") or self.headers.get_all("Trailer"):
            self._reject(400)
            return
        lengths = self.headers.get_all("Content-Length", [])
        if len(lengths) > 1 or (lengths and not lengths[0].isascii()):
            self._reject(400)
            return
        if lengths and (not lengths[0].isdigit() or len(lengths[0]) > 7):
            self._reject(400)
            return
        length = int(lengths[0]) if lengths else 0
        receipt = path == "/v1/command-receipts"
        limit = MAX_RECEIPT_BODY if receipt else MAX_DDM_BODY
        if length > limit or (self.command == "GET" and length):
            self._reject(413)
            return
        if self.command in ("PUT", "POST") and not lengths:
            self._reject(411)
            return

        if receipt:
            signature = self._single_header("X-NanoMDM-Receipt-Signature")
            content_type = self._single_header("Content-Type")
            if not signature or content_type != "application/json":
                self._reject(400)
                return
            headers = {
                "X-NanoMDM-Receipt-Signature": signature,
                "Content-Type": content_type,
            }
        else:
            enrollment = self._single_header("X-Enrollment-ID")
            signature = self._single_header("X-Hmac-Signature")
            if not enrollment or not signature or len(enrollment) > 256:
                self._reject(400)
                return
            headers = {
                "X-Enrollment-ID": enrollment,
                "X-Hmac-Signature": signature,
            }
            if self.command == "PUT":
                content_type = self._single_header("Content-Type")
                if content_type != "application/json":
                    self._reject(400)
                    return
                headers["Content-Type"] = content_type
        body = self.rfile.read(length)
        if len(body) != length:
            self._reject(400)
            return

        # Recheck before each request: no request is forwarded to a replaced,
        # missing, or incorrectly owned socket. Deus SO_PEERCRED and HMAC
        # verification are still the authoritative receiver controls.
        upstream = None
        try:
            check_socket(self.server.socket_path)
            upstream = UnixHTTPConnection(self.server.socket_path)
            upstream.request(self.command, path, body=body, headers=headers)
            response = upstream.getresponse()
            result = response.read(MAX_RESPONSE_BODY + 1)
            if len(result) > MAX_RESPONSE_BODY:
                raise RuntimeError("oversized DDM response")
            status = response.status
            response_headers = {
                name: response.getheader(name)
                for name in ("Content-Type", "X-Hmac-Signature")
            }
        except (OSError, http.client.HTTPException, RuntimeError):
            self._reject(502)
            return
        finally:
            if upstream is not None:
                upstream.close()

        self.send_response(status)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(result)))
        for name, value in response_headers.items():
            if value is not None:
                self.send_header(name, value)
        self.end_headers()
        self.wfile.write(result)
        self.close_connection = True


def serve(socket_path=SOCKET, listen=LISTEN):
    check_socket(socket_path)
    server = BoundedHTTPServer(listen, Handler)
    server.socket_path = socket_path
    server.serve_forever()


if __name__ == "__main__":
    serve()
