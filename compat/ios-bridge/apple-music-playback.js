"use strict";

const CATALOG_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const APPLE_NUMERIC_ID = /^[0-9]{1,40}$/;
const LOOP_MODES = new Set(["off", "one", "all"]);

function createAppleMusicPlaybackDispatcher({
  windowRef = typeof window !== "undefined" ? window : null,
  fetchImpl = typeof fetch !== "undefined" ? fetch.bind(globalThis) : null
} = {}) {
  if (!windowRef) throw new Error("window-required");

  const errorCode = error => String(error?.code || error?.name || "playback-failed")
    .replace(/[^a-zA-Z0-9_.-]/g, "").slice(0, 80);
  const playableIdOf = item => String(
    item?.attributes?.playParams?.catalogId ||
    item?.attributes?.playParams?.id ||
    item?.playParams?.catalogId ||
    item?.playParams?.id ||
    item?.id || ""
  );
  const currentQueueIdOf = mk => {
    const direct = playableIdOf(mk?.nowPlayingItem);
    if (direct) return direct;
    const items = Array.isArray(mk?.queue?.items) ? mk.queue.items : [];
    const position = Number.isInteger(mk?.queue?.position) ? mk.queue.position : -1;
    return position >= 0 && position < items.length ? playableIdOf(items[position]) : "";
  };
  const logicalIdOf = raw => {
    const equivalent = windowRef.__foliaAppleEquivalent;
    return equivalent && raw === equivalent.replacement ? equivalent.originalId : raw;
  };

  async function alignStorefront(mk) {
    const cached = windowRef.__foliaStorefront?.data?.data?.[0]?.id;
    const account = typeof cached === "string" ? cached : mk?.storefrontCountryCode;
    if (mk?.isAuthorized !== true || typeof account !== "string" || !/^[a-z]{2}$/.test(account)) return;
    if (mk.storefrontId !== account) {
      mk.storefrontId = account;
      windowRef.__foliaStorefrontAligned = true;
    }
    if (windowRef.__foliaStorefrontAligned !== true) return;
    const modes = windowRef.MusicKit?.PlaybackMode;
    if (!modes || mk.playbackMode !== modes.PREVIEW_ONLY ||
        typeof mk.hasMusicSubscription !== "function") return;

    if (typeof windowRef.__foliaSubscribed !== "boolean") {
      if (!windowRef.__foliaSubscription) {
        windowRef.__foliaSubscription = Promise.resolve()
          .then(() => mk.hasMusicSubscription())
          .then(answer => { if (typeof answer === "boolean") windowRef.__foliaSubscribed = answer; })
          .catch(() => {})
          .finally(() => { windowRef.__foliaSubscription = null; });
      }
      let timer;
      await Promise.race([
        windowRef.__foliaSubscription,
        new Promise(resolve => { timer = setTimeout(resolve, 3000); })
      ]);
      clearTimeout(timer);
    }
    if (windowRef.__foliaSubscribed === true) mk.playbackMode = modes.MIXED_CONTENT;
  }

  async function lookupEquivalent(mk, originalId) {
    const modern = mk.api?.v3;
    const legacy = mk.api;
    const direct = fetchImpl && typeof mk.developerToken === "string" && mk.developerToken &&
      typeof mk.musicUserToken === "string" && mk.musicUserToken
      ? async (path, query) => {
          const url = new URL(path, "https://api.music.apple.com");
          for (const [key, value] of Object.entries(query || {})) url.searchParams.set(key, String(value));
          const response = await fetchImpl(url, { headers: {
            Authorization: "Bearer " + mk.developerToken,
            "Music-User-Token": mk.musicUserToken
          } });
          let data = null;
          try { data = await response.json(); } catch {}
          return { status: response.status, data };
        } : null;
    const call = typeof modern?.music === "function" ? modern.music.bind(modern)
      : typeof legacy?.music === "function" ? legacy.music.bind(legacy) : direct;
    if (!call) return "";
    const account = await call("v1/me/storefront");
    const storefront = account?.data?.data?.[0]?.id;
    if (!/^[a-z]{2}$/.test(String(storefront || ""))) return "";
    const result = await call("v1/catalog/" + storefront + "/songs", {
      "filter[equivalents]": originalId
    });
    const matches = result?.data?.meta?.filters?.equivalents?.[originalId];
    if (!Array.isArray(matches)) return "";
    return String(matches.find(item => item?.type === "songs" &&
      APPLE_NUMERIC_ID.test(String(item.id)) && String(item.id) !== originalId)?.id || "");
  }

  async function dispatch(request) {
    let stage = "ready";
    try {
      if (!request || typeof request !== "object" || Array.isArray(request)) {
        return { ok: false, error: "invalid-request" };
      }
      const mk = windowRef.MusicKit?.getInstance?.();
      if (!mk || typeof mk.setQueue !== "function") return { ok: false, error: "not-ready" };
      const p = request.params && typeof request.params === "object" ? request.params : {};
      const operation = request.operation;

      if (operation === "play") {
        if (!Array.isArray(p.tracks) || !p.tracks.length || p.tracks.length > 100 ||
            p.tracks.some(track => typeof track?.catalogId !== "string" || !CATALOG_ID.test(track.catalogId))) {
          return { ok: false, error: "invalid-request" };
        }
        if (p.loopMode !== undefined && !LOOP_MODES.has(p.loopMode)) return { ok: false, error: "invalid-request" };
        const epoch = p.epoch;
        windowRef.__foliaAppleEpoch = epoch;
        windowRef.__foliaAppleFailure = false;
        const originalId = p.catalogId || p.tracks[0].catalogId;
        if (!CATALOG_ID.test(originalId)) return { ok: false, error: "invalid-request" };
        const start = { cancelled: false, accepted: false, at: Date.now(), catalogId: originalId };
        if (windowRef.__foliaAppleStart) windowRef.__foliaAppleStart.cancelled = true;
        windowRef.__foliaAppleStart = start;
        if (typeof mk.setShuffleMode === "function") mk.setShuffleMode(0);
        if (typeof mk.setRepeatMode === "function") {
          mk.setRepeatMode(p.loopMode === "one" ? 1 : p.loopMode === "all" ? 2 : 0);
        }
        try { await alignStorefront(mk); } catch {}
        stage = "queue";
        const queueWork = Promise.resolve(windowRef.__foliaAppleQueueWork).catch(() => {}).then(async () => {
          if (windowRef.__foliaAppleEpoch !== epoch) return false;
          try { await mk.pause(); } catch {}
          if (windowRef.__foliaAppleEpoch !== epoch) return false;
          windowRef.__foliaAppleEquivalent = null;
          try {
            await mk.setQueue({ song: originalId, startPlaying: false });
          } catch (error) {
            if (!APPLE_NUMERIC_ID.test(originalId) || !/NOT_FOUND|mk-007/i.test(String(error?.message || error))) throw error;
            stage = "equivalent-lookup";
            const replacement = await lookupEquivalent(mk, originalId);
            if (!replacement) { stage = "equivalent-empty"; throw error; }
            if (windowRef.__foliaAppleEpoch !== epoch) return false;
            stage = "equivalent-queue";
            await mk.setQueue({ song: replacement, startPlaying: false });
            windowRef.__foliaAppleEquivalent = { originalId, replacement };
          }
          const queuedId = logicalIdOf(currentQueueIdOf(mk));
          if (queuedId && queuedId !== originalId) {
            try { await mk.pause(); } catch {}
            stage = "identity-check";
            throw new Error("queue-identity-mismatch");
          }
          return true;
        });
        windowRef.__foliaAppleQueueWork = queueWork;
        if (!(await queueWork)) return { ok: false, error: "stale-request" };
        stage = "volume";
        if (windowRef.__foliaAppleEpoch !== epoch) return { ok: false, error: "stale-request" };
        mk.volume = Math.max(0, Math.min(1, Number(p.volume) || 0));
        stage = "play";
        try {
          await mk.play();
        } catch (error) {
          if (windowRef.__foliaAppleStart === start && !start.cancelled) {
            windowRef.__foliaAppleFailure = true;
            windowRef.__foliaAppleFailureCode = errorCode(error);
          }
          throw error;
        }
        const playedId = logicalIdOf(currentQueueIdOf(mk));
        if (playedId && playedId !== originalId) {
          try { await mk.pause(); } catch {}
          stage = "identity-check";
          throw new Error("queue-identity-mismatch");
        }
        if (windowRef.__foliaAppleStart !== start || start.cancelled) {
          return { ok: false, error: "stale-request" };
        }
        start.accepted = true;
      } else if (operation === "pause" || operation === "stop") {
        if (operation === "stop") windowRef.__foliaAppleEpoch = "";
        if (windowRef.__foliaAppleStart) windowRef.__foliaAppleStart.cancelled = true;
        await mk.pause();
      } else if (operation === "resume") {
        windowRef.__foliaAppleFailure = false;
        try { await alignStorefront(mk); } catch {}
        const oldStart = windowRef.__foliaAppleStart;
        const item = mk.nowPlayingItem;
        const start = { cancelled: false, accepted: false, at: Date.now(),
          catalogId: oldStart && !oldStart.started ? oldStart.catalogId : playableIdOf(item) };
        windowRef.__foliaAppleStart = start;
        await mk.play();
        if (windowRef.__foliaAppleStart !== start || start.cancelled) return { ok: false, error: "stale-request" };
        start.accepted = true;
      } else if (operation === "seek") {
        if (!Number.isFinite(p.seconds) || p.seconds < 0) return { ok: false, error: "invalid-request" };
        await mk.seekToTime(p.seconds);
      } else if (operation === "volume") {
        if (!Number.isFinite(p.volume)) return { ok: false, error: "invalid-request" };
        mk.volume = Math.max(0, Math.min(1, p.volume));
      } else if (operation === "repeat") {
        if (!LOOP_MODES.has(p.loopMode)) return { ok: false, error: "invalid-request" };
        if (typeof mk.setRepeatMode === "function") mk.setRepeatMode(p.loopMode === "one" ? 1 : p.loopMode === "all" ? 2 : 0);
      } else if (operation === "prepareNext") {
        try { await alignStorefront(mk); } catch {}
        const idOf = item => logicalIdOf(playableIdOf(item));
        if (String(idOf(mk.nowPlayingItem)) !== p.catalogId) return { ok: false, error: "stale-request" };
        if (!Array.isArray(p.nextIds) || p.nextIds.length > 2 ||
            p.nextIds.some(id => typeof id !== "string" || !CATALOG_ID.test(id))) {
          return { ok: false, error: "invalid-request" };
        }
        if (typeof mk.playLater !== "function") return { ok: false, error: "unsupported" };
        const items = Array.isArray(mk.queue?.items) ? mk.queue.items : [];
        const index = Number.isInteger(mk.queue?.position) ? mk.queue.position :
          items.findIndex(item => String(idOf(item)) === p.catalogId);
        const tail = items.slice(index + 1).map(item => String(idOf(item)));
        if (JSON.stringify(tail) !== JSON.stringify(p.nextIds)) {
          const extendsTail = tail.length <= p.nextIds.length && tail.every((id, i) => id === p.nextIds[i]);
          if (!extendsTail) {
            if (typeof mk.queue?.clearAfterCurrent !== "function") return { ok: false, error: "unsupported" };
            await mk.queue.clearAfterCurrent();
          }
          const append = extendsTail ? p.nextIds.slice(tail.length) : p.nextIds;
          if (append.length) await mk.playLater({ songs: append });
        }
      } else if (operation === "next") {
        await mk.skipToNextItem();
      } else if (operation === "previous") {
        try { await mk.skipToPreviousItem(); } catch { await mk.seekToTime(0); }
      } else if (operation === "toggle") {
        if (mk.isPlaying) {
          if (windowRef.__foliaAppleStart) windowRef.__foliaAppleStart.cancelled = true;
          await mk.pause();
        } else {
          await mk.play();
        }
      } else if (operation !== "status") {
        return { ok: false, error: "invalid-request" };
      }

      const item = mk.nowPlayingItem;
      const rawId = playableIdOf(item);
      const id = logicalIdOf(rawId);
      const position = Number(mk.currentPlaybackTime);
      const duration = Number(mk.currentPlaybackDuration);
      if (windowRef.__foliaAppleStart && String(id) === windowRef.__foliaAppleStart.catalogId && mk.isPlaying) {
        windowRef.__foliaAppleStart.started = true;
      }
      return { ok: true, data: {
        catalogId: String(id),
        ...(windowRef.__foliaAppleFailure ? { errorCode: windowRef.__foliaAppleFailureCode || "playback-failed" } : {}),
        playing: mk.isPlaying === true,
        pageVisible: windowRef.document?.visibilityState === "visible",
        sdkState: Number(mk.playbackState) || 0,
        starting: !!windowRef.__foliaAppleStart && !windowRef.__foliaAppleStart.started,
        position: Number.isFinite(position) && position >= 0 ? position : 0,
        duration: Number.isFinite(duration) && duration > 0 ? duration : 0,
        ended: mk.playbackState === 5 || mk.playbackState === 10,
        previewOnly: mk.previewOnly === true,
        storefront: typeof mk.storefrontId === "string" ? mk.storefrontId.slice(0, 8) : "",
        subscribed: typeof windowRef.__foliaSubscribed === "boolean" ? windowRef.__foliaSubscribed : null,
        failed: windowRef.__foliaAppleFailure === true || (!!windowRef.__foliaAppleStart &&
          !windowRef.__foliaAppleStart.cancelled && !windowRef.__foliaAppleStart.accepted &&
          !windowRef.__foliaAppleStart.started && Date.now() - windowRef.__foliaAppleStart.at > 45_000)
      } };
    } catch (error) {
      return { ok: false, error: "playback-failed", errorCode: errorCode(error),
        errorMessage: String(error?.message || "").split("https://")[0].split("http://")[0]
          .replace(/[A-Za-z0-9_=-]{40,}/g, "[redacted]").slice(0, 160), stage };
    }
  }

  return { dispatch };
}

function installAppleMusicPlaybackDispatcher(windowRef, options = {}) {
  const service = createAppleMusicPlaybackDispatcher({ ...options, windowRef });
  windowRef.__foliaAppleMusicPlaybackDispatch = async request => {
    const result = await service.dispatch(request);
    try {
      windowRef.__foliaAppleMusicPlaybackEvent?.({
        id: typeof request?.id === "string" ? request.id : "",
        payload: result
      });
    } catch {}
    return result;
  };
  return service;
}

module.exports = { createAppleMusicPlaybackDispatcher, installAppleMusicPlaybackDispatcher };
