# N60 Pro Build Gate

This gate is mandatory before any push that can trigger the long GitHub Actions firmware build.

## Purpose
The goal is to minimize Codex quota and multi-hour full-build iterations by moving every reasonable check before the integration build.

## Final product principle
- Preserve official ImmortalWrt 25.12.1 behavior wherever possible.
- Add only the N60 Pro high-power proprietary 237 Wi-Fi/RF path on top of the official base.
- Keep the required hardware adaptation: 2 GiB RAM, 512 MiB SPI-NAND, WildEdition MAX 506.5 MiB firmware area.
- WARP/HNAT/WHNAT/Fast-NAT disabled is the current diagnostic-phase state, not a permanent final-product goal.

## Gate A — evidence and scope
- [ ] The current failure domain/root cause is supported by logs, source, or a reproducible static fact; it is not a guess.
- [ ] Existing project history and disproved theories in `docs/CODEX_CONTEXT.md` were reused instead of re-investigated blindly.
- [ ] The whole relevant failure chain was audited for other cheap/static problems that can be fixed in the same batch.
- [ ] The batch contains only related, evidence-backed changes; unrelated DTS/network/storage/Wi-Fi/workflow changes are not mixed in.

## Gate B — immutable project baseline
- [ ] Official ImmortalWrt 25.12.1 commit is `a3378d1a2c15beb2faf4b0bce9c00f07143efa29`.
- [ ] Kernel baseline is official Linux 6.12 from that release.
- [ ] Official N60 Pro Ethernet / PHY / DSA / switch/platform networking remains authoritative.
- [ ] No donor whole `target/linux/mediatek/` overlay/import exists.
- [ ] BL2/FIP/U-Boot/bootloader partitions are untouched.
- [ ] Hardware target remains MT7986A, 2 GiB DDR4, 512 MiB SPI-NAND.
- [ ] Intended UBI/firmware area remains `0x0580000` + `0x1fa80000` unless the user explicitly changes it.

## Gate C — proprietary 237 Wi-Fi invariants
Required baseline and diagnostic selections remain true:

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
CONFIG_MTK_MGMT_TXPWR_CTRL=y
CONFIG_MTK_TPC_SUPPORT=y
CONFIG_MTK_TXBF_SUPPORT=y

#42 verified baseline:
7.6.7.3 + mt7986-fw-20260601

Post-#45 Golden exact RF enclave candidate:
Golden exact `package/mtk/drivers/mt_wifi/` from
`padavanonly/immortalwrt-mt798x-6.6`
commit `4c657c93546c86cd9f9d83cd5931b5056e652dbb`.
`PKG_VERSION:=7.6.6.1-$(PKG_SUFFIX)`
Golden native patches `002` through `022` apply before the local Linux 6.12 overlay `100`, `103`, `109`, and `112` through `118`.
# CONFIG_MTK_MT7986_NEW_FW is not set
```

The current candidate is a temporary Golden exact RF enclave inside the current official 25.12.1 / Linux 6.12 platform. It is not a final decision to select Linux 6.6, and WARP/HNAT/WHNAT/Fast-NAT disabled remains the current diagnostic isolation state rather than a permanent final-product policy. Final RF stack and acceleration selection are decided by real-device 50/48 power, RSSI, and throughput results.

#43 firmware-only A/B lesson:
- Golden firmware-only A/B failed on real hardware: power remained raw `44` / `45`.
- Runtime again showed an EEPROM request length of `0x5000`, while the official `eeprom_factory_0` nvmem cell is `0x1000`.
- Current nvmem partial-read path: `0x0000-0x0fff` is real EEPROM, while `0x1000-0x4fff` becomes synthetic `0x00` due to zero-fill.
- Raw factory MTD semantics: `0x0000-0x0fff` is real EEPROM, while `0x1000-0x4fff` is real erased `0xFF`; current evidence shows non-FF bytes in that range = `0`.
- Current RF calibration-path candidate keeps the official `eeprom_factory_0` cell unchanged and adds only the N60 Pro `mediatek,mtd-eeprom = <&factory 0x0>;` path to restore true factory byte semantics from factory offset `0x0`, including erased `0xFF`.
- This is not a final root-cause judgment; the real-device target remains raw `50` / `48`.

#44 MTD EEPROM semantics lesson:
- Raw factory MTD EEPROM semantics were restored and runtime reads showed `e2p 0x1000`, `0x1002`, `0x2000`, and `0x4ffe` as `FFFF`.
- High-power still failed on real hardware: power remained raw `44` / `45`.
- Do not reopen firmware-only, nvmem partial zero-fill, EEPROM `0x1000` vs `0x5000`, RF offset, SKU, Backoff, Thermal, PowerUp, ePAGain, profile, WARP/HNAT for this candidate without new evidence.

#45 donor 7661 host-driver A/B lesson:
- Donor 7.6.6.1 host + Golden firmware + raw factory MTD EEPROM changed real-device power to raw `46` / `42`.
- This proves host-side environment affects TX power, but donor 7661 does not reproduce the Golden raw `50` / `48`.
- The next candidate uses the Golden exact vendored `mt_wifi` 7.6.6.1 package, Golden native patch stack, Golden bundled firmware, Golden RF Kconfig behavior, and only the required Linux 6.12 integration overlay.

Required RF profile files remain present:
- `l1profile.dat`
- `mt7986-ax6000.dbdc.b0.dat`
- `mt7986-ax6000.dbdc.b1.dat`
- `mt7986-sku.dat`
- `mt7986-sku-bf.dat`

Required RF behavior remains:
- `CountryCode=CN`
- `E2pAccessMode=2`
- `SKUenable=0`
- `TxPower=100`
- iPA/iLNA
- N60 Pro first radio EEPROM offset is `0x0`

#39 config lesson:
- `mtk_wifi_utility` real-device manual load returned rc=0; RBUS and PCIe `14c3:7986` are verified [permanent].
- Hidden mt_wifi Kconfig can re-resolve `CONFIG_MTK_RT_FIRST_IF_RF_OFFSET` to `0xc0000`; MT7986 must resolve to `0x0`.
- Rebase must preserve `CONFIG_CONNINFRA_AUTO_UP=y` and `CONFIG_CONNINFRA_EMI_SUPPORT=y`.
- Both final resolved `.config` and artifact `config.buildinfo` must gate these three symbols.

#40 runtime lesson:
- Manual module load chain `mtk_wifi_utility -> conninfra -> mt_wifi` returned rc=0 and restored both radios after `wifi down && wifi up`.
- Dual-band AP, 2.4 GHz HE40, 5 GHz HE160, mobile DHCP/LuCI, WAN DHCP/default route/DNS, and Wi-Fi-client NAT to WAN Internet were verified on real hardware.
- Reboot Wi-Fi failure is the current NOAUTOLOAD boot-order condition: netifd setup can run while `mt_wifi` is not yet available.
- `iwpriv` is called by `mtwifi-cfg-ucode`; artifact must include `/usr/sbin/iwpriv`.
- Observed `INDEX0_EEPROM_size=0x5000` with nvmem cell size `0x1000` and `copied=0x1000`; the compatibility layer zero-fills the requested buffer first, and #41 must not change EEPROM size/cell/backend without new evidence.

## Gate D — Linux 6.12 compatibility invariants
Only the required WEXT compatibility delta is allowed unless explicitly approved:

```text
CONFIG_WIRELESS_EXT=y
CONFIG_WEXT_CORE=y
CONFIG_WEXT_PRIV=y
CONFIG_WEXT_PROC=y
CONFIG_WEXT_SPY=y
```

- [ ] `wifi_utility -> conninfra -> mt_wifi` package/module dependency chain is internally consistent.
- [ ] Known EEPROM symbol requirements are satisfied.
- [ ] N60 Pro DTS keeps `factory: partition@180000` at `reg = <0x180000 0x200000>;`.
- [ ] N60 Pro DTS keeps `eeprom_factory_0: eeprom@0` at `reg = <0x0 0x1000>;` and does not expand it to `0x5000`.
- [ ] N60 Pro DTS includes `mediatek,mtd-eeprom = <&factory 0x0>;` for the proprietary Wi-Fi calibration read path.
- [ ] No known unresolved modpost/link/kernel-symbol error remains in the changed failure domain.
- [ ] WARP/HNAT/WHNAT/Fast-NAT remain disabled.
- [ ] During the current diagnostic phase, only the proprietary base Wi-Fi modules are auto-loaded: `mtk_wifi_utility` boot autoload priority 09, `conninfra` boot autoload priority 10, and `mt_wifi` normal autoload priority 11.
- [ ] `mt_wifi` must not be promoted into `modules-boot.d`; utility/conninfra keep donor boot-stage behavior, while `mt_wifi` only needs normal kmodloader availability before netifd wireless setup.
- [ ] `mtwifi-cfg-ucode` depends on `wireless-tools`, and its temporary acceleration-isolation reload list does not reference `mtk_warp_proxy` or `mtk_warp`.

## Gate E — cheap validation completed
Run only checks relevant to the change, but do every applicable cheap check before the full build:
- [ ] `git status --short` checked before work.
- [ ] Changed shell scripts pass `bash -n`.
- [ ] Patch/application steps have been checked for clean application where practical.
- [ ] Relevant Kconfig/Makefile/package dependency facts were checked.
- [ ] Resulting `.config` / `defconfig` critical symbols were checked when config is affected.
- [ ] Relevant targeted package/module/compile check was run if it is materially cheaper than a full firmware build and feasible.
- [ ] Full local firmware build was NOT used as the default validation step.
- [ ] Complete `git diff` was reviewed and contains only intended changes.

## Gate F — ChatGPT review
Before a build-triggering push:
- [ ] ChatGPT reviewed the root cause, change set, diff scope, and cheap-validation results.
- [ ] No obvious known failure remains that would make a long build predictably wasteful.
- [ ] ChatGPT explicitly considers the batch ready for one integration build.

If any applicable item is failed or unknown, do not push just to test a guess.

## GitHub Actions rule
The full GitHub Actions firmware build is only the final integration proof for a pre-validated batch.
If it fails:
1. preserve/download the full failure log;
2. locate the first real unignored terminating error and associated package/target;
3. analyze the entire relevant failure domain before the next edit;
4. do not immediately start another full build.

If it succeeds, inspect the produced buildinfo/profile/image/hash evidence before real-device flashing.
