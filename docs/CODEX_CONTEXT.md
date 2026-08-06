# Codex Context — N60 Pro

Updated: 2026-08-07

## Working model
- ChatGPT decides architecture, debugging direction, and the exact scope of each change.
- Codex executes requested inspection/edit/git/gh tasks.
- By default, inspection tasks are read-only. Do not modify or push unless explicitly instructed.

## Hardware / boot facts
- Device: Netcore N60 Pro, MT7986A.
- Hardware mod: 2 GiB RAM + 512 MiB SPI-NAND.
- U-Boot: N60PRO U-Boot 2025 WildEdition.
- Current WildEdition page shows the 512 MiB MAX / ~506.5 MiB layout and no U-Boot-side NMBM management.
- UBI/firmware area begins around `0x0580000`; intended size `0x1fa80000` (~506.5 MiB).
- Normal firmware work must not modify BL2/FIP/U-Boot.
- NMBM is not categorically forbidden. Linux-side NMBM may be valid if the final storage design calls for it, but its actual state/effect must be verified rather than assumed from a DTS property alone.

## Proven-good baselines
### Official initramfs
Official ImmortalWrt 25.12.1 initramfs boots correctly on this modified hardware:
- DHCP works.
- Router is reachable at `192.168.1.1`.
- LuCI works.
- All four LAN ports are recognized.
- ~1.94 GiB RAM is recognized.

This proves the modified hardware, U-Boot, RAM, and basic official N60 Pro networking support are viable.

### Proven-good flashed sysupgrade reference
The user also has a forum-built N60 Pro sysupgrade `.bin` that repeatedly boots successfully on this same router even after erasing UBI and resetting U-Boot environment variables.
Use this firmware only as compatibility evidence/reference, NOT as the base tree for the final firmware.
Known useful structural facts from the reference:
- classic sysupgrade TAR layout
- separate kernel FIT and squashfs rootfs payloads
- intended 512 MiB / ~506.5 MiB flash layout
- it demonstrates that the installed WildEdition + modified NAND can boot a conventional kernel/rootfs sysupgrade design reliably

## Final firmware target
- Official ImmortalWrt 25.12.1 commit: `a3378d1a2c15beb2faf4b0bce9c00f07143efa29`.
- Linux 6.12 from that release.
- Official N60 Pro Ethernet / PHY / DSA / switch remains authoritative.
- MTK compatibility donor: `chasey-dev/immortalwrt-mt798x-rebase` commit `eb724bb94de346f36b35bdb0f7de31b529bbc885`.
- Proprietary `mt_wifi` 7.6.7.3.
- 237 radio source commit: `ec9ef10efc65da1e6d1de4e2c043c0e13d08eed8`.
- Required RF behavior: `E2pAccessMode=2`, `SKUenable=0`, `TxPower=100`, iPA/iLNA, MT7986/MT7976.
- Final system should differ from pristine official 25.12.1 only where required by the 2 GiB / 512 MiB hardware and proprietary 237 Wi-Fi path.

## Important build history
- Build #17 compiled successfully but the flashed image had broken LAN/DHCP because a donor MediaTek target overlay replaced official networking integration.
- Commit `e54d88620b985a49365634bc716191d8e3089df6` stopped the full donor `target/linux/mediatek/` overlay and restored official DTS/Ethernet/PHY/DSA authority.
- Build #19 failed on missing `mt_eeprom_read_wifi`; fixed by importing only donor `wifi_utility` plus required Linux 6.12 compatibility patches. Commit `77a573c31257d99cb97c8364d5c798c2e63885a6`.
- Build #20 passed that point but failed in WARP because `net/ra_nat.h` was missing.
- Commits `5e4f9c6d2e4fc82c329d7391857ce1226a180270` and `090d415697d41401964b541f529297e5b6741549` decoupled `mt_wifi` from WARP/HNAT and disabled WARP/HNAT/WHNAT/Fast-NAT.
- Commit `b060bf18e8f146e94f1daf7094fde80135747b3d` added CI assertions for that isolation state.

## Build #21 result
GitHub Actions Run #21:
- run id: `31102432600`
- head: `b060bf18e8f146e94f1daf7094fde80135747b3d`
- compile result: SUCCESS
- produced the expected N60 Pro 25.12.1 / Linux 6.12 / mt_wifi 7.6.7.3 artifact
- real-device result: FAILS TO ENTER LINUX / remains in U-Boot-state indication after flashing and power cycling

Therefore Build #21 solved the compile chain but did NOT solve the boot/runtime chain.
Do not treat compile success as proof of a correct firmware design.

## Current architecture issue under investigation
The current builder keeps the official 25.12.1 N60 Pro FIT-rootdisk style image path, including the official N60 Pro image/DTS boot model, while expanding RAM and UBI size.
The proven-good flashed reference uses a classic sysupgrade TAR with separate kernel/rootfs payloads.

Before the next long build, audit the whole path rather than changing one symptom at a time:
- pristine official N60 Pro DTS/storage/boot properties
- current 2 GiB / 512 MiB DTS edits
- official `Device/netcore_n60-pro` image profile
- generated sysupgrade format
- UBI/rootfs/kernel volume expectations
- WildEdition boot expectations
- NMBM state/effect
- proprietary Wi-Fi imports and their true minimum dependencies

Do not copy the reference firmware's whole DTS, network stack, package set, or system tree. It is evidence, not a source base.

## Files that normally matter
- `.github/workflows/build.yml` — pinned sources, CI assertions, build/log/artifact flow.
- `scripts/prepare.sh` — minimal proprietary Wi-Fi import, compatibility pieces, RF profiles, hardware/layout edits and guard rails.
- `config/n60pro-extra.config` — target and proprietary Wi-Fi feature selections.
- pristine official 25.12.1 `target/linux/mediatek/image/filogic.mk` and N60 Pro DTS — comparison baseline only unless an explicit task says to patch their resulting tree.

## Current decision policy
1. Do not trigger the next long build merely to test another guess.
2. First perform a read-only architecture audit and identify every required change for a bootable 2 GiB / 512 MiB image.
3. Keep official N60 Pro Ethernet/PHY/DSA/switch untouched.
4. Keep donor imports limited to the proprietary Wi-Fi path and justified Linux 6.12 compatibility pieces.
5. Do not decide NMBM policy from assumptions; report actual config/DTS/boot-layout facts and let ChatGPT choose the final design.
6. After ChatGPT approves one complete minimal plan, implement it in one focused change, inspect the diff, then push once for the next GitHub Actions build.
7. After a successful build, inspect the produced image structure as required before asking the user to flash it.

## What not to upload into a Codex project
Do not duplicate full official ImmortalWrt trees, full donor trees, piles of old logs, or unrelated firmware artifacts.
If binary comparison is explicitly requested, use only the specific known-good reference firmware and the specific test artifact needed for that task, preferably outside git tracking.
