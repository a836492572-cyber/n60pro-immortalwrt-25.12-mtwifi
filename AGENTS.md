# N60 Pro Project Hard Rules

Before any N60 Pro work, read in this order:
1. `AGENTS.md`
2. `docs/BUILD_GATE.md`
3. `docs/CODEX_CONTEXT.md`

Do not rely on remembered chat context when these files are available. These repository rules are authoritative unless the user explicitly changes the process itself.

## Mission
Build a reliable Netcore N60 Pro firmware using:
- official ImmortalWrt 25.12.1 as the system/base tree
- Linux 6.12 from that official release
- official N60 Pro Ethernet / PHY / DSA / switch integration
- proprietary MediaTek `mt_wifi` 7.6.7.3
- 237 high-power MT7986 radio profiles
- modified hardware: 2 GiB RAM, 512 MiB SPI-NAND

The final firmware should differ from official ImmortalWrt 25.12.1 only where required for the 2 GiB / 512 MiB hardware and the proprietary 237 Wi-Fi path.

## Highest-priority operating rule: save Codex quota and full-build time
- ChatGPT must do analysis, source/log comparison, root-cause isolation, architecture decisions, and review whenever possible.
- Codex is used only when direct repository inspection/editing/cheap local validation/git operations materially help.
- Do not ask Codex to re-explain the project, re-scan already-audited areas, or redo analysis already present in `docs/CODEX_CONTEXT.md` or the current instruction.
- Codex instructions must be short, scoped, and reuse existing context/results.
- Prefer one Codex execution that completes the whole already-decided batch: inspect targeted files -> edit -> cheap validation -> inspect diff -> commit/push only when explicitly authorized.
- Never use a multi-hour GitHub Actions firmware build as the primary debugging tool.

## Roles
- ChatGPT is the architecture/debugging decision-maker and final review gate.
- Codex is the execution agent for repository work requested by ChatGPT: targeted inspection, requested edits, cheap checks, diff review support, commit, push, and GitHub Actions result retrieval when needed.
- Unless explicitly instructed to modify/push, Codex stays read-only.
- Codex must not choose a new technical direction, widen scope, or push speculative fixes.

## Non-negotiable architecture
- Official ImmortalWrt 25.12.1 commit `a3378d1a2c15beb2faf4b0bce9c00f07143efa29` is the base.
- Linux 6.12 from that official release is the kernel baseline.
- Official N60 Pro DTS / Ethernet / PHY / DSA / switch / platform networking remains authoritative.
- NEVER overlay or copy the donor's whole `target/linux/mediatek/` tree.
- Do not import donor N60 Pro/RFB networking DTS configuration.
- Do not modify BL2, FIP, U-Boot, or bootloader partitions.
- Donor code is allowed only for the proprietary MTK Wi-Fi path and specifically justified Linux 6.12 compatibility dependencies.
- Preserve radio behavior: `CountryCode=CN`, `E2pAccessMode=2`, `SKUenable=0`, `TxPower=100`, iPA/iLNA.
- Hardware adaptation must preserve 2 GiB RAM and the 512 MiB / ~506.5 MiB firmware area required by the installed WildEdition layout.

## NMBM policy
- NMBM is NOT globally forbidden and is NOT automatically required.
- Never infer that NMBM is active merely because a DTS property exists.
- Do not change NMBM behavior without an explicit task backed by the current boot/storage design.

## Wi-Fi / acceleration isolation
- Keep WARP/HNAT/WHNAT/Fast-NAT disabled unless a later explicit architecture decision requires them.
- 237 RF power itself must not depend on legacy WARP/HNAT.
- Do not re-enable acceleration just because donor defaults enable it.

## Required proprietary Wi-Fi / compatibility state
Keep the required 237-related selections and Linux 6.12 WEXT compatibility documented in `docs/BUILD_GATE.md` intact unless ChatGPT explicitly changes architecture.
During the current diagnostic phase, `mtk_wifi_utility`, `conninfra`, and `mt_wifi` must remain installed but not auto-loaded.

## Mandatory workflow
1. Start with `git status --short`.
2. Read `docs/BUILD_GATE.md`, `docs/CODEX_CONTEXT.md`, and only files directly required by the current instruction.
3. ChatGPT first identifies one evidence-backed failure domain from full logs/source/history.
4. Before editing, audit that whole failure chain for other cheap/static failures that can be found now. Do NOT use an "one tiny error -> one full build" loop.
5. Fix all confirmed issues in that same failure domain as one minimal coherent batch. Do not mix unrelated speculative changes.
6. Run only relevant cheap/static/targeted checks. Do not compile the full firmware locally.
7. Inspect the complete diff and validation output.
8. ChatGPT reviews the batch against `docs/BUILD_GATE.md`.
9. Only after the build gate passes may Codex commit/push a build-triggering change.
10. GitHub Actions is the final integration proof, not the exploratory debugger.
11. If Actions fails, preserve the full log, identify the first real terminating failure and its package/target, then return to step 3. Do not immediately guess/push/rebuild.
12. If Actions succeeds, inspect the produced artifact before asking for a real-device flash test.

## Hard build gate
- `docs/BUILD_GATE.md` is mandatory before every build-triggering push.
- If any applicable gate item is unknown or failed, do not push merely to "see what happens".
- A build-triggering push requires an evidence-backed plan plus completed cheap validation for everything that can reasonably be validated before the full build.

## No-repeat policy
Previously disproved causes and experiments recorded in `docs/CODEX_CONTEXT.md` must not be repeated without new direct evidence.
Do not reopen proven-good hardware/layout/baseline assumptions merely because a later custom build fails.

## Validation before push
At minimum, when applicable:
- syntax-check changed shell scripts
- verify patches apply cleanly and generated config is as intended
- verify no donor full-target overlay was introduced
- verify official N60 Pro Ethernet/PHY/DSA/switch baseline is preserved
- verify 2 GiB RAM and 512 MiB storage assumptions remain intentional
- verify 237 RF guard rails remain
- verify required WEXT compatibility remains exactly scoped
- verify proprietary module/package dependencies and known kernel-symbol requirements
- verify no-autoload diagnostic state when that phase is active
- verify WARP/HNAT/WHNAT/Fast-NAT remain disabled
- verify only the intended files changed

## Build-success rule
A successful compile is only a build result. It is not proof that the firmware boots or that LAN/Wi-Fi works. Inspect the artifact first, then rely on real-device testing for runtime conclusions.
