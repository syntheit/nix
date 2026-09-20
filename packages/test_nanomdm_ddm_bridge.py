"""Offline transport tests; no live NanoMDM or Deus service is contacted."""

import http.client
import importlib.util
import os
import socket
import socketserver
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "ddm_bridge", Path(__file__).with_name("nanomdm-ddm-bridge.py")
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


class UpstreamHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.reply()

    def do_PUT(self):
        self.reply()

    def do_POST(self):
        self.reply()

    def reply(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.server.requests.append((self.command, self.path, body, dict(self.headers)))
        self.send_response(204 if self.command == "POST" else 200)
        self.send_header("X-Hmac-Signature", "response-signature")
        self.send_header("Content-Length", "2" if self.command != "POST" else "0")
        self.end_headers()
        if self.command != "POST":
            self.wfile.write(b"{}")

    def log_message(self, *_args):
        pass


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.socket_path = os.path.join(self.tmp.name, "socket")
        self.unix = UnixServer(self.socket_path, UpstreamHandler)
        self.unix.requests = []
        os.chmod(self.socket_path, 0o600)
        self.addCleanup(self.unix.server_close)
        self.unix_thread = threading.Thread(target=self.unix.serve_forever, daemon=True)
        self.unix_thread.start()
        self.addCleanup(self.unix.shutdown)
        self.bridge = bridge.BoundedHTTPServer(("127.0.0.1", 0), bridge.Handler)
        self.bridge.socket_path = self.socket_path
        self.addCleanup(self.bridge.server_close)
        self.bridge_thread = threading.Thread(target=self.bridge.serve_forever, daemon=True)
        self.bridge_thread.start()
        self.addCleanup(self.bridge.shutdown)

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.bridge.server_address[1], timeout=3
        )
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        result = (response.status, response.read(), dict(response.getheaders()))
        connection.close()
        return result

    def raw_request(self, request):
        with socket.create_connection(self.bridge.server_address, timeout=3) as conn:
            conn.sendall(request)
            conn.shutdown(socket.SHUT_WR)
            return conn.recv(512).split(b"\r\n", 1)[0]

    def test_only_allowlisted_ddm_and_receipt_routes_forward(self):
        ddm_headers = {
            "X-Enrollment-ID": "enrollment-1",
            "X-Hmac-Signature": "request-signature",
            "X-Untrusted-Extra": "must-not-forward",
        }
        status, body, headers = self.request("GET", "/tokens", headers=ddm_headers)
        self.assertEqual((status, body, headers.get("X-Hmac-Signature")), (200, b"{}", "response-signature"))
        self.assertNotIn("X-Untrusted-Extra", self.unix.requests[-1][3])
        status, _, _ = self.request(
            "GET", "/declaration/activation/com.themalli.deus.os-update.activation",
            headers=ddm_headers,
        )
        self.assertEqual(status, 200)
        status, _, _ = self.request(
            "PUT", "/status", b'{"ok":true}',
            {**ddm_headers, "Content-Type": "application/json"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(self.unix.requests[-1][:3], ("PUT", "/status", b'{"ok":true}'))
        status, _, _ = self.request(
            "POST", "/v1/command-receipts", b"{}",
            {"Content-Type": "application/json", "X-NanoMDM-Receipt-Signature": "sha256=abc"},
        )
        self.assertEqual(status, 204)
        candidate = b'{"is_supervised":null,"serial_number":null,"product_name":null}'
        status, body, _ = self.request(
            "POST", "/v1/device-information-receipts", candidate,
            {
                "Content-Type": "application/json",
                "X-NanoMDM-Receipt-Signature": "sha256=signed-metadata",
                "X-Untrusted-Extra": "must-not-forward",
            },
        )
        self.assertEqual((status, body), (204, b""))
        method, path, forwarded, headers = self.unix.requests[-1]
        self.assertEqual((method, path, forwarded), (
            "POST", "/v1/device-information-receipts", candidate,
        ))
        self.assertEqual(headers["X-NanoMDM-Receipt-Signature"], "sha256=signed-metadata")
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertNotIn("X-Untrusted-Extra", headers)
        self.assertEqual(len(self.unix.requests), 5)

        for method, path in (
            ("GET", "/status"),
            ("PUT", "/tokens"),
            ("POST", "/tokens"),
            ("GET", "/tokens?x=1"),
            ("GET", "/declaration/activation/a%2fb"),
            ("GET", "/declaration/activation/a/extra"),
            ("GET", "/v1/device-information-receipts"),
            ("PUT", "/v1/device-information-receipts"),
            ("POST", "/v1/device-information-receipts/"),
            ("POST", "/v1/device-information-receipts?x=1"),
            ("POST", "/v1/device-information-receipts%2f"),
        ):
            status, _, _ = self.request(method, path, headers=ddm_headers)
            self.assertEqual(status, 404, (method, path))
        self.assertEqual(len(self.unix.requests), 5)

    def test_raw_request_smuggling_inputs_do_not_forward(self):
        host = f"Host: 127.0.0.1:{self.bridge.server_address[1]}\r\n"
        for malformed in (
            "Content-Length: 2\r\nContent-Length: 2\r\n",
            "Content-Length: 2,2\r\n",
            "Content-Length: 2\r\nTransfer-Encoding: chunked\r\n",
        ):
            request = (
                "PUT /status HTTP/1.1\r\n" + host
                + "X-Enrollment-ID: enrollment-1\r\n"
                + "X-Hmac-Signature: request-signature\r\n"
                + "Content-Type: application/json\r\n"
                + malformed + "\r\n{}"
            ).encode()
            self.assertIn(b" 400 ", self.raw_request(request))
        wrong_host = (
            "GET /tokens HTTP/1.1\r\nHost: example.org\r\n"
            "X-Enrollment-ID: enrollment-1\r\n"
            "X-Hmac-Signature: request-signature\r\n\r\n"
        ).encode()
        self.assertIn(b" 400 ", self.raw_request(wrong_host))
        absolute_path = (
            "GET http://example.org/tokens HTTP/1.1\r\n" + host
            + "X-Enrollment-ID: enrollment-1\r\n"
            + "X-Hmac-Signature: request-signature\r\n\r\n"
        ).encode()
        self.assertIn(b" 404 ", self.raw_request(absolute_path))
        normalized_path = (
            "GET //tokens HTTP/1.1\r\n" + host
            + "X-Enrollment-ID: enrollment-1\r\n"
            + "X-Hmac-Signature: request-signature\r\n\r\n"
        ).encode()
        self.assertIn(b" 400 ", self.raw_request(normalized_path))
        self.assertEqual(self.unix.requests, [])

    def test_missing_signature_or_unsafe_request_never_forwards(self):
        status, _, _ = self.request("GET", "/tokens")
        self.assertEqual(status, 400)
        status, _, _ = self.request(
            "POST", "/v1/command-receipts", b"{}",
            {"X-NanoMDM-Receipt-Signature": "sha256=abc"},
        )
        self.assertEqual(status, 400)
        for headers in (
            {"X-NanoMDM-Receipt-Signature": "sha256=abc"},
            {"Content-Type": "application/json"},
            {
                "Content-Type": "text/plain",
                "X-NanoMDM-Receipt-Signature": "sha256=abc",
            },
        ):
            status, _, _ = self.request(
                "POST", "/v1/device-information-receipts", b"{}", headers,
            )
            self.assertEqual(status, 400)
        status, _, _ = self.request(
            "POST", "/v1/device-information-receipts",
            b"x" * (bridge.MAX_RECEIPT_BODY + 1),
            {
                "Content-Type": "application/json",
                "X-NanoMDM-Receipt-Signature": "sha256=abc",
            },
        )
        self.assertEqual(status, 413)
        host = f"Host: 127.0.0.1:{self.bridge.server_address[1]}\r\n"
        duplicate_signature = (
            "POST /v1/device-information-receipts HTTP/1.1\r\n" + host
            + "Content-Type: application/json\r\n"
            + "X-NanoMDM-Receipt-Signature: sha256=abc\r\n"
            + "X-NanoMDM-Receipt-Signature: sha256=abc\r\n"
            + "Content-Length: 2\r\n\r\n{}"
        ).encode()
        self.assertIn(b" 400 ", self.raw_request(duplicate_signature))
        status, _, _ = self.request(
            "PUT", "/status", b"x" * (bridge.MAX_DDM_BODY + 1),
            {
                "X-Enrollment-ID": "enrollment-1",
                "X-Hmac-Signature": "request-signature",
                "Content-Type": "application/json",
            },
        )
        self.assertEqual(status, 413)
        self.assertEqual(self.unix.requests, [])

    def test_replaced_or_exposed_socket_fails_closed(self):
        os.chmod(self.socket_path, 0o666)
        with self.assertRaises(RuntimeError):
            bridge.check_socket(self.socket_path)
        status, _, _ = self.request(
            "GET", "/tokens",
            headers={"X-Enrollment-ID": "enrollment-1", "X-Hmac-Signature": "abc"},
        )
        self.assertEqual(status, 502)
        status, _, _ = self.request(
            "POST", "/v1/device-information-receipts", b"{}",
            {
                "Content-Type": "application/json",
                "X-NanoMDM-Receipt-Signature": "sha256=abc",
            },
        )
        self.assertEqual(status, 502)
        self.assertEqual(self.unix.requests, [])


if __name__ == "__main__":
    unittest.main()
