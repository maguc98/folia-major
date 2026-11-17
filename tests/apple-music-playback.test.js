"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createAppleMusicPlaybackDispatcher } = require("../compat/ios-bridge/apple-music-playback");

function fixture() {
  const windowRef = { document: { visibilityState: "visible" }, MusicKit: {} };
  const mk = {
    isAuthorized: true, storefrontCountryCode: "us", storefrontId: "us",
    playbackMode: 0, volume: 1, isPlaying: false, playbackState: 0,
    currentPlaybackTime: 4, currentPlaybackDuration: 180, previewOnly: false,
    nowPlayingItem: null, queue: { items: [], position: 0 },
    setShuffleMode() {}, setRepeatMode() {},
    async pause() { this.isPlaying = false; },
    async setQueue({ song }) {
      this.nowPlayingItem = { id: song, attributes: { playParams: { catalogId: song } } };
      this.queue.items = [this.nowPlayingItem];
      this.queue.position = 0;
    },
    async play() { this.isPlaying = true; this.playbackState = 2; },
    async seekToTime(seconds) { this.currentPlaybackTime = seconds; },
    async playLater({ songs }) { this.queue.items.push(...songs.map(id => ({ id }))); },
    async skipToNextItem() { this.nowPlayingItem = this.queue.items[1] || this.nowPlayingItem; },
    async skipToPreviousItem() { throw new Error("no-previous"); }
  };
  windowRef.MusicKit.getInstance = () => mk;
  return { windowRef, mk, dispatch: createAppleMusicPlaybackDispatcher({ windowRef }).dispatch };
}

test("Apple Music play validates catalog IDs and publishes status", async () => {
  const { mk, dispatch } = fixture();
  const invalid = await dispatch({ operation: "play", params: { tracks: [{ catalogId: "../no" }] } });
  assert.equal(invalid.error, "invalid-request");
  const result = await dispatch({ operation: "play", params: { tracks: [{ catalogId: "12345" }], epoch: 1, volume: 0.7 } });
  assert.equal(result.ok, true);
  assert.equal(mk.isPlaying, true);
  assert.equal(mk.volume, 0.7);
  assert.equal(result.data.catalogId, "12345");
});

test("Apple Music prepareNext checks identity and appends only the missing tail", async () => {
  const { mk, dispatch } = fixture();
  await dispatch({ operation: "play", params: { tracks: [{ catalogId: "a" }], epoch: 1 } });
  mk.queue.items.push({ id: "b" });
  let result = await dispatch({ operation: "prepareNext", params: { catalogId: "a", nextIds: ["b", "c"] } });
  assert.equal(result.ok, true);
  assert.deepEqual(mk.queue.items.map(item => item.id), ["a", "b", "c"]);
  result = await dispatch({ operation: "prepareNext", params: { catalogId: "wrong", nextIds: ["x"] } });
  assert.equal(result.error, "stale-request");
});

test("Apple Music pause cancels a pending start and seek/volume are validated", async () => {
  const { windowRef, mk, dispatch } = fixture();
  await dispatch({ operation: "play", params: { tracks: [{ catalogId: "12345" }], epoch: 7 } });
  const start = windowRef.__foliaAppleStart;
  await dispatch({ operation: "pause" });
  assert.equal(start.cancelled, true);
  assert.equal(mk.isPlaying, false);
  assert.equal((await dispatch({ operation: "seek", params: { seconds: -1 } })).error, "invalid-request");
  assert.equal((await dispatch({ operation: "volume", params: { volume: 9 } })).ok, true);
  assert.equal(mk.volume, 1);
});
