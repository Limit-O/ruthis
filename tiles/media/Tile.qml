import QtQuick

// 媒体磁贴：MPRIS 播放器状态与控制（经 api.media）
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"
    readonly property var media: api ? api.media : null
    // 播放控制钮尺寸随磁贴缩放
    readonly property int ctlSize: Math.max(28, Math.min(40, tile.height * 0.34, tile.width * 0.25))

    Text {
        visible: !tile.media || !tile.media.available
        anchors.centerIn: parent
        text: "无正在播放的媒体"
        color: tile.fg; opacity: 0.45; font.pixelSize: 13
    }

    Column {
        visible: tile.media && tile.media.available
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Row {
            spacing: 6
            Image {
                source: "image://icons/kenney/" + tile.iconVariant + "/"
                        + (tile.media && tile.media.playing ? "musicOn" : "musicOff")
                width: 14; height: 14
                sourceSize: Qt.size(28, 28)
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: tile.media && tile.media.playing ? "正在播放" : "已暂停"
                color: tile.fg; opacity: 0.5; font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            width: parent.width
            text: tile.media ? tile.media.title : ""
            color: tile.fg; font.pixelSize: 17; font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: !tile.media ? ""
                  : tile.media.artist === "" ? tile.media.player
                                             : tile.media.artist + " · " + tile.media.player
            color: tile.fg; opacity: 0.7; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Row {
            spacing: Math.min(24, tile.width * 0.12)
            anchors.horizontalCenter: parent.horizontalCenter
            Item {
                width: tile.ctlSize * 0.85; height: tile.ctlSize * 0.9
                Text { anchors.centerIn: parent; text: "⏮"; color: tile.fg; opacity: 0.85; font.pixelSize: tile.ctlSize * 0.48 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.media.previous() }
            }
            Item {
                width: tile.ctlSize; height: tile.ctlSize
                Rectangle {
                    anchors.centerIn: parent
                    width: tile.ctlSize; height: tile.ctlSize; radius: tile.ctlSize / 2
                    color: "#22ffffff"
                    border.width: 1; border.color: "#3bffffff"
                }
                Text { anchors.centerIn: parent; text: tile.media && tile.media.playing ? "⏸" : "▶"; color: tile.fg; font.pixelSize: tile.ctlSize * 0.42 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.media.toggle() }
            }
            Item {
                width: tile.ctlSize * 0.85; height: tile.ctlSize * 0.9
                Text { anchors.centerIn: parent; text: "⏭"; color: tile.fg; opacity: 0.85; font.pixelSize: tile.ctlSize * 0.48 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.media.next() }
            }
        }
    }
}
