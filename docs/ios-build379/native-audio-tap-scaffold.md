# Native audio-tap analyzer scaffold

> This is a newly authored AVFoundation / MediaToolbox implementation informed by symbols and string labels in the supplied build-379 executable. It is not the recovered original DSP source.

## Binary evidence used

The supplied executable includes `NativeAudioTapAnalyzer`, `MTAudioProcessingTap`, the init/finalize/prepare/unprepare/process callback names, and analyzer fields labelled `alpha150`, `alpha400`, `alpha1200`, `alpha3500`, `alpha12000` plus corresponding low-pass state fields. The web callback contract exposes an `audio` event with `power`, `bass`, `lowMid`, `mid`, `vocal`, and `treble`.

These identifiers support the existence of an audio-tap based analyzer with several frequency split stages. They do not reveal the original filter design, sample scaling, RMS/peak method, window length, attack/release smoothing, or output normalization.

## Replacement implementation

`compat/ios-bridge/ios/NativeAudioTapAnalyzer.swift`:

- Creates an `MTAudioProcessingTap` and installs it into `AVMutableAudioMixInputParameters` for the current audio track.
- Supports common Float32, Int16, and Int32 sample formats, mono/stereo or multiple buffer layouts.
- Splits audio using one-pole low-pass stages at 150, 400, 1,200, 3,500, and 12,000 Hz.
- Calculates RMS envelope estimates for the overall signal and adjacent frequency bands.
- Applies a simple envelope smoothing step and bounds each output to 0...1.
- Publishes at no more than 20 callbacks per second on the main queue.
- Uses a separately retained tap cookie with a weak analyzer reference so the processing tap does not keep the host player alive.

`FoliaAVPlayerEngine` attaches the mix when an AVPlayerItem becomes ready and removes it when the item is replaced. The native callback is published as:

```json
{
  "type": "audio",
  "session": "web-session-id",
  "generation": 3,
  "power": 0.42,
  "bass": 0.21,
  "lowMid": 0.14,
  "mid": 0.18,
  "vocal": 0.11,
  "treble": 0.08
}
```

The six numeric values are illustrative, not captured output. `compat/ios-bridge/audio-event-adapter.js` validates the event envelope and normalized band ranges before it is passed to a visualizer.

## Integration and runtime caveats

- The audio tap only exists on the AVPlayer-backed path. It does not analyze MusicKit, a WebAudio element, system-wide audio, or every protected/DRM media path.
- Some formats, assets, or playback routes may reject audio-mix tap installation or provide a sample format not supported by this scaffold. In that case the player continues without visualization data and emits a bounded analysis error.
- The cutoff labels come from binary fields, but the one-pole filter implementation and normalization are a proposed compatibility model; do not assume its amplitudes match build 379.
- The processing callback must remain lightweight. Device profiling is required to check allocations, buffer layout, CPU usage, thermal impact, and glitches at real sample rates.
- Compare captured `audio` events against the original app for silence, sine sweeps, pink noise, speech, bass-heavy music, low-volume tracks, and route changes before calibrating UI thresholds.
- The original analyzer's exact source, data flow, and runtime output were not recovered from the IPA. This scaffold must be compiled against the target iOS SDK and tested on devices before shipping.


## Host wiring note

The audio analyzer publishes through the same `window.__foliaNativePlayerEvent` callback as the player transport. The optional JS guard/adapter is available at `compat/ios-bridge/audio-event-adapter.js`; it is a validation utility for test/consumer code, not a rewrite of the immutable production Folia bundle. A host that uses the exact bundled page should verify its audio-event handling before assuming the new event names update every visualizer renderer.
