# AI Denoise and Lightroom SDK gaps — research notes

Status: research log, not a spec. Recorded 2026-10-05 on Lightroom Classic 15.5.1
(Windows), plugin SDK 15.0, process version 15.4, Canon CR3 raw.
Tool used: `src/plugin/DevelopSettingsProbe.lua` (File > Plug-in Extras >
Dump develop settings (diagnostic)); output `DevelopSettingsDump.txt` in the
MIDI2LR log folder.

## 1. How non-destructive AI Denoise is stored (observed, LrC 15.5.1)

- There is **no top-level develop setting** for Denoise. `getValue` returns `nil`
  for `Denoise`, `DenoiseAmount`, `EnableDenoise`, `AIDenoise*`,
  `EnhanceDenoise*`, `RawDetails`, `SuperResolution`, `ReflectionRemoval*`.
- **`getRange` is not a validity test**: it returns `-100,100` for any unknown key.
- Denoise lives in the develop setting **`FilterList`** (readable via
  `photo:getDevelopSettings()` and `LrDevelopController.getValue('FilterList')`,
  identical content):
  - Denoise off: `FilterList = {}`.
  - Denoise on: `FilterList.Filters[1]` with `Name = "Enhance"`,
    `Title = "$$$/CRaw/Filter/Title/Denoise=Denoise"`, `FilterID = 1`,
    `OrderIndexN = 100000`, `ShouldDeleteImagesDueToUpstream = true`,
    Src/Dst bounds, `MinDisplayVersion = MinEditVersion = 285212672`,
    `CompressedSettings = <MD5>`, `Table_<MD5> = <encoded blob>`, `Images = {...}`.
  - Turning Denoise on also sets `ColorNoiseReduction` to 0 (default 25).
- **Blob encoding** (`Table_<MD5>`), verified by decoding both samples:
  1. Adobe base-85, alphabet
     ``0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?`'|()[]{}@%$#``,
     5 chars -> 4 bytes little-endian, least-significant digit first
     (a trailing group of n chars yields n-1 bytes).
  2. First 4 bytes = uncompressed length (LE), rest = zlib stream.
  3. Uncompressed payload = 16-byte header (four LE uint32: `3, 1, 1, <xmp length>`)
     followed by an XMP packet.
  4. `CompressedSettings` and the `Table_` suffix = **uppercase MD5 of the
     uncompressed payload** (header + XMP). Verified for both samples.
- Decoded XMP (Amount 25 / 60):
  ```
  crs:Details="False"  crs:SuperResolution="1/1"  crs:Denoise="True"
  crs:DenoiseLumaAmount="25" | "60"  crs:UpstreamWasBaked="False"
  ```
- Amount 25 vs 60 — the only differences in the whole dump:
  | field | 25 | 60 |
  |---|---|---|
  | `DenoiseLumaAmount` (in blob) | 25 | 60 |
  | `CompressedSettings` | EE676A53141BE0B627A347C7DB292A60 | 478A05E843875CCBE35FEAA1DF36CC33 |
  | `Images[1].BlendParams[1]` | 469762048/2^30 = 0.4375 | 835132530/2^30 = 0.7778 |
  | `Images[1].BlendParams[2]` | 536870912/2^30 = 0.5 | 878516038/2^30 = 0.8182 |
  The AI result identifiers (`GroupDigest`, `OriginalInstanceDigest`,
  `GlobalInputDigest`) are unchanged: the AI image is computed once and the
  Amount is applied as a blend. Amount -> BlendParams formula unknown (2 points only).

## 2. Implications for MIDI2LR

- **Read-only status** (Denoise on/off + Amount in a bezel): feasible. Needs a
  pure-Lua zlib inflate (e.g. LibDeflate, zlib licence) + the base-85 decoder.
- **Changing the Amount** on a photo that already has Denoise: plausibly feasible,
  untested — rewrite XMP, re-encode, recompute MD5 (`LrMD5`), update BlendParams
  (formula needed, or check whether LrC recomputes them), write via
  `applyDevelopSettings`. Unsupported/undocumented; may break with LrC updates.
- **Turning Denoise on** has no dedicated SDK call. Candidate routes, untested:
  1. Develop preset that includes Denoise, applied with
     `photo:applyDevelopPreset(preset, nil, nil, true)` (4th arg `updateAISettings`,
     LrC 13.3+). The plugin currently omits the 4th arg (`Presets.lua`).
  2. Copy/paste settings (plugin already simulates Ctrl+C/Ctrl+V).
  3. Writing a `FilterList` without `Images`, then `photo:updateAISettings()`.
  An Amount control is only worth building once one of these works.
- Enhance dialog shortcut (older Enhance workflow): Ctrl+Alt+I (Win) /
  Control+Option+I (Mac) — source: jkost.com (Adobe), not re-verified on 15.x.

To collect more data: run the probe on the same photo at Amounts 0, 10, 50, 75, 100
(fits the BlendParams formula), and with Raw Details / Super Resolution toggled.

## 3. SDK features available but not used by the plugin

Sources: John R. Ellis's per-version "Changes to the LR SDK" threads on
community.adobe.com (diffs of the official API docs; the official reference
ships only inside the SDK zip), Adobe bug threads with staff replies,
Lightroom Queen release notes. Secondary sources; verify before relying on them.

| API | Purpose | Min LrC | Value |
|---|---|---|---|
| `UpdateAISettings` / `UpdateAISettingsAll` commands (implemented in ClientUtilities.lua, commented out in Database.lua since 2025-05-22) | recompute AI masks/adaptive | 13.3 (race fixed 15.6) | high |
| `photo:applyDevelopPreset(..., updateAISettings)` | presets with AI parts get computed | 13.3 | high |
| `setValue('PointColors', table)`, `ColorVariance` | global Point Color | 13.0 / 15.0 | high |
| Spot API: `getAllSpots`, `countAllSpots`, `get/setSelectedSpot*`, `moveSelectedSpot`, `deleteSelectedSpot` | heal/clone/remove by knob | 14.0 | med-high |
| `goToRemove`, `goToEyeCorrection` | open panels | 14.0 | med |
| `gotoNextVariation`, `gotoPreviousVariation`, `deleteSelectedVariation` | Generative Remove variations | 14.0 | med |
| `LensBlurCatEye` (getRange 0..100 observed), other LensBlur sub-keys | lens blur | 13.0/14.0 | med |
| `ToneCurvePV2012Red/Green/Blue` (readable, observed); PointCurve up/down commands commented out in Database.lua | per-channel curves | old | med |
| `photo:createDevelopSnapshot` | snapshot | old | med |
| LrSelection `selectAll/None/Inverse/First/Last`, `deselectOthers`, `clearLabels`, `removeFromCatalog` | selection | <=14.3 | med |
| `EnableDistractionRemoval` (readable, observed true), `HDRMaxValue` (observed 2.3), `AILook` (table) | toggles | 11-15 | low-med |
| `setValue(..., withClippingOn)`, `gridView`, `toggleSecondaryDisplayFullscreen`, `deleteAllEmptyMasks`, `LrApplication.shutdown` | misc | 5-14.3 | low |

Not possible via SDK (keyboard shortcuts only): running the Enhance dialog,
copy/paste/sync settings dialogs, brush size/flow/density and mask painting,
duplicate/rename mask, soft proofing, Match Total Exposures.
