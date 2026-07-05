# LabelBot — Plan

A macOS app for printing labels to a **Brother PT-P710BT** ("P-touch Cube Plus"),
primarily for labeling Gridfinity bins (screws, threaded inserts, etc.).

## Decisions

- **Platform:** macOS SwiftUI app (this repo).
- **Transports:** Both **USB** and **Bluetooth**, behind one protocol.
- **Rendering:** Pure Swift (CoreText / CoreGraphics → Brother raster), no external deps.
- **First label:** Plain single-line text, auto-sized to tape width.

## How the printer works

The PT-P710BT has no third-party SDK. You drive it with Brother's **raster command
language** — a documented byte protocol
([Software Developer's Manual](https://download.brother.com/welcome/docp100064/cv_pte550wp750wp710bt_eng_raster_102.pdf)).

- **Bluetooth is Bluetooth _Classic_ (SPP / RFCOMM)**, not BLE → use **IOBluetooth**
  on macOS, not CoreBluetooth. Printer must be paired in System Settings first.
- **USB** presents as a Brother printer-class device (vendor id `0x04F9`). macOS's
  built-in USB printing class driver may claim it — the main risk to de-risk.
- Print engine: **180 dpi**, TZe tape **3.5–24 mm**. Raster line = **128 dots (16 bytes)**.

Print flow (same for both transports):

```
ESC @              reset
ESC i a 01         raster mode
ESC i z ...        print info (media type / width / #raster-lines)
ESC i M / ESC i K  autocut / advanced mode
M 00               compression off (Phase 0)
G <len> <bytes>    one raster line per column of the image, repeated
1A                 print + feed
```

Status is a 32-byte reply (request with `ESC i S`) → cover-open, no-tape, wrong-width.

## Prior art (protocol references, all Python)

- [treideme/brother_pt](https://github.com/treideme/brother_pt) — clean raster impl, P710BT verified.
- [robby-cornelissen/pt-p710bt-label-maker](https://github.com/robby-cornelissen/pt-p710bt-label-maker) — PNG→raster over Bluetooth.
- [labelprinterkit](https://pypi.org/project/labelprinterkit/) / [brother-label](https://pypi.org/project/brother-label/).

## Architecture

```
LabelRenderer      String + TapeConfig  →  1-bit bitmap        (CoreText / CoreGraphics)
RasterEncoder      bitmap               →  Brother raster Data  (ESC-command packer)
PrinterTransport   protocol { connect / send / readStatus / disconnect }
   ├─ USBTransport         (IOKit / IOUSBHost bulk endpoint)
   └─ BluetoothTransport   (IOBluetooth RFCOMM / SPP)
PrinterManager     @Observable — discovery, connection state, print()
ContentView        text field · tape picker · connect · print · status
```

## Phases

- **Phase 0 — Transport spike (de-risk).** Push a hardcoded test bitmap (solid bar)
  over both USB and Bluetooth; read status. Proves connectivity before building on top.
  _Requires the physical printer (USB cable + Bluetooth paired)._
  - ✅ **USB validated** (2026-07-04): test label prints.
  - ⏳ Bluetooth: not yet validated on hardware.

  Confirmed hardware facts:
  - PT-P710BT USB **VID 0x04F9 / PID 0x20AF**; printer interface class 7,
    bulk **OUT 0x02 / IN 0x81**.
  - Must run **unsandboxed** — a sandboxed app can't seize the printer-class USB
    interface even with `com.apple.security.device.usb`.
  - Modern IOUSBHost: a top-level `idVendor` match key finds nothing; enumerate the
    class and filter in code.
  - Printer requires **TIFF/PackBits-compressed** raster (`M 0x02`), lines framed as
    `0x47 <len-LE16> <packbits>` / `0x5A` for blank. Uncompressed data prints nothing
    yet reports no error.
- **Phase 1 — Renderer + encoder.** `String → 1-bit bitmap → raster`, correct for
  12 mm & 24 mm tape, verified on real tape.
  - ✅ **Validated on 24 mm** (2026-07-04): single-line text prints upright, correct
    orientation with `reverseLength = false`, `flipAcross = false`.
  - Tape pin table (ptouch-print): 6→32, 9→50, 12→70, 18→112, 24→128 dots,
    centered (offset = (128 − dots)/2). Only 24 mm exercised so far.
- **Phase 2 — App UI.** Text field, tape-width picker, transport picker, connect +
  print, live status/errors.
- **Phase 3 — Polish.** Remember last connection + auto-reconnect, print preview,
  human-readable errors from status bytes.

- **Fastener icons** (2026-07-04): drive + head type pickers, layout icons-left /
  text-right. Two icon sources:
  - **Drawn** — our own vector icons (Core Graphics), license-clean, crisp on tape.
  - **Imported** — image files dropped in `~/Library/Application Support/LabelBot/Icons/`,
    named `head-<type>.<ext>` / `drive-<type>.<ext>` (png/pdf/svg). For comparing
    against other icon sets you export yourself.

  Note: `label.alch.shop` icons are opentype.js font glyphs extruded in three.js
  (proprietary, no license) — not liftable SVGs. Use only as visual inspiration.

  Icon styles (drawn): **Simple** = separate head side-profile + drive top view;
  **Bolt** = one integrated bolt with a zig-zag threaded body and the drive cut
  into the head face. The Bolt style reimplements the look of
  [ndevenish/gflabel](https://github.com/ndevenish/gflabel)'s `webbolt` fragment
  (BSD-3-Clause) in Core Graphics — proportions/geometry borrowed, no code copied.
  Head map for Bolt: pan→rounded corner, countersunk→cone, socket/hex/flange→
  rectangle, button→dome, grub/none→plain body.

- **Structured options** (2026-07-04): label spec built from Category
  (Screws/Bolts · Nuts & Washers · Threaded Inserts) → contextual Head/Drive/Thread
  for screws → Units (Metric/Imperial) → Size entry toggle (guided pickers *or* free
  text) → optional custom text. Icons switch by category (screw head+drive, hex nut,
  insert barrel); wood screws draw a pointed shaft. Insert icon is a bit busy — refine.

- **Batch printing** (2026-07-04): the app edits a *queue* of labels, not one.
  - `LabelSpec` (Codable/Equatable/Identifiable) is one label's full config; the
    tape width is shared across the batch (it's the physically loaded tape).
    `PrinterManager` holds `labels: [LabelSpec]` + `selection`; `current` is a
    get/set binding to the selected spec.
  - UI: `HSplitView` master-detail — a queue list (thumbnail + summary, add /
    duplicate / delete / reorder, per-label copies) on the left, the editor on the
    right; log pane below. Toolbar "Print all · N", a Batch menu (open / save JSON /
    add-from-list), and a "cut between labels" toggle.
  - **Print / cut / print / cut**: one `RasterEncoder.batchJob` — the init/header is
    sent once, then per page `ESC i z` + margin + `M 02` + raster + terminator. Pages
    before the last end with `0x0C` (print), the last with `0x1A` (print + feed).
    Auto-cut (`ESC i M 0x40`) + "cut every 1 label" (`ESC i A 0x01`) cut between each.
    Verified at the byte level in `LabelBotTests`; not yet run on hardware.
  - Bulk create: "add from list" turns a pasted list of sizes into one label each,
    using the selected label as a template. Save/open a batch as JSON (`LabelBatch`).

## Later (beyond part 1)

Multi-line + fonts → Gridfinity templates (name + size + icon) → symbol/icon library.
Per-label progress would need sequential jobs (poll status to "ready" between labels)
instead of the single multi-page job.

## Entitlements

Sandboxed app needs `com.apple.security.device.usb`,
`com.apple.security.device.bluetooth`, and `NSBluetoothAlwaysUsageDescription`.
