"use strict";

/*
 * Proposed build-379 compatibility state coordinator.
 * This is a deterministic model for integration tests, not recovered Folia code
 * and not an AVPlayer implementation.
 */
function createPlayerState(initial = {}) {
  return {
    session: typeof initial.session === "string" ? initial.session : null,
    generation: Number.isSafeInteger(initial.generation) && initial.generation >= 0 ? initial.generation : -1,
    transport: "detached",
    desiredPlaying: false,
    current: null,
    upcoming: [],
    previous: [],
    lifecycle: "foreground",
    waitingForQueue: false,
    endedForURL: null,
    lastError: null
  };
}

function validTrack(track) {
  return track && typeof track === "object" && !Array.isArray(track) &&
    typeof track.trackKey === "string" && track.trackKey.length > 0 &&
    typeof track.url === "string" && track.url.length > 0;
}

function adopt(state, event) {
  if (typeof event.session !== "string" || !event.session ||
      !Number.isSafeInteger(event.generation) || event.generation < 0) return false;
  if (state.session === event.session && event.generation < state.generation) return false;
  if (state.session !== event.session) {
    state.session = event.session;
    state.generation = event.generation;
    state.transport = "attached";
    state.desiredPlaying = false;
    state.current = null;
    state.upcoming = [];
    state.previous = [];
    state.waitingForQueue = false;
    state.endedForURL = null;
    state.lastError = null;
    return true;
  }
  if (event.generation < state.generation) return false;
  state.generation = event.generation;
  return true;
}

function reducePlayerState(previousState, event) {
  const state = {
    ...previousState,
    upcoming: [...previousState.upcoming],
    previous: [...previousState.previous],
    current: previousState.current ? { ...previousState.current } : null
  };
  if (!event || typeof event.type !== "string") return state;

  if (event.type === "attach") {
    if (adopt(state, event)) state.transport = "attached";
    return state;
  }

  if (event.type === "load") {
    if (!validTrack(event.track) || !adopt(state, event)) return state;
    state.current = { ...event.track };
    state.upcoming = Array.isArray(event.upcoming) ? event.upcoming.filter(validTrack).map(t => ({ ...t })) : [];
    state.previous = Array.isArray(event.previous) ? event.previous.filter(validTrack).map(t => ({ ...t })) : [];
    state.transport = "loading";
    state.desiredPlaying = event.autoplay === true;
    state.waitingForQueue = false;
    state.endedForURL = null;
    state.lastError = null;
    return state;
  }

  if (event.session !== state.session || event.generation !== state.generation) return state;

  switch (event.type) {
    case "ready":
      if (state.current) state.transport = state.desiredPlaying ? "playing" : "paused";
      break;
    case "transport-state":
      // Reflect native transport reality without rewriting the user's desired intent.
      if (state.current && typeof event.playing === "boolean") {
        state.transport = event.playing ? "playing" : "paused";
      }
      break;
    case "play":
      state.desiredPlaying = true;
      if (state.waitingForQueue && state.upcoming.length) {
        if (state.current) state.previous.push(state.current);
        state.current = state.upcoming.shift();
        state.transport = "loading";
        state.waitingForQueue = false;
      } else if (state.current && state.transport !== "loading" && state.transport !== "ended") {
        state.transport = "playing";
      }
      break;
    case "pause":
      state.desiredPlaying = false;
      if (state.current && state.transport !== "loading") state.transport = "paused";
      break;
    case "queue":
      state.upcoming = Array.isArray(event.upcoming) ? event.upcoming.filter(validTrack).map(t => ({ ...t })) : [];
      state.previous = Array.isArray(event.previous) ? event.previous.filter(validTrack).map(t => ({ ...t })) : state.previous;
      if (state.waitingForQueue && state.desiredPlaying && state.upcoming.length) {
        if (state.current) state.previous.push(state.current);
        state.current = state.upcoming.shift();
        state.transport = "loading";
        state.waitingForQueue = false;
      }
      break;
    case "ended": {
      if (!state.current) break;
      const endedURL = typeof event.url === "string" ? event.url : state.current.url;
      // Ignore late end notifications from a replaced item and duplicate notifications
      // for the same URL. The original binary exposes an endedForURL state marker.
      if (endedURL !== state.current.url || state.endedForURL === endedURL) break;
      state.endedForURL = endedURL;
      if (state.desiredPlaying && state.upcoming.length) {
        state.previous.push(state.current);
        state.current = state.upcoming.shift();
        state.transport = "loading";
        state.waitingForQueue = false;
      } else {
        state.transport = "ended";
        state.waitingForQueue = true;
      }
      break;
    }
    case "failed":
      state.transport = "failed";
      state.lastError = typeof event.message === "string" ? event.message : "playback-failed";
      break;
    case "background":
      state.lifecycle = "background";
      break;
    case "foreground":
      state.lifecycle = "foreground";
      break;
    case "interruption-began":
      state.lifecycle = "interrupted";
      break;
    case "interruption-ended":
      state.lifecycle = "foreground";
      // Resume is represented as intent only; host must decide whether AVPlayer can resume.
      break;
    case "detach":
      state.transport = "detached";
      state.desiredPlaying = false;
      state.current = null;
      state.upcoming = [];
      state.previous = [];
      state.waitingForQueue = false;
      state.endedForURL = null;
      break;
    default:
      break;
  }
  return state;
}

module.exports = { createPlayerState, reducePlayerState };
