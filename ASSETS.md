# Atmora asset inventory

Everything in `Assets/` was made for Atmora. There are no third-party recordings, sample packs, loops, icon assets, wallpapers, stock photography, or textures.

## Audio

All eighteen ambience layers, plus the UI click, share the same delivery format:

| Property | Value |
| --- | --- |
| Duration | 40.000 s exactly (1,280,000 frames) |
| Sample rate | 32,000 Hz |
| Channels | Stereo |
| Container / codec | M4A / AAC, 128 kbps |
| Loop construction | 41.5 s generated, final 1.5 s equal-power crossfaded into the head, trimmed to exactly 40 s |
| Normalization | Target RMS with a per-layer peak ceiling; no compression or limiting |
| Reverb | Circular FFT reverb, so tails wrap at the seam |
| Total size | About 12 MB |

### Rainy Cabin

| Layer | File | Default | Synthesis | RMS | Peak |
| --- | --- | ---: | --- | ---: | ---: |
| Rain | `rainy-cabin/rain.m4a` | 0.78 | Stereo shaped noise, roof rumble, and hundreds of short panned drop pings | −20.74 dBFS | −5.50 dBFS |
| Distant Thunder | `rainy-cabin/thunder.m4a` | 0.30 | Three low rumbling events with long reverb, placed across the loop | −32.00 dBFS | −8.08 dBFS |
| Fireplace | `rainy-cabin/fireplace.m4a` | 0.55 | Low bed plus dense fine crackle and occasional larger pops | −25.00 dBFS | −10.33 dBFS |

### Train Compartment

| Layer | File | Default | Synthesis | RMS | Peak |
| --- | --- | ---: | --- | ---: | ---: |
| Rail Rhythm | `train/rhythm.m4a` | 0.72 | Rolling rail bed with paired bogie clacks on a steady joint period | −23.00 dBFS | −8.53 dBFS |
| Carriage | `train/carriage.m4a` | 0.56 | Low carriage rumble, 48/96 Hz hum, body creaks, and fitting rattles | −28.00 dBFS | −13.59 dBFS |
| Distant Horn | `train/horn.m4a` | 0.30 | Two three-note horn events with vibrato and long night reverb | −33.00 dBFS | −11.67 dBFS |

### Sakura Night

| Layer | File | Default | Synthesis | RMS | Peak |
| --- | --- | ---: | --- | ---: | ---: |
| Falling Petals | `sakura-night/petals.m4a` | 0.66 | Breeze-shaped noise with soft petal brushes and a slow stereo drift | −29.00 dBFS | −12.66 dBFS |
| Night Stream | `sakura-night/stream.m4a` | 0.52 | Water over stones, low burble, and sparse droplet pings | −27.00 dBFS | −12.90 dBFS |
| Lantern Chimes | `sakura-night/chimes.m4a` | 0.34 | Restrained pentatonic koto/glass notes, upper partials, and distant insects | −32.00 dBFS | −14.09 dBFS |

### Cloud Library

| Layer | File | Default | Synthesis | RMS | Peak |
| --- | --- | ---: | --- | ---: | ---: |
| Window Rain | `cloud-library/window-rain.m4a` | 0.70 | Soft rain on an arched roof, low rumble, and scattered drops | −27.00 dBFS | −13.25 dBFS |
| Turning Pages | `cloud-library/pages.m4a` | 0.38 | Paper sweeps, a distant clock, settling shelves, and quiet room tone | −34.00 dBFS | −19.90 dBFS |
| Warm Hush | `cloud-library/hush.m4a` | 0.48 | A warm D-major add9 pad, low room tone, and a few hearth-like crackles | −30.00 dBFS | −18.25 dBFS |

### Sunset Drive

| Layer | File | Default | Synthesis | RMS | Peak |
| --- | --- | ---: | --- | ---: | ---: |
| Open Road | `sunset-drive/road.m4a` | 0.56 | Low tire hum, rolling road texture, open-window wind, expansion-joint thumps, and soft gusts | −27.00 dBFS | −12.89 dBFS |
| Radio Song | `sunset-drive/song.m4a` | 0.62 | A warm 84 BPM Fmaj7 / Cmaj7 / G6 / Am7 loop with electric piano, bass, brushed snare, and a singing lead | −25.00 dBFS | −12.15 dBFS |
| Coastal Air | `sunset-drive/air.m4a` | 0.42 | Sea breeze, distant surf swells, and a few far-off gull calls | −28.00 dBFS | −12.99 dBFS |

### Seaside Records

| Layer | File | Default | Synthesis | RMS | Peak |
| --- | --- | ---: | --- | ---: | ---: |
| Vinyl Warmth | `seaside-records/vinyl.m4a` | 0.46 | Warm room hum, fine surface hiss, dense quiet crackle, and occasional dust pops | −34.00 dBFS | −19.35 dBFS |
| Ocean Air | `seaside-records/waves.m4a` | 0.68 | Slow tide-shaped surf, individual wave swells, and a low sea rumble | −25.50 dBFS | −9.00 dBFS |
| Faint Piano | `seaside-records/piano.m4a` | 0.34 | Sparse Cmaj7 / Am9 / Fmaj7 / G6 voicings with independent partial decay and room tone | −35.53 dBFS | −14.00 dBFS |

### UI click

| Sound | File | Synthesis | RMS | Peak |
| --- | --- | --- | ---: | ---: |
| Mouse click | `ui/click.m4a` | A dry plastic contact tick, a short resonant button body, and a quiet low thump; a second, softer release tick follows 20 ms later | −52.29 dBFS | −6.50 dBFS |

The click is a one-shot transient that is effectively over within 120 ms. It is deliberately low-RMS relative to the ambience beds; its peak and the player's volume set its perceived level. It is played once when the ambience changes, through a dedicated `AVAudioPlayer` so it never disturbs the looping ambience graph, and it is excluded from the loop crossfade so its attack stays intact.

The authoritative measured values live in `Assets/Audio/manifest.json`; the tables above are a readable copy.

## In-app scene artwork

The six ambiences are drawn entirely in SwiftUI `Canvas` by `Sources/Atmora/UI/SceneArtwork.swift`. There are no bitmaps inside the app.

- Anime-inspired visual language: saturated gradients, cel-shaded bands, luminous rim light, stylised clouds, and drifting particles.
- Every object participates in the motion: rain, clouds, moon glow, lamp sway, plant leaves, steam, dust, the scrolling train landscape, curtains, the cup, drifting sakura petals, lanterns, a torii, an arched library window, a sleeping cat, floating pages, a golden-hour coastal drive with a glowing stereo and drifting notes, sea glints, a turning record, and dust in window light.
- When animation is active the whole scene is redrawn inside a `TimelineView`, rather than compositing a static base with a small motion overlay.
- The same renderer feeds the main window, the menu-bar thumbnail, and the Living Desktop preview.
- Optional Living Desktop effects live in `Sources/Atmora/UI/DesktopEffectsOverlay.swift`: ambience-tinted bloom and ambience-specific drifting particles, each independently switchable with a shared intensity.

## Desktop wallpapers

Six original still wallpapers live in `Assets/Wallpapers/`, one per ambience. They are bundled as reference stills and packaging assets; Living Desktop itself never writes them to the system desktop.

| Property | Value |
| --- | --- |
| Dimensions | 3840 × 2160 (4K UHD, 16:9) |
| Format | JPEG, quality 90 |
| Size | About 0.6–0.8 MB each |
| Generator | `Tools/generate_wallpapers.py` |
| Construction | Vertical gradients, radial glows, procedural geometry, grain, and vignette |
| Third-party content | None |

| Ambience | File | Composition |
| --- | --- | --- |
| Rainy Cabin | `rainy-cabin.jpg` | A warm-lit cabin window, rain streaks, droplets, mullions, and amber interior light |
| Train Compartment | `train.jpg` | A night train window with moon, hills, village lights, curtains, seats, and a cup |
| Sakura Night | `sakura-night.jpg` | A moonlit river, a vermilion torii, strung paper lanterns, a cherry tree, falling petals, and fireflies |
| Cloud Library | `cloud-library.jpg` | An arched window above a cloud sea, a bookcase, a pendant lamp, an armchair with a sleeping cat, and a candle |
| Sunset Drive | `sunset-drive.jpg` | A golden-hour coastal road, a low sun over the sea, a small car ahead, cypress silhouettes, and a warm dashboard |
| Seaside Records | `seaside-records.jpg` | A warm record shop with a sea-view window, record shelves, a turntable, a pendant lamp, and dust in the light |

The wallpapers are calmer and less detailed than the animated in-app scenes. They are composed to keep desktop icons and text legible rather than to reproduce a frame of animation. Random seeds are fixed per wallpaper, so the geometry and grain are deterministic.

### Regenerating wallpapers

Requirements: Python 3, NumPy, Pillow.

```sh
python3 Tools/generate_wallpapers.py
```

The script writes all six JPEGs to `Assets/Wallpapers/`. It uses the same broad palette and forms as the app, but the compositions are generated independently rather than captured from SwiftUI.

## Why the loops are seamless

1. Each layer is generated at 41.5 seconds.
2. The last 1.5 seconds are crossfaded into the first 1.5 seconds with an equal-power curve, then the result is trimmed to exactly 40 seconds.
3. Reverb is applied circularly, so decays wrap around the loop instead of ending abruptly.
4. The test suite decodes every file and compares the jump from the last sample to the first sample against the largest ordinary sample-to-sample jump in the file. A seam jump larger than that fails the test.
5. The app schedules the decoded buffer with `AVAudioPlayerNode.scheduleBuffer(..., options: .loops)`, so playback repeats without re-triggering the file.

## Regenerating audio

Requirements: Python 3, NumPy, and macOS `afconvert`.

```sh
python3 Tools/generate_audio.py
```

The script writes the `.m4a` files and `manifest.json`. Random seeds are fixed per layer, so the synthesis is deterministic. AAC encoder output can vary slightly by macOS version, which may change file sizes and measured peak values.

## Brand and app icon

Atmora's identity is a quiet horizon with a warm semicircle of light resting on it, plus one or two restrained reflection strokes. The same geometry is used in three places:

- **`BrandMark` / `BrandLockup`** in `Sources/Atmora/UI/BrandMark.swift`: the standalone in-app symbol and the horizontal wordmark used in the window and menu-bar headers.
- **`Assets/AppIcon.icns`**: a 2048 px squircle source with the horizon, sun, and reflection, generated by `Tools/generate_icon.py`.
- **`MenuBarIcon`**: an 18 pt template glyph using the same horizon and semicircle, drawn with AppKit paths so it stays crisp and adapts to the menu-bar appearance.

The icon deliberately avoids text, crescent moons, leaves, and stock meditation imagery. The mark is built from clean geometry so it remains recognizable at 32 px and 16 px.

`Tools/generate_icon.py` renders the 2048 px source, produces every required iconset size, and calls `iconutil`.

Requirements: Python 3, NumPy, Pillow.

```sh
python3 Tools/generate_icon.py
```

The intermediate `Assets/AppIcon.iconset` directory is removed after the `.icns` is written.

## Licensing

The audio is dedicated to the public domain under **CC0 1.0 Universal**. This is recorded in `Assets/Audio/manifest.json`. The icon, brand mark, menu-bar glyph, and six wallpapers were made for this project and contain no third-party imagery.

No source-code license has been chosen for the repository. The app itself links only Apple frameworks; the asset tooling uses NumPy and Pillow.
