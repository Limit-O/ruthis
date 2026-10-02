#pragma once

#include <QFile>
#include <QObject>
#include <QSysInfo>

class SysInfo : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE QString kernelVersion() const
    {
        return QSysInfo::kernelVersion();
    }

    Q_INVOKABLE QString uptimeString() const
    {
        QFile f(QStringLiteral("/proc/uptime"));
        if (!f.open(QIODevice::ReadOnly))
            return QStringLiteral("—");
        const qint64 secs = qint64(f.readLine().split(' ').first().toDouble());
        const int d = int(secs / 86400);
        const int h = int((secs % 86400) / 3600);
        const int m = int((secs % 3600) / 60);
        if (d > 0)
            return QStringLiteral("已运行 %1 天 %2 时 %3 分").arg(d).arg(h).arg(m);
        return QStringLiteral("已运行 %1 时 %2 分").arg(h).arg(m);
    }

    Q_INVOKABLE QString memoryString() const
    {
        QFile f(QStringLiteral("/proc/meminfo"));
        if (!f.open(QIODevice::ReadOnly))
            return QStringLiteral("—");
        // /proc 文件报告长度为 0，atEnd() 不可靠，须一次性读完再按行拆
        const QList<QByteArray> lines = f.readAll().split('\n');
        qint64 total = 0, avail = 0;
        for (const QByteArray &line : lines) {
            if (line.startsWith("MemTotal:"))
                total = value(line);
            else if (line.startsWith("MemAvailable:"))
                avail = value(line);
        }
        if (total <= 0)
            return QStringLiteral("—");
        const int pct = int(100.0 * (total - avail) / total + 0.5);
        return QStringLiteral("内存 %1 GiB · %2 %")
            .arg((total - avail) / 1048576.0, 0, 'f', 1)
            .arg(pct);
    }

private:
    static qint64 value(const QByteArray &line)
    {
        const QByteArray rest = line.mid(line.indexOf(':') + 1);
        return rest.trimmed().split(' ').first().toLongLong();
    }
};
