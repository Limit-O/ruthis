import QtQuick
import QtQuick.Controls

// 音量磁贴：默认输出设备的音量/静音（经 api.audio）；滑条样式磁贴自带，不依赖外壳组件
Item {
    id: tile
    property var api
    property var cfg
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"
    readonly property var audio: api ? api.audio : null

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 4
        spacing: 5

        Row {
            spacing: 10
            Item {
                width: 24; height: 24
                Image {
                    anchors.centerIn: parent
                    source: "image://icons/kenney/" + tile.iconVariant + "/"
                            + (tile.audio && tile.audio.muted ? "audioOff" : "audioOn")
                    width: 18; height: 18
                    sourceSize: Qt.size(36, 36)
                    fillMode: Image.PreserveAspectFit
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (tile.audio) tile.audio.toggleMute()
                }
            }
            Text {
                text: tile.audio ? (tile.audio.muted ? "已静音" : tile.audio.volume + " %") : "—"
                color: tile.fg; opacity: 0.85; font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Slider {
            id: volSlider
            width: parent.width
            height: 26   // 自定义 background 无隐含尺寸，在 Column 里必须显式给高
            from: 0; to: 100; stepSize: 1
            value: tile.audio ? tile.audio.volume : 0
            onMoved: if (tile.audio) tile.audio.setVolume(value)
            background: Rectangle {
                x: volSlider.leftPadding
                y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                width: volSlider.availableWidth
                height: 6
                radius: 3
                // 轨道/手柄跟随文字明暗，亮背景不再隐身
                color: Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b, 0.18)
                Rectangle {
                    width: volSlider.visualPosition * parent.width
                    height: parent.height
                    radius: 3
                    color: "#7fd0ff"
                }
            }
            handle: Rectangle {
                x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                width: 16; height: 16
                radius: 8
                color: volSlider.pressed ? "#7fd0ff" : tile.fg
                border.width: 1
                border.color: Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b, 0.45)
            }
        }
    }
}
