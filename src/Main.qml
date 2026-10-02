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

    // 磁贴文字颜色随卡片颜色自动取黑/白（按卡片与深色壁纸混合后的亮度）
    readonly property color tileFg: {
        const lum = 0.299 * cardColor.r + 0.587 * cardColor.g + 0.114 * cardColor.b
        const eff = lum * tileOpacity + 0.03 * (1 - tileOpacity)
        return eff > 0.5 ? "#151a22" : "#f4f7ff"
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
                    Math.min(1, root.tileOpacity + (dragArea.pressed ? 0.07 : 0)))
                border.width: 1
                border.color: Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b,
                    Math.min(1, root.tileOpacity * 1.8 + 0.12))
            }

            // ---- 时钟 ----
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: model.type === "clock"

                property string timeStr: ""
                property string dateStr: ""

                function tick() {
                    const d = new Date()
                    timeStr = Qt.formatTime(d, "HH:mm")
                    dateStr = d.toLocaleDateString(Qt.locale(), "yyyy年M月d日 dddd")
                }

                Timer { interval: 500; running: true; repeat: true; onTriggered: parent.tick() }
                Component.onCompleted: tick()

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.parent.timeStr
                        color: root.tileFg
                        font.pixelSize: 76
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.parent.dateStr
                        color: root.tileFg
                        opacity: 0.75
                        font.pixelSize: 17
                    }
                }
            }

            // ---- 系统 ----
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: model.type === "sys"

                property string uptimeStr: "—"
                property string memStr: "—"

                function refresh() {
                    uptimeStr = SysInfo.uptimeString()
                    memStr = SysInfo.memoryString()
                }

                Timer { interval: 2000; running: true; repeat: true; onTriggered: parent.refresh() }
                Component.onCompleted: refresh()

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 7
                    Text {
                        text: "Linux " + SysInfo.kernelVersion()
                        color: root.tileFg; opacity: 0.6; font.pixelSize: 13
                    }
                    Text {
                        text: parent.parent.uptimeStr
                        color: root.tileFg; font.pixelSize: 18; font.weight: Font.Medium
                    }
                    Text {
                        text: parent.parent.memStr
                        color: root.tileFg; opacity: 0.8; font.pixelSize: 14
                    }
                }
            }

            // ---- 便签 ----
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: model.type === "note"

                TextEdit {
                    anchors.fill: parent
                    anchors.topMargin: 28
                    text: model.text
                    color: root.tileFg
                    font.pixelSize: 15
                    wrapMode: TextEdit.Wrap
                    selectionColor: "#7fd0ff"
                    selectedTextColor: "#101418"
                    onEditingFinished: {
                        model.text = text
                        root.saveTiles()
                    }
                }
                Row {
                    spacing: 5
                    // 用户自定义图标（属性面板可设图片路径/主题名）
                    Image {
                        visible: model.icon !== ""
                        source: model.icon !== "" ? "image://icons/" + model.icon : ""
                        width: 14; height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        sourceSize: Qt.size(28, 28)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    // 默认自绘图标：三条横线
                    Item {
                        visible: model.icon === ""
                        width: 12; height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle { y: 1; width: 12; height: 2; color: root.tileFg; opacity: 0.9 }
                        Rectangle { y: 5; width: 12; height: 2; color: root.tileFg; opacity: 0.6 }
                        Rectangle { y: 9; width: 8; height: 2; color: root.tileFg; opacity: 0.6 }
                    }
                    Text {
                        text: "便签"
                        color: root.tileFg
                        opacity: 0.6
                        font.pixelSize: 12
                    }
                }
            }

            // ---- 应用 / 设置（同为图标磁贴）----
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: model.type === "app" || model.type === "settings"

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    // 自绘几何图标（设置磁贴）：调音台滑杆
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: model.type === "settings"
                        width: 36; height: 36
                        // 三条轨道
                        Rectangle { x: 0; y: 5; width: 36; height: 3; color: root.tileFg; opacity: 0.55 }
                        Rectangle { x: 0; y: 16; width: 36; height: 3; color: root.tileFg; opacity: 0.55 }
                        Rectangle { x: 0; y: 27; width: 36; height: 3; color: root.tileFg; opacity: 0.55 }
                        // 三个错位的滑块
                        Rectangle { x: 22; y: 2; width: 7; height: 9; color: root.tileFg }
                        Rectangle { x: 6; y: 13; width: 7; height: 9; color: root.tileFg }
                        Rectangle { x: 15; y: 24; width: 7; height: 9; color: root.tileFg }
                    }

                    // 应用磁贴：图标主题里的真实图标
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: model.type === "app" && model.icon !== ""
                        source: model.icon !== "" ? "image://icons/" + model.icon : ""
                        sourceSize: Qt.size(64, 64)
                        width: 40; height: 40
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    // 应用磁贴：无图标时的字符兜底
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: model.type === "app" && model.icon === ""
                        text: model.glyph
                        font.pixelSize: 36
                        color: root.tileFg
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.label
                        color: root.tileFg
                        font.pixelSize: 14
                    }
                }
            }

            // ---- 后台（任务磁贴）----
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: model.type === "tasks"

                Column {
                    anchors.fill: parent
                    spacing: 6

                    Row {
                        spacing: 6
                        Text { text: "后台"; color: root.tileFg; opacity: 0.6; font.pixelSize: 12 }
                        Text { text: Bridge.windows.length; color: root.tileFg; opacity: 0.4; font.pixelSize: 12 }
                    }

                    Text {
                        visible: Bridge.windows.length === 0
                        text: "暂无后台应用"
                        color: root.tileFg; opacity: 0.5; font.pixelSize: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    ListView {
                        visible: Bridge.windows.length > 0
                        width: parent.width
                        height: parent.height - 24
                        clip: true
                        spacing: 3
                        model: Bridge.windows

                        delegate: Item {
                            id: winRow
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: 34

                            Rectangle {
                                anchors.fill: parent
                                color: rowMa.containsMouse ? "#1affffff" : "transparent"
                                border.width: modelData.active ? 1 : 0
                                border.color: "#557fd0ff"
                            }
                            Image {
                                id: winIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22
                                source: "image://icons/" + (modelData.cls || "")
                                sourceSize: Qt.size(24, 24)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Text {
                                anchors.left: winIcon.right
                                anchors.leftMargin: 10
                                anchors.right: closeButton.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.caption
                                color: root.tileFg
                                opacity: modelData.active ? 1 : 0.8
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                id: closeButton
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22
                                color: closeMa.containsMouse ? "#3eff4444" : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"; color: root.tileFg; opacity: 0.7; font.pixelSize: 12
                                }
                                MouseArea {
                                    id: closeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Bridge.closeWindow(modelData.id)
                                }
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Bridge.activateWindow(modelData.id)
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: dragArea
                // 不锚定 bottom，height 才能生效：便签只热区顶部 36px，
                // 正文区域留给 TextEdit 接收点击和键盘
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                height: model.type === "note" ? 36 : parent.height
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                property bool moved: false

                drag.target: tile
                drag.threshold: 5
                drag.minimumX: 0
                drag.maximumX: root.width - tile.width
                drag.minimumY: 0
                drag.maximumY: root.height - tile.height

                onPressed: {
                    moved = false
                    // 点击磁贴即把焦点从便签文本框移走，停止输入
                    tile.forceActiveFocus()
                    ghost.width = tile.width
                    ghost.height = tile.height
                    updateGhost()
                    ghost.visible = true
                }
                onPositionChanged: {
                    if (drag.active) {
                        moved = true
                        updateGhost()
                    }
                }
                onReleased: {
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
                onClicked: (mouse) => {
                    // 右键：属性菜单
                    if (mouse.button === Qt.RightButton) {
                        const p = mapToItem(root, mouse.x, mouse.y)
                        tileMenu.x = Math.max(4, Math.min(p.x, root.width - tileMenu.width - 4))
                        tileMenu.y = Math.max(4, Math.min(p.y, root.height - tileMenu.height - 4))
                        tileMenu.tileIndex = model.index
                        tileMenu.open()
                        return
                    }
                    if (moved)
                        return
                    if (model.type === "app")
                        Launcher.launch(model.command)
                    else if (model.type === "settings")
                        settingsPopup.open()
                }

                function updateGhost() {
                    ghost.x = Math.round(tile.x / root.step) * root.step
                    ghost.y = Math.round(tile.y / root.step) * root.step
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
            open()
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
            spacing: 14

            Text { text: "添加磁贴"; color: "#f4f7ff"; font.pixelSize: 18; font.bold: true }

            Grid {
                columns: 3
                spacing: 10

                Repeater {
                    model: [
                        { type: "note", label: "便签" },
                        { type: "app", label: "应用" },
                        { type: "tasks", label: "后台" },
                        { type: "clock", label: "时钟" },
                        { type: "sys", label: "系统" },
                        { type: "settings", label: "设置" }
                    ]
                    delegate: GlassButton {
                        required property var modelData
                        text: modelData.label
                        width: 96
                        onClicked: root.addTile(modelData.type)
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
                tilesModel.append({ type: "app", cx: spot.cx, cy: spot.cy, cw: 1, ch: 1,
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
                        asynchronous: true
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
            { type: "sys", cx: 4, cy: 1, cw: 2, ch: 1, text: "", glyph: "", label: "", command: "", icon: "" },
            { type: "note", cx: 4, cy: 2, cw: 2, ch: 2,
              text: "☐ 补完系统升级\n☐ 验证新登录器\n☐ 剪第一条视频", glyph: "", label: "", command: "", icon: "" },
            { type: "app", cx: 1, cy: 3, cw: 1, ch: 1, glyph: "", label: "终端", command: "konsole", icon: "utilities-terminal" },
            { type: "app", cx: 2, cy: 3, cw: 1, ch: 1, glyph: "", label: "浏览器", command: "firefox", icon: "firefox" },
            { type: "app", cx: 3, cy: 3, cw: 1, ch: 1, glyph: "", label: "文件", command: "dolphin", icon: "system-file-manager" },
            { type: "settings", cx: 4, cy: 4, cw: 1, ch: 1, glyph: "", label: "设置", command: "", icon: "" }
        ]
    }

    function addTile(type) {
        // 应用磁贴走应用选择列表，免手打命令/图标/名称
        if (type === "app") {
            addPopup.close()
            appPicker.assignIndex = -1
            appPicker.open()
            return
        }
        const spec = {
            note:     { w: 2, h: 2, text: "新便签", glyph: "", label: "", command: "", icon: "" },
            app:      { w: 1, h: 1, text: "", glyph: "", label: "应用", command: "", icon: "" },
            tasks:    { w: 2, h: 3, text: "", glyph: "", label: "", command: "", icon: "" },
            clock:    { w: 3, h: 2, text: "", glyph: "", label: "", command: "", icon: "" },
            sys:      { w: 2, h: 1, text: "", glyph: "", label: "", command: "", icon: "" },
            settings: { w: 1, h: 1, text: "", glyph: "", label: "设置", command: "", icon: "" }
        }[type]
        if (!spec)
            return
        const spot = findFreeSpot(spec.w, spec.h)
        if (!spot)
            return
        tilesModel.append({ type: type, cx: spot.cx, cy: spot.cy, cw: spec.w, ch: spec.h,
            text: spec.text, glyph: spec.glyph, label: spec.label, command: spec.command, icon: spec.icon })
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
            tilesHidden: root.tilesHidden
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

        let defs = (data.tiles && data.tiles.length > 0) ? data.tiles : defaultTiles()
        // 旧版 tiles.json 里没有设置磁贴，补一枚
        if (!defs.some(function (t) { return t.type === "settings" }))
            defs.push({ type: "settings", cx: 4, cy: 4, cw: 1, ch: 1, glyph: "", label: "设置", command: "", icon: "" })
        // 补齐 icon 角色；已知命令自动配图标主题名
        const iconMap = { konsole: "utilities-terminal", firefox: "firefox", dolphin: "system-file-manager" }
        defs.forEach(function (t) {
            t.icon = t.icon || (t.type === "app" ? (iconMap[t.command] || "") : "")
            tilesModel.append(t)
        })

        // 旧布局里没有后台磁贴的，自动补一块
        if (!defs.some(function (t) { return t.type === "tasks" })) {
            const spot = findFreeSpot(2, 3)
            if (spot)
                tilesModel.append({ type: "tasks", cx: spot.cx, cy: spot.cy, cw: 2, ch: 3,
                    text: "", glyph: "", label: "", command: "", icon: "" })
        }

        Bridge.setup()

        // 调试用：ruthis --open-settings 启动时直接弹出设置面板并自截窗口
        if (Qt.application.arguments.indexOf("--open-settings") !== -1) {
            settingsPopup.open()
            Store.grabWindow(AppWindow)
        }
    }
}
