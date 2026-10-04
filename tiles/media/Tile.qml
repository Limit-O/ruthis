import QtQuick

// 媒体磁贴：MPRIS 播放器状态与控制（经 api.media）
// 控制图标用 Canvas 矢量绘制，随 ctlSize 缩放、颜色跟随文字明暗
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"
    readonly property var media: api ? api.media : null
    // 播放控制钮尺寸随磁贴缩放
    readonly property int ctlSize: Math.max(30, Math.min(42, tile.height * 0.34, tile.width * 0.25))

    component MediaIcon: Canvas {
        property string kind: "play"
        property color color: "#ffffff"
        width: size; height: size
        onKindChanged: requestPaint()
        onColorChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = color
            const u = width / 10   // 10 等分网格
            if (kind === "play") {
                ctx.beginPath()
                ctx.moveTo(2.4 * u, 1.2 * u)
                ctx.lineTo(9 * u, 5 * u)
                ctx.lineTo(2.4 * u, 8.8 * u)
                ctx.closePath()
                ctx.fill()
            } else if (kind === "pause") {
                ctx.fillRect(2.2 * u, 1.4 * u, 2.2 * u, 7.2 * u)
                ctx.fillRect(5.6 * u, 1.4 * u, 2.2 * u, 7.2 * u)
            } else if (kind === "previous") {
                ctx.fillRect(1.4 * u, 1.4 * u, 1.4 * u, 7.2 * u)
                ctx.beginPath()
                ctx.moveTo(8.6 * u, 1.4 * u)
                ctx.lineTo(3.6 * u, 5 * u)
                ctx.lineTo(8.6 * u, 8.6 * u)
                ctx.closePath()
                ctx.fill()
            } else if (kind === "next") {
                ctx.fillRect(7.2 * u, 1.4 * u, 1.4 * u, 7.2 * u)
                ctx.beginPath()
                ctx.moveTo(1.4 * u, 1.4 * u)
                ctx.lineTo(6.4 * u, 5 * u)
                ctx.lineTo(1.4 * u, 8.6 * u)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

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
            spacing: Math.min(22, tile.width * 0.1)
            anchors.horizontalCenter: parent.horizontalCenter
            Item {
                width: tile.ctlSize * 0.85; height: tile.ctlSize * 0.9
                MediaIcon {
                    anchors.centerIn: parent
                    kind: "previous"; size: tile.ctlSize * 0.5; color: tile.fg; opacity: 0.85
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.media.previous() }
            }
            Item {
                width: tile.ctlSize; height: tile.ctlSize
                Rectangle {
                    anchors.centerIn: parent
                    width: tile.ctlSize; height: tile.ctlSize; radius: tile.ctlSize / 2
                    color: Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b,
                                   tile.media && tile.media.playing ? 0.14 : 0.08)
                    border.width: 1
                    border.color: Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b,
                                          tile.media && tile.media.playing ? 0.4 : 0.25)
                }
                MediaIcon {
                    anchors.centerIn: parent
                    kind: tile.media && tile.media.playing ? "pause" : "play"
                    size: tile.ctlSize * 0.46; color: tile.fg
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.media.toggle() }
            }
            Item {
                width: tile.ctlSize * 0.85; height: tile.ctlSize * 0.9
                MediaIcon {
                    anchors.centerIn: parent
                    kind: "next"; size: tile.ctlSize * 0.5; color: tile.fg; opacity: 0.85
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.media.next() }
            }
        }
    }
}
