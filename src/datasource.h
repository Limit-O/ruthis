#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QFile>
#include <QIODevice>
#include <QMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QtDBus>

#include "tileregistry.h"

// 声明式磁贴的数据源：按 manifest.source 周期拉取一段文本，输出统一放
// output（去首尾空白，截断 4KB），渲染交给 tiles/_generic/Tile.qml。
//   {"type":"command","cmd":"...","interval":秒}      /bin/sh -c 执行
//   {"type":"file","path":"...","interval":秒}         读文件
//   {"type":"http","url":"...","interval":秒}          GET（10s 超时）
//   {"type":"dbus","service":..,"path":..,"iface":..,
//    "property":..,"interval":秒}                      读 DBus 属性（3s 超时）
// 空输出/失败置 failed=true，由渲染器显示占位。
class TileDataSource : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString output READ output NOTIFY dataChanged)
    Q_PROPERTY(bool failed READ failed NOTIFY dataChanged)
    // 完整 manifest，供通用渲染器读取 render 配置
    Q_PROPERTY(QVariantMap manifest READ manifest CONSTANT)
public:
    explicit TileDataSource(const QVariantMap &sourceConf, const QVariantMap &manifest,
                            QObject *parent = nullptr)
        : QObject(parent), m_manifest(manifest)
    {
        m_type = sourceConf.value(QStringLiteral("type")).toString();
        m_cmd = sourceConf.value(QStringLiteral("cmd")).toString();
        m_path = sourceConf.value(QStringLiteral("path")).toString();
        m_url = sourceConf.value(QStringLiteral("url")).toString();
        m_service = sourceConf.value(QStringLiteral("service")).toString();
        m_iface = sourceConf.value(QStringLiteral("iface")).toString();
        m_property = sourceConf.value(QStringLiteral("property")).toString();
        int secs = sourceConf.value(QStringLiteral("interval")).toInt();
        if (secs <= 0)
            secs = 60;
        if (secs < 2)
            secs = 2;
        m_timer.setInterval(secs * 1000);
        connect(&m_timer, &QTimer::timeout, this, &TileDataSource::fetch);
        connect(&m_proc, &QProcess::finished, this, &TileDataSource::onProcFinished);
        fetch();
        m_timer.start();
    }

    QString output() const { return m_output; }
    bool failed() const { return m_failed; }
    QVariantMap manifest() const { return m_manifest; }

signals:
    void dataChanged();

private:
    void fetch()
    {
        if (m_type == QLatin1String("command")) {
            if (m_proc.state() != QProcess::NotRunning)
                return;
            m_proc.start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), m_cmd});
        } else if (m_type == QLatin1String("file")) {
            QFile f(m_path);
            setOutput(f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll())
                                                  : QString());
        } else if (m_type == QLatin1String("http")) {
            QNetworkRequest req{QUrl(m_url)};
            req.setTransferTimeout(10000);
            QNetworkReply *reply = m_mgr.get(req);
            connect(reply, &QNetworkReply::finished, this, [this, reply] {
                reply->deleteLater();
                setOutput(reply->error() == QNetworkReply::NoError
                              ? QString::fromUtf8(reply->readAll())
                              : QString());
            });
        } else if (m_type == QLatin1String("dbus")) {
            QDBusMessage msg = QDBusMessage::createMethodCall(
                m_service, m_path, QStringLiteral("org.freedesktop.DBus.Properties"),
                QStringLiteral("Get"));
            msg.setArguments({m_iface, m_property});
            // 第三参为毫秒超时，防异常服务卡住 GUI 线程
            const QDBusReply<QVariant> reply =
                QDBusConnection::sessionBus().call(msg, QDBus::Block, 3000);
            setOutput(reply.isValid() ? reply.value().toString() : QString());
        }
    }

    void onProcFinished(int code, QProcess::ExitStatus status)
    {
        const bool ok = status == QProcess::NormalExit && code == 0;
        setOutput(ok ? QString::fromUtf8(m_proc.readAllStandardOutput()) : QString());
    }

    void setOutput(const QString &raw)
    {
        QString t = raw.trimmed();
        if (t.size() > 4096)
            t = t.left(4096);
        m_failed = t.isEmpty();
        if (t != m_output)
            m_output = t;
        emit dataChanged();
    }

    QTimer m_timer;
    QProcess m_proc;
    QNetworkAccessManager m_mgr;
    QVariantMap m_manifest;
    QString m_type;
    QString m_cmd;
    QString m_path;
    QString m_url;
    QString m_service;
    QString m_iface;
    QString m_property;
    QString m_output;
    bool m_failed = false;
};

// 数据源池：按磁贴类型惰性创建并缓存（manifest 声明了 source 的类型才有）
class TileSources : public QObject {
    Q_OBJECT
public:
    explicit TileSources(const TileRegistry *registry, QObject *parent = nullptr)
        : QObject(parent), m_registry(registry)
    {
    }

    Q_INVOKABLE QObject *forType(const QString &type)
    {
        if (m_pool.contains(type))
            return m_pool.value(type);
        const QVariantMap conf = m_registry->sourceConfig(type);
        if (conf.isEmpty())
            return nullptr;
        auto *ds = new TileDataSource(conf, m_registry->kind(type), this);
        m_pool.insert(type, ds);
        return ds;
    }

private:
    const TileRegistry *m_registry;
    QMap<QString, QObject *> m_pool;
};
