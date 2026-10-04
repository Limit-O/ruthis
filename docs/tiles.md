# ruthis 磁贴制作与使用指南

ruthis 的本体只是一个"磁贴平台"：网格布局、拖拽、持久化、添加菜单都是外壳提供的。
**每一枚磁贴都是一个插件**，官方磁贴与第三方磁贴完全同机制——都住在磁盘上的磁贴目录里，
不编进二进制。做一个新磁贴，最少只需要一个十几行的 JSON 文件。

## 一、磁贴放在哪

```
~/.local/share/ruthis/tiles/<类型名>/
    manifest.json    # 必须：身份与配置声明
    Tile.qml         # 组件式磁贴才有；声明式磁贴不需要
```

- 仓库自带的官方磁贴用 `scripts/install-tiles.sh` 安装到上述目录；
- 第三方磁贴 = 把一个目录拷进去，重启 ruthis 即出现在"添加磁贴"菜单；
- 删除磁贴 = 右键磁贴删除实例 + 删掉目录（不再出现于菜单）；
- 同名类型后扫描的目录覆盖先扫描的（`--dev` 时源码目录优先级最高，方便调试）。

## 二、manifest.json 字段

```jsonc
{
  "name": "媒体",            // 显示名（添加菜单按钮文字、新磁贴默认标签）
  "category": "信息",        // 添加菜单分组；未知分组排在固定分组之后
  "size": [2, 2],            // 新建时的默认尺寸（格）
  "icon": "musicOn",         // kenney 图标名，或完整 id（如 "kenney/White/gear"、主题名、路径）
  "api": 1,                  // 依赖的外壳 api 版本
  "props": [ ... ],          // 组件私有设置（见下），可省略
  "source": { ... },         // 声明式数据源（见下），组件式磁贴不需要
  "render": { ... }          // 声明式渲染方式（仅声明式磁贴用）
}
```

### props：组件私有设置

在磁贴右键"属性…"面板里自动生成编辑器，实例值保存在该磁贴自己的
`~/.config/ruthis/tiles.json` 里（`opts` 字段），磁贴内通过 `cfg.opts.<key>` 读取。

| type | 编辑器 | 值 |
|---|---|---|
| `text` | 单行文本框 | 字符串 |
| `select` | 按钮组（单选） | `options` 里的某一项 |
| `toggle` | 开关按钮 | `"开"` / `"关"` |

```json
"props": [
  { "key": "showNet", "name": "网速", "type": "toggle", "default": "开" },
  { "key": "fontSize", "name": "字号", "type": "text", "default": "15" },
  { "key": "unit", "name": "单位", "type": "select", "options": ["℃", "℉"], "default": "℃" }
]
```

`opts` 里没有的键 = 未设置过，插件应回退到 manifest 里的 `default`。

## 三、组件式磁贴（Tile.qml）

`Tile.qml` 的根 Item 约定三个可注入属性，外壳会自动赋值：

```qml
import QtQuick

Item {
    id: tile
    property var api    // 平台服务（下表）
    property var cfg    // 本磁贴实例数据
    property var ds     // 数据源（仅声明式磁贴会被赋值）

    // 你的内容。外壳已提供 12px 内容安全区，不要让内容再贴边。
}
```

### cfg（实例数据）

| 字段 | 含义 |
|---|---|
| `cfg.index` | 在磁贴列表中的下标（写回数据用） |
| `cfg.type` | 类型名（目录名） |
| `cfg.text` / `cfg.glyph` / `cfg.label` / `cfg.command` / `cfg.icon` | 磁贴常规字段（属性面板可编辑） |
| `cfg.opts` | 私有设置对象（`props` 的实例值） |

### api（平台服务）

| 成员 | 说明 |
|---|---|
| `api.sys` | 系统：`cpuPercent()`、`memoryString()`、`uptimeString()`、`netSpeedString()`、`diskString()`、`kernelVersion()`、`hasBattery()`、`batteryPercent()`、`batteryStatus()` |
| `api.media` | MPRIS：`available`、`playing`、`title`、`artist`、`player`、`toggle()/next()/previous()` |
| `api.audio` | 音量：`volume`（0-100）、`muted`、`setVolume(n)`、`toggleMute()` |
| `api.windows` | 后台窗口：`windows`（`[{id,caption,cls,active,closeable}]`）、`activateWindow(id)`、`closeWindow(id)` |
| `api.fg` | 文字颜色（跟随明暗设置，**所有内容颜色都应从它派生**） |
| `api.iconVariant` | kenney 图标色系（`"White"`/`"Black"`） |
| `api.tileRadius` / `api.cardColor` | 外观 |
| `api.launch(cmd)` | 启动应用 |
| `api.openSettings()` | 打开设置面板 |
| `api.updateTile(index, key, value)` | 写回磁贴数据（自动持久化） |

### 交互与颜色约定

- **左键属于内容**：需要点击交互就在插件里放自己的 MouseArea；
  拖动磁贴用右键按住拖动，右键点按 = 属性菜单（外壳处理，插件不用管）；
- **颜色禁止写死**：一律从 `api.fg` 派生（半透明底色用
  `Qt.rgba(api.fg.r, api.fg.g, api.fg.b, 透明度)`），否则在亮/暗壁纸上会隐身；
- 图标用 `image://icons/kenney/ + api.iconVariant + /名字`，黑白随明暗自动切换。

### 一个最小例子（tiles/hello/）

```qml
import QtQuick

Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"

    Text {
        anchors.centerIn: parent
        text: "你好，ruthis ✨"
        color: tile.fg
        font.pixelSize: 17
    }
}
```

## 四、声明式磁贴（不需要写 QML）

manifest 里声明 `source` 且不提供 Tile.qml 时，外壳用通用渲染器
（`render` 决定样式）自动呈现。**一条命令/一个地址就是一个磁贴**。

### source：数据从哪来

```jsonc
"source": {
  "type": "command",          // /bin/sh -c 执行，取 stdout
  "cmd": "cut -d ' ' -f1-3 /proc/loadavg",
  "interval": 5               // 刷新秒数（≥2，默认 60）
}
```

| type | 额外字段 | 说明 |
|---|---|---|
| `command` | `cmd` | shell 命令，取 stdout |
| `file` | `path` | 读文件（/proc、/sys、状态文件） |
| `http` | `url` | GET 请求（10 秒超时），取响应体 |
| `dbus` | `service` `path` `iface` `property` | 读 DBus 属性（3 秒超时） |

输出统一去除首尾空白、截断 4KB；空输出或失败显示"（暂无数据）"。

### render：怎么展示

```jsonc
"render": { "type": "text" }                    // 默认：多行文本
"render": { "type": "bar", "max": 100 }         // 取输出里第一个数字画进度条
```

bar 模式数值超过 `max` 的 90% 时进度条变红（适合磁盘/温度类）。

### 例子

```jsonc
// 天气（http）：拷进磁贴目录即可用
{
  "name": "天气", "category": "信息", "size": [2, 1], "icon": "star", "api": 1,
  "source": { "type": "http", "url": "https://wttr.in/?format=3", "interval": 1800 },
  "render": { "type": "text" }
}

// 根分区用量（command + bar）
{
  "name": "示例·磁盘", "category": "演示", "size": [2, 1], "icon": "contrast", "api": 1,
  "source": { "type": "command", "cmd": "df / | tail -1 | awk '{print $5}'", "interval": 30 },
  "render": { "type": "bar" }
}
```

## 五、调试

```bash
ruthis --dev        # 从源码目录加载 QML，改动 src/Main.qml 与 tiles/*/ 即热重载
                    # （源码 tiles/ 目录优先于安装目录，改插件不用重新安装）
ruthis --open-add   # 启动即弹出添加磁贴面板
ruthis --open-settings
```

日志走 stderr；磁贴运行数据问题的排查入口在 `/tmp/ruthis-debug.log`。

## 六、现有官方磁贴一览

| 类型 | 说明 | 私有设置 |
|---|---|---|
| clock | 时钟/日期 | 显示秒数 |
| sys | 内核/运行时间/CPU/内存/网速/磁盘 | CPU、网速、磁盘显示开关 |
| battery | 电量与充放状态 | — |
| media | MPRIS 正在播放与控制 | — |
| volume | 默认输出音量/静音 | — |
| app | 应用启动器 | — |
| tasks | 后台窗口栅格（激活/关闭） | — |
| note | 便签 | 字号 |
| settings | 打开设置面板 | — |
| loadavg | 系统负载（声明式示例） | — |

示例插件：`hello`（组件式最小例）、`example-disk`（声明式 bar 例）。
