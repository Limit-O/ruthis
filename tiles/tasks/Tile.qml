import QtQuick

// 后台磁贴：迷你磁贴栅格。点卡片激活 / 中键关闭 / 悬停角标关闭（经 api.windows）
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"
    readonly property string iconBase: "image://icons/kenney/" + tile.iconVariant + "/"
    readonly property var wins: api ? api.windows : null
    readonly property int winCount: tile.wins ? tile.wins.windows.length : 0

    Column {
        anchors.fill: parent
        spacing: 6

        Row {
            spacing: 6
            Image {
                source: tile.iconBase + "menuGrid"
                width: 14; height: 14
                sourceSize: Qt.size(28, 28)
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text { text: "后台"; color: tile.fg; opacity: 0.6; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Text { text: tile.winCount; color: tile.fg; opacity: 0.4; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }

        Text {
            visible: tile.winCount === 0
            text: "暂无后台应用"
            color: tile.fg; opacity: 0.5; font.pixelSize: 14
            anchors.horizontalCenter: parent.horizontalCenter
        }

        GridView {
            id: winGrid
            visible: tile.winCount > 0
            width: parent.width
            height: parent.height - 24
            clip: true
            cellWidth: 62
            cellHeight: 66
            model: tile.wins ? tile.wins.windows : null

            delegate: Item {
                id: winCell
                width: winGrid.cellWidth
                height: winGrid.cellHeight
                required property var modelData

                Rectangle {
                    anchors.centerIn: parent
                    width: 56; height: 60
                    radius: tile.api ? tile.api.tileRadius : 0
                    color: winMa.containsMouse
                           ? Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b, 0.14)
                           : Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b, 0.07)
                    border.width: winCell.modelData.active ? 1 : 0
                    border.color: "#667fd0ff"

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        width: 26; height: 26
                        source: "image://icons/" + (winCell.modelData.cls || "")
                        sourceSize: Qt.size(32, 32)
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        width: parent.width - 6
                        text: winCell.modelData.caption
                        color: tile.fg
                        opacity: winCell.modelData.active ? 1 : 0.75
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                    // 悬停时才出现的关闭角标：关不掉的窗口不显示（中键同理）
                    Rectangle {
                        visible: winMa.containsMouse && winCell.modelData.closeable !== false
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -3
                        anchors.topMargin: -3
                        width: 16; height: 16
                        radius: 8
                        color: cellCloseMa.containsMouse ? "#77ff5555" : "#4dff5555"
                        Text { anchors.centerIn: parent; text: "✕"; color: tile.fg; font.pixelSize: 9 }
                        MouseArea {
                            id: cellCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tile.wins.closeWindow(winCell.modelData.id)
                        }
                    }
                    MouseArea {
                        id: winMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.MiddleButton) {
                                if (winCell.modelData.closeable !== false)
                                    tile.wins.closeWindow(winCell.modelData.id)
                            } else {
                                tile.wins.activateWindow(winCell.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
