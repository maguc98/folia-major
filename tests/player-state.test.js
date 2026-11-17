"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createPlayerState, reducePlayerState } = require("../compat/ios-bridge/player-state");

const track = (trackKey, url = "https://media.example/" + trackKey + ".m4a") => ({ trackKey, url });
const send = (state, type, extra = {}) => reducePlayerState(state, { type, session: "s1", generation: 1, ...extra });

test("load adopts session and separates desired intent from transport readiness", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [] });
  assert.equal(state.transport, "loading");
  assert.equal(state.desiredPlaying, true);
  state = send(state, "ready");
  assert.equal(state.transport, "playing");
});

test("explicit pause is retained through a later ready event", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true });
  state = send(state, "pause");
  state = send(state, "ready");
  assert.equal(state.desiredPlaying, false);
  assert.equal(state.transport, "paused");
});

test("stale session generations cannot change current state", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: false });
  const before = state;
  state = reducePlayerState(state, { type: "load", session: "s1", generation: 0, track: track("old"), autoplay: true });
  assert.deepEqual(state, before);
});

test("new session resets prior queue and current item", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [track("b")] });
  state = reducePlayerState(state, { type: "attach", session: "s2", generation: 0 });
  assert.equal(state.session, "s2");
  assert.equal(state.current, null);
  assert.deepEqual(state.upcoming, []);
  assert.equal(state.desiredPlaying, false);
});

test("late queue arrival resumes progression only after ended was waiting", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [] });
  state = send(state, "ready");
  state = send(state, "ended");
  assert.equal(state.waitingForQueue, true);
  assert.equal(state.transport, "ended");
  state = send(state, "queue", { upcoming: [track("b")], previous: [] });
  assert.equal(state.current.trackKey, "b");
  assert.equal(state.transport, "loading");
  assert.equal(state.waitingForQueue, false);
});

test("queued next item advances immediately on ended", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [track("b")] });
  state = send(state, "ended");
  assert.equal(state.current.trackKey, "b");
  assert.equal(state.transport, "loading");
  assert.equal(state.previous[0].trackKey, "a");
});

test("failed playback records an error without changing session identity", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true });
  state = send(state, "failed", { message: "network" });
  assert.equal(state.transport, "failed");
  assert.equal(state.lastError, "network");
  assert.equal(state.session, "s1");
});

test("invalid track load does not mutate state", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true });
  const before = state;
  state = reducePlayerState(state, { type: "load", session: "s1", generation: 2, track: { url: "bad" }, autoplay: true });
  assert.deepEqual(state, before);
});

test("background and foreground transitions preserve explicit pause intent", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true });
  state = send(state, "ready");
  state = send(state, "pause");
  state = send(state, "background");
  state = send(state, "foreground");
  assert.equal(state.lifecycle, "foreground");
  assert.equal(state.desiredPlaying, false);
  assert.equal(state.transport, "paused");
});

test("interruption end changes lifecycle but does not invent a resume command", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true });
  state = send(state, "ready");
  state = send(state, "interruption-began");
  state = send(state, "pause");
  state = send(state, "interruption-ended");
  assert.equal(state.lifecycle, "foreground");
  assert.equal(state.desiredPlaying, false);
  assert.equal(state.transport, "paused");
});


test("duplicate ended notifications for the same URL do not advance twice", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [track("b")] });
  state = send(state, "ended", { url: "https://media.example/a.m4a" });
  assert.equal(state.current.trackKey, "b");
  const afterFirstEnd = state;
  state = send(state, "ended", { url: "https://media.example/a.m4a" });
  assert.deepEqual(state, afterFirstEnd);
});

test("late queue does not auto-start after the user has paused", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [] });
  state = send(state, "ready");
  state = send(state, "pause");
  state = send(state, "ended");
  state = send(state, "queue", { upcoming: [track("b")], previous: [] });
  assert.equal(state.current.trackKey, "a");
  assert.equal(state.transport, "ended");
  assert.equal(state.waitingForQueue, true);
  state = send(state, "play");
  assert.equal(state.current.trackKey, "b");
  assert.equal(state.transport, "loading");
});

test("late ended event from replaced URL cannot advance the new item", () => {
  let state = createPlayerState();
  state = send(state, "load", { track: track("a"), autoplay: true, upcoming: [track("b"), track("c")] });
  state = send(state, "ended", { url: "https://media.example/a.m4a" });
  assert.equal(state.current.trackKey, "b");
  const before = state;
  state = send(state, "ended", { url: "https://media.example/a.m4a" });
  assert.deepEqual(state, before);
});


const { mapNativePlayerEvent, applyNativePlayerEvent } = require("../compat/ios-bridge/native-event-adapter");

test("native state callback updates transport without erasing desired play intent", () => {
  let state = send(createPlayerState(), "load", { track: track("a"), autoplay: true });
  state = applyNativePlayerEvent(state, { type: "state", session: "s1", generation: 1, playing: false });
  assert.equal(state.transport, "paused");
  assert.equal(state.desiredPlaying, true);
});

test("native loaded and error callbacks map to ready and failed states", () => {
  let state = send(createPlayerState(), "load", { track: track("a"), autoplay: true });
  state = applyNativePlayerEvent(state, { type: "loaded", session: "s1", generation: 1 });
  assert.equal(state.transport, "playing");
  state = applyNativePlayerEvent(state, { type: "error", session: "s1", generation: 1, message: "decode" });
  assert.equal(state.transport, "failed");
  assert.equal(state.lastError, "decode");
});

test("native event adapter rejects stale generation and malformed envelopes", () => {
  let state = send(createPlayerState(), "load", { track: track("a"), autoplay: true });
  const before = state;
  state = applyNativePlayerEvent(state, { type: "state", session: "s1", generation: 0, playing: false });
  assert.deepEqual(state, before);
  assert.equal(mapNativePlayerEvent({ type: "state", session: "s1", generation: 1, playing: "false" }), null);
  assert.equal(mapNativePlayerEvent({ type: "ended", session: "", generation: 1 }), null);
});

test("native ended callback uses URL identity and cannot advance twice", () => {
  let state = send(createPlayerState(), "load", { track: track("a"), autoplay: true, upcoming: [track("b")] });
  state = applyNativePlayerEvent(state, { type: "ended", session: "s1", generation: 1, url: "https://media.example/a.m4a" });
  assert.equal(state.current.trackKey, "b");
  const once = state;
  state = applyNativePlayerEvent(state, { type: "ended", session: "s1", generation: 1, url: "https://media.example/a.m4a" });
  assert.deepEqual(state, once);
});

test("non-state native callbacks are left to timeline and visualizer consumers", () => {
  assert.equal(mapNativePlayerEvent({ type: "time", session: "s1", generation: 1, position: 3 }), null);
  assert.equal(mapNativePlayerEvent({ type: "audio", session: "s1", generation: 1, bass: 10 }), null);
  assert.equal(mapNativePlayerEvent({ type: "auto-advanced", session: "s1", generation: 1, trackKey: "b" }), null);
});
