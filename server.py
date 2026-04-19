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
from urllib.parse import parse_qs, urlparse


ROOT = Path(__file__).resolve().parent
WEB_ROOT = ROOT / "web"
HOST = "127.0.0.1"
PORT = 8421
BRIDGE_PATH = ROOT / ".build" / "debug" / "VolumeBridge"
EQ_BRIDGE_PATH = ROOT / ".build" / "debug" / "EqBridge"
APP_ROUTES = {"/", "/volume", "/eq/low", "/eq/mid", "/eq/high"}
SURFACE_BANKS = {"main", "fx"}
SURFACE_ROUTES = {"volume", "low", "mid", "high"}
SURFACE_PARAMETERS = {"primary", "frequency", "shape"}


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

    def get_surface_value(self, bank: str, route: str, parameter: str, secondary_parameter: str | None = None) -> dict[str, Any]:
        self._validate_surface(bank, route, parameter)
        if secondary_parameter is not None:
            self._validate_surface(bank, route, secondary_parameter)
        payload: dict[str, Any] = {"action": "status", "bank": bank, "route": route, "parameter": parameter}
        if secondary_parameter is not None:
            payload["secondaryParameter"] = secondary_parameter
        response = self.request(payload)
        response["bank"] = bank
        response["route"] = route
        response["parameter"] = parameter
        response["value"] = int(response.get("value", 50))
        return response

    def set_surface_value(self, bank: str, route: str, parameter: str, value: int, secondary_parameter: str | None = None) -> dict[str, Any]:
        self._validate_surface(bank, route, parameter)
        if secondary_parameter is not None:
            self._validate_surface(bank, route, secondary_parameter)
        clamped = int(clamp(value, 0, 100))
        payload: dict[str, Any] = {"action": "set", "bank": bank, "route": route, "parameter": parameter, "value": clamped}
        if secondary_parameter is not None:
            payload["secondaryParameter"] = secondary_parameter
        response = self.request(payload)
        response["bank"] = bank
        response["route"] = route
        response["parameter"] = parameter
        response["value"] = int(response.get("value", clamped))
        return response

    def set_surface_gesture(
        self,
        bank: str,
        route: str,
        primary_value: int,
        secondary_parameter: str,
        secondary_value: int,
    ) -> dict[str, Any]:
        self._validate_surface(bank, route, "primary")
        self._validate_surface(bank, route, secondary_parameter)
        clamped_primary = int(clamp(primary_value, 0, 100))
        clamped_secondary = int(clamp(secondary_value, 0, 100))
        response = self.request(
            {
                "action": "gesture",
                "bank": bank,
                "route": route,
                "parameter": "primary",
                "value": clamped_primary,
                "secondaryParameter": secondary_parameter,
                "secondaryValue": clamped_secondary,
            }
        )
        response["bank"] = bank
        response["route"] = route
        response["parameter"] = "primary"
        response["value"] = int(response.get("value", clamped_primary))
        return response

    def stop(self) -> None:
        with self.lock:
            if self.process and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            self.process = None

    def _validate_surface(self, bank: str, route: str, parameter: str) -> None:
        if bank not in SURFACE_BANKS:
            raise ValueError(f"Unknown bank: {bank}")
        if route not in SURFACE_ROUTES:
            raise ValueError(f"Unknown route: {route}")
        if parameter not in SURFACE_PARAMETERS:
            raise ValueError(f"Unknown parameter: {parameter}")


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
        query = parse_qs(parsed.query)

        if parsed.path == "/api/state":
            bank = query.get("bank", ["main"])[0]
            route = query.get("route", ["volume"])[0]
            parameter = query.get("parameter", ["primary"])[0]
            secondary_parameter = query.get("secondaryParameter", [None])[0]
            try:
                self.send_json(self.surface_state(bank, route, parameter, secondary_parameter))
            except ValueError as error:
                self.send_error(HTTPStatus.NOT_FOUND, str(error))
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
        value = int(clamp(float(payload.get("value", 0)), 0, 100))

        if parsed.path == "/api/control":
            bank = str(payload.get("bank", "main"))
            route = str(payload.get("route", "volume"))
            parameter = str(payload.get("parameter", "primary"))
            secondary_parameter = payload.get("secondaryParameter")
            secondary_value = payload.get("secondaryValue")
            try:
                if secondary_parameter is not None and secondary_value is not None:
                    self.send_json(self.surface_gesture(bank, route, value, str(secondary_parameter), int(clamp(float(secondary_value), 0, 100))))
                else:
                    self.send_json(self.surface_set(bank, route, parameter, value, str(secondary_parameter) if secondary_parameter is not None else None))
            except ValueError as error:
                self.send_error(HTTPStatus.NOT_FOUND, str(error))
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def surface_state(self, bank: str, route: str, parameter: str, secondary_parameter: str | None = None) -> dict[str, Any]:
        eq_status = EQ.get_surface_value(bank, route, parameter, secondary_parameter)

        if eq_status.get("connected"):
            return eq_status

        if bank == "main" and route == "volume" and parameter == "primary":
            current_volume = VOLUME.get_current_volume()
            return {
                "ok": True,
                "connected": True,
                "backend": "coreaudio",
                "detail": "Direct output volume",
                "bank": bank,
                "route": route,
                "parameter": parameter,
                "value": current_volume,
                "displayValue": f"{current_volume}%",
                "parameterLabel": "GAIN",
                "clipDetected": False,
            }

        return eq_status

    def surface_set(self, bank: str, route: str, parameter: str, value: int, secondary_parameter: str | None = None) -> dict[str, Any]:
        eq_status = EQ.set_surface_value(bank, route, parameter, value, secondary_parameter)

        if eq_status.get("connected"):
            return eq_status

        if bank == "main" and route == "volume" and parameter == "primary":
            actual = VOLUME.set_system_volume(value)
            return {
                "ok": True,
                "connected": True,
                "backend": "coreaudio",
                "detail": "Direct output volume",
                "bank": bank,
                "route": route,
                "parameter": parameter,
                "value": actual,
                "displayValue": f"{actual}%",
                "parameterLabel": "GAIN",
                "clipDetected": False,
            }

        return eq_status

    def surface_gesture(self, bank: str, route: str, primary_value: int, secondary_parameter: str, secondary_value: int) -> dict[str, Any]:
        eq_status = EQ.set_surface_gesture(bank, route, primary_value, secondary_parameter, secondary_value)

        if eq_status.get("connected"):
            return eq_status

        if bank == "main" and route == "volume":
            actual = VOLUME.set_system_volume(primary_value)
            eq_status["value"] = actual
            eq_status["displayValue"] = f"{actual}%"
            eq_status["parameterLabel"] = "GAIN"
            return eq_status

        return eq_status

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
