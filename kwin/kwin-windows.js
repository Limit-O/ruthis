// ruthis window bridge — 在 KWin 脚本引擎中运行
// 通过 DBus 向 ruthis 推送窗口列表，并接受聚焦/关闭指令

function windowList() {
    var out = [];
    var wins = workspace.windowList();
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        if (!w.normalWindow)
            continue;
        out.push({
            id: String(w.internalId),
            caption: w.caption,
            cls: String(w.resourceClass),
            active: workspace.activeWindow === w,
            closeable: w.closeable !== undefined ? w.closeable : true
        });
    }
    return JSON.stringify(out);
}

function push() {
    callDBus("org.ruthis", "/", "local.ruthis.WindowsBridge", "UpdateWindows", windowList());
}

workspace.windowAdded.connect(push);
workspace.windowRemoved.connect(push);
workspace.windowActivated.connect(push);

push();
