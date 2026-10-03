#pragma once

#include <QElapsedTimer>
#include <QDir>
#include <QFile>
#include <QObject>
#include <QSysInfo>

#include <sys/statvfs.h>

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

    // CPU 占用：/proc/stat 相邻两次采样的差值，首次调用无基线返回 "—"
    Q_INVOKABLE QString cpuPercent()
    {
        QFile f(QStringLiteral("/proc/stat"));
        if (!f.open(QIODevice::ReadOnly))
            return QStringLiteral("—");
        // 首行形如 "cpu  user nice system idle iowait irq softirq steal ..."
        const QList<QByteArray> fields = f.readLine().split(' ');
        quint64 v[8] = {};
        int n = 0;
        for (int i = 1; i < fields.size() && n < 8; ++i)
            v[n++] = fields[i].toULongLong();
        const quint64 total = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7];
        const quint64 busy = total - (v[3] + v[4]);   // 减去 idle + iowait
        if (m_cpuTotal == 0) {
            m_cpuTotal = total;
            m_cpuBusy = busy;
            return QStringLiteral("—");
        }
        const quint64 dTotal = total - m_cpuTotal;
        const quint64 dBusy = busy - m_cpuBusy;
        m_cpuTotal = total;
        m_cpuBusy = busy;
        if (dTotal == 0)
            return QStringLiteral("—");
        return QString::number(int(100 * dBusy / dTotal));
    }

    // 全网卡（除 lo）收发速率，采样间隔由 QML 轮询节奏决定
    Q_INVOKABLE QString netSpeedString()
    {
        QFile f(QStringLiteral("/proc/net/dev"));
        if (!f.open(QIODevice::ReadOnly))
            return QStringLiteral("—");
        const QList<QByteArray> lines = f.readAll().split('\n');
        quint64 rx = 0, tx = 0;
        for (int i = 2; i < lines.size(); ++i) {   // 前两行是表头
            const int colon = lines[i].indexOf(':');
            if (colon < 0 || lines[i].left(colon).trimmed() == "lo")
                continue;
            // 字段按空格分割，须滤掉连续空格产生的空 token
            const QList<QByteArray> v = lines[i].mid(colon + 1).split(' ');
            if (v.size() < 16)
                continue;
            rx += v[0].toULongLong();
            tx += v[8].toULongLong();
        }
        if (!m_netBaseline) {
            m_rx = rx;
            m_tx = tx;
            m_netElapsed.start();
            m_netBaseline = true;
            return QStringLiteral("↑ — · ↓ —");
        }
        const double secs = m_netElapsed.restart() / 1000.0;
        if (secs <= 0)
            return QStringLiteral("↑ — · ↓ —");
        const QString up = speedString((rx - m_rx) / secs);
        const QString down = speedString((tx - m_tx) / secs);
        m_rx = rx;
        m_tx = tx;
        return QStringLiteral("↑ %1 · ↓ %2").arg(up, down);
    }

    // 根分区（或 /home，取先 statvfs 成功者）用量
    Q_INVOKABLE QString diskString() const
    {
        struct statvfs st;
        if (statvfs("/home", &st) != 0 && statvfs("/", &st) != 0)
            return QStringLiteral("—");
        const double total = double(st.f_blocks) * double(st.f_frsize);
        const double used = total - double(st.f_bfree) * double(st.f_frsize);
        if (total <= 0)
            return QStringLiteral("—");
        return QStringLiteral("磁盘 %1 / %2 GiB · %3 %")
            .arg(used / 1073741824.0, 0, 'f', 0)
            .arg(total / 1073741824.0, 0, 'f', 0)
            .arg(int(100.0 * used / total + 0.5));
    }

    Q_INVOKABLE bool hasBattery() const
    {
        return !batteryPaths().isEmpty();
    }

    // 多电池取平均
    Q_INVOKABLE int batteryPercent() const
    {
        int sum = 0, n = 0;
        for (const QString &dir : batteryPaths()) {
            QFile f(dir + QStringLiteral("/capacity"));
            if (f.open(QIODevice::ReadOnly)) {
                sum += f.readAll().trimmed().toInt();
                ++n;
            }
        }
        return n ? sum / n : -1;
    }

    Q_INVOKABLE QString batteryStatus() const
    {
        QStringList raw;
        for (const QString &dir : batteryPaths()) {
            QFile f(dir + QStringLiteral("/status"));
            if (f.open(QIODevice::ReadOnly))
                raw << QString::fromUtf8(f.readAll().trimmed());
        }
        if (raw.isEmpty())
            return QStringLiteral("无电池");
        if (raw.contains(QStringLiteral("Charging")))
            return QStringLiteral("充电中");
        if (raw.contains(QStringLiteral("Discharging")))
            return QStringLiteral("放电中");
        if (raw.contains(QStringLiteral("Full")))
            return QStringLiteral("已充满");
        return QStringLiteral("未充电");
    }

private:
    static qint64 value(const QByteArray &line)
    {
        const QByteArray rest = line.mid(line.indexOf(':') + 1);
        return rest.trimmed().split(' ').first().toLongLong();
    }

    static QString speedString(double bytesPerSec)
    {
        if (bytesPerSec >= 1073741824.0)
            return QStringLiteral("%1 GB/s").arg(bytesPerSec / 1073741824.0, 0, 'f', 1);
        if (bytesPerSec >= 1048576.0)
            return QStringLiteral("%1 MB/s").arg(bytesPerSec / 1048576.0, 0, 'f', 1);
        return QStringLiteral("%1 KB/s").arg(bytesPerSec / 1024.0, 0, 'f', 0);
    }

    static QStringList batteryPaths()
    {
        QStringList out;
        const QDir powerSupply(QStringLiteral("/sys/class/power_supply"));
        for (const QString &name : powerSupply.entryList()) {
            if (name.startsWith(QStringLiteral("BAT")))
                out << powerSupply.filePath(name);
        }
        return out;
    }

    quint64 m_cpuTotal = 0;
    quint64 m_cpuBusy = 0;
    quint64 m_rx = 0;
    quint64 m_tx = 0;
    bool m_netBaseline = false;
    QElapsedTimer m_netElapsed;
};
