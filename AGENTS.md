# N60 Pro Codex Rules

Read `docs/CODEX_CONTEXT.md` before changing code.

## Mission
Build a reliable Netcore N60 Pro firmware using:
- official ImmortalWrt 25.12.1 as the base
- Linux 6.12
- proprietary MediaTek `mt_wifi` 7.6.7.3
- 237 high-power MT7986 radio profiles
- modified hardware: 2 GiB RAM, 512 MiB SPI-NAND

## Non-negotiable architecture
- Official ImmortalWrt N60 Pro DTS / Ethernet / PHY / DSA / PPE is authoritative.
- NEVER overlay or copy the donor's whole `target/linux/mediatek/` tree.
- Import donor code only when a build error proves a specific dependency is required.
- Do not import donor N60 Pro/RFB DTS networking configuration.
- Do not modify BL2, FIP, U-Boot, bootloader layout, or add NMBM.
- Keep the existing official-DTS edits for 2 GiB RAM and 512 MiB UBI only.
- Preserve radio profile values: `CountryCode=CN`, `E2pAccessMode=2`, `SKUenable=0`, `TxPower=100`, iPA/iLNA.

## Current isolation strategy
- Keep legacy WARP/HNAT/WHNAT/Fast-NAT disabled unless a later task explicitly requires them.
- `mt_wifi` must build and run without `kmod-warp`, `kmod-mediatek_hnat`, or `mtk_warp_proxy.ko` during LAN isolation.
- Do not re-enable acceleration merely because donor defaults enable it.

## Token/time-saving workflow
1. Run `git status --short` and inspect the latest relevant commit/diff.
2. Read only `docs/CODEX_CONTEXT.md`, the failing file(s), and directly related Makefile/Kconfig/patches.
3. For CI failures, inspect the compact `build-error-<run>` artifact first. Read full logs only if the compact artifact is insufficient.
4. Form one concrete root-cause hypothesis and make the smallest patch that tests it.
5. Do not perform broad refactors, dependency upgrades, formatting sweeps, or unrelated cleanup.
6. Do not compile the full firmware locally. Use cheap local static checks only; GitHub Actions is the build machine.
7. Do not repeatedly clone/re-index official or donor trees if a checkout already exists.
8. Prefer targeted `grep/find` over recursive exploration of entire source trees.
9. Reuse pinned commits from `.github/workflows/build.yml`; do not search for newer versions unless explicitly asked.
10. After checks, make one focused commit and push once. The push should trigger GitHub Actions.
11. If CI fails, continue from that exact failure; do not restart architecture analysis.
12. Keep final responses short: root cause, files changed, commit SHA, run number/status.

## Validation before push
- `bash -n scripts/prepare.sh`
- verify no donor full-target overlay was introduced
- verify official N60 Pro DTS guard rails remain
- verify high-power radio guard rails remain
- verify the requested acceleration state (currently disabled) survives `make defconfig` checks in CI

## Build-success rule
A successful compile is not proof that LAN is fixed. After a successful image, stop changing networking code and wait for real-device LAN/DHCP testing. If LAN works, preserve that networking baseline.