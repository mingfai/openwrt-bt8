# openwrt-bt8 — Changes from upstream OpenWRT

> **r11 (branch `25.12.5-rebase`)** re-bases the delta onto upstream **v25.12.5**
> (snapshot commit of `f0a60ee`). See [r11](#r11--rebase-to-upstream-v25125) below.
> The sections that follow describe the v25.12.2-era history.

## v25.12.2 era (r2 – r10)

This fork adds ASUS ZenWiFi BT8–specific optimizations on top of
[upstream OpenWRT v25.12.2](https://github.com/openwrt/openwrt/tree/v25.12.2).

**Base commit:** [`43b9dce`](https://github.com/mingfai/openwrt-bt8/commit/43b9dce) — "OpenWrt v25.12.2 base + BT8 custom patches"

## Features / changes by area

### Wi-Fi regulatory database (6 GHz)

- FCC 6 GHz LPI power lifted to 24 / 27 / 30 dBm at 80 / 160 / 320 MHz — prior cap of 12 / 14 dBm crippled 6 GHz throughput on MT7996
  ([`82e6a7f`](https://github.com/mingfai/openwrt-bt8/commit/82e6a7f) — r3)
- HK 6 GHz LPI corrected from 23 → 24 dBm per HKCA 1081 regulatory requirement
  ([`c750585`](https://github.com/mingfai/openwrt-bt8/commit/c750585) — r9)
- Patches under `package/firmware/wireless-regdb/patches/`:
  - `500-world-regd-5GHz.patch`
  - `501-world-regd-6GHz.patch` (adds 6 GHz to World regdomain with wmmrule=ETSI)
  - `502-us-regd-6GHz-no-ir.patch` (removes NO-IR from US 6 GHz, adds wmmrule=ETSI)
  - `503-6ghz-lpi-power.patch` (LPI EIRP lift per above)

### MT76 driver + MediaTek PHY

- MT798x WAN PHY `write_mmd` delay — adds 7–8 ms delay for MT7987/MT7988 2.5G PHY. Fixes a 42% packet-loss symptom caused by spurious TX Pause frames
  ([`dfd207b`](https://github.com/mingfai/openwrt-bt8/commit/dfd207b) — r2)
- MT7996 NULL-sta-deref + per-phy station tracking fixes — backported from wireless-next Mar 2026. Patches `100-mt7996-fix-null-sta-deref-in-eapol-mlo-path.patch`, `110-mt7996-switch-deflink-only-if-lookup-ok.patch`, `111-mt7996-decrement-sta-counter-on-reset-iter.patch`
  ([`f6d8ea5`](https://github.com/mingfai/openwrt-bt8/commit/f6d8ea5) — r4)
- `mt76` driver bumped to commit `018f603` — 8 MLO link-management bug fixes. Also swapped `ca-bundle` → `ca-certificates` (smaller, better-maintained)
  ([`542ccea`](https://github.com/mingfai/openwrt-bt8/commit/542ccea) — r5)

### Roaming + mesh

- 802.11s mesh + multi-WAN + full `wpad` (replaces `wpad-basic`) — enables mesh backhaul between bt8a / bt8b, plus WPA3-SAE and 802.11r FT
  ([`3720cc5`](https://github.com/mingfai/openwrt-bt8/commit/3720cc5) — r4)
- `usteer 2025.10.04~1d6524c6-r1` — client-steering daemon, seamless roaming between bt8a / bt8b (independent of 802.11r FT)
  ([`7a0d727`](https://github.com/mingfai/openwrt-bt8/commit/7a0d727) — r9)
- Defensive bridge-migration killer — prevents all-Wi-Fi-drop symptom when `br-lan` enumerates (OpenWRT 25.12 `uci-defaults/11_network-migrate-bridges` can rewrite `interface.lan.device` during sysupgrade-with-keep-config)
  ([`7a0d727`](https://github.com/mingfai/openwrt-bt8/commit/7a0d727) — r9)

### Packages baked in

- `python3-light`, `luci`, `sudo`, `curl`, `ethtool` — for offline first-boot bootstrap. Previously fetched post-flash via `apk`, which required WAN connectivity
  ([`53d2d82`](https://github.com/mingfai/openwrt-bt8/commit/53d2d82), [`35b84a1`](https://github.com/mingfai/openwrt-bt8/commit/35b84a1) — r5)
- `CAKE` + `sqm-scripts` + `luci-app-sqm` — bufferbloat management on the WAN side
  ([`b0c356a`](https://github.com/mingfai/openwrt-bt8/commit/b0c356a) — r5; restored by [`f9de968`](https://github.com/mingfai/openwrt-bt8/commit/f9de968) after defconfig revert)
- `mwan3 2.12.0-r3` + `luci-app-mwan3` — multi-WAN routing with LuCI UI. Eliminates post-boot `apk install` dance for WireGuard failover
  ([`40761d1`](https://github.com/mingfai/openwrt-bt8/commit/40761d1) — r10)
- `ip-tiny` disabled — conflicts with `ip-full`; explicit disable in `.config`
  ([`ced8969`](https://github.com/mingfai/openwrt-bt8/commit/ced8969) — r5)
- `.config` stabilization — every required package pinned `=y` so defconfig can't silently revert
  ([`7aeb591`](https://github.com/mingfai/openwrt-bt8/commit/7aeb591) — r9-fix; [`af657a4`](https://github.com/mingfai/openwrt-bt8/commit/af657a4) — r9-fix2)

### Congestion control

- BBR enabled (`kmod-tcp-bbr`) — cubic TCP halves cwnd on packet loss, tanking NDT/Google speedtest results on lossy 2.5G links; BBR ignores loss as a congestion signal
  ([`82e6a7f`](https://github.com/mingfai/openwrt-bt8/commit/82e6a7f) — r3)

## Patch file index

All patches under `package/…/patches/`, applied at build time by OpenWRT's Quilt-style patch system:

| Path | Purpose | Commit |
|---|---|---|
| `package/firmware/wireless-regdb/patches/500-world-regd-5GHz.patch` | 5 GHz regdomain adjustments | 82e6a7f |
| `package/firmware/wireless-regdb/patches/501-world-regd-6GHz.patch` | Adds 6 GHz to World regdomain | 82e6a7f |
| `package/firmware/wireless-regdb/patches/502-us-regd-6GHz-no-ir.patch` | Removes NO-IR from US 6 GHz | 82e6a7f |
| `package/firmware/wireless-regdb/patches/503-6ghz-lpi-power.patch` | LPI EIRP lifts (FCC + HKCA 1081) | 82e6a7f + c750585 |
| `package/kernel/mt76/patches/100-mt7996-fix-null-sta-deref-in-eapol-mlo-path.patch` | MT7996 NULL sta deref in EAPOL path | f6d8ea5 |
| `package/kernel/mt76/patches/110-mt7996-switch-deflink-only-if-lookup-ok.patch` | MLO stability (Lorenzo Bianconi) | f6d8ea5 |
| `package/kernel/mt76/patches/111-mt7996-decrement-sta-counter-on-reset-iter.patch` | Per-phy station tracking | f6d8ea5 |
| `target/linux/mediatek/patches-6.12/…` (~20 files) | MT7988/Filogic backports from kernel v6.13 / v6.14 to 6.12 (pinctrl, device-tree, thermal, USB, PCIe) | 43b9dce (base) |

## Release tags

| Tag | Date | Commit | Notes |
|---|---|---|---|
| [`v25.12.2-bt8-r2`](https://github.com/mingfai/openwrt-bt8/releases/tag/v25.12.2-bt8-r2) | 2026-04-12 | `dfd207b` | MT798x 2.5G WAN PHY fix |
| [`v25.12.2-bt8-r3`](https://github.com/mingfai/openwrt-bt8/releases/tag/v25.12.2-bt8-r3) | 2026-04-13 | `82e6a7f` | 6 GHz LPI power + BBR |
| [`v25.12.2-bt8-r4`](https://github.com/mingfai/openwrt-bt8/releases/tag/v25.12.2-bt8-r4) | 2026-04-14 | `f6d8ea5` + `3720cc5` | mt76 MLO fixes + 802.11s mesh |
| r5–r9 | — | see commits | **Not tagged.** Iterative dev builds; superseded by r10 |
| [`v25.12.2-bt8-r10`](https://github.com/mingfai/openwrt-bt8/releases/tag/v25.12.2-bt8-r10) | 2026-04-17 | `40761d1` | mwan3 baked in, usteer, CAKE, mt76 MLO fixes, HK 6 GHz regdb correction. First tagged release since r4 |

## r11 — rebase to upstream v25.12.5

A tree-diff of the r10 base commit `43b9dce` against upstream `v25.12.2` shows the
**true** custom delta is 9 files (the "~20 mediatek backports", regdb `500` and mt76
`110`/`111` listed above are upstream's own or never existed in this repo):

| File | r11 status |
|---|---|
| `files/etc/vpn-ssid-template.sh` | unchanged |
| `files/etc/uci-defaults/00-disable-bridge-migration` | unchanged |
| `package/kernel/mt76/Makefile` (→ `018f603`, 2026-03-21) | unchanged; upstream 25.12.5 still pins `39c960c` |
| `package/kernel/mt76/patches/100-mt7996-fix-null-sta-deref-in-eapol-mlo-path.patch` | unchanged |
| `package/firmware/wireless-regdb/patches/501-world-regd-6GHz.patch` | unchanged (applies at offset) |
| `package/firmware/wireless-regdb/patches/502-us-regd-6GHz-no-ir.patch` | unchanged (applies at offset) |
| `package/firmware/wireless-regdb/patches/503-6ghz-lpi-power.patch` | **refreshed** for regdb 2026.05.30 — HK hunk dropped (upstream now ships HK 5945–6425 MHz at 24 dBm NO-OUTDOOR); US hunk (12 → 30 dBm) regenerated on top of 502 |
| `target/linux/mediatek/patches-6.12/999-net-phy-mediatek-mt798x-add-write-mmd-delay.patch` | unchanged; applies on upstream 701+752 (byte-identical since 25.12.2) |
| `.config` | r10 config as defconfig seed; CI re-resolves it |

Build: `.github/workflows/build-bt8.yml` (upstream workflows removed on this branch).
Upstream bugs still open at r11: openwrt/openwrt#22542 (mt7988 EEE/link — keep the
`rc.local` EEE-off workaround), #24215 (mt7996 firmware timeout on BT8).

| Tag | Date | Base | Notes |
|---|---|---|---|
| `v25.12.5-bt8-r11` | 2026-09-13 | upstream v25.12.5 `f0a60ee` | pre-release until verified on bt8a; flash with `sysupgrade -n` |

## Appendix: commit chronology

| SHA | Tag | Subject |
|---|---|---|
| `43b9dce` | base | OpenWrt v25.12.2 base + BT8 custom patches |
| `dfd207b` | r2 | mt798x: fix WAN download speed — add write_mmd delay for 2.5G PHY |
| `82e6a7f` | r3 | 6ghz-lpi-power + BBR — r3 build |
| `f6d8ea5` | r4 | r4: backport mt76 mt7996 NULL deref fixes from wireless-next Mar 2026 |
| `3720cc5` | r4 | bt8: enable 802.11s mesh + multi-WAN + full wpad |
| `ced8969` | r5 | bt8: disable ip-tiny (conflicts with ip-full) |
| `b0c356a` | r5 | bt8: enable CAKE + sqm-scripts + luci-app-sqm for bufferbloat management |
| `f9de968` | r5 | bt8: restore sqm-scripts + mwan3 packages that defconfig reverted |
| `542ccea` | r5 | bt8: bump mt76 to 018f603 (8 MLO link-management fixes) + ca-bundle→ca-certificates |
| `53d2d82` | r5 | config: bake in python3-light+luci+sudo+curl+ethtool for offline bootstrap |
| `35b84a1` | r5 | config: defconfig auto-resolve for bake-in packages |
| `c750585` | r9 | wireless-regdb: correct HK 6 GHz LPI from 23→24 dBm per HKCA 1081 |
| `7a0d727` | r9 | r9: add usteer + defensive bridge-migration killer |
| `7aeb591` | r9-fix | r9-fix: stabilize luci-base + usteer in .config |
| `af657a4` | r9-fix2 | r9-fix2: commit fully resolved .config (all packages =y) |
| `40761d1` | r10 | r10-prep: force mwan3 + luci-app-mwan3 =y in .config |
