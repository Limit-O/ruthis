import QtQuick

// 系统磁贴：CPU/内存/网速/磁盘（经 api.sys 轮询）
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"

    property string uptimeStr: "—"
    property string cpuMemStr: "—"
    property string netStr: "—"
    property string diskStr: "—"

    function refresh() {
        if (!api)
            return
        uptimeStr = api.sys.uptimeString()
        cpuMemStr = "CPU " + api.sys.cpuPercent() + " % · " + api.sys.memoryString()
        netStr = api.sys.netSpeedString()
        diskStr = api.sys.diskString()
    }

    Timer { interval: 2000; running: true; repeat: true; onTriggered: tile.refresh() }
    Component.onCompleted: refresh()
    onApiChanged: refresh()

    Column {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        spacing: 6
        Text {
            text: api ? ("Linux " + api.sys.kernelVersion()) : ""
            color: tile.fg; opacity: 0.55; font.pixelSize: 12
        }
        Text {
            text: tile.uptimeStr
            color: tile.fg; font.pixelSize: 16; font.weight: Font.Medium
        }
        Text {
            text: tile.cpuMemStr
            color: tile.fg; opacity: 0.85; font.pixelSize: 13
        }
        Text {
            text: tile.netStr
            color: tile.fg; opacity: 0.85; font.pixelSize: 13
        }
        Text {
            text: tile.diskStr
            color: tile.fg; opacity: 0.85; font.pixelSize: 13
        }
    }
}
