import QtQuick

// 时钟磁贴：字号随磁贴尺寸自适应，可显示秒数（右键属性面板配置）
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"

    property string timeStr: ""
    property string dateStr: ""

    function tick() {
        const d = new Date()
        const showSecs = tile.cfg && tile.cfg.opts && tile.cfg.opts.seconds === "开"
        timeStr = Qt.formatTime(d, showSecs ? "HH:mm:ss" : "HH:mm")
        dateStr = d.toLocaleDateString(Qt.locale(), "yyyy年M月d日 dddd")
    }

    Timer { interval: 500; running: true; repeat: true; onTriggered: tile.tick() }
    Component.onCompleted: tick()
    onCfgChanged: tick()

    Column {
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.timeStr
            color: tile.fg
            font.pixelSize: Math.max(20, Math.min(tile.height * 0.42, tile.width * 0.28))
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.dateStr
            color: tile.fg
            opacity: 0.75
            font.pixelSize: Math.max(10, Math.min(17, tile.height * 0.12))
        }
    }
}
