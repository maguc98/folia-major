"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { mapNativeAudioEvent, AUDIO_KEYS } = require("../compat/ios-bridge/audio-event-adapter");

const makeEvent = (overrides = {}) => ({
  type: "audio", session: "session-1", generation: 4,
  power: 0.4, bass: 0.2, lowMid: 0.3, mid: 0.4, vocal: 0.5, treble: 0.6,
  ...overrides
});

test("audio adapter accepts all six finite normalized bands", () => {
  const result = mapNativeAudioEvent(makeEvent());
  assert.deepEqual(Object.keys(result).filter(key => AUDIO_KEYS.includes(key)).sort(), [...AUDIO_KEYS].sort());
  assert.equal(result.vocal, 0.5);
});

test("audio adapter rejects missing, non-finite and out-of-range bands", () => {
  for (const event of [
    makeEvent({ bass: undefined }),
    makeEvent({ bass: NaN }),
    makeEvent({ bass: Infinity }),
    makeEvent({ bass: -0.01 }),
    makeEvent({ bass: 1.01 })
  ]) assert.equal(mapNativeAudioEvent(event), null);
});

test("audio adapter rejects stale or malformed envelopes", () => {
  assert.equal(mapNativeAudioEvent(makeEvent({ session: "" })), null);
  assert.equal(mapNativeAudioEvent(makeEvent({ generation: -1 })), null);
  assert.equal(mapNativeAudioEvent(makeEvent({ type: "time" })), null);
});
