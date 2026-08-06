# N60 Pro ImmortalWrt 25.12.1 + MTK mtwifi

目标：在官方 ImmortalWrt 25.12.1 N60 Pro 的基础上，只加入硬件适配和 237 高功率 MTK 私有 Wi-Fi 所必需的修改。

## 固定基础

- 官方 ImmortalWrt 25.12.1 release commit：`a3378d1a2c15beb2faf4b0bce9c00f07143efa29`
- Linux 6.12
- Netcore N60 Pro / MT7986A
- 官方 N60 Pro Ethernet / PHY / DSA / switch / PPE 保持权威，不使用 donor target 覆盖

## 硬件

- 2 GiB RAM
- 512 MiB SPI-NAND
- WildEdition U-Boot 2025
- UBI 起点：`0x00580000`
- 目标固件区域：`0x1fa80000`（约 506.5 MiB）
- BL2 / FIP / U-Boot 不由普通固件修改
- NMBM 是否使用由最终确认的存储/启动方案决定，不预设必须启用或禁用

## Wi-Fi

- MediaTek proprietary `mt_wifi` 7.6.7.3
- MT7986 / MT7976
- 237 高功率射频配置
- `E2pAccessMode=2`
- `SKUenable=0`
- `TxPower=100`
- iPA/iLNA
- 只引入 proprietary Wi-Fi 在 Linux 6.12 上运行所必需的 donor package / compatibility dependency

## 当前隔离原则

- 不复制 donor 整个 `target/linux/mediatek/`
- 不替换官方 N60 Pro DTS / Ethernet / PHY / DSA / switch
- WARP / HNAT / WHNAT / Fast-NAT 当前保持禁用，除非后续经过明确架构确认需要启用
- 不预装代理、Docker、iStore 等无关第三方组件

## 工作方式

- 下一次长时间构建前，先静态审计完整启动链：U-Boot -> NAND/UBI -> kernel -> rootfs
- GitHub Actions 负责完整编译
- 编译成功不代表真机启动、LAN 或 Wi-Fi 已验证，最终以真机测试为准

详细规则见 `AGENTS.md`，当前项目状态和已验证事实见 `docs/CODEX_CONTEXT.md`。
