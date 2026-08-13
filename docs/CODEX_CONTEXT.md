# Codex Context — N60 Pro

Updated: 2026-08-12

Read `AGENTS.md` and `docs/BUILD_GATE.md` before using this file. Those two files contain the permanent process rules; this file records current technical state and proven/disproven facts.

## Working model
- ChatGPT decides architecture, debugging direction, failure domain, and exact change scope.
- Codex performs only targeted repository inspection/edit/cheap validation/git work requested by ChatGPT.
- Optimize for low Codex quota and few full builds: reuse this context, avoid broad rescans, do not make Codex repeat analysis already completed.
- GitHub Actions is the final integration build, not the exploratory debugger.
- A build-triggering push must pass `docs/BUILD_GATE.md` first.

## Hardware / boot facts
- Device: Netcore N60 Pro, MT7986A.
- Hardware mod: 2 GiB DDR4 + 512 MiB SPI-NAND.
- U-Boot: N60PRO U-Boot 2025 WildEdition.
- UBI/firmware area begins at `0x0580000`; intended size `0x1fa80000` (~506.5 MiB).
- Normal firmware work must not modify BL2/FIP/U-Boot.
- NMBM is not categorically forbidden or required; never change it from assumption alone.

## Final firmware target — hard requirements
- Final product principle: preserve official ImmortalWrt 25.12.1 behavior wherever possible; add only the N60 Pro high-power proprietary 237 Wi-Fi/RF path; keep the required 2 GiB RAM, 512 MiB SPI-NAND, and WildEdition MAX 506.5 MiB hardware adaptation.
- WARP/HNAT/WHNAT/Fast-NAT disabled is the current diagnostic-phase state, not a permanent final-product goal.
- Official ImmortalWrt 25.12.1 commit: `a3378d1a2c15beb2faf4b0bce9c00f07143efa29`.
- Linux 6.12 from that release.
- 官方 N60 Pro 网络实现是当前已真机验证的 known-good baseline；没有明确必要性和证据时保持，不整套导入 donor 网络基线。
- MTK donor: `chasey-dev/immortalwrt-mt798x-rebase` commit `eb724bb94de346f36b35bdb0f7de31b529bbc885`.
- Proprietary `mt_wifi` 7.6.7.3.
- 237 radio source commit: `ec9ef10efc65da1e6d1de4e2c043c0e13d08eed8`.
- Donor code is limited to proprietary Wi-Fi and specifically justified Linux 6.12 compatibility pieces; never import the donor whole `target/linux/mediatek/` tree.
- WARP/HNAT/WHNAT/Fast-NAT remain disabled unless architecture is explicitly changed later.

Required 237 selections:
```text
CONFIG_MTK_CHIP_MT7986=y
CONFIG_CONNINFRA_AUTO_UP=y
CONFIG_CONNINFRA_EMI_SUPPORT=y
CONFIG_MTK_FIRST_IF_EEPROM_FLASH=y
CONFIG_MTK_FIRST_IF_IPAILNA=y
CONFIG_MTK_FIRST_IF_MT7986=y
CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0
CONFIG_MTK_WIFI_ADIE_TYPE="mt7976"
CONFIG_MTK_WIFI_SKU_TYPE="AX6000"
CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y
CONFIG_MTK_MT_WIFI_MT7986_20260601=y
```

Required RF files:
- `l1profile.dat`
- `mt7986-ax6000.dbdc.b0.dat`
- `mt7986-ax6000.dbdc.b1.dat`
- `mt7986-sku.dat`
- `mt7986-sku-bf.dat`

Required RF behavior:
- `CountryCode=CN`
- `E2pAccessMode=2`
- `SKUenable=0`
- `TxPower=100`
- first radio EEPROM offset is `0x0`
- iPA/iLNA

Required Linux 6.12 WEXT compatibility delta:
```text
CONFIG_WIRELESS_EXT=y
CONFIG_WEXT_CORE=y
CONFIG_WEXT_PRIV=y
CONFIG_WEXT_PROC=y
CONFIG_WEXT_SPY=y
```
Do not widen the generic kernel config beyond evidence-backed minimum compatibility deltas.

## Proven-good hardware baseline
The strongest positive control is the pure official 25.12.1 classic image:
- `N60Pro_DIAG_OFFICIAL25_classic_no-linux-ubi.bin`
- size: `15,739,148`
- SHA256: `f5291994c67d290569b67891d73f76ee3e02ccd9a3e583ffcbce2669cfa90e18`
- exact official 25.12.1 sysupgrade raw Image + official rootfs, 2 GiB RAM / 506.5 MiB UBI classic layout
- real-device result: boots normally and enters the system

Therefore do NOT blame 2 GiB RAM, 512 MiB NAND, WildEdition U-Boot, Linux 6.12, classic image route, or the 506.5 MiB UBI size again without new direct evidence.

Official initramfs also boots correctly on this hardware with DHCP/LuCI/all LAN ports/~1.94 GiB RAM.

## Proprietary Wi-Fi dependency facts
- `wifi_utility` provides EEPROM helpers used by both `conninfra` and `mt_wifi`.
- `conninfra` and `mt_wifi` directly require `mt_eeprom_read_wifi`; `mt_wifi` also uses `mt_eeprom_write_wifi`.
- `wifi_utility` was modularized as `mtk_wifi_utility.ko` to avoid embedding it in vmlinux.
- Initial module build hit unexported `__of_find_all_nodes`; code was changed to compatible-node iteration and later compiled.
- Current diagnostic intent after #40: auto-load only the proprietary base chain `mtk_wifi_utility -> conninfra -> mt_wifi`; keep WARP/HNAT/WHNAT/Fast-NAT isolated.
- #38 real-device result: ITB recovery and classic BIN both booted successfully; SSH/Shell are available after system boot even though TTL is not currently usable.
- #38 Wi-Fi diagnostic: manual `mtk_wifi_utility` load returned rc=255, but PCIe enumerated `14c3:7986`.
- #38 RF evidence: `factory+0` is the actual EEPROM area; `factory+0xc0000` is erased, so N60 Pro RF offset must be `0x0`.

## Important no-repeat conclusions
Do not repeat these experiments/theories without new direct evidence:
- Whole donor MediaTek target overlay broke official networking authority; never reintroduce it.
- #25 proprietary build had no DHCP/IP/LAN and Wi-Fi LED off.
- #26 disabled proprietary module AUTOLOAD and still had no system/IP: autoload/order alone is disproved.
- #22 no-linux-ubi failed: `linux,ubi` alone is not the cause.
- Reference rootfs + #22 kernel failed: rootfs size/content alone is not the primary cause.
- #22 kernel + reference DTB failed: #22 DTB is not the sole cause.
- RBUS matcher disable experiment failed; do not repeat.
- Marker v1/v2 tests were non-diagnostic.
- #22 kernel + official initramfs failed: evidence points to custom kernel side, but it is not standalone proof of one exact kernel cause.
- #18 hybrid did not establish a known-good custom kernel; do not call #18 known-good.
- #25 kernel + proven-good official classic DTB failed: do not repeat DTB-swap theory as the main fix.
- Official kernel + #25 rootfs hybrid is invalid as a clean rootfs diagnostic because of module ABI/symbol mismatch.
- ITB vs classic is resolved by the pure official classic positive control.
- Smaller Image size is not failure evidence.
- Do not return to module autoload as the sole suspect.

## Build history relevant to the current state
### #28
- Run ID `31224445779`, head `99a57a0409d9f0817c5bc8d6329aa8fc5dacf458`.
- Fatal: `iwe_stream_add_point` / `iwe_stream_add_event` undefined in `mt_wifi.ko`.
- Root fact: legacy WEXT is required by proprietary mt_wifi.

### #29
- Commit `cff1a0bbbb0676d91393ae3acc84f2f53eb14a1d`.
- Run ID `31240440992`.
- Restored only the five required WEXT symbols on official generic kernel baseline.
- Failed because CI still had a raw `git diff --exit-code -- target/linux/generic/config-6.12` guard that contradicted the intentional WEXT delta; not a compiler failure.

### #30
- Commit `2d1bac8d1aaa66f9ae5b068714678dd03a8b3279`.
- Run ID `31240892620`.
- Real fatal: optional `package/kernel/rtl8812au-ct` failed with `-Werror=restrict`.
- Root cause was the official release buildbot config enabling huge repository scope such as `CONFIG_ALL_KMODS=y` / `CONFIG_ALL_NONSHARED=y`.
- This optional package is not part of the N60 Pro proprietary Wi-Fi target and should not be treated as a product requirement.

### #31
- Commit `4465d1b8eaefa91095d59bef2e20859039e967fa`.
- Run ID `31252319910`.
- Parallel build plus full serial retry hit the 6-hour timeout; no artifact.
- Lesson: do not compile the release buildbot's huge optional package scope and do not duplicate full work with a serial retry.

### #32
- Commit `e6dd5a6b78b21cb82baf8e59e18fc7d1ef8646e0`.
- Run ID `31275263302`.
- Buildbot-only bulk selectors/modules were pruned; one parallel build only.
- Failed after about 2h26m.
- The compact failure artifact did NOT preserve enough context to honestly identify the real root package/fatal.
- Do not patch based on ignored errors/configure probes from the truncated summary.

### #33
- Head before governance-doc commits: `7a878d48b88a2186be47d1ab77f841aabb83c135`.
- Run ID `31281536082`.
- CI diagnostic-only change preserved the full `build-parallel.log.gz` on failure and larger matched-error context.

### #35-#37
- #35 restored the official release kernel package-to-Kconfig sidecar while keeping actual package build scope trimmed.
- #36 collected the N60 Pro recovery ITB artifact.
- WEXT-only recovery control booted on real hardware with DHCP and `192.168.1.1`, proving the five WEXT symbols themselves are not the boot failure cause.
- #37 limited the main WEXT Kconfig patch to only the required WEXT prompt changes.

### #38
- Commit `9dbb1da7c4d3f1d09a6ccb63d6e0e73c38a3a5e1`.
- Run ID `31449747534`.
- Switched the MTK Wi-Fi frontend to pinned donor `mtwifi-cfg-ucode`.
- Real-device result: both recovery ITB and classic BIN boot successfully.
- Runtime access: TTL is not currently usable, but SSH/Shell are available after Linux boots.
- Wi-Fi diagnostic result: manual `mtk_wifi_utility` load returned rc=255, while PCIe still enumerated `14c3:7986`.
- EEPROM evidence: `factory+0` contains the actual radio EEPROM; `factory+0xc0000` is erased. The N60 Pro RF offset invariant is therefore `CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0`.

### #39
- Run ID `31489250155`.
- Real-device result: manual `mtk_wifi_utility` load returned rc=0; RBUS and PCIe `14c3:7986` are verified [permanent].
- Artifact config exposed that hidden mt_wifi Kconfig re-resolved `CONFIG_MTK_RT_FIRST_IF_RF_OFFSET` to `0xc0000`; MT7986 must resolve to `0x0`.
- Rebase also missed `CONFIG_CONNINFRA_AUTO_UP=y` and `CONFIG_CONNINFRA_EMI_SUPPORT=y`.
- Both final resolved `.config` and artifact `config.buildinfo` must gate `CONFIG_MTK_RT_FIRST_IF_RF_OFFSET=0x0`, `CONFIG_CONNINFRA_AUTO_UP=y`, and `CONFIG_CONNINFRA_EMI_SUPPORT=y`.

### #40
- Real-device result: `mtk_wifi_utility.ko`, `conninfra.ko`, and `mt_wifi.ko` manual `insmod` all returned rc=0; the utility -> conninfra -> mt_wifi module chain is verified.
- EEPROM factory offset 0 is valid: `eeFlashId=0x7986`, two A-dies were recognized as MT7975, and `ra0` / `rax0` received real MAC addresses.
- After manual module load and `wifi down && wifi up`, both radios worked: 2.4 GHz HE40, 5 GHz HE160, mobile 2.4/5 GHz association, DHCP, and LuCI access passed.
- WAN eth1/GPY211C passed on real hardware: carrier, DHCP/default route/DNS/router Internet, and Wi-Fi client -> LAN -> NAT/firewall -> WAN -> Internet.
- Reboot Wi-Fi failure was traced to NOAUTOLOAD boot order: netifd setup can run while `mt_wifi` is unavailable, logging `[Driver] mt_wifi is buit-in. Install as kmod(s)!!`; manual module load plus `wifi down && wifi up` restores both radios.
- Runtime observed `iwpriv` missing while `mtwifi-cfg-ucode` calls `iwpriv` for `KickStaRssiLow` and `AssocReqRssiThres`; `wireless-tools` must be included as the provider of `/usr/sbin/iwpriv`.
- Runtime observed `INDEX0_EEPROM_size=0x5000` requesting len `0x5000` from a `0x1000` nvmem cell with `copied=0x1000`. The compatibility backend zero-fills first, and real Wi-Fi passed, so #41 does not change EEPROM size, DTS cell size, or the 5203 backend.
- #41 still isolates WARP/HNAT/WHNAT/Fast-NAT. Limiting `mtwifi-cfg-ucode` reload to `mt_wifi` is a current compatibility/acceleration-isolation behavior, not a permanent decision to remove hardware acceleration; restoring WARP/HNAT later requires a separate dependency-chain audit.

## Current repository workflow trigger fact
`.github/workflows/build.yml` currently runs on push to `main` only when these paths change:
- `.github/workflows/build.yml`
- `scripts/**`
- `config/**`

Governance-only changes to `AGENTS.md` and `docs/**` do not trigger the firmware build.

## Current process hardening
Permanent process is defined in:
- `AGENTS.md`
- `docs/BUILD_GATE.md`

Key rule: one evidence-backed failure domain is analyzed broadly enough to find all cheap/static issues in that chain, then one coherent minimal batch is changed and prevalidated before one full Actions build. Do not use an "one small error -> one full build" loop.

## Current technical action after #40
- Fix only the confirmed proprietary Wi-Fi boot-order/frontend dependency domain for #41.
- Auto-load only the proprietary base chain: `mtk_wifi_utility` boot autoload priority 09, `conninfra` boot autoload priority 10, and `mt_wifi` normal autoload priority 11.
- `mt_wifi` must not be promoted into `modules-boot.d`; utility/conninfra keep donor boot-stage behavior, while `mt_wifi` only needs normal kmodloader availability before netifd wireless setup.
- Add the missing `wireless-tools` runtime dependency for `mtwifi-cfg-ucode` so `/usr/sbin/iwpriv` is present.
- Keep boot/storage/network/WEXT/RF/EEPROM/backend/DTS unchanged.
- Keep WARP/HNAT/WHNAT/Fast-NAT isolated for this diagnostic phase; do not restore acceleration without a later explicit architecture decision.

## Post-#42 Golden firmware-only A/B candidate
- #42 does not reopen #41 autoload; that domain is treated as PASS.
- Current `mt_wifi` 7.6.7.3 + `mt7986-fw-20260601` measured 2.4 GHz / 5 GHz power as raw `44` / `45`.
- Golden 237 `mt_wifi` 7.6.6.1 bundled rebb firmware measured 2.4 GHz / 5 GHz power as raw `50` / `48`.
- TX-power command/event ABI between 7.6.6.1 and 7.6.7.3 was audited as compatible for a firmware-only A/B.
- This Post-#42 Golden firmware-only A/B candidate keeps the 7.6.7.3 host driver and changes only the MT7986 firmware blobs to Golden 7.6.6.1 bundled rebb files.
- This is not a final firmware decision; the result is decided by real-device testing.

## Post-#43 RF calibration-path candidate
- #43 Golden firmware-only A/B failed on real hardware: power remained raw `44` / `45`.
- The Golden runtime firmware blobs were present in rootfs, so do not keep changing firmware for this failure.
- Real-device logs again showed an EEPROM request of `0x5000`, while the official `eeprom_factory_0` nvmem cell provides only `0x1000` and `copied=0x1000`.
- New real-device evidence shows factory `0x1000-0x4fff` is erased: non-FF bytes = `0`.
- Current nvmem partial-read path is real EEPROM at `0x0000-0x0fff`, then synthetic `0x00` at `0x1000-0x4fff` due to zero-fill.
- Raw factory MTD is real EEPROM at `0x0000-0x0fff`, then real erased `0xFF` at `0x1000-0x4fff`.
- The Linux 6.12 `wifi_utility` backend zero-fills first, partially copies the nvmem cell, returns success, and therefore does not fall back to raw Factory MTD.
- The current candidate uses N60 Pro `mediatek,mtd-eeprom = <&factory 0x0>;` to restore true factory byte semantics from factory offset `0x0`, including erased `0xFF`.
- The official `0x1000` nvmem cell remains unchanged.
- This is an RF calibration-path A/B, not a final root-cause judgment; the real-device target remains raw `50` / `48`.

## Post-#44 host-driver A/B candidate
- #43 firmware-only A/B failed on real hardware: 7.6.7.3 host + Golden 7661 firmware remained raw `44` / `45`.
- #44 raw factory MTD EEPROM semantics A/B also failed for high-power: `e2p 0x1000`, `0x1002`, `0x2000`, and `0x4ffe` read as `FFFF`, but power remained raw `44` / `45`.
- Closed for this candidate: firmware-only, nvmem partial zero-fill, EEPROM `0x1000` vs `0x5000`, RF offset, SKU, Backoff, Thermal, PowerUp, ePAGain, profile, WARP/HNAT.
- Golden RF source vs donor 7661 is not RF-different in the targeted RF-symbol files; observed differences are donor non-RF patches such as flash API, memory shrink, site survey/stainfo, and return-type cleanup.
- Current candidate changes only host driver version from `CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y` to `CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7661=y`, while keeping Golden firmware, raw factory MTD EEPROM, RF offset `0x0`, iPA/iLNA, autoload 09/10/11, WARP/HNAT isolation, official network DTS, and classic NAND/UBI boot unchanged.
- 7661 needs the cumulative Linux 6.12 compatibility stack `022` through `035`, plus fortify/compile patches `037-1` through `037-4` and `038`. Behavioral patches `039` and `040` are intentionally not imported.

## Files that normally matter
- `AGENTS.md` — permanent project/Codex hard rules.
- `docs/BUILD_GATE.md` — mandatory pre-build gate.
- `docs/CODEX_CONTEXT.md` — current technical state and no-repeat knowledge.
- `.github/workflows/build.yml` — pinned sources, CI assertions, build/log/artifact flow.
- `scripts/prepare.sh` — proprietary Wi-Fi import, compatibility pieces, RF profiles, hardware/layout edits and guard rails.
- `scripts/rebase-official-release-config.sh` — official release config/kernel baseline handling and WEXT delta.
- `scripts/fix-wifi-utility-module.sh` — wifi_utility module packaging/build adaptations.
- `config/n60pro-extra.config` — target and proprietary Wi-Fi selections where still used.

## Codex efficiency rule
For each task, Codex should receive only the already-decided target, relevant files, required edits/checks, and explicit push authorization. Prefer targeted `grep/find/git diff` and cheap checks; avoid broad tree exploration, repeated project explanation, full local firmware builds, and speculative cleanup.
