#pragma once

#include <QDir>
#include <QFile>
#include <QImage>
#include <QObject>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>

class TileStore : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE QString load() const
    {
        return read(configDir(), QStringLiteral("tiles.json"));
    }

    Q_INVOKABLE void save(const QString &json) const
    {
        write(configDir(), QStringLiteral("tiles.json"), json);
    }

    Q_INVOKABLE QString loadSettings() const
    {
        return read(configDir(), QStringLiteral("settings.json"));
    }

    Q_INVOKABLE void saveSettings(const QString &json) const
    {
        write(configDir(), QStringLiteral("settings.json"), json);
    }

    // 本会话的终端会吞掉 QML 应用的 stdout/stderr，调试信息改走文件
    Q_INVOKABLE void log(const QString &line) const
    {
        QFile f(QStringLiteral("/tmp/ruthis-debug.log"));
        if (f.open(QIODevice::WriteOnly | QIODevice::Append))
            f.write(line.toUtf8() + '\n');
    }

    // 窗口被遮挡时外部截不到屏，由应用自行渲染抓帧
    Q_INVOKABLE void grabWindow(QObject *windowObj) const
    {
        auto *w = qobject_cast<QQuickWindow *>(windowObj);
        log(QStringLiteral("[grab] windowObj=%1 cast=%2")
                .arg(windowObj ? QStringLiteral("set") : QStringLiteral("null"),
                     w ? QStringLiteral("ok") : QStringLiteral("fail")));
        if (!w)
            return;
        QTimer::singleShot(500, w, [this, w]() {
            const QImage img = w->grabWindow();
            const bool ok = img.save(QStringLiteral("/tmp/ruthis-window.png"));
            log(QStringLiteral("[grab] %1x%2 saved=%3")
                    .arg(img.width()).arg(img.height()).arg(ok ? "yes" : "no"));
        });
    }

private:
    static QString configDir()
    {
        return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    }

    static QString filePath(const QString &dir, const QString &name)
    {
        return dir + QLatin1Char('/') + name;
    }

    static QString read(const QString &dir, const QString &name)
    {
        QFile f(filePath(dir, name));
        if (!f.open(QIODevice::ReadOnly))
            return QStringLiteral("{}");
        return QString::fromUtf8(f.readAll());
    }

    static void write(const QString &dir, const QString &name, const QString &json)
    {
        QDir().mkpath(dir);
        QFile f(filePath(dir, name));
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            f.write(json.toUtf8());
    }
};
