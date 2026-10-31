# Touchline 23

[English](README.md) · [移植说明](docs/fifa23/README.md) · [上游来源](docs/UPSTREAM.md) · [打包工具](docs/packaging-gui.zh-CN.md)

Touchline 23 是**一款游戏**的原生 Apple 芯片移植：《FIFA 23 遗产版》（Nintendo
Switch），Title ID `01001C8016B4E000`。游戏自身的 ARM64 代码直接运行；内核服务、
文件系统、音频输出和 GPU 接口（NVN）为 macOS 与 iOS 重新实现，因此既不是 Switch
模拟器，也没有超出 Apple 内核要求的 ROM 改造。

本项目基于 [nxnative](https://github.com/seedds/nxnative)，经
[ohxiaoguang/nxnative-zzg](https://github.com/ohxiaoguang/nxnative-zzg) 取得。
执行架构、图形后端与最早的移植都是上游成果；本项目取自哪个提交见[上游来源](docs/UPSTREAM.md)。

## 支持的游戏

| | |
| --- | --- |
| 游戏 | FIFA 23 遗产版（Nintendo Switch） |
| Title ID | `01001C8016B4E000` |
| 本体 | 1.0.0（`v0`） |
| 更新 | 1.0.3（`v196608`），可选 |
| Shader chain | `a885c56c665a`（`dm/gfx/nvn/dmsh_chain.h`） |

本体与更新是同一个程序的两次构建：更新需要它自己的 RomFS、自己的 `main` 与
`sdk`，以及对应的重写模块。不要把新版 RomFS 和旧版代码混用。Shader 库由本体的
EASF 归档生成，对两个版本都有效（更新没有新增 Shader），profile 中记录了这两个
构建版本。

## 平台

- **Apple 芯片 + macOS 26 或更高**：产物是普通 `.app`，从你选择的文件夹读取游戏，
  存档、日志与临时文件也写在那个文件夹的 `Touchline23/` 里。
- **iPhone / iPad，iOS 26 或更高**：产物是未签名的 `.ipa`，由你自行签名并侧载。
  iOS 不允许 App 访问自身容器以外的文件，因此游戏文件放在 App 的 `Documents`
  目录下（任意子目录都可以）。

两个平台都需要足够的内存：启动时宿主保留 5 GiB 的客户机地址空间，一场比赛常驻
约 2.8 GiB。6 GB 及以上内存的设备是实际目标。

## 游戏文件由你提供

仓库中没有任何游戏数据。你需要自己的游戏副本：

- `01001C8016B4E000` 的本体 `.xci` 或 `.nsp`；
- 可选的 1.0.3 更新 `.nsp`；
- 你的主机 `prod.keys`。

**外置资源（默认）**：启动器只要求选择一个文件夹，它在其中（含子目录）识别本体与
更新，按内容核对 App 构建时使用的模块 ID，然后原地读取容器——不解包、不复制、不改名。
App 与 IPA 中不含游戏容器、密钥或 RomFS。

**Directory 模式**：RomFS 解包一次并打入 App，之后不再需要其他文件；产物大得多，
游戏版本也固定在构建时。需要自包含 App 时使用。

## 构建

环境：Apple 芯片 Mac、Xcode 26（Metal 工具链、`swiftc`、`iconutil`）、.NET 10、
`spirv-cross`，iOS 还需要 `xcodegen`，以及带 `capstone`、`lz4`、`fontTools`、
`pycryptodome` 的 Python 3（重写器和 EASF 工具使用）。

```sh
./scripts/build-mac.sh --nsp-dir "/你的/fifa23 文件夹"
./scripts/build-ios.sh --nsp-dir "/你的/fifa23 文件夹"
```

该文件夹放着本体容器、可选的更新和 `prod.keys`，脚本会自行分辨。产物写入
`Release/`：`Touchline23.app` 与 `Touchline23.ipa`。

两个脚本执行同样的阶段，每一阶段都可以复用上次的成果：

| 阶段 | 跳过方式 |
| --- | --- |
| ExeFS 与控制数据（`nx_extract`，仅程序） | `--exefs <ExeFS 目录>` |
| 重写后的 `main` 与 `sdk`（`dm/tools/patch_nso.py`） | `--patched <build/patched>` |
| Metal Shader 库（`dmsh_build.py`，macOS 与 iOS） | `--shaders`、`--ios-shaders` |
| 已备好的 EASF 包 | `--shader-pack <pkg>` |

`--work` 指定工作目录（默认 `build/work`），`--out` 指定产物，`--app-name`、
`--version`、`--language`、`--show-fps`、`--icon` 改变启动器显示的内容。
完整选项见 `./scripts/build-mac.sh --help`。

只有当 Shader 库的 `inputs.tsv` 与本 profile 的输入一致时才会被接受，因此来自其他
游戏、其他 profile 版本或其他 chain 的库会被拒绝，而不是被悄悄链入。从头生成
520 个库很慢；第二次构建会复用第一次的成果。

### 打包工具

`scripts/build_packaging_gui.py --output <目录>` 构建 **Touchline 23 打包工具**：
一个 SwiftUI App，用点击完成同样的工作——选择游戏文件夹、检查配置、查看日志、
取得 App 或 IPA。它自带 Python、读取器、提取器和 profile，可以放到任意位置。
见[使用说明](docs/packaging-gui.zh-CN.md)。

## 已验证的功能

证据按功能分别记录：Mac 上的检查不等于 iPhone 上的检查，IPA 结构审计也不等于实际
游玩。细节与出处见[兼容性](docs/fifa23/compatibility.md)与[验证记录](docs/fifa23/validation.md)。

| 功能 | 状态 |
| --- | --- |
| 原生启动进入菜单并进入比赛 | 可用，Mac 与 iPhone |
| 掌机 / 座机模式 | 两种模式均已报告可用 |
| 球员、球场、体育场、光照、观众 | 已测试场景渲染正常 |
| 比赛音效、观众声、解说 | 可用，Mac 与 iPhone |
| 球员指示、2D / 3D 雷达 | 可用 |
| 存档 | 可用，可从存档继续比赛 |
| iOS 触屏操作与手柄 | 可用 |
| 球员动态阴影 | 已修复；Mac 正式比赛中截取到投影 |
| 场边人员（摄影、安保、旗手） | 已观察到正常显示 |

## 已知问题与限制

- 场馆、天气、特殊场景与长时间运行的覆盖仍不完整，iPad 尚无单独记录。
- iOS 的物理内存是另一道限制：5 GiB 地址保留并不代表 jetsam 不会结束进程。
  未使用 Increased Memory Limit 权限签名的构建，仍可能在重场景中被系统终止。
- 采样帧耗时接近 60 fps，但偶有长帧，因此不作稳定 60 fps 的承诺。
- 载入时音频可能欠载；少数诊断服务调用尚未实现（日志中会有 `[RED]` 行）。
- 联网功能、amiibo 与 Switch 自身的网络服务不在本移植范围内。
- IPA 未签名，签名与安装由你完成。

## 目录

| 路径 | 用途 |
| --- | --- |
| `dm/host/` | 宿主：内核服务、NVN → Metal、音频、文件系统、输入 |
| `dm/gfx/` | Shader 翻译链及其工具（`dmsh_*`） |
| `dm/games/01001C8016B4E000/` | 游戏 profile：常量、Shader 表、构建版本 |
| `dm/tools/` | 重写器、提取器、profile 辅助工具 |
| `dm/macos/`、`dm/ios/`、`dm/apple/` | 启动器、平台胶水层与 iOS 工程 |
| `gui/`、`tools/packaging_gui/` | 打包 App 及其引擎 |
| `scripts/` | 用户运行的命令 |
| `docs/` | 指南、移植笔记与验证记录 |

## 测试

```sh
python3 -m unittest discover -s scripts/tests            # 构建脚本、打包、profile
make -C dm/host/tests GAME=01001C8016B4E000 run          # 本机宿主单元测试
python3 -m unittest discover -s dm/resource/tests        # 容器读取器
DM_GAME=01001C8016B4E000 python3 -m unittest discover -s dm/gfx/tests
cd gui && swift test                                      # 打包 App 的模型层
```

Python 测试不需要游戏文件。构建出真实的 App 或 IPA 是另一回事，只有在设备上实际
运行才能说明游戏能不能玩。

## 许可

MIT，见 [LICENSE](LICENSE)。nxnative 及其贡献者保留署名，第三方声明在
`dm/third_party/`。本仓库不分发任何游戏代码、游戏数据、密钥、字体、美术资源或已编译
的 Shader 库；App 图标由 `assets/app-icon/make_icon.swift` 绘制。
