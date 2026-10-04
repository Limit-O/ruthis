import QtQuick

// 通用声明式磁贴渲染器：manifest.source 拉数据（ds 由外壳注入），manifest.render 定展示。
//   render.type: "text"（默认，多行文本）| "bar"（取输出首个数字画进度条，max 定满值，默认 100）
Item {
    id: tile
    property var api
    property var cfg
    property var ds   // TileDataSource，外壳注入；声明式磁贴必有
    readonly property color fg: api ? api.fg : "#f4f7ff"
    readonly property string iconVariant: api ? api.iconVariant : "White"

    readonly property var renderConf: tile.ds ? (tile.ds.manifest.render || {}) : ({})
    readonly property string renderType: tile.renderConf.type || "text"
    readonly property real barMax: tile.renderConf.max !== undefined ? tile.renderConf.max : 100
    readonly property real barVal: {
        if (!tile.ds || tile.renderType !== "bar")
            return 0
        const m = String(tile.ds.output).match(/-?[0-9]+(?:\.[0-9]+)?/)
        return m ? parseFloat(m[0]) : 0
    }
    readonly property string headerIcon: {
        const ic = tile.cfg && tile.cfg.icon ? tile.cfg.icon : ""
        if (ic === "")
            return ""
        return ic.indexOf("/") !== -1 ? "image://icons/" + ic
                                      : "image://icons/kenney/" + tile.iconVariant + "/" + ic
    }

    Column {
        anchors.fill: parent
        spacing: 5

        Row {
            spacing: 6
            Image {
                visible: tile.headerIcon !== ""
                source: tile.headerIcon
                width: 14; height: 14
                sourceSize: Qt.size(28, 28)
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: tile.cfg ? (tile.cfg.label || "") : ""
                color: tile.fg; opacity: 0.6; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // bar 模式：数值行 + 进度条
        Text {
            visible: tile.renderType === "bar"
            text: tile.ds ? tile.ds.output : ""
            color: tile.fg; opacity: 0.85; font.pixelSize: 13
            elide: Text.ElideRight
            width: parent.width
        }
        Rectangle {
            visible: tile.renderType === "bar"
            width: parent.width
            height: 6
            radius: 3
            color: Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b, 0.18)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(tile.barMax, tile.barVal)) / tile.barMax
                height: parent.height
                radius: 3
                color: tile.barVal >= tile.barMax * 0.9 ? "#ff7b72" : "#7fd0ff"
            }
        }

        // text 模式：多行文本占满余下空间
        Text {
            visible: tile.renderType === "text"
            text: tile.ds && tile.ds.output !== "" ? tile.ds.output : "（暂无数据）"
            opacity: tile.ds && tile.ds.output !== "" ? 0.85 : 0.4
            color: tile.fg
            font.pixelSize: 13
            width: parent.width
            height: tile.renderType === "text" ? parent.height - 24 : 0
            wrapMode: Text.Wrap
            clip: true
        }
    }
}
