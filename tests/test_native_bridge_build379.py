#!/usr/bin/env python3
"""Dependency-free structural tests for the build-379 bridge fixtures.

These tests validate the observed web-side envelope shapes. They do not emulate
WebKit, AVPlayer, Apple Music, Feiniu Music, or the native Swift implementation.
"""
from __future__ import annotations

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "native-bridge-build379.json"

PLAYER_COMMANDS = {
    "load", "play", "pause", "seek", "volume", "muted", "status",
    "upcoming", "startup_prompts_seen",
}
PLAYER_EVENTS = {
    "loaded", "error", "state", "time", "ended", "auto-advanced", "audio",
}
PROVIDER_ACTIONS = {
    "appleMusicOpen", "appleMusicClose", "appleMusicLogout",
    "appleMusicRequest", "appleMusicStatus", "fnmusicLogin",
    "fnmusicLogout", "fnmusicRequest", "fnmusicStatus",
}


def validate_player_request(message: dict) -> None:
    assert message.get("cmd") in PLAYER_COMMANDS, message
    cmd = message["cmd"]
    if cmd != "startup_prompts_seen":
        assert isinstance(message.get("generation"), int), message
        assert isinstance(message.get("session"), str) and message["session"], message
    if cmd == "load":
        assert isinstance(message.get("url"), str) and message["url"], message
        assert isinstance(message.get("position"), (int, float)), message
        assert isinstance(message.get("autoplay"), bool), message
    elif cmd == "seek":
        assert isinstance(message.get("position"), (int, float)), message
        assert message["position"] >= 0, message
    elif cmd == "volume":
        assert isinstance(message.get("volume"), (int, float)), message
        assert 0 <= message["volume"] <= 1, message
    elif cmd == "muted":
        assert isinstance(message.get("muted"), bool), message
    elif cmd == "upcoming":
        assert isinstance(message.get("currentTrackKey"), str), message
        assert "track" in message and isinstance(message.get("upcoming"), list), message
        assert isinstance(message.get("previous"), list), message


def validate_player_event(message: dict) -> None:
    assert message.get("type") in PLAYER_EVENTS, message
    if "session" in message:
        assert isinstance(message["session"], str), message
    if "generation" in message:
        assert isinstance(message["generation"], int), message
    kind = message["type"]
    if kind in {"state", "time"}:
        assert isinstance(message.get("playing"), bool), message
        assert isinstance(message.get("position"), (int, float)), message
    if kind == "time":
        assert isinstance(message.get("duration"), (int, float)), message
    if kind == "auto-advanced":
        assert message.get("trackKey") and message.get("url"), message
    if kind == "audio":
        for band in ("power", "bass", "lowMid", "mid", "vocal", "treble"):
            assert isinstance(message.get(band), (int, float)), (band, message)


def validate_provider_request(message: dict) -> None:
    assert isinstance(message.get("id"), str) and message["id"], message
    action = message.get("action")
    assert action in PROVIDER_ACTIONS, message
    if action == "appleMusicRequest":
        assert isinstance(message.get("operation"), str) and message["operation"], message
        assert isinstance(message.get("params"), dict), message
    if action == "fnmusicRequest":
        assert isinstance(message.get("path"), str) and message["path"].startswith("/"), message
        assert isinstance(message.get("method"), str) and message["method"], message


def validate_provider_reply(message: dict) -> None:
    assert isinstance(message.get("id"), str) and message["id"], message
    payload = message.get("payload")
    assert isinstance(payload, dict) and isinstance(payload.get("ok"), bool), message
    if payload["ok"]:
        assert "data" in payload, message
    else:
        assert isinstance(payload.get("error"), str) and payload["error"], message


class Build379BridgeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_player_requests(self) -> None:
        self.assertGreaterEqual(len(self.data["player_requests"]), 9)
        for item in self.data["player_requests"]:
            with self.subTest(message=item):
                validate_player_request(item)

    def test_player_events(self) -> None:
        self.assertGreaterEqual(len(self.data["player_events"]), 7)
        for item in self.data["player_events"]:
            with self.subTest(message=item):
                validate_player_event(item)

    def test_provider_requests(self) -> None:
        ids = []
        for item in self.data["provider_requests"]:
            with self.subTest(message=item):
                validate_provider_request(item)
                ids.append(item["id"])
        self.assertEqual(len(ids), len(set(ids)), "request IDs must be unique")

    def test_provider_replies(self) -> None:
        for item in self.data["provider_replies"]:
            with self.subTest(message=item):
                validate_provider_reply(item)

    def test_reject_invalid_player_volume(self) -> None:
        with self.assertRaises(AssertionError):
            validate_player_request({"cmd": "volume", "volume": 1.5, "generation": 1, "session": "fixture"})

    def test_reject_unknown_provider_action(self) -> None:
        with self.assertRaises(AssertionError):
            validate_provider_request({"id": "fixture-id", "action": "arbitraryURL"})

    def test_reject_malformed_provider_reply(self) -> None:
        with self.assertRaises(AssertionError):
            validate_provider_reply({"id": "fixture-id", "payload": {"ok": False}})


if __name__ == "__main__":
    unittest.main(verbosity=2)
