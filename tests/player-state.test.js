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
  state = send(state, "interruption-began");
  state = send(state, "pause");
  state = send(state, "interruption-ended");
  assert.equal(state.lifecycle, "foreground");
  assert.equal(state.desiredPlaying, false);
  assert.equal(state.transport, "paused");
});
