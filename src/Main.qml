import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects

Item {
    id: root

    property int gap: 14
    property int cell: 96
    readonly property int step: cell + gap

    // ---- 外观设置（settings.json 持久化）----
    property real tileOpacity: 0.10
    property int tileRadius: 0
    property color cardColor: "#ffffff"
    property string wallpaperUrl: ""
    property bool tilesHidden: false

    function cardEffectiveLum() {
        const lum = 0.299 * cardColor.r + 0.587 * cardColor.g + 0.114 * cardColor.b
        return lum * tileOpacity + 0.03 * (1 - tileOpacity)
    }

    // 文字/图标明暗：auto 跟随卡片亮度，light/dark 手动钉死（设置面板可调）
    property string fgMode: "auto"
    // 玻璃质感（顶部高光+描边），设置面板可关
    property bool glass: true
    // 覆盖面：拖拽进行中（输入区临时放开为全屏，否则 mask 会截断拖拽事件）
    property bool overlayDragActive: false
    // 弹窗或拖拽期间覆盖面输入区放开为全屏
    readonly property bool overlayInputFull: overlayDragActive || tileMenu.opened
        || tileProps.opened || addPopup.opened || settingsPopup.opened
    onOverlayInputFullChanged: syncOverlayMask()
    readonly property color tileFg: fgMode === "light" ? "#f4f7ff"
        : fgMode === "dark" ? "#151a22"
        : (cardEffectiveLum() > 0.5 ? "#151a22" : "#f4f7ff")
    // kenney 图标黑白两版与文字同步（暗底白图标，亮底黑图标）
    readonly property string iconVariant: fgMode === "light" ? "White"
        : fgMode === "dark" ? "Black"
        : (cardEffectiveLum() > 0.5 ? "Black" : "White")

    // ---- Z 轴状态（docs/z-axis.md）----
    property bool flipMode: false
    property int flipIndex: 0
    property int zRevision: 0
    // 覆盖面模式（本实例是置顶磁贴的 LayerTop 宿主窗口）
    readonly property bool overlayMode: OverlayMode === true
    // 悬停中的磁贴：Super+</> 微调它的层次
    property Item hoveredTile: null

    // ---- 透视纵深（真 3D 后退：位置向消失点收敛 + 缩放 + rotateY）----
    readonly property real eye: 1000          // 相机距离
    readonly property real planeGap: 150      // 层间 z 间距
    readonly property real vpX: width / 2     // 消失点
    readonly property real vpY: height * 0.42
    function recedeS(d) { return root.eye / (root.eye + root.planeGap * d) }

    // 4x4 行主序矩阵乘（行向量约定：p' = p·M）
    function mul4(a, b) {
        const r = []
        for (let i = 0; i < 4; i++)
            for (let j = 0; j < 4; j++) {
                let v = 0
                for (let k = 0; k < 4; k++)
                    v += a[i * 4 + k] * b[k * 4 + j]
                r.push(v)
            }
        return r
    }
    // 第 d 层的透视矩阵：绕自身竖直中轴 rotateY + 均匀缩放 + 透视除法（近大远小）
    function recedeMatrix(d, w) {
        if (!root.flipMode || d <= 0)
            return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        const ang = Math.min(40, 6 * d) * Math.PI / 180
        const s = root.recedeS(d)
        const c = w / 2
        const cos = Math.cos(ang), sin = Math.sin(ang)
        const t1 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -c, 0, 0, 1]
        const sc = [s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        const ry = [cos, 0, -sin, 0, 0, 1, 0, 0, sin, 0, cos, 0, 0, 0, 0, 1]
        const t2 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, c, 0, 0, 1]
        const p = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, -1 / root.eye, 0, 0, 0, 1]
        return mul4(mul4(mul4(mul4(t1, sc), ry), t2), p)
    }
    // 非 pinned 磁贴的全部 z 平面（升序去重）；zRevision 变化时重算
    readonly property var planes: {
        void zRevision
        const zs = []
        for (let i = 0; i < tilesModel.count; i++) {
            const t = tilesModel.get(i)
            if (t.pinned !== true && zs.indexOf(t.z || 0) === -1)
                zs.push(t.z || 0)
        }
        zs.sort(function (a, b) { return a - b })
        return zs
    }
    // 落定：选中平面的磁贴整体升到最上（保持层内相对次序）
    function landFlip() {
        const target = root.planes[root.flipIndex]
        let maxZ = 0
        for (let i = 0; i < tilesModel.count; i++) {
            const t = tilesModel.get(i)
            if (t.pinned !== true && (t.z || 0) > maxZ) maxZ = t.z || 0
        }
        for (let i = 0; i < tilesModel.count; i++) {
            const t = tilesModel.get(i)
            if (t.pinned !== true && (t.z || 0) === target)
                tilesModel.setProperty(i, "z", maxZ + 1)
        }
        root.zRevision++
        root.saveTiles()
        root.flipMode = false
    }
    // 翻转模式的层卡：深灰玻璃填充 + 亮色描边，选中层描边更粗、卡体更实
    readonly property color layerCardLine: "#7fd0ff"

    // 第 idx 平面全部磁贴的包围盒（像素；zRevision 驱动重算，与 planes 同一技巧）
    function planeRect(idx) {
        void zRevision
        const z = planes[idx]
        let minCx = 1e9, minCy = 1e9, maxCx = -1, maxCy = -1
        for (let i = 0; i < tilesModel.count; i++) {
            const t = tilesModel.get(i)
            if (t.pinned === true || (t.z || 0) !== z)
                continue
            minCx = Math.min(minCx, t.cx); minCy = Math.min(minCy, t.cy)
            maxCx = Math.max(maxCx, t.cx + t.cw); maxCy = Math.max(maxCy, t.cy + t.ch)
        }
        if (maxCx < 0)
            return null
        return { x: minCx * step, y: minCy * step,
                 width: (maxCx - minCx) * step - gap, height: (maxCy - minCy) * step - gap }
    }

    function cancelFlip() { root.flipMode = false }

    // 平台服务集：注入每个磁贴插件（tiles/<type>/Tile.qml 的 api 属性）
    readonly property var api: QtObject {
        property var sys: SysInfo
        property var media: Media
        property var audio: Audio
        property var windows: Bridge
        property color fg: root.tileFg
        property string iconVariant: root.iconVariant
        property int tileRadius: root.tileRadius
        property color cardColor: root.cardColor
        function launch(cmd) { Launcher.launch(cmd) }
        function openSettings() { settingsPopup.open() }
        function updateTile(index, key, value) {
            tilesModel.setProperty(index, key, value)
            root.saveTiles()
        }
    }

    // ================= ruthis 自有风格控件 =================
    component GlassButton: Button {
        id: gb
        background: Rectangle {
            color: gb.pressed ? "#2effffff" : gb.hovered ? "#24ffffff" : "#17ffffff"
            border.width: 1
            border.color: gb.visualFocus ? "#667fd0ff" : "#2bffffff"
        }
        contentItem: Text {
            text: gb.text
            color: "#f4f7ff"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component GlassSlider: Slider {
        id: gs
        implicitWidth: 200
        implicitHeight: 26
        background: Rectangle {
            x: gs.leftPadding
            y: gs.topPadding + gs.availableHeight / 2 - height / 2
            width: gs.availableWidth
            height: 6
            color: "#1affffff"
            Rectangle {
                width: gs.visualPosition * parent.width
                height: parent.height
                color: "#7fd0ff"
            }
        }
        handle: Rectangle {
            x: gs.leftPadding + gs.visualPosition * (gs.availableWidth - width)
            y: gs.topPadding + gs.availableHeight / 2 - height / 2
            width: 16; height: 16
            color: gs.pressed ? "#cfe9ff" : "#eaf3ff"
            border.width: 1
            border.color: "#3bffffff"
        }
    }

    component GlassTextField: TextField {
        id: gtf
        color: "#f4f7ff"
        placeholderTextColor: "#669fb0d0"
        selectByMouse: true
        background: Rectangle {
            color: "#14ffffff"
            border.width: 1
            border.color: gtf.activeFocus ? "#667fd0ff" : "#2bffffff"
        }
    }

    // 添加磁贴选择器的种类按钮：kenney 图标 + 文字
    component TileKindButton: Button {
        id: tkb
        property string iconName: ""
        property string labelText: ""
        implicitWidth: 96
        implicitHeight: 72
        background: Rectangle {
            color: tkb.pressed ? "#2effffff" : tkb.hovered ? "#24ffffff" : "#17ffffff"
            radius: 6
            border.width: 1
            border.color: tkb.hovered ? "#337fd0ff" : "#2bffffff"
        }
        contentItem: Column {
            spacing: 5
            Image {
                visible: tkb.iconName !== ""
                source: tkb.iconName === "" ? ""
                        : tkb.iconName.indexOf("/") !== -1 ? "image://icons/" + tkb.iconName
                        : "image://icons/kenney/" + root.iconVariant + "/" + tkb.iconName
                width: 26; height: 26
                sourceSize: Qt.size(52, 52)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: tkb.labelText
                color: "#f4f7ff"
                font.pixelSize: 13
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // 面板通用背景
    component GlassPanel: Rectangle {
        color: "#f2141a26"
        border.width: 1
        border.color: "#33ffffff"
    }
    // =====================================================

    // ---- 背景：壁纸/渐变。桌面层模式下 ruthis 就是壁纸的渲染者 ----
    // 覆盖面模式必须全透明，露出其下的真实窗口
    Rectangle {
        anchors.fill: parent
        visible: root.wallpaperUrl === "" && !root.overlayMode
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1c2333" }
            GradientStop { position: 1.0; color: "#0c0f16" }
        }
    }

    Image {
        anchors.fill: parent
        visible: root.wallpaperUrl !== "" && !root.overlayMode
        source: root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // 拖拽时的吸附落点预览
    Rectangle {
        id: ghost
        visible: false
        color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b, 0.10)
        radius: root.tileRadius
        border.width: 2
        border.color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b, 0.7)
    }

    ListModel { id: tilesModel }

    Repeater {
        id: tilesRepeater
        model: tilesModel

        delegate: Item {
            id: tile

            // 隐藏时全部隐去（含设置磁贴），Ctrl+H 唯一入口。
            // 覆盖面模式只渲染置顶磁贴；桌面模式下置顶磁贴迁入覆盖面，主面不再渲染
            visible: !root.tilesHidden
                && (root.overlayMode ? isPinned : !(isPinned && DesktopMode))

            // Z 轴：pinned 恒在最上且不参与翻转（层级巡航不影响置顶，docs/z-axis.md 2.5）；
            // 常态渲染 z 以最低平面归一——负 z 的磁贴不许沉到壁纸（z=0 前序兄弟）之下
            readonly property bool isPinned: model.pinned === true
            readonly property int planeIdx: root.planes.indexOf(model.z || 0)
            readonly property int flipDepth: root.flipMode && !isPinned && root.planes.length > 1
                ? (planeIdx - root.flipIndex + root.planes.length) % root.planes.length
                : 0

            z: isPinned ? 1000000
               : root.flipMode ? (root.planes.length - flipDepth) * 100
               // 拖动中抬到全部平面之上（同层互斥由落点碰撞检测保证）
               : (model.z || 0) - (root.planes.length ? root.planes[0] : 0)
                 + (dragArea.pressed ? 500000 : 0)

            // 透视纵深：中心向消失点收敛（矩阵同时做缩放+rotateY，等价真实 z 后退）
            readonly property real recedeS: root.recedeS(flipDepth)
            x: root.flipMode ? root.vpX + (model.cx * root.step + width / 2 - root.vpX) * recedeS - width / 2
                             : model.cx * root.step
            y: root.flipMode ? root.vpY + (model.cy * root.step + height / 2 - root.vpY) * recedeS - height / 2
                             : model.cy * root.step
            width: model.cw * root.step - root.gap
            height: model.ch * root.step - root.gap
            transform: Matrix4x4 { matrix: root.recedeMatrix(flipDepth, tile.width) }

            Behavior on x {
                enabled: !dragArea.drag.active
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
            Behavior on y {
                enabled: !dragArea.drag.active
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            HoverHandler {
                id: tileHover
                onHoveredChanged: {
                    if (hovered)
                        root.hoveredTile = tile
                    else if (root.hoveredTile === tile)
                        root.hoveredTile = null
                }
            }

            // 翻转时非选中平面用模糊+压暗表现纵深（不是消失）
            readonly property bool blurOn: root.flipMode && flipDepth > 0 && root.planes.length > 1
            readonly property int mIndex: model.index

            // 拖拽共用状态与落格逻辑——须挂在委托根 tile 上：
            // dragArea 以 tile.beginDrag() 等限定名调用，挂在 card 里会 TypeError
            property bool moved: false
            property int dragOrigCx: 0
            property int dragOrigCy: 0

            function beginDrag() {
                moved = false
                tile.dragOrigCx = model.cx
                tile.dragOrigCy = model.cy
                root.overlayDragActive = root.overlayMode
                tile.forceActiveFocus()
                ghost.width = tile.width
                ghost.height = tile.height
                tile.updateGhost()
                ghost.visible = true
            }
            function dragProgress() {
                if (dragArea.drag.active) {
                    moved = true
                    tile.updateGhost()
                }
            }
            function dragEnded() {
                ghost.visible = false
                root.overlayDragActive = false
                const maxCx = Math.max(0, Math.floor(root.width / root.step) - model.cw)
                const maxCy = Math.max(0, Math.floor(root.height / root.step) - model.ch)
                const nx = Math.max(0, Math.min(Math.round(tile.x / root.step), maxCx))
                const ny = Math.max(0, Math.min(Math.round(tile.y / root.step), maxCy))
                // 同层互斥（docs/z-axis.md §1）：落点与同层/置顶磁贴重叠则弹回原格
                let overlap = false
                for (let i = 0; i < tilesModel.count && !overlap; i++) {
                    if (i === model.index)
                        continue
                    const t = tilesModel.get(i)
                    if (t.pinned !== true && (t.z || 0) !== (model.z || 0))
                        continue
                    if (nx < t.cx + t.cw && t.cx < nx + model.cw &&
                        ny < t.cy + t.ch && t.cy < ny + model.ch)
                        overlap = true
                }
                if (overlap) {
                    tile.x = tile.dragOrigCx * root.step
                    tile.y = tile.dragOrigCy * root.step
                    model.cx = tile.dragOrigCx
                    model.cy = tile.dragOrigCy
                } else {
                    tile.x = nx * root.step
                    tile.y = ny * root.step
                    model.cx = nx
                    model.cy = ny
                }
                root.saveTiles()
            }
            function updateGhost() {
                ghost.x = Math.round(tile.x / root.step) * root.step
                ghost.y = Math.round(tile.y / root.step) * root.step
            }
            function openTileMenu(mouse) {
                const p = tile.mapToItem(root, mouse.x, mouse.y)
                tileMenu.x = Math.max(4, Math.min(p.x, root.width - tileMenu.width - 4))
                tileMenu.y = Math.max(4, Math.min(p.y, root.height - tileMenu.height - 4))
                tileMenu.tileIndex = model.index
                tileMenu.tilePinned = model.pinned === true
                tileMenu.open()
            }

            // 卡片内容容器：模糊时整卡交给 MultiEffect 绘制，原体隐藏
            // （Qt 6.11 实测：QML 自定义 ShaderEffect 静默不渲染，须用内置 MultiEffect）
            Item {
                id: card
                anchors.fill: parent
                visible: !tile.blurOn

                // 磁贴下的假投影已按需求移除（黑幕观感）；高度感交给透视纵深

                Rectangle {
                    anchors.fill: parent
                    radius: root.tileRadius
                    color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b,
                        Math.min(1, root.tileOpacity + (dragArea.pressed ? 0.07
                                  : tileHover.hovered ? 0.05 : 0)))
                    border.width: root.glass ? 1 : 0
                    border.color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b,
                        Math.min(1, root.tileOpacity * 1.8 + (tileHover.hovered ? 0.2 : 0.12)))
                }
                // 顶部内高光：玻璃质感（设置面板可关）
                Rectangle {
                    visible: root.glass
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 1
                    height: parent.height / 2
                    radius: root.tileRadius
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#12ffffff" }
                        GradientStop { position: 1; color: "#00ffffff" }
                    }
                }

                // 拖拽区：右键按住拖动移动磁贴，右键点按弹出菜单；左键完全留给磁贴内容
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.RightButton
                    cursorShape: dragArea.pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                    drag.target: tile
                    drag.threshold: 5
                    drag.minimumX: 0
                    drag.maximumX: root.width - tile.width
                    drag.minimumY: 0
                    drag.maximumY: root.height - tile.height

                    onPressed: (mouse) => tile.beginDrag()
                    onPositionChanged: tile.dragProgress()
                    onReleased: tile.dragEnded()
                    onClicked: (mouse) => {
                        if (!tile.moved)
                            tile.openTileMenu(mouse)
                    }
                }

                // 内容宿主：磁贴即插件（tiles/<type>/manifest.json + Tile.qml），
                // 外壳只负责卡片背景/拖拽/缩放/菜单，内容全部委托给插件组件
                readonly property var cfg: ({ index: index, type: model.type,
                    text: model.text, glyph: model.glyph, label: model.label,
                    command: model.command, icon: model.icon,
                    opts: (function () {
                        try { return model.opts ? JSON.parse(model.opts) : {} }
                        catch (e) { return {} }
                    })() })

                Loader {
                    id: tileHost
                    anchors.fill: parent
                    anchors.margins: 12   // 全局内容安全区：插件内容不贴边框
                    // TileRegistry 判空：退出期 context 属性先于 QML 销毁，避免噪音报错
                    source: TileRegistry ? TileRegistry.source(model.type) : ""
                    onLoaded: {
                        tileHost.item.api = root.api
                        tileHost.item.cfg = card.cfg
                        // 声明式磁贴（manifest.source）才有 ds 属性，注入前先探测
                        if ("ds" in tileHost.item)
                            tileHost.item.ds = Sources ? Sources.forType(model.type) : null
                    }
                }

                // 置顶徽章已按需求移除：置顶磁贴迁入覆盖面，无需特殊标识

                // Super+滚轮：单磁贴沿 Z 微调（按平面边界步进）；其余滚轮放行给内容
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        if (!(wheel.modifiers & Qt.MetaModifier) || !AppWindow.active
                            || model.pinned === true || root.flipMode) {
                            wheel.accepted = false
                            return
                        }
                        root.nudgeTileZ(tile, wheel.angleDelta.y > 0)
                        wheel.accepted = true
                    }
                }
            } // card

            // 模糊管线：翻转时非选中平面由 MultiEffect 绘制模糊纹理表现纵深。
            // 远层轻模糊+压暗（保持可辨识），选中层=交互层保持锐利全亮
            MultiEffect {
                anchors.fill: card
                source: card
                visible: tile.blurOn
                blurEnabled: tile.blurOn
                blur: Math.min(1, 0.04 + 0.05 * tile.flipDepth)
                blurMax: 16
                brightness: 1 - Math.min(0.35, 0.06 * tile.flipDepth)
                autoPaddingEnabled: true
            }

            // 翻转时点按模糊磁贴 = 选中其所在平面（Win7 Flip 语义：点谁选谁）
            MouseArea {
                anchors.fill: parent
                enabled: root.flipMode && tile.blurOn
                visible: enabled
                onClicked: root.flipIndex = tile.planeIdx
            }
        }
    }

    // ---- 翻转模式：每层一张整体透明卡，包住该层全部磁贴（层色描边，点卡选层）----
    // 卡 z 取"本层磁贴 z - 1"：垫在自己层磁贴之下、更深内容之上，玻璃片式的层语言
    Repeater {
        model: root.flipMode ? root.planes.length : 0

        delegate: Rectangle {
            id: layerCard
            required property int index
            readonly property int depth: (index - root.flipIndex + root.planes.length) % root.planes.length
            readonly property bool selected: index === root.flipIndex
            readonly property var box: root.planeRect(index)

            readonly property real cardS: root.recedeS(depth)
            x: box ? root.vpX + (box.x + box.width / 2 - root.vpX) * cardS - box.width / 2 - 8 : 0
            y: box ? root.vpY + (box.y + box.height / 2 - root.vpY) * cardS - box.height / 2 - 8 : 0
            width: box ? box.width + 16 : 0
            height: box ? box.height + 16 : 0
            visible: box !== null
            z: (root.planes.length - depth) * 100 - 1
            radius: root.tileRadius + 8
            color: Qt.rgba(0.07, 0.09, 0.13, selected ? 0.60 : 0.45)
            border.width: selected ? 3 : 2
            border.color: layerCardLine
            opacity: selected ? 1 : 0.75
            transform: Matrix4x4 { matrix: root.recedeMatrix(depth, layerCard.width) }

            MouseArea {
                anchors.fill: parent
                onClicked: root.flipIndex = layerCard.index
            }
        }
    }

    // ---- 磁贴属性菜单（右键）----
    Popup {
        id: tileMenu
        width: 150
        height: menuCol.implicitHeight + 2 * padding
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property int tileIndex: -1
        property bool tilePinned: false

        background: GlassPanel {}

        contentItem: Column {
            id: menuCol
            spacing: 6
            GlassButton {
                text: "属性…"
                width: parent.width
                onClicked: {
                    tileProps.openFor(tileMenu.tileIndex)
                    tileMenu.close()
                }
            }
            GlassButton {
                id: pinBtn
                text: (tileMenu.tilePinned ? "✓ " : "") + "永久置顶"
                opacity: tileMenu.tilePinned ? 1 : 0.75
                width: parent.width
                onClicked: {
                    const i = tileMenu.tileIndex
                    if (i < 0)
                        return
                    tileMenu.tilePinned = !tileMenu.tilePinned
                    tilesModel.setProperty(i, "pinned", tileMenu.tilePinned)
                    root.zRevision++
                    root.saveTiles()
                }
            }
            GlassButton {
                text: "删除磁贴"
                width: parent.width
                onClicked: {
                    tilesModel.remove(tileMenu.tileIndex)
                    root.saveTiles()
                    tileMenu.close()
                }
            }
        }
    }

    // ---- 磁贴属性面板 ----
    Popup {
        id: tileProps
        anchors.centerIn: parent
        width: 440
        height: propsCol.implicitHeight + 2 * padding
        padding: 24
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property int tileIndex: -1
        property bool isApp: false
        property bool isNote: false

        property var currentOpts: {}
        property var kindProps: []
        property bool pinOn: false

        function openFor(index) {
            tileIndex = index
            const t = tilesModel.get(index)
            isApp = t.type === "app"
            isNote = t.type === "note"
            widthField.value = t.cw
            heightField.value = t.ch
            nameField.text = t.label
            commandField.text = t.command
            iconField.text = t.icon
            pinOn = t.pinned === true
            try { currentOpts = t.opts ? JSON.parse(t.opts) : {} } catch (e) { currentOpts = {} }
            kindProps = TileRegistry.kind(t.type).props || []
            open()
        }

        function setOpt(key, value) {
            if (tileIndex < 0)
                return
            const o = Object.assign({}, currentOpts)
            o[key] = value
            currentOpts = o
            tilesModel.setProperty(tileIndex, "opts", JSON.stringify(o))
            root.saveTiles()
        }

        function commitText() {
            if (tileIndex < 0)
                return
            tilesModel.setProperty(tileIndex, "label", nameField.text)
            tilesModel.setProperty(tileIndex, "command", commandField.text)
            tilesModel.setProperty(tileIndex, "icon", iconField.text)
            root.saveTiles()
        }

        background: GlassPanel {}

        contentItem: Column {
            id: propsCol
            spacing: 12

            Text { text: "磁贴属性"; color: "#f4f7ff"; font.pixelSize: 18; font.bold: true }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "宽（格）"; color: "#c3cfe6"; width: 100; anchors.verticalCenter: parent.verticalCenter }
                GlassSlider {
                    id: widthField
                    width: parent.width - 170
                    anchors.verticalCenter: parent.verticalCenter
                    from: 1; to: 16; stepSize: 1
                    onMoved: {
                        if (tileProps.tileIndex >= 0) {
                            tilesModel.setProperty(tileProps.tileIndex, "cw", value)
                            root.saveTiles()
                        }
                    }
                }
                Text { text: widthField.value + " 格"; color: "#9fb0d0"; width: 50; anchors.verticalCenter: parent.verticalCenter }
            }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "高（格）"; color: "#c3cfe6"; width: 100; anchors.verticalCenter: parent.verticalCenter }
                GlassSlider {
                    id: heightField
                    width: parent.width - 170
                    anchors.verticalCenter: parent.verticalCenter
                    from: 1; to: 10; stepSize: 1
                    onMoved: {
                        if (tileProps.tileIndex >= 0) {
                            tilesModel.setProperty(tileProps.tileIndex, "ch", value)
                            root.saveTiles()
                        }
                    }
                }
                Text { text: heightField.value + " 格"; color: "#9fb0d0"; width: 50; anchors.verticalCenter: parent.verticalCenter }
            }

            GlassTextField {
                id: nameField
                visible: tileProps.isApp
                width: parent.width
                placeholderText: "名称"
                onEditingFinished: tileProps.commitText()
            }

            GlassTextField {
                id: commandField
                visible: tileProps.isApp
                width: parent.width
                placeholderText: "启动命令（如 konsole）"
                onEditingFinished: tileProps.commitText()
            }

            Row {
                spacing: 8
                width: parent.width
                GlassTextField {
                    id: iconField
                    visible: tileProps.isApp || tileProps.isNote
                    width: parent.width - 90
                    placeholderText: "图标主题名，或图片路径（如 /home/x/i.png）"
                    onEditingFinished: tileProps.commitText()
                }
                GlassButton {
                    text: "选图…"
                    width: 82
                    visible: tileProps.isApp || tileProps.isNote
                    onClicked: Launcher.pickIconFile()
                }
            }

            // 永久置顶（docs/z-axis.md 2.5）
            Row {
                spacing: 8
                GlassButton {
                    text: (tileProps.pinOn ? "✓ " : "") + "永久置顶"
                    opacity: tileProps.pinOn ? 1 : 0.55
                    onClicked: {
                        if (tileProps.tileIndex < 0)
                            return
                        tileProps.pinOn = !tileProps.pinOn
                        tilesModel.setProperty(tileProps.tileIndex, "pinned", tileProps.pinOn)
                        root.zRevision++
                        root.saveTiles()
                    }
                }
            }

            // 组件私有设置：由 manifest.props 声明，自动生成编辑器
            Repeater {
                model: tileProps.kindProps
                delegate: Column {
                    id: propEntry
                    required property var modelData
                    width: propsCol.width
                    spacing: 6

                    Text { text: modelData.name; color: "#c3cfe6"; font.pixelSize: 13 }

                    GlassTextField {
                        visible: propEntry.modelData.type === "text"
                        width: parent.width
                        placeholderText: propEntry.modelData.default || ""
                        text: {
                            const v = tileProps.currentOpts[propEntry.modelData.key]
                            return v !== undefined ? String(v) : ""
                        }
                        onEditingFinished: tileProps.setOpt(propEntry.modelData.key, text)
                    }

                    Row {
                        visible: propEntry.modelData.type === "select"
                        spacing: 8
                        Repeater {
                            model: propEntry.modelData.options || []
                            delegate: GlassButton {
                                required property var modelData
                                text: (tileProps.currentOpts[propEntry.modelData.key] === modelData
                                       ? "✓ " : "") + modelData
                                opacity: tileProps.currentOpts[propEntry.modelData.key] === modelData ? 1 : 0.55
                                onClicked: tileProps.setOpt(propEntry.modelData.key, modelData)
                            }
                        }
                    }

                    Row {
                        visible: propEntry.modelData.type === "toggle"
                        GlassButton {
                            property bool on: {
                                const v = tileProps.currentOpts[propEntry.modelData.key]
                                return v !== undefined ? (v === "开" || v === true)
                                                       : propEntry.modelData.default === "开"
                            }
                            text: (on ? "✓ " : "") + propEntry.modelData.name
                            opacity: on ? 1 : 0.55
                            onClicked: tileProps.setOpt(propEntry.modelData.key, on ? "关" : "开")
                        }
                    }
                }
            }

            GlassButton {
                text: "从应用列表选择…"
                visible: tileProps.isApp
                width: parent.width
                onClicked: {
                    appPicker.assignIndex = tileProps.tileIndex
                    appPicker.open()
                }
            }

            GlassButton {
                text: "删除磁贴"
                width: parent.width
                onClicked: {
                    tilesModel.remove(tileProps.tileIndex)
                    root.saveTiles()
                    tileProps.close()
                }
            }
        }
    }

    // ---- 添加磁贴选择器（Ctrl+N）----
    Popup {
        id: addPopup
        anchors.centerIn: parent
        width: 360
        height: addCol.implicitHeight + 2 * padding
        padding: 24
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: GlassPanel {}

        contentItem: Column {
            id: addCol
            spacing: 12

            Text { text: "添加磁贴"; color: "#f4f7ff"; font.pixelSize: 18; font.bold: true }

            // 分组来自 TileRegistry 扫描的 manifest，新增磁贴类型零行主文件改动
            Repeater {
                model: {
                    const groups = []
                    const kinds = TileRegistry ? TileRegistry.kinds() : []
                    for (let i = 0; i < kinds.length; i++) {
                        const k = kinds[i]
                        let g = null
                        for (let j = 0; j < groups.length; j++) {
                            if (groups[j].cat === k.category) { g = groups[j]; break }
                        }
                        if (!g) {
                            g = { cat: k.category, kinds: [] }
                            groups.push(g)
                        }
                        g.kinds.push(k)
                    }
                    return groups
                }

                delegate: Column {
                    required property var modelData
                    spacing: 8

                    Text {
                        text: modelData.cat
                        color: "#9fb0d0"; font.pixelSize: 12; opacity: 0.9
                    }
                    Flow {
                        spacing: 8
                        width: addCol.width
                        Repeater {
                            model: modelData.kinds
                            delegate: TileKindButton {
                                required property var modelData
                                iconName: modelData.icon
                                labelText: modelData.name
                                onClicked: root.addTile(modelData.type)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- 应用选择列表 ----
    Popup {
        id: appPicker
        anchors.centerIn: parent
        width: 470
        height: 540
        padding: 24
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        // -1 = 选择后新建磁贴；>=0 = 替换该磁贴的应用属性
        property int assignIndex: -1
        property var allItems: []
        property var items: []

        function refreshFilter() {
            const q = appSearch.text.toLowerCase()
            items = allItems.filter(function (a) {
                return q === "" || a.name.toLowerCase().indexOf(q) !== -1
                    || a.exec.toLowerCase().indexOf(q) !== -1
            })
        }

        function choose(app) {
            if (assignIndex >= 0) {
                tilesModel.setProperty(assignIndex, "label", app.name)
                tilesModel.setProperty(assignIndex, "command", app.exec)
                tilesModel.setProperty(assignIndex, "icon", app.icon)
                root.saveTiles()
                tileProps.openFor(assignIndex)   // 刷新属性面板字段
            } else {
                const tz = topZ()
                const spot = findFreeSpot(1, 1, tz)
                if (!spot)
                    return
                appendTile({ type: "app", cx: spot.cx, cy: spot.cy, cw: 1, ch: 1, z: tz,
                    text: "", glyph: "", label: app.name, command: app.exec, icon: app.icon })
                root.saveTiles()
            }
            close()
        }

        onOpened: {
            if (allItems.length === 0)
                allItems = Apps.apps()
            refreshFilter()
        }

        background: GlassPanel {}

        contentItem: Column {
            id: appCol
            spacing: 12

            Text {
                text: appPicker.assignIndex >= 0 ? "选择应用（将替换属性）" : "选择应用"
                color: "#f4f7ff"; font.pixelSize: 18; font.bold: true
            }

            GlassTextField {
                id: appSearch
                width: parent.width
                placeholderText: "搜索应用…"
                onTextChanged: appPicker.refreshFilter()
            }

            ListView {
                id: appList
                width: parent.width
                height: 330
                clip: true
                spacing: 4
                model: appPicker.items

                delegate: Item {
                    id: appRow
                    width: appList.width
                    height: 44

                    required property var modelData

                    Rectangle {
                        anchors.fill: parent
                        color: appMa.containsMouse ? "#1affffff" : "transparent"
                        border.width: 1
                        border.color: appMa.containsMouse ? "#337fd0ff" : "transparent"
                    }
                    Image {
                        id: appIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32
                        visible: modelData.icon !== ""
                        source: modelData.icon !== "" ? "image://icons/" + modelData.icon : ""
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        anchors.left: appIcon.visible ? appIcon.right : parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - appIcon.width - 130
                        text: modelData.name
                        color: "#f4f7ff"
                        font.pixelSize: 15
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                        text: modelData.exec
                        color: "#669fb0d0"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                    }
                    MouseArea {
                        id: appMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appPicker.choose(appRow.modelData)
                    }
                }
            }
        }
    }

    // ---- 设置面板 ----
    Popup {
        id: settingsPopup
        anchors.centerIn: parent
        width: 480
        height: contentColumn.implicitHeight + 2 * padding
        padding: 24
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: GlassPanel {}

        contentItem: Column {
            id: contentColumn
            spacing: 14

            Text { text: "设置"; color: "#f4f7ff"; font.pixelSize: 22; font.bold: true }

            Text { text: "磁贴外观"; color: "#9fb0d0"; font.pixelSize: 13 }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "卡片颜色"; color: "#c3cfe6"; width: 100; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: ["#ffffff", "#1b1e26", "#3daee9", "#9b59b6", "#e67e22", "#27ae60"]
                        delegate: Rectangle {
                            width: 28; height: 28
                            color: modelData
                            border.width: root.cardColor === modelData ? 3 : 1
                            border.color: root.cardColor === modelData ? "#7fd0ff" : "#2bffffff"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.cardColor = modelData; root.saveSettings() }
                            }
                        }
                    }
                    GlassButton {
                        text: "自定义…"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: colorDialog.open()
                    }
                }
            }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "卡片透明度"; color: "#c3cfe6"; width: 100; anchors.verticalCenter: parent.verticalCenter }
                GlassSlider {
                    width: parent.width - 190
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0; to: 1; stepSize: 0.01
                    value: root.tileOpacity
                    onMoved: { root.tileOpacity = value; root.saveSettings() }
                }
                Text { text: Math.round(root.tileOpacity * 100) + " %"; color: "#9fb0d0"; width: 60; anchors.verticalCenter: parent.verticalCenter }
            }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "卡片圆角"; color: "#c3cfe6"; width: 100; anchors.verticalCenter: parent.verticalCenter }
                GlassSlider {
                    width: parent.width - 190
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0; to: 48; stepSize: 1
                    value: root.tileRadius
                    onMoved: { root.tileRadius = value; root.saveSettings() }
                }
                Text { text: root.tileRadius + " px"; color: "#9fb0d0"; width: 60; anchors.verticalCenter: parent.verticalCenter }
            }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "文字/图标明暗"; color: "#c3cfe6"; width: 110; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [
                            { v: "auto", n: "自动" },
                            { v: "light", n: "浅色" },
                            { v: "dark", n: "深色" }
                        ]
                        delegate: GlassButton {
                            required property var modelData
                            text: (root.fgMode === modelData.v ? "✓ " : "") + modelData.n
                            width: 76
                            opacity: root.fgMode === modelData.v ? 1 : 0.55
                            onClicked: { root.fgMode = modelData.v; root.saveSettings() }
                        }
                    }
                }
            }

            Row {
                spacing: 12
                GlassButton {
                    text: (root.glass ? "✓ " : "") + "玻璃质感"
                    opacity: root.glass ? 1 : 0.55
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: { root.glass = !root.glass; root.saveSettings() }
                }
                Text { text: "顶部高光与卡片描边"; color: "#9fb0d0"; anchors.verticalCenter: parent.verticalCenter }
            }

            Row {
                spacing: 12
                width: parent.width
                Text { text: "磁贴间距"; color: "#c3cfe6"; width: 100; anchors.verticalCenter: parent.verticalCenter }
                GlassSlider {
                    width: parent.width - 190
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0; to: 40; stepSize: 1
                    value: root.gap
                    onMoved: { root.gap = value; root.saveSettings() }
                }
                Text { text: root.gap + " px"; color: "#9fb0d0"; width: 60; anchors.verticalCenter: parent.verticalCenter }
            }

            Text {
                text: "壁纸（演示模式背景；桌面层模式使用系统壁纸）"
                color: "#9fb0d0"; font.pixelSize: 13
                width: parent.width; wrapMode: Text.Wrap
            }

            Row {
                spacing: 8
                width: parent.width
                GlassTextField {
                    id: wallField
                    width: parent.width - 160
                    placeholderText: "选择或粘贴图片路径"
                    onEditingFinished: {
                        root.wallpaperUrl = text ? "file://" + text : ""
                        root.saveSettings()
                    }
                }
                GlassButton { text: "浏览"; onClicked: Launcher.pickImageFile() }
                GlassButton {
                    text: "清除"
                    onClicked: {
                        root.wallpaperUrl = ""
                        root.saveSettings()
                        wallField.clear()
                    }
                }
            }

            Item { width: 1; height: 4 }

            Text {
                text: "Ctrl+N 添加磁贴 · 右键拖动磁贴 · 悬停+Super+滚轮或 [ ] 调层次 · Super+Tab 翻图层 · Ctrl+H 隐藏/显示"
                color: "#669fb0d0"; font.pixelSize: 12
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            GlassButton { text: "完成"; onClicked: settingsPopup.close(); anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    Connections {
        target: Launcher
        function onFilePicked(path) {
            root.wallpaperUrl = "file://" + path
            root.saveSettings()
        }
        function onIconPicked(path) {
            iconField.text = path
            tileProps.commitText()
        }
    }

    ColorDialog {
        id: colorDialog
        title: "自定义卡片颜色"
        selectedColor: root.cardColor
        onAccepted: { root.cardColor = selectedColor; root.saveSettings() }
    }

    Shortcut {
        sequence: "Ctrl+H"
        onActivated: { root.tilesHidden = !root.tilesHidden; root.saveSettings() }
    }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: addPopup.open()
    }

    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (root.flipMode) { root.cancelFlip(); return }
            if (addPopup.opened) addPopup.close()
            else if (tileProps.opened) tileProps.close()
            else if (tileMenu.opened) tileMenu.close()
            else if (settingsPopup.opened) settingsPopup.close()
            else root.forceActiveFocus()   // 结束便签输入
        }
    }

    Shortcut {
        sequence: "Ctrl+Q"
        onActivated: Qt.quit()
    }

    // ---- Z 轴：Super+滚轮 / Super+[ ] 微调悬停磁贴层次（按平面边界步进）----
    // ">" "]" 拉近提升，"<" "[" 推远下沉；须先悬停磁贴且桌面持有焦点（2.4）
    function nudgeTileZ(tileItem, up) {
        if (!tileItem || root.flipMode || !AppWindow.active)
            return
        const i = tileItem.mIndex
        const t = tilesModel.get(i)
        if (t.pinned === true)
            return
        const cur = t.z || 0
        let nz
        if (up) {
            const next = root.planes.find(function (v) { return v > cur })
            nz = next !== undefined ? next : cur + 1
        } else {
            const prev = root.planes.slice().reverse().find(function (v) { return v < cur })
            nz = prev !== undefined ? prev : cur - 1
        }
        tilesModel.setProperty(i, "z", nz)
        root.zRevision++
        root.saveTiles()
    }
    Shortcut {
        sequence: "Meta+]"
        enabled: root.hoveredTile !== null && !root.flipMode && AppWindow.active
        onActivated: root.nudgeTileZ(root.hoveredTile, true)
    }
    Shortcut {
        sequence: "Meta+["
        enabled: root.hoveredTile !== null && !root.flipMode && AppWindow.active
        onActivated: root.nudgeTileZ(root.hoveredTile, false)
    }

    // ---- Z 轴：Super+Tab 图层翻转切换器（docs/z-axis.md 2.2）----
    Shortcut {
        sequence: "Meta+Tab"
        enabled: !root.flipMode && root.planes.length > 1
        onActivated: {
            root.flipMode = true
            root.flipIndex = root.planes.length - 1
            flipOverlay.forceActiveFocus()
        }
    }
    Shortcut {
        sequence: "Tab"
        enabled: root.flipMode
        onActivated: root.flipIndex = (root.flipIndex + 1) % root.planes.length
    }
    Shortcut {
        sequence: "Meta+Shift+Tab"
        enabled: root.flipMode
        onActivated: root.flipIndex = (root.flipIndex - 1 + root.planes.length) % root.planes.length
    }

    // 翻转模式的模态覆盖层：暗化、捕获点击取消、监听 Super 松开落定
    Rectangle {
        id: flipOverlay
        anchors.fill: parent
        visible: root.flipMode
        onVisibleChanged: if (visible)
            Store.log("[flip] planes=" + root.planes + " flipIndex=" + root.flipIndex)
        color: "#55000000"
        focus: root.flipMode
        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R)
                root.landFlip()
        }
        // Super 仍按住时 Tab 事件带 Meta 修饰，Shortcut("Tab") 匹配不上——循环必须在此按键名处理
        Keys.onPressed: (event) => {
            if (event.key !== Qt.Key_Tab)
                return
            const dir = (event.modifiers & Qt.ShiftModifier) !== 0 ? -1 : 1
            root.flipIndex = (root.flipIndex + dir + root.planes.length) % root.planes.length
            event.accepted = true
        }
        MouseArea { anchors.fill: parent; onClicked: root.cancelFlip() }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            text: "图层 " + (root.flipIndex + 1) + " / " + root.planes.length
                  + "  ·  同卡同层  ·  Tab 切换  ·  松开 Super 落定  ·  Esc 取消"
            color: "#f4f7ff"
            font.pixelSize: 14
            style: Text.Outline
            styleColor: "#80000000"
        }
    }

    function defaultTiles() {
        return [
            { type: "clock", cx: 1, cy: 1, cw: 3, ch: 2, text: "", glyph: "", label: "", command: "", icon: "" },
            { type: "sys", cx: 4, cy: 1, cw: 2, ch: 2, text: "", glyph: "", label: "", command: "", icon: "" },
            { type: "note", cx: 4, cy: 2, cw: 2, ch: 2,
              text: "☐ 补完系统升级\n☐ 验证新登录器\n☐ 剪第一条视频", glyph: "", label: "", command: "", icon: "" },
            { type: "app", cx: 1, cy: 3, cw: 1, ch: 1, glyph: "", label: "终端", command: "konsole", icon: "utilities-terminal" },
            { type: "app", cx: 2, cy: 3, cw: 1, ch: 1, glyph: "", label: "浏览器", command: "firefox", icon: "firefox" },
            { type: "app", cx: 3, cy: 3, cw: 1, ch: 1, glyph: "", label: "文件", command: "dolphin", icon: "system-file-manager" },
            { type: "settings", cx: 4, cy: 4, cw: 1, ch: 1, glyph: "", label: "设置", command: "", icon: "" }
        ]
    }

    // 统一追加：补齐 opts/z/pinned 角色（ListModel 角色集合由首条元素决定，历史数据必须归一化）
    function appendTile(t) {
        if (t.opts === undefined) t.opts = ""
        if (t.z === undefined) t.z = 0
        if (t.pinned === undefined) t.pinned = false
        tilesModel.append(t)
    }

    function addTile(type) {
        // 应用磁贴走应用选择列表，免手打命令/图标/名称
        if (type === "app") {
            addPopup.close()
            appPicker.assignIndex = -1
            appPicker.open()
            return
        }
        const k = TileRegistry.kind(type)
        if (!k || k.w === undefined)
            return
        const tz = topZ()
        const spot = findFreeSpot(k.w, k.h, tz)
        if (!spot)
            return
        appendTile({ type: type, cx: spot.cx, cy: spot.cy, cw: k.w, ch: k.h, z: tz,
            text: type === "note" ? "新便签" : "", glyph: "", label: k.name, command: "", icon: "" })
        root.saveTiles()
        addPopup.close()
    }

    // 当前最上层非 pinned 磁贴的 z——新磁贴落位于此平面（docs/z-axis.md §3/§5.5）
    function topZ() {
        let mz = 0
        for (let i = 0; i < tilesModel.count; i++) {
            const t = tilesModel.get(i)
            if (t.pinned !== true && (t.z || 0) > mz)
                mz = t.z || 0
        }
        return mz
    }

    // 在网格上为 w×h 磁贴找落点。同层互斥（docs/z-axis.md §3/§5.3）：
    // 只统计 targetZ 同带与 pinned 的占用，跨层重叠合法
    function findFreeSpot(w, h, targetZ) {
        const cols = Math.floor(root.width / root.step)
        const rows = Math.floor(root.height / root.step)
        for (let cy = 0; cy <= rows - h; cy++) {
            for (let cx = 0; cx <= cols - w; cx++) {
                let free = true
                for (let i = 0; i < tilesModel.count; i++) {
                    const t = tilesModel.get(i)
                    if (t.pinned !== true && (t.z || 0) !== targetZ)
                        continue
                    if (cx < t.cx + t.cw && t.cx < cx + w &&
                        cy < t.cy + t.ch && t.cy < cy + h) {
                        free = false
                        break
                    }
                }
                if (free)
                    return { cx: cx, cy: cy }
            }
        }
        return null
    }

    function saveTiles() {
        const arr = []
        for (let i = 0; i < tilesModel.count; i++)
            arr.push(tilesModel.get(i))
        Store.save(JSON.stringify({ tiles: arr }))
    }

    function saveSettings() {
        Store.saveSettings(JSON.stringify({
            tileOpacity: root.tileOpacity,
            tileRadius: root.tileRadius,
            gap: root.gap,
            cardColor: root.cardColor.toString(),
            wallpaperUrl: root.wallpaperUrl,
            tilesHidden: root.tilesHidden,
            fgMode: root.fgMode
        }))
    }

    // 调试辅助：--test-menu 合成事件验证右键菜单整条链路
    function debugTileCenter() {
        const it = tilesRepeater.itemAt(0)
        if (!it)
            return []
        const p = it.mapToItem(root, it.width / 2, it.height / 2)
        return [p.x, p.y]
    }
    function debugPinBtnCenter() {
        const p = pinBtn.mapToItem(root, pinBtn.width / 2, pinBtn.height / 2)
        return [p.x, p.y]
    }

    function applySettings(s) {
        if (typeof s.tileOpacity === "number") root.tileOpacity = s.tileOpacity
        if (typeof s.tileRadius === "number") root.tileRadius = s.tileRadius
        if (typeof s.gap === "number") root.gap = s.gap
        if (typeof s.cardColor === "string") root.cardColor = s.cardColor
        if (typeof s.wallpaperUrl === "string") root.wallpaperUrl = s.wallpaperUrl
        if (typeof s.tilesHidden === "boolean") root.tilesHidden = s.tilesHidden
        if (typeof s.fgMode === "string") root.fgMode = s.fgMode
        if (typeof s.glass === "boolean") root.glass = s.glass
    }

    // 覆盖面实例据主面保存动作重载（含输入 mask 跟随）
    function reloadTiles() {
        tilesModel.clear()
        let data = {}
        try { data = JSON.parse(Store.load()) } catch (e) { data = {} }
        let defs = (data.tiles && data.tiles.length > 0) ? data.tiles : defaultTiles()
        // 旧版 tiles.json 里没有设置磁贴，补一枚
        if (!defs.some(function (t) { return t.type === "settings" }))
            defs.push({ type: "settings", cx: 4, cy: 4, cw: 1, ch: 1, glyph: "", label: "设置", command: "", icon: "" })
        // 补齐 icon 角色；已知命令自动配图标主题名
        const iconMap = { konsole: "utilities-terminal", firefox: "firefox", dolphin: "system-file-manager" }
        defs.forEach(function (t) {
            t.icon = t.icon || (t.type === "app" ? (iconMap[t.command] || "") : "")
            appendTile(t)
        })

        // 旧布局里没有后台磁贴的，自动补一块（覆盖面实例不补：只渲染置顶）
        if (!root.overlayMode && !defs.some(function (t) { return t.type === "tasks" })) {
            const tz = topZ()
            const spot = findFreeSpot(2, 3, tz)
            if (spot)
                appendTile({ type: "tasks", cx: spot.cx, cy: spot.cy, cw: 2, ch: 3, z: tz,
                    text: "", glyph: "", label: "", command: "", icon: "" })
        }
        syncOverlayMask()
    }

    function syncOverlayMask() {        // 覆盖面窗口输入区 = 置顶磁贴矩形并集；其余区域点击穿透到真实窗口。
        // 拖拽/弹窗期间放开为全屏（mask 截断拖拽与菜单外点击）
        if (!root.overlayMode)
            return
        const rects = []
        if (root.overlayDragActive || tileMenu.opened || tileProps.opened
                || addPopup.opened || settingsPopup.opened) {
            rects.push({ x: 0, y: 0, w: root.width, h: root.height })
        } else {
            for (let i = 0; i < tilesModel.count; i++) {
                const t = tilesModel.get(i)
                if (t.pinned !== true)
                    continue
                rects.push({ x: t.cx * root.step, y: t.cy * root.step,
                             w: t.cw * root.step - root.gap, h: t.ch * root.step - root.gap })
            }
        }
        Store.applyMask(OverlayWindow, JSON.stringify(rects))
    }

    Component.onCompleted: {
        let data = {}, s = {}
        try { data = JSON.parse(Store.load()) } catch (e) { data = {} }
        try { s = JSON.parse(Store.loadSettings()) } catch (e) { s = {} }
        applySettings(s)
        reloadTiles()

        if (!root.overlayMode)
            Bridge.setup()

        // 调试旗标只在主面生效（覆盖面无键盘焦点且不应弹面板）
        if (!root.overlayMode) {
            if (Qt.application.arguments.indexOf("--open-settings") !== -1) {
                settingsPopup.open()
                Store.grabWindow(AppWindow)
            }
            if (Qt.application.arguments.indexOf("--open-add") !== -1) {
                addPopup.open()
                Store.grabWindow(AppWindow)
            }
            if (Qt.application.arguments.indexOf("--open-flip") !== -1 && root.planes.length > 1) {
                root.flipMode = true
                root.flipIndex = root.planes.length - 1
                flipOverlay.forceActiveFocus()
                Store.grabWindow(AppWindow)
            }
        }
    }
    onWidthChanged: syncOverlayMask()
    onHeightChanged: syncOverlayMask()

    // 覆盖面跟随主面的保存动作刷新
    Connections {
        target: root.overlayMode ? Store : null
        function onTilesChanged() { root.reloadTiles() }
        function onSettingsChanged() {
            let s = {}
            try { s = JSON.parse(Store.loadSettings()) } catch (e) { s = {} }
            root.applySettings(s)
        }
    }
}
