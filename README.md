# StylusDeck

<p align="center">
  <img src="assets/brand/stylusdeck-logo.png" alt="StylusDeck logo" width="320">
</p>

<p align="center">
  A macOS live-audio control surface for drawing tablets, pen displays, mice, and macro-key setups.
</p>

<p align="center">
  <img src="assets/screenshots/volume-window.png" alt="StylusDeck screenshot" width="100%">
</p>

## What It Does

StylusDeck taps live system audio and gives you instant absolute-position control over:

- volume
- 3-band EQ
- DJ filter
- echo
- output trim
- limiter ceiling

It plays the wet signal to your real output device and mirrors the same processed signal to `BlackHole 2ch` for OBS.

## Quick Start

```bash
./start.sh
```

That script will:

- check macOS prerequisites
- install `BlackHole 2ch` if needed
- build the app
- install `~/Applications/StylusDeck.app`
- launch StylusDeck

After setup, you can open `~/Applications/StylusDeck.app` directly from Finder.

## Control Model

StylusDeck uses one active lane at a time:

- `Y` = main control
- `X` = companion control
- `Shift + X` = tertiary/shape-style control on supported lanes

### Main Bank

- `1` Volume: `Y` volume, `X` trim, `Shift + X` limiter ceiling
- `2` Low: `Y` gain, `X` frequency, `Shift + X` slope
- `3` Mid: `Y` gain, `X` frequency, `Shift + X` Q
- `4` High: `Y` gain, `X` frequency, `Shift + X` slope

### FX Bank

Press `5` to switch to `FX`.

- `1` Filter: `Y` sweep, `X` resonance, `Shift + X` character
- `2` Unused
- `3` Unused
- `4` Echo: `Y` wet, `X` time, `Shift + X` feedback

## Shortcuts

- `1` `2` `3` `4` select the lane in the current bank
- `5` toggle `MAIN` / `FX`
- `6` reset the current parameter
- `C` keyboard alias for reset
- `F` toggle fullscreen
- `Mode` switch between Drag and Hover

## Visualizer

StylusDeck includes a native visualizer with a `Visuals` panel.

- visualizer is **off by default**
- available modes: `Wave Ribbon`, `Radial Halo`, `Spectrum Bars`, `Orbit Sphere`
- while the `Visuals` panel is open, pointer movement does not affect sound

The visualizer is still a **work in progress**. Expect performance issues when visuals are enabled, especially in heavier modes.

## Running

Native app:

```bash
./start.sh
```

or:

```bash
./scripts/run.sh
```

Optional web UI:

```bash
./scripts/run-web.sh
```

## Requirements

- macOS
- Xcode Command Line Tools
- Homebrew
- `BlackHole 2ch`

## OBS

In OBS, add `Audio Input Capture` and choose `BlackHole 2ch`.

## Notes

- Keep StylusDeck running while you want live processing active.
- On normal exit, it restores temporary audio-routing changes.
- The native app is the primary experience.
