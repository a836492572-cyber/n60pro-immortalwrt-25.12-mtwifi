#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: rebase-hnat-eth-patch-56.py <999-eth-91 patch>")

p = Path(sys.argv[1])
s = p.read_text()

OPEN = "@@ -4531,6 +4562,7 @@ static int mtk_open(struct net_device *dev)"
STOP = "@@ -4718,10 +4751,12 @@ static int mtk_stop(struct net_device *dev)"
PROBE = "@@ -7222,6 +7257,7 @@ static int mtk_probe(struct platform_device *pdev)"
ERR = "@@ -7306,7 +7343,9 @@ static int mtk_probe(struct platform_device *pdev)"
FOOTER = "-- \n2.45.2\n"

for marker in (OPEN, STOP, PROBE, ERR, FOOTER):
    if s.count(marker) != 1:
        raise SystemExit(f"unexpected donor patch shape for marker {marker!r}: {s.count(marker)}")

# The pinned donor patch targets a newer vendor mtk_eth_soc.c layout. Re-anchor
# only the incompatible PPE ownership regions to official 25.12.1 / Linux 6.12.
def replace_span(text: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:]

open_hunk = r'''@@ -3838,7 +3869,9 @@ static int mtk_open(struct net_device *dev)
 		if (err)
 			return err;
 
+#if !defined(CONFIG_NET_MEDIATEK_HNAT) && !defined(CONFIG_NET_MEDIATEK_HNAT_MODULE)
 		for (i = 0; i < ARRAY_SIZE(eth->ppe); i++)
 			mtk_ppe_start(eth->ppe[i]);
+#endif
 
 		for (i = 0; i < MTK_MAX_DEVS; i++) {
'''

stop_hunk = r'''@@ -3968,7 +4001,9 @@ static int mtk_stop(struct net_device *dev)
 	mtk_dma_free(eth);
 
+#if !defined(CONFIG_NET_MEDIATEK_HNAT) && !defined(CONFIG_NET_MEDIATEK_HNAT_MODULE)
 	for (i = 0; i < ARRAY_SIZE(eth->ppe); i++)
 		mtk_ppe_stop(eth->ppe[i]);
+#endif
 
 	if (mac->pextp)
 		phy_power_off(mac->pextp);
'''

err_hunk = r'''@@ -5750,6 +5785,8 @@ err_unreg_netdev:
 	mtk_unreg_dev(eth);
 err_deinit_ppe:
+#if !defined(CONFIG_NET_MEDIATEK_HNAT) && !defined(CONFIG_NET_MEDIATEK_HNAT_MODULE)
 	mtk_ppe_deinit(eth);
+#endif
 	mtk_mdio_cleanup(eth);
 err_free_dev:
 	mtk_free_dev(eth);
'''

s = replace_span(s, OPEN, STOP, open_hunk)
s = replace_span(s, STOP, PROBE, stop_hunk)
s = replace_span(s, ERR, FOOTER, err_hunk)

# Standalone mtk_hnat/hnat.c consumes these NETSYS-v2 PPE flow-check bits. The
# donor tree provides them in 999-hnat-02. Carry only the exact definitions,
# without importing the donor Ethernet patch series. Do not anchor this hunk to
# the donor FE_INT_STATUS2 neighbourhood: official 25.12.1's earlier patch stack
# changes that region. The include guard is stable and the macro definitions are
# position-independent.
flow_check_header_hunk = r'''diff --git a/drivers/net/ethernet/mediatek/mtk_eth_soc.h b/drivers/net/ethernet/mediatek/mtk_eth_soc.h
--- a/drivers/net/ethernet/mediatek/mtk_eth_soc.h
+++ b/drivers/net/ethernet/mediatek/mtk_eth_soc.h
@@ -10,1 +10,4 @@
 #define MTK_ETH_H
+#define MTK_FE_INT_ENABLE2	0x2C
+#define MTK_FE_INT2_PPE0_FLOW_CHK	BIT(28)
+#define MTK_FE_INT2_PPE1_FLOW_CHK	BIT(29)
'''

for macro in ("MTK_FE_INT_ENABLE2", "MTK_FE_INT2_PPE0_FLOW_CHK", "MTK_FE_INT2_PPE1_FLOW_CHK"):
    if macro in s:
        raise SystemExit(f"flow-check prerequisite already present before injection: {macro}")
s = s.replace(FOOTER, flow_check_header_hunk + FOOTER, 1)

if s.count("#if !defined(CONFIG_NET_MEDIATEK_HNAT) && !defined(CONFIG_NET_MEDIATEK_HNAT_MODULE)") < 5:
    raise SystemExit("HNAT guard count unexpectedly low after rebase")
if "mtk_ppe_roaming_start" in s or "mtk_ppe_roaming_stop" in s:
    raise SystemExit("donor-only PPE roaming context survived HNAT patch rebase")
if PROBE not in s:
    raise SystemExit("probe PPE-init guard hunk was lost")
for macro in ("MTK_FE_INT_ENABLE2", "MTK_FE_INT2_PPE0_FLOW_CHK", "MTK_FE_INT2_PPE1_FLOW_CHK"):
    if s.count(macro) != 1:
        raise SystemExit(f"flow-check prerequisite count != 1 after injection: {macro}: {s.count(macro)}")

p.write_text(s)

# The pinned HNAT hook includes donor mtk_eth_reset.h only for the private
# MTK_FE_RESET_NAT_DONE notifier value. That header is created by the donor's
# broad internal-SER Ethernet patch, which #56 intentionally does not import.
# Keep the official 25.12.1 Ethernet/reset baseline untouched and localize only
# this one event ID inside the standalone vendor HNAT hook.
hnat_hook = (
    p.parent.parent
    / "files-6.12"
    / "drivers/net/ethernet/mediatek/mtk_hnat/hnat_nf_hook.c"
)
if not hnat_hook.is_file():
    raise SystemExit(f"missing HNAT hook source: {hnat_hook}")

hs = hnat_hook.read_text()
reset_include = '#include "../mtk_eth_reset.h"\n'
reset_compat = '''/* N60PRO_HWACCEL_56_RESET_EVENT_COMPAT
 * Donor mtk_eth_reset.h is intentionally not imported: the HNAT hook needs
 * only this notifier event ID, while official Ethernet/SER stays untouched.
 */
#ifndef MTK_FE_RESET_NAT_DONE
#define MTK_FE_RESET_NAT_DONE\t(0x4001)
#endif
'''

if reset_include in hs:
    if hs.count(reset_include) != 1:
        raise SystemExit(f"unexpected mtk_eth_reset.h include count: {hs.count(reset_include)}")
    if "N60PRO_HWACCEL_56_RESET_EVENT_COMPAT" in hs:
        raise SystemExit("HNAT reset compat marker already present beside donor include")
    hs = hs.replace(reset_include, reset_compat, 1)
elif "N60PRO_HWACCEL_56_RESET_EVENT_COMPAT" not in hs:
    raise SystemExit("HNAT hook has neither donor reset include nor #56 compat marker")

if '../mtk_eth_reset.h' in hs:
    raise SystemExit("donor mtk_eth_reset.h dependency survived #56 compatibility edit")
if hs.count("N60PRO_HWACCEL_56_RESET_EVENT_COMPAT") != 1:
    raise SystemExit("HNAT reset compat marker count != 1")
if hs.count("#define MTK_FE_RESET_NAT_DONE") != 1:
    raise SystemExit("HNAT reset event definition count != 1")

hnat_hook.write_text(hs)
print("rebase HNAT Ethernet patch #56 for official 25.12.1 + stable flow-check/reset prerequisites: OK")
