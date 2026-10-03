#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QtDBus>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

// 媒体磁贴后端：轮询会话总线的 MPRIS 播放器（org.mpris.MediaPlayer2.*）。
//   选择策略：正在 Playing 的优先，否则取第一个；
//   控制指令经 PlayPause/Next/Previous 异步下发。
//   同步 Get 调用一律限 800ms 超时，防行为异常的播放器卡住 GUI 线程。
class MediaInfo : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY mediaChanged)
    Q_PROPERTY(QString title READ title NOTIFY mediaChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY mediaChanged)
    Q_PROPERTY(QString player READ player NOTIFY mediaChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY mediaChanged)
public:
    using QObject::QObject;

    explicit MediaInfo(QObject *parent = nullptr)
        : QObject(parent)
    {
        connect(&m_timer, &QTimer::timeout, this, &MediaInfo::refresh);
        m_timer.start(2000);
        QMetaObject::invokeMethod(this, &MediaInfo::refresh, Qt::QueuedConnection);
    }

    bool available() const { return !m_service.isEmpty(); }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString player() const { return m_player; }
    bool playing() const { return m_playing; }

    Q_INVOKABLE void toggle() { playerCall(QStringLiteral("PlayPause")); }
    Q_INVOKABLE void next() { playerCall(QStringLiteral("Next")); }
    Q_INVOKABLE void previous() { playerCall(QStringLiteral("Previous")); }

signals:
    void mediaChanged();

private:
    static QVariant getPlayerProperty(const QString &service, const QString &name)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(
            service, QStringLiteral("/org/mpris/MediaPlayer2"),
            QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        m.setArguments({QStringLiteral("org.mpris.MediaPlayer2.Player"), name});
        // 第三参为毫秒超时：防行为异常的播放器长时间卡住 GUI 线程
        const QDBusReply<QVariant> reply = QDBusConnection::sessionBus().call(m, QDBus::Block, 800);
        return reply.isValid() ? reply.value() : QVariant();
    }

    static QVariantMap getMetadata(const QString &service)
    {
        // Metadata 是 a{sv}，Qt DBus 以 QDBusArgument 包装返回
        const QVariant v = getPlayerProperty(service, QStringLiteral("Metadata"));
        if (!v.canConvert<QDBusArgument>())
            return {};
        return qdbus_cast<QVariantMap>(v.value<QDBusArgument>());
    }

    static QString playerShortName(const QString &service)
    {
        QString name = service.mid(qstrlen("org.mpris.MediaPlayer2."));
        const int dot = name.indexOf('.');
        if (dot > 0)
            name = name.left(dot);   // 去掉 .instanceNNN 之类的后缀
        return name;
    }

    void refresh()
    {
        const QDBusReply<QStringList> names =
            QDBusConnection::sessionBus().interface()->registeredServiceNames();
        QString pick, playingSvc;
        if (names.isValid()) {
            for (const QString &n : names.value()) {
                if (!n.startsWith(QStringLiteral("org.mpris.MediaPlayer2.")))
                    continue;
                if (playingSvc.isEmpty()
                    && getPlayerProperty(n, QStringLiteral("PlaybackStatus"))
                           == QStringLiteral("Playing"))
                    playingSvc = n;
                else if (pick.isEmpty())
                    pick = n;
            }
        }
        const QString svc = !playingSvc.isEmpty() ? playingSvc : pick;

        QString title, artist, pname;
        bool isPlaying = false;
        if (!svc.isEmpty()) {
            isPlaying = getPlayerProperty(svc, QStringLiteral("PlaybackStatus"))
                        == QStringLiteral("Playing");
            const QVariantMap meta = getMetadata(svc);
            title = meta.value(QStringLiteral("xesam:title")).toString();
            artist = meta.value(QStringLiteral("xesam:artist")).toStringList()
                         .join(QStringLiteral(", "));
            if (title.isEmpty())
                title = QStringLiteral("未知曲目");
            pname = playerShortName(svc);
        }

        if (svc == m_service && title == m_title && artist == m_artist
            && pname == m_player && isPlaying == m_playing)
            return;
        m_service = svc;
        m_title = title;
        m_artist = artist;
        m_player = pname;
        m_playing = isPlaying;
        emit mediaChanged();
    }

    void playerCall(const QString &method)
    {
        if (m_service.isEmpty())
            return;
        QDBusInterface iface(m_service, QStringLiteral("/org/mpris/MediaPlayer2"),
                             QStringLiteral("org.mpris.MediaPlayer2.Player"),
                             QDBusConnection::sessionBus(), this);
        iface.asyncCall(method);
        QTimer::singleShot(300, this, &MediaInfo::refresh);   // 状态尽快回读
    }

    QTimer m_timer;
    QString m_service;
    QString m_title;
    QString m_artist;
    QString m_player;
    bool m_playing = false;
};
