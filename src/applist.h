#pragma once

#include <QDir>
#include <QFileInfo>
#include <QObject>
#include <QRegularExpression>
#include <QSettings>
#include <QVariantList>
#include <QVariantMap>

// 扫描系统已安装应用（.desktop 文件），供 QML 应用选择列表使用
class AppList : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE QVariantList apps()
    {
        if (!m_cache.isEmpty())
            return m_cache;

        const QStringList dirs = {
            QStringLiteral("/usr/share/applications"),
            QDir::homePath() + QStringLiteral("/.local/share/applications")
        };
        const QString locale = QLocale::system().name();

        for (const QString &dir : dirs) {
            const QFileInfoList files =
                QDir(dir).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
            for (const QFileInfo &fi : files) {
                QSettings s(fi.absoluteFilePath(), QSettings::IniFormat);
                s.beginGroup(QStringLiteral("Desktop Entry"));
                const bool isApp = s.value(QStringLiteral("Type")).toString()
                                       == QStringLiteral("Application");
                const bool hidden = s.value(QStringLiteral("NoDisplay")).toBool()
                                    || s.value(QStringLiteral("Hidden")).toBool();
                const QString nameKey = QStringLiteral("Name[%1]").arg(locale);
                QString name = s.value(nameKey).toString();
                if (name.isEmpty())
                    name = s.value(QStringLiteral("Name")).toString();
                const QString exec = stripFieldCodes(
                    s.value(QStringLiteral("Exec")).toString());
                const QString icon = s.value(QStringLiteral("Icon")).toString();
                s.endGroup();

                if (isApp && !hidden && !name.isEmpty() && !exec.isEmpty()) {
                    QVariantMap m;
                    m.insert(QStringLiteral("name"), name);
                    m.insert(QStringLiteral("icon"), icon);
                    m.insert(QStringLiteral("exec"), exec);
                    m_cache.append(m);
                }
            }
        }
        return m_cache;
    }

private:
    // 去掉 Exec 里的字段代码（%f %F %u %U %i %c 等）
    static QString stripFieldCodes(const QString &exec)
    {
        static const QRegularExpression re(QStringLiteral("\\s%[a-zA-Z]"));
        QString out = exec;
        out.replace(re, QString());
        return out.trimmed();
    }

    QVariantList m_cache;
};
