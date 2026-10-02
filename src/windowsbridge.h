#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QStandardPaths>
#include <QVariantList>

// 任务磁贴的窗口桥：
//   1. 从资源释放 KWin 辅助脚本并通过 DBus 让 KWin 加载
//   2. 注册 org.ruthis 服务，接收脚本推送的窗口列表
//   3. 反向调用脚本注册的 Activate/Close 管理窗口
class WindowsBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
public:
    using QObject::QObject;

    QVariantList windows() const { return m_windows; }

    Q_INVOKABLE void setup()
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.registerService(QStringLiteral("org.ruthis"));
        bus.registerObject(QStringLiteral("/"), this, QDBusConnection::ExportAllInvokables);
        installScript();
        loadKWinScript();
    }

    Q_INVOKABLE void activateWindow(const QString &id)
    {
        runActionScript(id, QStringLiteral("workspace.activeWindow = wins[i];"));
    }

    Q_INVOKABLE void closeWindow(const QString &id)
    {
        runActionScript(id, QStringLiteral("wins[i].close();"));
    }

    // KWin 脚本经 DBus 调用（方法名大小写须与脚本一致）
    Q_INVOKABLE void UpdateWindows(const QString &json)
    {
        QVariantList list;
        const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
        for (const auto &v : doc.array())
            list.append(v.toObject().toVariantMap());
        if (list != m_windows) {
            m_windows = list;
            log(QStringLiteral("[bridge] 收到窗口推送: %1 个").arg(list.size()));
            emit windowsChanged(m_windows);
        }
    }

signals:
    void windowsChanged(const QVariantList &windows);

private:
    static QString scriptPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
             + QStringLiteral("/kwin-windows.js");
    }

    static void installScript()
    {
        QFile src(QStringLiteral(":/kwin/kwin-windows.js"));
        QFile dst(scriptPath());
        if (!src.open(QIODevice::ReadOnly))
            return;
        const QByteArray content = src.readAll();
        QByteArray current;
        if (dst.open(QIODevice::ReadOnly))
            current = dst.readAll();
        dst.close();
        if (current != content) {
            if (dst.open(QIODevice::WriteOnly | QIODevice::Truncate))
                dst.write(content);
        }
    }

    static QDBusMessage scriptingCall(const QString &method, const QList<QVariant> &args = {})
    {
        QDBusMessage m = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"),
            QStringLiteral("org.kde.kwin.Scripting"), method);
        m.setArguments(args);
        return QDBusConnection::sessionBus().call(m);
    }

    void loadKWinScript() const
    {
        const QString plugin = QStringLiteral("ruthis-windows");
        scriptingCall(QStringLiteral("unloadScript"), {plugin});
        const QDBusReply<int> id = scriptingCall(
            QStringLiteral("loadScript"), {scriptPath(), plugin});
        if (!id.isValid()) {
            log(QStringLiteral("[bridge] loadScript 失败: ") + id.error().message());
            return;
        }
        QDBusMessage run = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Scripting/Script%1").arg(id.value()),
            QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run"));
        QDBusConnection::sessionBus().asyncCall(run);
        log(QStringLiteral("[bridge] 脚本已加载, id=%1").arg(id.value()));
    }

    // 这个 KWin 版本没有 registerDBus，指令方向用"生成一次性脚本"实现
    void runActionScript(const QString &id, const QString &action)
    {
        static int counter = 0;
        const QString plugin = QStringLiteral("ruthis-cmd-%1").arg(++counter);
        const QString path = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
            + QStringLiteral("/cmd-%1.js").arg(counter);
        const QString js = QStringLiteral(
            "(function() { var wins = workspace.windowList();"
            " for (var i = 0; i < wins.length; i++) {"
            " if (String(wins[i].internalId) === \"%1\") { %2 return; } } })()")
                               .arg(id, action);
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return;
        f.write(js.toUtf8());
        f.close();

        const QDBusReply<int> sid = scriptingCall(
            QStringLiteral("loadScript"), {path, plugin});
        if (!sid.isValid()) {
            log(QStringLiteral("[bridge] 指令脚本加载失败: ") + sid.error().message());
            return;
        }
        QDBusMessage run = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Scripting/Script%1").arg(sid.value()),
            QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run"));
        QDBusConnection::sessionBus().call(run);
        scriptingCall(QStringLiteral("unloadScript"), {plugin});
    }

    static void log(const QString &line)
    {
        QFile f(QStringLiteral("/tmp/ruthis-debug.log"));
        if (f.open(QIODevice::WriteOnly | QIODevice::Append))
            f.write(line.toUtf8() + '\n');
    }

    QVariantList m_windows;
};
