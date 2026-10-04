import QtQuick
import QtQuick.Controls

// 置顶磁贴宿主窗口内容（PinnedSurfaces 为每枚置顶磁贴开一个 LayerTop 小窗）
Rectangle {
    id: root
    color: "transparent"

    // json 初值为空串，parse 会抛错；小窗销毁期 context 属性会变 null，均须守卫
    readonly property bool ready: OverlayTileData !== null && OverlayTileData.json !== ""
    readonly property var tile: ready ? JSON.parse(OverlayTileData.json) : ({})
    readonly property var st: ready ? JSON.parse(OverlayTileData.settings) : ({})

    function stv(key, def) {
        return st[key] !== undefined ? st[key] : def
    }
    readonly property color cardCol: stv("cardColor", "#ffffff")
    readonly property real cardLum: 0.299 * cardCol.r + 0.587 * cardCol.g + 0.114 * cardCol.b
    readonly property color fgColor: st.fgMode === "light" ? "#f4f7ff"
        : st.fgMode === "dark" ? "#151a22"
        : (cardLum > 0.5 ? "#151a22" : "#f4f7ff")
    readonly property string iconVariant: st.fgMode === "light" ? "White"
        : st.fgMode === "dark" ? "Black"
        : (cardLum > 0.5 ? "Black" : "White")

    function safeOpts() {
        try { return tile.opts ? JSON.parse(tile.opts) : {} } catch (e) { return {} }
    }
    readonly property var cfg: ({ index: 0, type: tile.type,
        text: tile.text || "", glyph: tile.glyph || "", label: tile.label || "",
        command: tile.command || "", icon: tile.icon || "", opts: safeOpts() })

    readonly property var api: QtObject {
        property var sys: SysInfo
        property var media: Media
        property var audio: Audio
        property var windows: Bridge
        property color fg: root.fgColor
        property string iconVariant: root.iconVariant
        property int tileRadius: st.tileRadius !== undefined ? st.tileRadius : 0
        property color cardColor: root.cardCol
        function launch(cmd) { Launcher.launch(cmd) }
        function updateTile(i, k, v) {}   // 宿主窗口不提供属性改写
    }

    Rectangle {
        anchors.fill: parent
        radius: stv("tileRadius", 0)
        color: Qt.rgba(cardCol.r, cardCol.g, cardCol.b, stv("tileOpacity", 0.5))
        border.width: stv("glassBorder", true) ? 1 : 0
        border.color: Qt.rgba(cardCol.r, cardCol.g, cardCol.b,
            Math.min(1, stv("tileOpacity", 0.5) * 1.8 + 0.12))
    }
    Rectangle {
        visible: stv("glassHighlight", true)
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: parent.height / 2
        radius: stv("tileRadius", 0)
        gradient: Gradient {
            GradientStop { position: 0; color: "#12ffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
        }
    }

    Loader {
        anchors.fill: parent
        anchors.margins: 12
        // TileRegistry 判空：退出期 context 属性先于 QML 销毁
        source: root.ready && TileRegistry ? TileRegistry.source(root.tile.type) : ""
        onLoaded: {
            item.api = root.api
            item.cfg = root.cfg
        }
    }

    // 右键 = 取消置顶（磁贴回到主面正常层）；左键完全归磁贴内容（启动等）
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: PinnedSurfaces.unpin(OverlayTileData.id)
    }
}
