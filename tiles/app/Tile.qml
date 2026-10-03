import QtQuick

// 应用磁贴内容：图标/字符兜底/名称。点击启动由外壳的拖拽热区处理
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"

    Column {
        anchors.centerIn: parent
        spacing: 8

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tile.cfg && tile.cfg.type === "app" && tile.cfg.icon !== ""
            source: tile.cfg && tile.cfg.type === "app" && tile.cfg.icon !== ""
                    ? "image://icons/" + tile.cfg.icon : ""
            sourceSize: Qt.size(64, 64)
            width: 40; height: 40
            fillMode: Image.PreserveAspectFit
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tile.cfg && tile.cfg.type === "app" && tile.cfg.icon === ""
            text: tile.cfg ? (tile.cfg.glyph || "") : ""
            font.pixelSize: 36
            color: tile.fg
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.cfg ? (tile.cfg.label || "") : ""
            color: tile.fg
            font.pixelSize: 14
        }
    }
}
