# N60 Pro ImmortalWrt 25.12.1 + MTK mtwifi

目标固件：

- 官方 ImmortalWrt 25.12.1（固定 `cd0a06bfd3fd`）
- Linux 6.12
- Netcore N60 Pro / MT7986A
- 2 GiB RAM
- 512 MiB SPI-NAND
- UBI：`0x00580000 + 0x1fa80000`（506.5 MiB）
- MTK `mt_wifi` + WARP/WED + HNAT
- 237 风格射频：iPA/iLNA、`SKUenable=0`、`TxPower=100`
- 纯净系统，不预装代理/Docker/iStore 等第三方插件

GitHub Actions 自动编译，产物在 Actions Artifacts 中下载。
