# N60 Pro Codex Rules

Read `docs/CODEX_CONTEXT.md` before doing any project work.

## Mission
Build a reliable Netcore N60 Pro firmware using:
- official ImmortalWrt 25.12.1 as the system/base tree
- Linux 6.12 from that official release
- official N60 Pro Ethernet / PHY / DSA / switch integration
- proprietary MediaTek `mt_wifi` 7.6.7.3
- 237 high-power MT7986 radio profiles
- modified hardware: 2 GiB RAM, 512 MiB SPI-NAND

The final firmware should differ from official ImmortalWrt 25.12.1 only where required for the 2 GiB / 512 MiB hardware and the proprietary 237 Wi-Fi path.

## Roles
- ChatGPT is the architecture/debugging decision-maker.
- Codex is the execution agent: inspect requested files/logs, make explicitly requested edits, run cheap checks, commit, push, and read GitHub Actions results.
- Unless an instruction explicitly says to modify/push, stay read-only.
- Do not choose a new technical direction, widen scope, or push speculative fixes on your own.

## Non-negotiable architecture
- Official ImmortalWrt 25.12.1 N60 Pro DTS / Ethernet / PHY / DSA / switch is authoritative.
- NEVER overlay or copy the donor's whole `target/linux/mediatek/` tree.
- Do not import donor N60 Pro/RFB networking DTS configuration.
- Do not modify BL2, FIP, U-Boot, or bootloader partitions.
- Donor code is allowed only for the proprietary MTK Wi-Fi path and specifically justified Linux 6.12 compatibility dependencies.
- Preserve radio behavior: `CountryCode=CN`, `E2pAccessMode=2`, `SKUenable=0`, `TxPower=100`, iPA/iLNA.
- Hardware adaptation must preserve 2 GiB RAM and the 512 MiB / ~506.5 MiB firmware area required by the installed WildEdition layout.

## NMBM policy
- NMBM is NOT globally forbidden and is NOT automatically required.
- The installed WildEdition U-Boot can operate with its current no-NMBM-management state, while Linux-side NMBM may still be a valid option if the final storage design requires it.
- Never infer that NMBM is active merely because a DTS property exists.
- Do not enable, disable, rebuild, or change NMBM behavior without an explicit task backed by the current boot/storage design.

## Wi-Fi / acceleration isolation
- Keep WARP/HNAT/WHNAT/Fast-NAT disabled unless a later explicit architecture decision requires them.
- 237 RF power itself must not depend on legacy WARP/HNAT.
- Do not re-enable acceleration just because donor defaults enable it.

## Architecture-first workflow
1. Run `git status --short` first.
2. Read `docs/CODEX_CONTEXT.md` and only the files directly required by the current instruction.
3. Before triggering a long firmware build after any boot/storage/target change, audit the complete image path: DTS -> image profile -> sysupgrade format -> UBI/rootfs layout -> boot expectations.
4. Do not use repeated long GitHub builds as a substitute for static architecture checking.
5. For a CI compile failure, inspect the compact `build-error-<run>` artifact first and identify the first real terminating error.
6. Make only the modification explicitly requested by ChatGPT; do not opportunistically fix unrelated issues.
7. Do not perform broad refactors, dependency upgrades, formatting sweeps, or unrelated cleanup.
8. Do not compile the full firmware locally. GitHub Actions is the build machine.
9. Prefer targeted `grep/find/git diff` over recursive exploration of whole trees.
10. Reuse the pinned commits in `.github/workflows/build.yml`; do not search for newer versions unless explicitly asked.
11. Before push, inspect the complete diff and confirm it stays inside the requested scope.
12. After one focused commit, push once and report the real commit SHA and GitHub Run number/status.
13. Do not continuously poll a running GitHub Action; report once and stop unless asked to check again.
14. Keep replies short: findings/root cause, changed files, commit SHA, Run number/status.

## Validation before push
At minimum:
- `bash -n scripts/prepare.sh` when that file changes
- verify no donor full-target overlay was introduced
- verify official N60 Pro Ethernet/PHY/DSA/switch baseline is preserved
- verify 2 GiB RAM and 512 MiB storage assumptions remain intentional
- verify high-power radio guard rails remain
- verify requested WARP/HNAT/NMBM state is deliberate
- if image/boot layout changes, verify the resulting output format and expected boot/storage layout before pushing

## Build-success rule
A successful compile is only a build result, not proof that the firmware boots or that LAN/Wi-Fi works. After a successful build, inspect the produced image structure as required and wait for real-device testing before declaring the corresponding runtime issue solved.
