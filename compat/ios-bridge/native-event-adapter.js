"use strict";

const { reducePlayerState } = require("./player-state");

/*
 * Maps only state-bearing callbacks from window.__foliaNativePlayerEvent.
 * Timeline/audio/auto-advanced notifications remain available to the UI layer;
 * they are not treated as a second queue-advance command here.
 */
function mapNativePlayerEvent(nativeEvent) {
  if (!nativeEvent || typeof nativeEvent !== "object" || Array.isArray(nativeEvent)) return null;
  if (typeof nativeEvent.session !== "string" || !nativeEvent.session ||
      !Number.isSafeInteger(nativeEvent.generation) || nativeEvent.generation < 0) return null;

  const base = { session: nativeEvent.session, generation: nativeEvent.generation };
  switch (nativeEvent.type) {
    case "loaded":
      return { ...base, type: "ready" };
    case "error":
      return {
        ...base,
        type: "failed",
        message: typeof nativeEvent.message === "string" ? nativeEvent.message : "native-playback-failed"
      };
    case "state":
      if (typeof nativeEvent.playing !== "boolean") return null;
      return { ...base, type: "transport-state", playing: nativeEvent.playing };
    case "ended":
      return {
        ...base,
        type: "ended",
        ...(typeof nativeEvent.url === "string" ? { url: nativeEvent.url } : {})
      };
    default:
      return null;
  }
}

function applyNativePlayerEvent(state, nativeEvent) {
  const mapped = mapNativePlayerEvent(nativeEvent);
  return mapped ? reducePlayerState(state, mapped) : state;
}

module.exports = { mapNativePlayerEvent, applyNativePlayerEvent };
