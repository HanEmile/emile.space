(meta
  (tag "project")
  (published "2026-11-14")
  (modified "2026-11-14")
  (author "Emile")
  (info "tag")
)

# lorahal: my LoRa gateway work, but as a library

I've been running a MikroTik R11e-LR8 LoRaWAN concentrator card on one of my
mini PCs for a couple of days now. If you google it, the literature tells you
the card only really works on RouterBOARDs, that it speaks SPI over the
miniPCIe connector, and that the USB connector is just a myth. That's mostly
outdated: the card I have has an STM32 bridge on board that exposes the SPI
bus as USB CDC-ACM, so on a €2 mPCIe→USB dongle it appears as `/dev/ttyACM0`
on anything that has a USB port.

The protocol that bridge has been speaking all along is Semtech's own
"PicoCell GW" protocol — Semtech once built a development gateway called the
PicoCell GW that used the same STM32↔SPI-to-SX1301 arrangement, and
MikroTik's card follows the same on-wire conventions. Which means the
userspace driver for using this card without RouterOS already existed *
almost*: `Lora-net/picoGW_hal`, a BSD-licensed C blob from Semtech, last
maintained around the time of 2017.

This stack of anecdotes was convincing enough that I decided the right shape
for my tooling is a library, and this is the post where `lorahal` becomes
public: a pure Go port of the host side of picoGW_hal, split into a bridge
package (the serial wire protocol, framing, resync, burst chunking) and a HAL
package (SX1301 driver with calibration, AGC/arbiter firmware upload, config,
RX, TX, airtime computation).

## the fun discoveries

The STM32 on these cards has opinions. Some of them, decoded after a day of
watching tcpdump, uart traces and the C reference implementation:

- `l` is the version handshake. You send your expected bridge firmware
  version as a 4-byte word and the MCU ACKs iff compatible. MikroTik shipped
  `0x010a0004` on these; the card I have likes `0x010a0006` too. The Go
  driver probes a small list and reports which value satisfied the MCU.
- Register reads can go sideways if you don't chunk the burst reads the way
  the MCU wants them (first/middle/end frames, 900 B chunks, vendor replies
  include status bytes anyone writing a driver will trip over at least twice
  — e.g. the classic "byte" (uint8_t)(ans[42] << 8) truncation in the C code
  amounts to "packet size is actually always at most 255 anyway").
- After every MCU reset, the card bounces through a "LoRa GW Bootloader"
  USB session for ~3 s before the application enumerates. Rude, but once
  you know, fine.
- Some long-running send calls randomly NAK after uptime. I now retry after
  a full firmware reload + reconfiguration, which also turned out to be the
  architecture decision that makes the whole thing self-healing anyway.

Verified working: version handshake, both calibrations, firmware upload,
start, RX with EU868 multi-SF configs, TX (airtime + self-heal), Semtech
UDP packet forwarding to TTN. Currently running 24/7 at my window sill
connected to
[my gateway on TTN](https://eu1.cloud.thethings.network/console).

## what it's for

The same setup that used to require an iC880a USB card for a hundred euros
plus an SPI-respecting SBC now runs on anything with a USB port, which for
me meant "N100 mini PC with NixOS + my fleet tooling would like to join
please". The package is
[github.com/HanEmile/lorahal](https://github.com/HanEmile/lorahal) — small
dependency surface (a serial library and stdlib), BSD-3 with the Semtech
attribution kept where it belongs, firmware blobs still loaded verbatim from
the reference implementation.

Boilerplate:

```go
h, _ := hal.Connect("/dev/ttyACM0")
defer h.Close(false)
h.BoardSetconf(hal.BoardConf{LorawanPublic: true, ClkSrc: 1})
h.RxrfSetconf(0, hal.RxRFConf{Enable: true, FreqHz: 867500000, ...})
// ...
pkts, _ := h.Receive(16)
```

The surrounding gateway/controller-thing that already runs on my router
(lora8 — web UI, Semtech UDP forwarder to TTN, prometheus metrics, JSONL
frame history, wireshark-style frame inspection incl. per-node payload
decryption when you own the AppSKey) is just one consumer of the library
now, and if there's one part of this I'm going to enjoy keeping around, it's
probably the part where a LoRaWAN concentrator is just a library import.
