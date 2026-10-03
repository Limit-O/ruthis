import QtQuick

// 电池磁贴：多电池平均电量与充放状态（经 api.sys）
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"

    property bool has: false
    property int pct: -1
    property string st: "—"

    function refresh() {
        if (!api)
            return
        has = api.sys.hasBattery()
        pct = api.sys.batteryPercent()
        st = api.sys.batteryStatus()
    }

    Timer { interval: 5000; running: true; repeat: true; onTriggered: tile.refresh() }
    Component.onCompleted: refresh()
    onApiChanged: refresh()

    Text {
        visible: !tile.has
        anchors.centerIn: parent
        text: "未检测到电池"
        color: tile.fg; opacity: 0.45; font.pixelSize: 13
    }

    Column {
        visible: tile.has
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Row {
            spacing: 10
            Image {
                source: "image://icons/kenney/" + tile.iconVariant + "/power"
                width: 19; height: 19
                sourceSize: Qt.size(38, 38)
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: tile.pct >= 0 ? tile.pct + " %" : "—"
                color: tile.fg; font.pixelSize: 19; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: tile.st
                color: tile.fg; opacity: 0.7; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Rectangle {
            width: parent.width
            height: 6
            radius: 3
            color: api ? Qt.rgba(api.cardColor.r, api.cardColor.g, api.cardColor.b, 0.25) : "transparent"
            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, tile.pct)) / 100
                height: parent.height
                radius: 3
                color: tile.pct <= 20 && tile.st === "放电中" ? "#ff7b72" : "#7fd0ff"
            }
        }
    }
}
