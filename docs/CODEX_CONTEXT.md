# Codex Context — N60 Pro

Updated: 2026-08-06

## Hardware / boot facts
- Device: Netcore N60 Pro, MT7986A.
- Hardware mod: 2 GiB RAM + 512 MiB SPI-NAND.
- U-Boot: N60PRO U-Boot 2025 WildEdition.
- Direct UBI; no NMBM.
- UBI starts around `0x0580000`; size `0x1fa80000` (~506.5 MiB).
- Normal firmware work must not touch BL2/FIP/U-Boot.

## Proven-good baseline
Official ImmortalWrt 25.12.1 initramfs boots correctly on this modified hardware:
- DHCP works.
- Router is reachable at `192.168.1.1`.
- LuCI works.
- All four LAN ports are recognized.
- ~1.94 GiB RAM is recognized.

Therefore hardware/U-Boot/NAND/RAM/cabling are not the cause of custom-image LAN failure.

## Firmware target
- Official ImmortalWrt 25.12.1 commit: `a3378d1a2c15beb2faf4b0bce9c00f07143efa29`.
- Linux 6.12.
- MTK donor: `chasey-dev/immortalwrt-mt798x-rebase` commit `eb724bb94de346f36b35bdb0f7de31b529bbc885`.
- Proprietary `mt_wifi` 7.6.7.3.
- 237 radio source commit: `ec9ef10efc65da1e6d1de4e2c043c0e13d08eed8`.
- Required RF behavior: `E2pAccessMode=2`, `SKUenable=0`, `TxPower=100`, iPA/iLNA.

## Important build history
- Build #17 compiled successfully, but flashed image had broken LAN/DHCP.
- Root cause direction: the donor MediaTek target tree had replaced official N60 Pro networking integration.
- Commit `e54d88620b985a49365634bc716191d8e3089df6` stopped the full donor `target/linux/mediatek/` overlay and restored official DTS/Ethernet/PHY/DSA authority.
- Build #19 then failed on missing `mt_eeprom_read_wifi`; fixed by importing only donor `wifi_utility` plus Linux 6.12 compatibility patches. Commit `77a573c31257d99cb97c8364d5c798c2e63885a6`.
- Build #20 passed that point but failed in WARP because `net/ra_nat.h` was missing.
- Instead of importing legacy HNAT networking code during LAN isolation, commits `5e4f9c6d2e4fc82c329d7391857ce1226a180270` and `090d415697d41401964b541f529297e5b6741549` decoupled `mt_wifi` from WARP/HNAT and disabled WARP/HNAT/WHNAT/Fast-NAT.
- Commit `b060bf18e8f146e94f1daf7094fde80135747b3d` added CI assertions that acceleration remains disabled.

## Current CI state at handoff
GitHub Actions Run #21:
- run id: `31102432600`
- head: `b060bf18e8f146e94f1daf7094fde80135747b3d`
- state when this document was written: `in_progress`
- purpose: verify/build proprietary MTK Wi-Fi while WARP/HNAT are disabled, keeping official LAN path intact.

Always check GitHub for the latest run before acting; this status can become stale.

## Files that normally matter
- `.github/workflows/build.yml` — pinned sources, CI config assertions, build/log artifact flow.
- `scripts/prepare.sh` — minimal donor import, WEXT/wifi_utility compatibility, RF profiles, official DTS RAM/UBI edits and guard rails.
- `config/n60pro-extra.config` — target and proprietary Wi-Fi feature selections.

## Decision tree
1. If #21 fails: inspect its compact `build-error-21` artifact; fix only the first real compile/link/config failure.
2. If #21 succeeds: do not add more networking code. Produce/identify the sysupgrade image and wait for device flash testing.
3. If flashed #21 has working LAN/DHCP: lock the official networking baseline; then validate proprietary Wi-Fi/RF behavior.
4. If flashed #21 still has broken LAN/DHCP: compare the generated runtime network configuration/package set against official 25.12.1. Do not restore donor target/DTS/HNAT wholesale.

## What not to upload into a Codex project
Do not duplicate large build logs, official ImmortalWrt source, donor source, firmware artifacts, or the U-Boot forum PDF unless a specific task requires them. They waste context and are already reproducible or summarized here.