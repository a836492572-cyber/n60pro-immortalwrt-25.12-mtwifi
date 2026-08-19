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

# The pinned donor patch is written for a newer vendor mtk_eth_soc.c layout.
# Official ImmortalWrt 25.12.1 / Linux 6.12 has the same PPE ownership points,
# but no donor PPE-roaming calls beside open/stop and a different error unwind.
# Re-anchor only those three failing regions. Keep the donor RX metadata hooks,
# Kconfig/Makefile changes and the probe PPE-init guard unchanged.

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

# Guard against accidentally deleting the already-clean probe ownership guard.
if s.count("#if !defined(CONFIG_NET_MEDIATEK_HNAT) && !defined(CONFIG_NET_MEDIATEK_HNAT_MODULE)") < 5:
    raise SystemExit("HNAT guard count unexpectedly low after rebase")
if "mtk_ppe_roaming_start" in s or "mtk_ppe_roaming_stop" in s:
    raise SystemExit("donor-only PPE roaming context survived HNAT patch rebase")
if PROBE not in s:
    raise SystemExit("probe PPE-init guard hunk was lost")

p.write_text(s)
print("rebase HNAT Ethernet patch #56 for official 25.12.1: OK")
