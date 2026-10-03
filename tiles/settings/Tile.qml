import QtQuick

// 设置磁贴内容：kenney 齿轮 + 名称。点击打开设置面板由外壳处理
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"

    Column {
        anchors.centerIn: parent
        spacing: 8

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "image://icons/kenney/" + tile.iconVariant + "/gear"
            width: 36; height: 36
            sourceSize: Qt.size(72, 72)
            fillMode: Image.PreserveAspectFit
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.cfg ? (tile.cfg.label || "") : ""
            color: tile.fg
            font.pixelSize: 14
        }
    }

    // 点按打开设置面板；按住拖动快捷键时让位给外壳拖拽
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => {
            if (tile.api && (mouse.modifiers & tile.api.dragModifiers))
                mouse.accepted = false
        }
        onClicked: if (tile.api) tile.api.openSettings()
    }
}
