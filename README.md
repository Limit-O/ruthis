# ruthis — 万物磁贴桌面

Windows Phone 风格的磁贴桌面 Shell。运行于 **KWin (Wayland)** 之上，
以 layer-shell 背景层铺满桌面：磁贴即桌面、桌面即启动器、后台窗口一目了然。

ruthis 的本体只是一个**磁贴平台**（网格、拖拽、持久化、添加菜单）；
每一枚磁贴都是**外置插件**，官方磁贴与第三方磁贴完全同机制。

## 特性

- **磁贴网格**：Metro 式网格布局，右键拖动移动、右键点按属性菜单、尺寸可调
- **Z 轴图层**（[docs/z-axis.md](docs/z-axis.md)）：同层网格互斥、跨层堆叠自由；
  悬停+Super+滚轮 / [ ] 调层次、Super+Tab 图层翻转切换器（Win7 Flip 式透视纵深）、
  磁贴永久置顶（LayerTop 覆盖面，浮于一切窗口之上）
- **插件化磁贴**：manifest.json + Tile.qml（组件式）或纯 manifest 声明式数据源
  （command / file / http / dbus），详见 [docs/tiles.md](docs/tiles.md)
- **信息磁贴**：时钟（秒数可开）、系统（CPU/内存/网速/磁盘，可开关显示项）、
  电池、媒体（MPRIS 正在播放与控制）、音量
- **后台磁贴**：运行中窗口的迷你磁贴栅格，点按激活、中键/角标关闭
  （关不掉的窗口不显示关闭钮）
- **KWin 深度集成**：桌面模式以 `scope=desktop` 注册为桌面窗口，
  Overview/桌面网格等特效正确将其作为壁纸背景；窗口列表经 KWin 脚本桥推送
- **外观**：卡片颜色/透明度/圆角/间距可调；文字与图标明暗自动跟随壁纸，
  也可在设置面板手动钉死（浅色/深色）；kenney CC0 图标包随明暗自动切换黑白

## 构建

依赖：Qt 6（Core / Gui / Quick / DBus / Network）、LayerShellQt、CMake ≥ 3.21、C++17

```bash
cmake -B build -S .
cmake --build build
```

## 运行

```bash
build/ruthis -d          # 桌面模式：layer-shell 背景层铺满桌面（日常用法）
build/ruthis             # 窗口模式：1280×800 预览窗口
build/ruthis --dev       # 开发模式：从源码目录加载 QML，改动即热重载
build/ruthis --open-settings   # 启动即打开设置面板（调试）
build/ruthis --open-add        # 启动即打开添加磁贴面板（调试）
build/ruthis --open-flip       # 启动即进入图层翻转模式并自截帧（调试）
```

官方磁贴需要安装到磁贴目录（外置化后与第三方磁贴同机制）：

```bash
scripts/install-tiles.sh     # 安装/更新到 ~/.local/share/ruthis/tiles/
```

## 快捷键

| 输入 | 作用 |
|---|---|
| Ctrl+N | 添加磁贴 |
| Ctrl+H | 隐藏/显示全部磁贴 |
| Esc | 关闭弹窗 / 取消图层翻转 |
| Ctrl+Q | 退出 |
| 右键拖动磁贴 | 移动磁贴 |
| 右键点按磁贴 | 属性菜单（永久置顶 / 属性 / 删除） |
| 悬停磁贴 + Super+滚轮或 [ ] | 沿 Z 轴推远/拉近（需桌面持有焦点，见 docs/z-axis.md） |
| Super+Tab | 图层翻转切换器：级联展开，连按切换，松开落定 |

## 数据与安装位置

| 路径 | 内容 |
|---|---|
| `~/.config/ruthis/tiles.json` | 磁贴布局与实例数据（位置/尺寸/z/置顶/私有设置） |
| `~/.config/ruthis/settings.json` | 外观设置 |
| `~/.local/share/ruthis/tiles/` | 磁贴插件目录（官方 + 第三方） |
| `~/.local/share/ruthis/icons/` | 预留图标目录 |
| `/tmp/ruthis-debug.log` | 桥接与磁贴运行日志 |

## 文档索引

- [docs/tiles.md](docs/tiles.md) — 磁贴制作与使用指南（manifest 全字段、api 契约、声明式磁贴、示例）
- [docs/z-axis.md](docs/z-axis.md) — Z 轴技术总纲（图层/纵深模型、滚轮与 Super+Tab 交互、窗口磁贴化衔接）
- [docs/commits.md](docs/commits.md) — 提交规范（何时提交、信息格式、历史整理）

## 目录结构

```
src/      外壳与后端（C++ 头文件风格：窗口桥/磁贴注册表/数据源/媒体/音量/系统信息）
tiles/    官方磁贴插件（外置，不编入二进制；_generic 为外壳自带的声明式渲染器）
assets/   kenney CC0 图标包（编译期嵌入）
kwin/     KWin 窗口桥脚本（经 DBus 注入）
scripts/  install-tiles.sh
docs/     文档
```

## KWin 集成注记

- 桌面模式通过 LayerShellQt `setScope("desktop")` 将窗口注册为**桌面窗口**，
  KWin 的 Overview/桌面网格等特效会将其视为壁纸背景而非普通窗口；
- 窗口列表桥接：`kwin/kwin-windows.js` 由程序经 DBus 自动注入 KWin 运行，
  无需手动安装 KWin 脚本。
