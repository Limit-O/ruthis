import QtQuick

// 便签磁贴：顶部 36px 是外壳拖拽热区，正文为可编辑文本
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"

    Row {
        spacing: 5
        Image {
            visible: tile.cfg && tile.cfg.icon !== ""
            source: tile.cfg && tile.cfg.icon !== "" ? "image://icons/" + tile.cfg.icon : ""
            width: 14; height: 14
            anchors.verticalCenter: parent.verticalCenter
            sourceSize: Qt.size(28, 28)
            fillMode: Image.PreserveAspectFit
        }
        Item {
            visible: !tile.cfg || tile.cfg.icon === ""
            width: 12; height: 12
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { y: 1; width: 12; height: 2; color: tile.fg; opacity: 0.9 }
            Rectangle { y: 5; width: 12; height: 2; color: tile.fg; opacity: 0.6 }
            Rectangle { y: 9; width: 8; height: 2; color: tile.fg; opacity: 0.6 }
        }
        Text {
            text: "便签"
            color: tile.fg
            opacity: 0.6
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    TextEdit {
        anchors.fill: parent
        anchors.topMargin: 28
        text: tile.cfg ? (tile.cfg.text || "") : ""
        color: tile.fg
        font.pixelSize: 15
        wrapMode: TextEdit.Wrap
        selectionColor: "#7fd0ff"
        selectedTextColor: "#101418"
        onEditingFinished: {
            if (api && tile.cfg && tile.cfg.text !== text)
                api.updateTile(tile.cfg.index, "text", text)
        }
    }
}
