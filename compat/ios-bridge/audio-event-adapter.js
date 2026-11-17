"use strict";

const AUDIO_KEYS = ["power", "bass", "lowMid", "mid", "vocal", "treble"];

function mapNativeAudioEvent(event) {
  if (!event || typeof event !== "object" || Array.isArray(event) ||
      event.type !== "audio" ||
      typeof event.session !== "string" || !event.session ||
      !Number.isSafeInteger(event.generation) || event.generation < 0) return null;

  const bands = {};
  for (const key of AUDIO_KEYS) {
    const value = event[key];
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) return null;
    bands[key] = value;
  }
  return { type: "audio", session: event.session, generation: event.generation, ...bands };
}

module.exports = { AUDIO_KEYS, mapNativeAudioEvent };
