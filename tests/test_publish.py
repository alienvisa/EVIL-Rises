from email.parser import BytesParser
from email.policy import default
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
from threading import Thread
import unittest
from unittest.mock import Mock

from scripts import publish_release


class PublishTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.archive = self.directory / "EVILRises-v0.4.5.zip"
        self.archive.write_bytes(b"release bytes")
        self.identity = {
            "version": "v0.4.5",
            "sourceCommit": "a" * 40,
            "filename": self.archive.name,
            "sha256": hashlib.sha256(b"release bytes").hexdigest(),
            "releaseType": "release",
            "projectId": 1828614,
        }
        self.assets = {}
        self.github = Mock()
        self.github.download.side_effect = self.download
        self.github.upload.side_effect = self.upload
        self.curseforge = Mock()
        self.curseforge.upload.return_value = 42

    def download(self, name, directory):
        if name not in self.assets:
            return None
        path = directory / name
        path.write_bytes(self.assets[name])
        return path

    def upload(self, *paths):
        self.assets.update({path.name: path.read_bytes() for path in paths})

    def test_failed_post_is_never_repeated_on_a_fresh_runner(self):
        self.curseforge.upload.side_effect = ValueError("ambiguous response")
        with self.assertRaisesRegex(ValueError, "ambiguous response"):
            publish_release.publish_curseforge(
                self.github, self.curseforge, self.archive, self.identity, "notes"
            )
        (self.directory / "curseforge-attempt.json").unlink()
        with self.assertRaisesRegex(ValueError, "upload history"):
            publish_release.publish_curseforge(
                self.github, self.curseforge, self.archive, self.identity, "notes"
            )
        self.assertEqual(self.curseforge.upload.call_count, 1)

    def test_receipt_allows_a_rerun_without_a_second_post(self):
        for _ in range(2):
            receipt = publish_release.publish_curseforge(
                self.github, self.curseforge, self.archive, self.identity, "notes"
            )
            self.assertEqual(receipt, {**self.identity, "id": 42})
        self.assertEqual(self.curseforge.upload.call_count, 1)

    def test_mismatched_receipt_blocks_finalization(self):
        self.assets["curseforge-upload.json"] = json.dumps(
            {**self.identity, "sha256": "0" * 64, "id": 42}
        ).encode()
        with self.assertRaisesRegex(ValueError, "receipt"):
            publish_release.publish_github(self.github, self.archive, self.identity)
        self.github.publish.assert_not_called()

    def test_curseforge_request_sends_staged_bytes_and_forever_version(self):
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                requests.append((self.path, self.headers["X-Api-Token"]))
                self.respond(b'[{"id":17053,"name":"1.60.1","gameVersionTypeID":88568}]')

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                parts = BytesParser(policy=default).parsebytes(
                    f'Content-Type: {self.headers["Content-Type"]}\r\n\r\n'.encode() + body
                )
                fields = {
                    part.get_param("name", header="content-disposition"): part.get_payload(decode=True)
                    for part in parts.iter_parts()
                }
                requests.append((self.path, self.headers["X-Api-Token"], fields))
                self.respond(b'{"id":42}')

            def respond(self, body):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            worker = Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                client = publish_release.CurseForge(
                    1828614, 16001, "test-token", f"http://127.0.0.1:{server.server_port}",
                )
                receipt = publish_release.publish_curseforge(
                    self.github, client, self.archive, self.identity, "notes",
                )
            finally:
                server.shutdown()
                worker.join()

        self.assertEqual(requests[0], ("/api/game/wow/versions", "test-token"))
        path, token, fields = requests[1]
        self.assertEqual((path, token), ("/api/projects/1828614/upload-file", "test-token"))
        self.assertEqual(fields["file"], b"release bytes")
        self.assertEqual(json.loads(fields["metadata"])["gameVersions"], [17053])
        self.assertEqual(json.loads(fields["metadata"])["releaseType"], "release")
        self.assertEqual(receipt["id"], 42)
