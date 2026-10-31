# Touchline 23 打包工具

[English](packaging-gui.md) · [项目说明](../README.zh-CN.md) · [启动器与界面记录](launcher-and-packaging-ui.md)

`scripts/build_packaging_gui.py --output <目录>` 构建
**Touchline23Packaging.app**：把 `scripts/build-mac.sh` 与 `scripts/build-ios.sh`
用参数做的事变成点击——选择游戏文件夹、检查、构建 App 或 IPA、查看日志。

App 可以移到源码仓库之外，资源通过自身 Bundle 定位。内置 SwiftUI 程序、可移动的
CPython 运行环境与构建模块、capstone、LZ4、fontTools、pycryptodome、Zstandard
backport、游戏 profile 与索引、只读 Reader、程序提取器、锁定版本的 Shader 翻译器，
以及编译宿主所需的源码。用户不需要指定源码、Python、Reader、ExeFS 或 Shader 源目录。
Bundle 是只读输入，缓存与中间文件另存。

界面默认跟随系统语言（英语／简体中文，其他语言回退英语），手动选择会保存；启动器
共用同一套词典。

## 系统与外部工具

需要 Apple silicon、macOS 26+、Xcode 及 Metal 工具链、.NET 10、SPIRV-Cross，iOS
打包另需 XcodeGen。设置中会显示这些工具是否存在并可重新检测；缺失只在真正需要时
报告，不会禁用打包。App 使用本机 ad-hoc 签名，未做发行证书签名与公证；IPA 未签名，
签名与侧载由用户完成。

## 打包步骤

1. 选择放着本体（XCI 或 NSP）、可选的 1.0.3 更新包和你自己的 `prod.keys` 的文件夹，
   也可以直接输入本体路径。
2. 选择 macOS App、iOS IPA 或两者。默认外置资源模式；Directory 模式会自动提取并
   内置 RomFS，需要更多磁盘空间。
3. 输出默认与游戏文件夹一致，更换本体会同步改变，直到你手动指定；
   “恢复默认输出目录”重新启用自动选择。
4. 点击“检查配置”：按容器 Title ID 找到 profile，只提取程序与控制数据（外置模式
   不会复制镜像或解压 RomFS），并校验每个模块的 Build ID 与实际显示版本。
5. 点击“开始打包…”：确认面板显示游戏、版本、目标、资源模式、Shader 状态与输出位置，
   “技术详情”默认折叠。“开始打包”调用与命令行脚本相同的引擎、打包器、产物审计与
   发布校验；双平台依次执行，失败或取消会停止后续目标。

“支持的游戏…”列出内置的 profile——这里只有一个，即 FIFA 23 遗产版——可按名称、
Title ID 或登记版本搜索。列入目录不代表首次 Shader 生成或设备运行已经验证，那是
实际构建校验的事。

## Shader 与缓存

默认缓存根目录：`~/Library/Caches/Touchline23Packaging/`，可在“设置与诊断”中改为
外置 SSD。切换目录不会移动或删除旧数据。管理的内容放在带所有权标记的
`Touchline23Packaging-v1/{programs,shaders,tasks}` 下，清理只处理这个命名空间。

缓存身份包含游戏、Shader 来源版本、全局 Chain 和 profile 输入摘要，并分别校验两个
平台的反射与编译库。只改输出目录不会重新编译。旧缓存不兼容时会记录原因、保留原内容
并在新位置生成；不会修改 Shader 表或标记来通过校验。

没有可用缓存时会真实执行：EASF 来源准备（自动发现密钥、按范围读取 BIG4 成员）、
`dmsh_build.py`、生成运行表、校验两个平台，最后原子发布缓存。生成的表必须与登记的
表逐字节相同。“计算缓存占用”只统计软件管理的内容；“清理缓存…”会重新测量并二次
确认，测量结果变化或存在构建租约时拒绝清理，不跟随符号链接删除目录外内容，保留游戏、
密钥、存档与最终产物。

## 输出与临时文件

最终输出目录只接收审计通过的 App/IPA；重名时追加编号，先以临时名称复制校验再发布
最终名称。提取的代码、Shader 临时源码、重写结果、宿主中间文件与 DerivedData 位于
缓存磁盘的任务目录；成功后清理，失败时保留小型脱敏诊断。日志与历史位于
`~/Library/Logs/Touchline23Packaging`。

FIFA 23 的 Switch 版本不含追加内容，外置模式的产物也不携带任何游戏数据：安装后把
DLC NSP 放进所选游戏文件夹，宿主会校验并把它挂载为独立的只读文件系统，不会覆盖本体
RomFS。容器内若带真正的 NSO/NRO 程序模块，会明确要求收集与重写；新增的 Shader 仍需
补齐对应库，而不是伪造覆盖证明。压缩 NSZ 必须先转换为 NSP。

版本未知、控制数据版本与代码 ID 矛盾、图形审计不支持、来源缺失、缓存无效或依赖失败
都会明确停止打包。本 profile 使用 NVN；引擎中的 GL 与 Vulkan 路径存在，但这里没有
profile 使用它们。

## 开发者构建独立 App

面向发行者，不是普通用户的安装步骤：

```sh
/你的/构建用-python scripts/build_packaging_gui.py \
  --output /新目录 \
  --python /带依赖的可移动-python \
  --python-site /可选的附加依赖目录 --test
```

使用带 `lib/libpython*.dylib` 的可移动 CPython standalone 安装。构建器挑选所需依赖并
保留其许可证，编译 Reader 与提取器，复制必要的源码/profile/工具，生成索引与资源清单，
校验复制后的 Python，构建并测试 Swift 代码，最后 ad-hoc 签名。不复制旧 venv，也不生成
指向旧解释器的启动脚本。构建机器另需 .NET SDK 与 LibHac 包。没有 DMG、更新器或发布步骤。
