#pragma once

#include <QtEndian>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// sway/i3 窗口桥：
//   1. 连接 $SWAYSOCK 的 i3 IPC，一条 socket 订阅 window 事件，一条下发命令
//   2. 事件驱动 GET_TREE，把容器树折叠成 {id,caption,cls,active} 窗口列表
//   3. 激活/关闭/浮动/精确摆放通过 RUN_COMMAND 下发（窗口磁贴化的执行面）
//   4. QML 侧契约与 KWin 版 WindowsBridge 一致，main.cpp 按会话环境二选一
class SwayBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
public:
    using QObject::QObject;

    QVariantList windows() const { return m_windows; }

    Q_INVOKABLE void setup()
    {
        const QString path = socketPath();
        if (path.isEmpty()) {
            log(QStringLiteral("[sway-bridge] 未找到 IPC socket（SWAYSOCK/I3SOCK 未设置）"));
            return;
        }
        m_refresh.setSingleShot(true);
        m_refresh.setInterval(30);   // 合并窗口事件爆发（拖拽/批量开关）
        connect(&m_refresh, &QTimer::timeout, this, &SwayBridge::refreshTree);

        connect(m_evt, &QLocalSocket::connected, this, [this] {
            writeMessage(m_evt, kSubscribe, QByteArray(R"(["window"])"));
        });
        connect(m_cmd, &QLocalSocket::connected, this, [this] {
            log(QStringLiteral("[sway-bridge] 已连接"));
            refreshTree();
        });
        connect(m_evt, &QLocalSocket::readyRead, this, [this] { drain(m_evt, m_evtBuf); });
        connect(m_cmd, &QLocalSocket::readyRead, this, [this] { drain(m_cmd, m_cmdBuf); });
        const auto onError = [this](QLocalSocket::LocalSocketError) {
            log(QStringLiteral("[sway-bridge] IPC 连接失败: ") + m_evt->errorString());
        };
        connect(m_evt, &QLocalSocket::errorOccurred, this, onError);

        m_evt->connectToServer(path);
        m_cmd->connectToServer(path);
    }

    Q_INVOKABLE void activateWindow(const QString &id)
    {
        runCommand(QStringLiteral("[con_id=%1] focus").arg(id));
    }

    Q_INVOKABLE void closeWindow(const QString &id)
    {
        runCommand(QStringLiteral("[con_id=%1] kill").arg(id));
    }

    // ---- 磁贴层管理原语（sway 执行面：floating + 任意几何）----
    Q_INVOKABLE void setFloating(const QString &id, bool floating)
    {
        runCommand(QStringLiteral("[con_id=%1] floating %2")
                       .arg(id, floating ? QStringLiteral("enable")
                                         : QStringLiteral("disable")));
    }

    Q_INVOKABLE void placeWindow(const QString &id, int x, int y, int w, int h)
    {
        runCommand(QStringLiteral("[con_id=%1] floating enable,"
                                  " move position %2 px %3 px,"
                                  " resize set width %4 px height %5 px")
                       .arg(id).arg(x).arg(y).arg(w).arg(h));
    }

signals:
    void windowsChanged(const QVariantList &windows);

private:
    enum : quint32 { kRunCommand = 0, kSubscribe = 2, kGetTree = 4 };
    static constexpr quint32 kEventBit = 0x80000000;

    static void log(const QString &line)
    {
        QFile f(QStringLiteral("/tmp/ruthis-debug.log"));
        if (f.open(QIODevice::WriteOnly | QIODevice::Append))
            f.write(line.toUtf8() + '\n');
    }

    static QString socketPath()
    {
        QString p = qEnvironmentVariable("SWAYSOCK");
        if (p.isEmpty())
            p = qEnvironmentVariable("I3SOCK");
        return p;
    }

    void runCommand(const QString &cmd)
    {
        writeMessage(m_cmd, kRunCommand, cmd.toUtf8());
    }

    void refreshTree()
    {
        writeMessage(m_cmd, kGetTree, QByteArrayLiteral("{}"));
    }

    static void appendU32(QByteArray &out, quint32 v)
    {
        char raw[4];
        qToLittleEndian(v, raw);
        out.append(raw, 4);
    }

    static void writeMessage(QLocalSocket *sock, quint32 type, const QByteArray &payload)
    {
        if (sock->state() != QLocalSocket::ConnectedState)
            return;
        QByteArray out;
        out.append(QByteArrayLiteral("i3-ipc"));
        appendU32(out, quint32(payload.size()));
        appendU32(out, type);
        out.append(payload);
        sock->write(out);
    }

    static bool takeFrame(QByteArray &buf, quint32 &type, QByteArray &payload)
    {
        if (buf.size() < 14 || qstrncmp(buf.constData(), "i3-ipc", 6) != 0) {
            buf.clear();
            return false;
        }
        const uchar *p = reinterpret_cast<const uchar *>(buf.constData());
        const quint32 len = qFromLittleEndian<quint32>(p + 6);
        if (quint32(buf.size()) - 14 < len)
            return false;
        type = qFromLittleEndian<quint32>(p + 10);
        payload = buf.mid(14, int(len));
        buf.remove(0, 14 + int(len));
        return true;
    }

    void drain(QLocalSocket *sock, QByteArray &buf)
    {
        buf.append(sock->readAll());
        quint32 type;
        QByteArray payload;
        while (takeFrame(buf, type, payload)) {
            if (type & kEventBit) {
                m_refresh.start();   // window 事件：任何变化都重拉树
            } else if (type == kGetTree) {
                applyTree(payload);
            } else if (type == kRunCommand) {
                const QJsonDocument doc = QJsonDocument::fromJson(payload);
                for (const auto &v : doc.array()) {
                    if (v.toObject().value(QStringLiteral("success")).toBool())
                        continue;
                    log(QStringLiteral("[sway-bridge] 命令失败: ") + QString::fromUtf8(doc.toJson(QJsonDocument::Compact)));
                    break;
                }
            } else if (type == kSubscribe) {
                log(QStringLiteral("[sway-bridge] 订阅: ") + QString::fromUtf8(payload));
            }
        }
    }

    void applyTree(const QByteArray &payload)
    {
        QVariantList list;
        const QJsonDocument doc = QJsonDocument::fromJson(payload);
        walk(doc.object(), list);
        if (list != m_windows) {
            m_windows = list;
            log(QStringLiteral("[sway-bridge] 窗口列表: %1 个").arg(list.size()));
            emit windowsChanged(m_windows);
        }
    }

    static void walk(const QJsonObject &node, QVariantList &out)
    {
        const QJsonValue appId = node.value(QStringLiteral("app_id"));
        const QJsonValue x11Win = node.value(QStringLiteral("window"));
        // wayland 原生窗口有 app_id，XWayland 窗口有 window(x11 id)+window_properties
        const bool realWindow = !appId.isNull()
            || (x11Win.isDouble() && x11Win.toDouble() > 0);
        if (realWindow) {
            QString cls = appId.toString();
            if (cls.isEmpty()) {
                const QJsonObject props =
                    node.value(QStringLiteral("window_properties")).toObject();
                cls = props.value(QStringLiteral("class")).toString();
            }
            QVariantMap w;
            w.insert(QStringLiteral("id"),
                     QString::number(qlonglong(node.value(QStringLiteral("id")).toDouble())));
            w.insert(QStringLiteral("caption"),
                     node.value(QStringLiteral("name")).toString());
            w.insert(QStringLiteral("cls"), cls);
            w.insert(QStringLiteral("active"),
                     node.value(QStringLiteral("focused")).toBool());
            out.append(w);
        }
        for (const auto &v : node.value(QStringLiteral("nodes")).toArray())
            walk(v.toObject(), out);
        for (const auto &v : node.value(QStringLiteral("floating_nodes")).toArray())
            walk(v.toObject(), out);
    }

    QLocalSocket *m_cmd = new QLocalSocket(this);
    QLocalSocket *m_evt = new QLocalSocket(this);
    QByteArray m_cmdBuf;
    QByteArray m_evtBuf;
    QTimer m_refresh;
    QVariantList m_windows;
};
