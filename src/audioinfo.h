#pragma once

#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QObject>

// 音量磁贴后端：默认输出设备的音量/静音。
//   首选 wpctl（WirePlumber，PipeWire 会话的标配），缺失时回退 pactl。
//   采样经 QProcess 异步执行，不阻塞 GUI 线程；2s 轮询 + 设置后快速回读。
class AudioInfo : public QObject {
    Q_OBJECT
    Q_PROPERTY(int volume READ volume NOTIFY audioChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY audioChanged)
public:
    using QObject::QObject;

    explicit AudioInfo(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_wpctl = !QStandardPaths::findExecutable(QStringLiteral("wpctl")).isEmpty();
        m_pactl = !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty();
        connect(&m_proc, &QProcess::finished, this, &AudioInfo::onFinished);
        connect(&m_timer, &QTimer::timeout, this, &AudioInfo::refresh);
        m_timer.start(2000);
        QMetaObject::invokeMethod(this, &AudioInfo::refresh, Qt::QueuedConnection);
    }

    int volume() const { return m_volume; }
    bool muted() const { return m_muted; }

    Q_INVOKABLE void setVolume(int pct)
    {
        pct = qBound(0, pct, 100);
        if (pct != m_volume) {   // 乐观更新，拖动滑条不发涩
            m_volume = pct;
            emit audioChanged();
        }
        if (m_wpctl)
            QProcess::startDetached(QStringLiteral("wpctl"),
                {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                 QString::number(pct / 100.0, 'f', 2)});
        else if (m_pactl)
            QProcess::startDetached(QStringLiteral("pactl"),
                {QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"),
                 QString::number(pct) + QStringLiteral("%")});
        scheduleRefresh();
    }

    Q_INVOKABLE void toggleMute()
    {
        if (m_wpctl)
            QProcess::startDetached(QStringLiteral("wpctl"),
                {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                 QStringLiteral("toggle")});
        else if (m_pactl)
            QProcess::startDetached(QStringLiteral("pactl"),
                {QStringLiteral("set-sink-mute"), QStringLiteral("@DEFAULT_SINK@"),
                 QStringLiteral("toggle")});
        scheduleRefresh();
    }

signals:
    void audioChanged();

private:
    enum Stage { Wpctl, PactlVol, PactlMute };

    void scheduleRefresh()
    {
        QTimer::singleShot(250, this, &AudioInfo::refresh);
    }

    void refresh()
    {
        if (m_proc.state() != QProcess::NotRunning)
            return;
        if (m_wpctl) {
            m_stage = Wpctl;
            m_proc.start(QStringLiteral("wpctl"),
                {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")});
        } else if (m_pactl) {
            m_stage = PactlVol;
            m_proc.start(QStringLiteral("pactl"),
                {QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")});
        }
    }

    void onFinished(int, QProcess::ExitStatus status)
    {
        if (status != QProcess::NormalExit)
            return;
        const QString out = QString::fromUtf8(m_proc.readAllStandardOutput());
        if (m_stage == Wpctl) {
            // 形如 "Volume: 0.45 [MUTED]"
            const int colon = out.indexOf(':');
            if (colon >= 0) {
                const QString num = out.mid(colon + 1).trimmed().split(' ').first();
                const int v = int(num.toFloat() * 100 + 0.5);
                if (v != m_volume) {
                    m_volume = v;
                    emit audioChanged();
                }
                const bool mu = out.contains(QStringLiteral("MUTED"));
                if (mu != m_muted) {
                    m_muted = mu;
                    emit audioChanged();
                }
            }
        } else if (m_stage == PactlVol) {
            // 形如 "Volume: front-left: 29490 /  45% / -18.00 dB ..."
            int pct = -1;
            const QList<QStringView> tokens =
                QStringView{out}.split(u' ', Qt::SkipEmptyParts);
            for (const QStringView t : tokens) {
                if (t.endsWith(u'%')) {
                    pct = t.left(t.size() - 1).toInt();
                    break;
                }
            }
            if (pct >= 0 && pct != m_volume) {
                m_volume = pct;
                emit audioChanged();
            }
            // 无 wpctl 时静音状态要接第二条命令查询
            if (m_pactl && m_proc.state() == QProcess::NotRunning) {
                m_stage = PactlMute;
                m_proc.start(QStringLiteral("pactl"),
                    {QStringLiteral("get-sink-mute"), QStringLiteral("@DEFAULT_SINK@")});
            }
        } else if (m_stage == PactlMute) {
            const bool mu = out.contains(QStringLiteral("yes"));
            if (mu != m_muted) {
                m_muted = mu;
                emit audioChanged();
            }
        }
    }

    QProcess m_proc;
    QTimer m_timer;
    Stage m_stage = Wpctl;
    int m_volume = 0;
    bool m_muted = false;
    bool m_wpctl = false;
    bool m_pactl = false;
};
