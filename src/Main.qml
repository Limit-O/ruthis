import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

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
    // 拖动磁贴的修饰键：ctrl/alt/shift（设置面板可调），按住拖动 + 光标抓手
    property string dragMod: "ctrl"
    readonly property int dragModifiers: dragMod === "alt" ? Qt.AltModifier
        : dragMod === "shift" ? Qt.ShiftModifier : Qt.ControlModifier
    readonly property color tileFg: fgMode === "light" ? "#f4f7ff"
        : fgMode === "dark" ? "#151a22"
        : (cardEffectiveLum() > 0.5 ? "#151a22" : "#f4f7ff")
    // kenney 图标黑白两版与文字同步（暗底白图标，亮底黑图标）
    readonly property string iconVariant: fgMode === "light" ? "White"
        : fgMode === "dark" ? "Black"
        : (cardEffectiveLum() > 0.5 ? "Black" : "White")

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
        property int dragModifiers: root.dragModifiers
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
    Rectangle {
        anchors.fill: parent
        visible: root.wallpaperUrl === ""
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1c2333" }
            GradientStop { position: 1.0; color: "#0c0f16" }
        }
    }

    Image {
        anchors.fill: parent
        visible: root.wallpaperUrl !== ""
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
        model: tilesModel

        delegate: Item {
            id: tile

            // 隐藏时全部隐去（含设置磁贴），Ctrl+H 唯一入口
            visible: !root.tilesHidden

            x: model.cx * root.step
            y: model.cy * root.step
            width: model.cw * root.step - root.gap
            height: model.ch * root.step - root.gap

            Behavior on x {
                enabled: !dragArea.drag.active
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
            Behavior on y {
                enabled: !dragArea.drag.active
                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.tileRadius
                color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b,
                    Math.min(1, root.tileOpacity + ((modDrag.pressed || stripDrag.pressed) ? 0.07 : 0)))
                border.width: 1
                border.color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b,
                    Math.min(1, root.tileOpacity * 1.8 + 0.12))
            }

            // 拖拽共用状态与落格逻辑
            property bool moved: false

            function beginDrag() {
                moved = false
                tile.forceActiveFocus()
                ghost.width = tile.width
                ghost.height = tile.height
                tile.updateGhost()
                ghost.visible = true
            }
            function dragProgress() {
                if (modDrag.drag.active || stripDrag.drag.active) {
                    moved = true
                    tile.updateGhost()
                }
            }
            function dragEnded() {
                ghost.visible = false
                const maxCx = Math.max(0, Math.floor(root.width / root.step) - model.cw)
                const maxCy = Math.max(0, Math.floor(root.height / root.step) - model.ch)
                const nx = Math.max(0, Math.min(Math.round(tile.x / root.step), maxCx))
                const ny = Math.max(0, Math.min(Math.round(tile.y / root.step), maxCy))
                tile.x = nx * root.step
                tile.y = ny * root.step
                model.cx = nx
                model.cy = ny
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
                tileMenu.open()
            }

            // 修饰键拖拽区：铺满磁贴、压在内容之下——按住拖动快捷键可从任意位置拖动，
            // 其余点击全部由上方内容自行处理，不做任何透传
            MouseArea {
                id: modDrag
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: modDrag.pressed ? Qt.ClosedHandCursor
                             : modHover.hovered ? Qt.OpenHandCursor : Qt.ArrowCursor
                drag.target: tile
                drag.threshold: 5
                drag.minimumX: 0
                drag.maximumX: root.width - tile.width
                drag.minimumY: 0
                drag.maximumY: root.height - tile.height

                onPressed: (mouse) => {
                    if (mouse.button === Qt.LeftButton && !(mouse.modifiers & root.dragModifiers)) {
                        mouse.accepted = false
                        return
                    }
                    tile.beginDrag()
                }
                onPositionChanged: tile.dragProgress()
                onReleased: tile.dragEnded()
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        tile.openTileMenu(mouse)
                }

                HoverHandler {
                    id: modHover
                    acceptedModifiers: root.dragModifiers
                    cursorShape: Qt.OpenHandCursor
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
                source: TileRegistry.source(model.type)
                onLoaded: tileHost.item.api = root.api
            }
            Binding {
                target: tileHost.item
                property: "cfg"
                value: cfg
                when: tileHost.status === Loader.Ready
            }
            // 声明式磁贴（manifest.source）才有 ds 属性，注入前先探测
            Binding {
                target: tileHost.item
                property: "ds"
                value: Sources.forType(model.type)
                when: tileHost.status === Loader.Ready && tileHost.item !== null
                      && ("ds" in tileHost.item)
            }

            // 顶部拖拽条：无需修饰键即可拖动/右键菜单，交互内容从它下方布局
            MouseArea {
                id: stripDrag
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                height: 36
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: stripDrag.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
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
                    if (mouse.button === Qt.RightButton)
                        tile.openTileMenu(mouse)
                }
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
                    const kinds = TileRegistry.kinds()
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
                const spot = findFreeSpot(1, 1)
                if (!spot)
                    return
                appendTile({ type: "app", cx: spot.cx, cy: spot.cy, cw: 1, ch: 1,
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
                width: parent.width
                Text { text: "拖动快捷键"; color: "#c3cfe6"; width: 110; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [
                            { v: "ctrl", n: "Ctrl" },
                            { v: "alt", n: "Alt" },
                            { v: "shift", n: "Shift" }
                        ]
                        delegate: GlassButton {
                            required property var modelData
                            text: (root.dragMod === modelData.v ? "✓ " : "") + modelData.n
                            width: 76
                            opacity: root.dragMod === modelData.v ? 1 : 0.55
                            onClicked: { root.dragMod = modelData.v; root.saveSettings() }
                        }
                    }
                }
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
                text: "Ctrl+N 添加磁贴 · Ctrl+H 隐藏/显示 · 右键磁贴属性/删除"
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

    // 统一追加：补齐 opts 角色（ListModel 角色集合由首条元素决定，历史数据必须归一化）
    function appendTile(t) {
        if (t.opts === undefined)
            t.opts = ""
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
        const spot = findFreeSpot(k.w, k.h)
        if (!spot)
            return
        appendTile({ type: type, cx: spot.cx, cy: spot.cy, cw: k.w, ch: k.h,
            text: type === "note" ? "新便签" : "", glyph: "", label: k.name, command: "", icon: "" })
        root.saveTiles()
        addPopup.close()
    }

    // 在网格上找第一块能放下 w×h 的空地
    function findFreeSpot(w, h) {
        const cols = Math.floor(root.width / root.step)
        const rows = Math.floor(root.height / root.step)
        for (let cy = 0; cy <= rows - h; cy++) {
            for (let cx = 0; cx <= cols - w; cx++) {
                let free = true
                for (let i = 0; i < tilesModel.count; i++) {
                    const t = tilesModel.get(i)
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
            fgMode: root.fgMode,
            dragMod: root.dragMod
        }))
    }

    Component.onCompleted: {
        let data = {}, s = {}
        try { data = JSON.parse(Store.load()) } catch (e) { data = {} }
        try { s = JSON.parse(Store.loadSettings()) } catch (e) { s = {} }

        if (typeof s.tileOpacity === "number") root.tileOpacity = s.tileOpacity
        if (typeof s.tileRadius === "number") root.tileRadius = s.tileRadius
        if (typeof s.gap === "number") root.gap = s.gap
        if (typeof s.cardColor === "string") root.cardColor = s.cardColor
        if (typeof s.wallpaperUrl === "string") root.wallpaperUrl = s.wallpaperUrl
        if (typeof s.tilesHidden === "boolean") root.tilesHidden = s.tilesHidden
        if (typeof s.fgMode === "string") root.fgMode = s.fgMode
        if (typeof s.dragMod === "string") root.dragMod = s.dragMod

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

        // 旧布局里没有后台磁贴的，自动补一块
        if (!defs.some(function (t) { return t.type === "tasks" })) {
            const spot = findFreeSpot(2, 3)
            if (spot)
                appendTile({ type: "tasks", cx: spot.cx, cy: spot.cy, cw: 2, ch: 3,
                    text: "", glyph: "", label: "", command: "", icon: "" })
        }

        Bridge.setup()

        // 调试用：ruthis --open-settings 启动时直接弹出设置面板并自截窗口
        if (Qt.application.arguments.indexOf("--open-settings") !== -1) {
            settingsPopup.open()
            Store.grabWindow(AppWindow)
        }
        // 调试用：--open-add 弹出添加磁贴面板（验证分类与图标）
        if (Qt.application.arguments.indexOf("--open-add") !== -1) {
            addPopup.open()
            Store.grabWindow(AppWindow)
        }
    }
}
