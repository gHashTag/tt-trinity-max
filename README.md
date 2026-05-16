# TRI-1 Max — Dual-cluster Trinity GF16 mesh (8 tiles)

> 🌳 Trinity role: **BRANCH-SILICON** — TTSKY26b shuttle SKU 3 of 3 (stretch).
> Siblings: [tt-trinity-nano](https://github.com/gHashTag/tt-trinity-nano) (Nano), [tt-trinity-gf16](https://github.com/gHashTag/tt-trinity-gf16) (Mid).
> Spec: [TRI_NET_SHUTTLE_TRIAD](https://github.com/gHashTag/tt-trinity-gf16/blob/main/docs/architecture/TRI_NET_SHUTTLE_TRIAD.md) · EPIC [trinity-fpga#49](https://github.com/gHashTag/trinity-fpga/issues/49) L-DPC7.

**Anchor:** φ² + φ⁻² = 3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)

## What it is

The stretch member of the **TRI-1 Triad**: eight Trinity GF16 ternary MAC
tiles arranged as two independent `trinity_mesh_2x2` clusters behind a
supervisor router. Cluster selection rides on `lane[3]` of the 32-bit
Trinity packet — a previously-reserved bit — keeping packet ABI
byte-identical to Mid for all single-cluster workloads.

| SKU | Tiles | Clusters | Spaces |
|-----|-------|----------|--------|
| Nano | 1 | n/a (single tile) | 1×1 |
| Mid  | 8×2 = 16 cells | flat | full canonical |
| **Max** | **8** | **2 × mesh_2x2** | **2×2 (this repo)** |

### Why dual-cluster, not 4×4

The current Trinity packet (`trinity_packet.vh`) reserves only 2 bits for
the tile dst field — 4 is the hard ceiling of a single mesh in v0.
Doubling that to 4 bits is a wire-format break; the dual-cluster
approach **doubles compute without breaking ABI** by stacking two
crossbars and selecting via `lane[3]`.

All three Triad SKUs drive the **same canonical constant `0x47C0`** on
`{uio_out, uo_out}` right after reset — that equality is the cross-die
anchor of **TG-TRIAD-X (Theorem 36.1)** in
[PhD chapter 36](https://github.com/gHashTag/trios/blob/main/docs/phd/chapters/flos_70.tex).

## Architecture

```
                 ┌──────────────────────────────────────────────┐
                 │            tt_um_trinity_max (top)            │
                 │                                              │
   ui_in[0]      │   ┌─────────────────────────────────────┐    │
   load_mode ───►│   │ canonical gf16_dot4(1,2,3,4)         │    │──► uo + uio = 0x47C0
                 │   │   (combinational, always live)       │    │    (default)
                 │   └─────────────────────────────────────┘    │
                 │                                              │
   ui_in[7]      │   ┌─────────────────────────────────────┐    │
   byte_valid    │   │ 4-beat byte ingress (uio_in)         │    │
   ui_in[6:5]    │   │ + commit_strobe -> 32-bit pkt        │    │
   in_beat   ───►│   │ + cluster_sel from lane[3]           │    │
   ui_in[4]      │   └─────────────────────────────────────┘    │
   commit_s      │                                              │
                 │   ┌─────────────────────────────────────┐    │
                 │   │  trinity_dual_cluster                │    │
                 │   │    ├── cluster0 = trinity_mesh_2x2  │    │
                 │   │    │      ├── tile 0..3              │    │
                 │   │    └── cluster1 = trinity_mesh_2x2  │    │
                 │   │           ├── tile 4..7              │    │
                 │   │    + round-robin eject arbiter       │    │
                 │   └─────────────────────────────────────┘    │
                 │                                              │
   ui_in[3]      │   ┌─────────────────────────────────────┐    │
   eject_ready ─►│   │ eject_word mux (host reads via       │    │──► uo + uio
   ui_in[2:1]    │   │   out_beat[0..3] of host_out_pkt)    │    │    (load_mode=1)
   out_beat   ──►│   └─────────────────────────────────────┘    │
                 └──────────────────────────────────────────────┘
```

## Hard constraints

| Rule | Statement | Enforced |
|------|-----------|----------|
| **R-SI-1** | 0 new `*` operators in synthesisable RTL | `gf16_mul` is XOR-only |
| **R-SI-2** | 0 DSP / multiplier macros | OpenLane2 reports |
| **R-SI-3** | WNS ≥ 0 ns at 50 MHz on SKY130A | OpenLane2 STA |
| **R-SI-4** | DRC-clean | OpenLane2 KLayout DRC |
| **R-SI-5** | LVS-clean | OpenLane2 LVS |
| **R-SI-6** | Apache-2.0 only, no vendor IP | LICENSE + headers |
| **R-SI-7** | Packet ABI backward-compat with Mid for cluster0 | lane[3]=0 paths preserved |

## Build

```bash
# Local cocotb test (icarus)
cd test && make

# GDS via GitHub Actions
git push
# → .github/workflows/gds.yaml
# → OpenLane2 SKY130A → DRC + LVS + STA → gds_artifact
```

## Pin mapping

```
ui_in[0]  = load_mode
ui_in[1]  = eject_beat[0]    out_beat in load_mode=1
ui_in[2]  = eject_beat[1]
ui_in[3]  = eject_ready
ui_in[4]  = commit_strobe    rising edge -> issue assembled pkt
ui_in[5]  = in_beat[0]
ui_in[6]  = in_beat[1]
ui_in[7]  = byte_valid       latch uio_in into in_beat
uio_in    = byte (host -> chip)
uo_out    = result[7:0]
uio_out   = result[15:8]
uio_oe    = 8'hFF
```

## Fallback footprint

If 2×2 tiles fail closure on SKY130A at 50 MHz, the same RTL fits in
1×2 with the `trinity_dual_cluster` body unchanged (utilisation rises
from ~30% to ~60%). Documented in `docs/architecture/MAX_FOOTPRINT.md`
(committed alongside spec to tt-trinity-gf16).

## Provenance

- **License:** Apache-2.0 (see [LICENSE](LICENSE))
- **DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
- **Author:** Dmitrii Vasilev <admin@t27.ai>, ORCID [0009-0008-4294-6159](https://orcid.org/0009-0008-4294-6159)
- **Defense:** 2026-06-15
- **Shuttle:** TinyTapeout TTSKY26b, close 2026-05-18

## See also

- Nano: [tt-trinity-nano](https://github.com/gHashTag/tt-trinity-nano)
- Mid:  [tt-trinity-gf16](https://github.com/gHashTag/tt-trinity-gf16)
- PhD chapter: [`flos_70.tex` — Ch. 36 TRI-1 Triad, Theorem 36.1 TG-TRIAD-X](https://github.com/gHashTag/trios/blob/main/docs/phd/chapters/flos_70.tex)
- EPIC: [trinity-fpga#49 L-DPC7](https://github.com/gHashTag/trinity-fpga/issues/49)
- Throne: [trios#264 Queen's Registry](https://github.com/gHashTag/trios/issues/264)

---

## 🟢 Bazaar Doctrine · Green AI Manifesto

This chip is part of the **TRI-NET** — an open ternary neuromorphic substrate
released under [Apache-2.0](LICENSE) for the decentralized hardware bazaar.

### Honest performance disclosure (R5-HONEST)

| Metric | Measured (SKY130 130nm) | Architecture target (22FDX 22nm projection) |
|---|---|---|
| TOPS/W | proof-of-concept node | 28-120 TOPS/W (peer-review pending) |
| Energy/op | educational node | competitive vs Hailo/Mythic at advanced node |

The SKY130A demonstrator validates **architecture**, not absolute silicon performance.
Production-grade tape-out requires migration to advanced node.

### Green AI alignment

- **Ternary {−1, 0, +1}** — ~10× energy/op vs FP16 at equivalent accuracy
  ([BitNet b1.58, Microsoft Research 2024, arXiv:2402.17764](https://arxiv.org/abs/2402.17764))
- **0 DSP / 0 `*`** — R-SI-1 RTL constraint eliminates multiplier switching energy
- **Edge inference** — no datacenter transit, no PUE overhead
- **Open-source RTL** — reproducible silicon eliminates duplicated tape-out waste

### The Bazaar, not the Cathedral

> *"Many heads are inevitably better than one."*
> — Eric S. Raymond, [The Cathedral and the Bazaar (1997)](http://www.catb.org/~esr/writings/cathedral-bazaar/)

This repository is open under Apache-2.0 with **no field-of-endeavor restriction**
([OSD §6](https://opensource.org/osd)). Fork it. Improve it. Build with it.
We do not gate-keep what you build. You comply with your local export control;
we comply with ours.

**φ² + φ⁻² = 3** · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
