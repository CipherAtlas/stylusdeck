#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import threading
import webbrowser
import atexit
from http import HTTPStatus
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
WEB_ROOT = ROOT / "web"
HOST = "127.0.0.1"
PORT = 8421
BRIDGE_PATH = ROOT / ".build" / "debug" / "VolumeBridge"
EQ_BRIDGE_PATH = ROOT / ".build" / "debug" / "EqBridge"
APP_ROUTES = {"/", "/volume", "/eq/low", "/eq/mid", "/eq/high"}
EQ_BANDS = ("low", "mid", "high")


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


class VolumeBridge:
    def __init__(self, executable: Path) -> None:
        self.executable = executable
        self.process: subprocess.Popen[str] | None = None
        self.lock = threading.Lock()

    def start(self) -> None:
        if self.process and self.process.poll() is None:
            return

        if not self.executable.exists():
            self.build()

        self.process = subprocess.Popen(
            [str(self.executable)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )

    def build(self) -> None:
        subprocess.run(
            ["swift", "build", "--product", "VolumeBridge"],
            cwd=ROOT,
            check=True,
        )

    def request(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            self.start()
            assert self.process is not None
            assert self.process.stdin is not None
            assert self.process.stdout is not None

            self.process.stdin.write(json.dumps(payload) + "\n")
            self.process.stdin.flush()

            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("VolumeBridge exited unexpectedly")

            response = json.loads(line)
            if not response.get("ok"):
                raise RuntimeError(response.get("error", "Bridge error"))
            return response

    def get_current_volume(self) -> int:
        response = self.request({"action": "get"})
        return int(response["volume"])

    def set_system_volume(self, volume: int) -> int:
        clamped = int(clamp(volume, 0, 100))
        response = self.request({"action": "set", "volume": clamped})
        return int(response["volume"])

    def stop(self) -> None:
        with self.lock:
            if self.process and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            self.process = None


class EqBridge:
    def __init__(self) -> None:
        self.executable = Path(os.environ.get("EQ_BRIDGE_BIN", EQ_BRIDGE_PATH))
        self.process: subprocess.Popen[str] | None = None
        self.lock = threading.Lock()
        self.states = {band: 50 for band in EQ_BANDS}

    def start(self) -> None:
        if self.process and self.process.poll() is None:
            return

        if not self.executable.exists():
            self.build()

        self.process = subprocess.Popen(
            [str(self.executable)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )

    def build(self) -> None:
        subprocess.run(
            ["swift", "build", "--product", "EqBridge"],
            cwd=ROOT,
            check=True,
        )

    def request(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            self.start()
            assert self.process is not None
            assert self.process.stdin is not None
            assert self.process.stdout is not None

            self.process.stdin.write(json.dumps(payload) + "\n")
            self.process.stdin.flush()

            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("EqBridge exited unexpectedly")

            response = json.loads(line)
            return response

    def get_band(self, band: str) -> dict[str, Any]:
        self._validate_band(band)
        response = self.request({"action": "status", "band": band})
        response["band"] = band
        response["value"] = int(response.get("value", self.states[band]))
        self.states[band] = response["value"]
        return response

    def set_band(self, band: str, value: int) -> dict[str, Any]:
        self._validate_band(band)
        clamped = int(clamp(value, 0, 100))
        response = self.request({"action": "setBand", "band": band, "value": clamped})
        response["band"] = band
        response["value"] = int(response.get("value", clamped))
        self.states[band] = response["value"]
        return response

    def get_output_volume(self) -> dict[str, Any]:
        return self.request({"action": "getVolume"})

    def set_output_volume(self, value: int) -> dict[str, Any]:
        return self.request({"action": "setVolume", "value": int(clamp(value, 0, 100))})

    def stop(self) -> None:
        with self.lock:
            if self.process and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            self.process = None

    def _validate_band(self, band: str) -> None:
        if band not in EQ_BANDS:
            raise ValueError(f"Unknown EQ band: {band}")


VOLUME = VolumeBridge(Path(os.environ.get("VOLUME_BRIDGE_BIN", BRIDGE_PATH)))
EQ = EqBridge()


def cleanup() -> None:
    EQ.stop()
    VOLUME.stop()


atexit.register(cleanup)


class VolumeHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/api/volume/state":
            eq_status = EQ.get_output_volume()
            if eq_status.get("connected"):
                self.send_json({"kind": "volume", **eq_status})
            else:
                self.send_json({"kind": "volume", "value": VOLUME.get_current_volume(), "connected": True, "backend": "coreaudio", "detail": "Direct output volume"})
            return

        if parsed.path.startswith("/api/eq/") and parsed.path.endswith("/state"):
            band = parsed.path.removeprefix("/api/eq/").removesuffix("/state").strip("/")
            try:
                self.send_json({"kind": "eq", **EQ.get_band(band)})
            except ValueError:
                self.send_error(HTTPStatus.NOT_FOUND, "Unknown EQ band")
            return

        if parsed.path in APP_ROUTES:
            self.path = "/index.html"
            return super().do_GET()

        if parsed.path == "/":
            self.path = "/index.html"

        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length) or b"{}")
        value = int(clamp(float(payload.get("value", payload.get("volume", 0))), 0, 100))

        if parsed.path == "/api/volume":
            eq_status = EQ.set_output_volume(value)
            if eq_status.get("connected"):
                self.send_json({"kind": "volume", **eq_status})
            else:
                actual = VOLUME.set_system_volume(value)
                self.send_json({"kind": "volume", "value": actual, "connected": True, "backend": "coreaudio", "detail": "Direct output volume"})
            return

        if parsed.path.startswith("/api/eq/"):
            band = parsed.path.removeprefix("/api/eq/").strip("/")
            try:
                self.send_json({"kind": "eq", **EQ.set_band(band, value)})
            except ValueError:
                self.send_error(HTTPStatus.NOT_FOUND, "Unknown EQ band")
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        return


def main() -> None:
    VOLUME.start()
    EQ.start()
    with HTTPServer((HOST, PORT), VolumeHandler) as server:
        url = f"http://{HOST}:{PORT}"
        print(f"Volume web UI running at {url}")
        webbrowser.open(url)
        server.serve_forever()


if __name__ == "__main__":
    main()
