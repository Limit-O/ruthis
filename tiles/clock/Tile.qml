import QtQuick

// 时钟磁贴
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"

    property string timeStr: ""
    property string dateStr: ""

    function tick() {
        const d = new Date()
        timeStr = Qt.formatTime(d, "HH:mm")
        dateStr = d.toLocaleDateString(Qt.locale(), "yyyy年M月d日 dddd")
    }

    Timer { interval: 500; running: true; repeat: true; onTriggered: tile.tick() }
    Component.onCompleted: tick()

    Column {
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.timeStr
            color: tile.fg
            font.pixelSize: 76
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.dateStr
            color: tile.fg
            opacity: 0.75
            font.pixelSize: 17
        }
    }
}
