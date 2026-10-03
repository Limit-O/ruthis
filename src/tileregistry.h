#pragma once

#include <QDir>
#include <QFile>
#include <QIODevice>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QStandardPaths>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

// 磁贴注册表：磁贴即插件。
//   内置磁贴位于 qrc:/tiles/<type>/（manifest.json + Tile.qml），
//   用户磁贴位于 AppDataLocation/tiles/<type>/，同名类型覆盖内置——
//   往用户目录丢一个文件夹就是一枚新磁贴，无需重编译。
//   manifest 字段：name（显示名）、category（添加菜单分组）、
//   size:[w,h]（默认尺寸）、icon（kenney 名，或完整 image://icons id）。
class TileRegistry : public QObject {
    Q_OBJECT
public:
    explicit TileRegistry(QObject *parent = nullptr)
        : QObject(parent)
    {
        rescan();
    }

    // 添加菜单数据源：[{type,name,category,w,h,icon}]，已按固定分类排序
    Q_INVOKABLE QVariantList kinds() const { return m_kinds; }

    // addTile 取默认尺寸/名称；未知类型返回空表
    Q_INVOKABLE QVariantMap kind(const QString &type) const
    {
        return m_byType.value(type).toMap();
    }

    Q_INVOKABLE QUrl source(const QString &type) const
    {
        return m_sources.value(type).value<QUrl>();
    }

    // manifest.source 配置（声明式磁贴用），无则空表
    Q_INVOKABLE QVariantMap sourceConfig(const QString &type) const
    {
        return m_sourceConf.value(type).toMap();
    }

private:
    void rescan()
    {
        const QString userRoot =
            QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/tiles");
        QStringList roots { QStringLiteral(":/tiles") };
        if (QDir(userRoot).exists())
            roots << userRoot;

        for (const QString &root : roots) {
            const QDir dir(root);
            for (const QString &t : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
                QFile f(dir.filePath(t + QStringLiteral("/manifest.json")));
                if (!f.open(QIODevice::ReadOnly))
                    continue;
                const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
                const QJsonArray sz = o.value(QStringLiteral("size")).toArray();
                const QVariantMap sourceConf =
                    o.value(QStringLiteral("source")).toObject().toVariantMap();
                const QString tileQml = dir.filePath(t + QStringLiteral("/Tile.qml"));
                // 必须可渲染：自带 Tile.qml，或声明 source 走通用渲染器，否则不算磁贴
                if (!QFile::exists(tileQml) && sourceConf.isEmpty())
                    continue;
                QVariantMap m;
                m.insert(QStringLiteral("type"), t);
                m.insert(QStringLiteral("name"),
                         o.value(QStringLiteral("name")).toString(t));
                m.insert(QStringLiteral("category"),
                         o.value(QStringLiteral("category")).toString(QStringLiteral("工具")));
                m.insert(QStringLiteral("w"), sz.at(0).toInt(1));
                m.insert(QStringLiteral("h"), sz.at(1).toInt(1));
                m.insert(QStringLiteral("icon"), o.value(QStringLiteral("icon")).toString());
                // 组件私有设置声明：[{key,name,type(text|select),options,default}]，
                // 属性面板据此自动生成编辑器，实例值存 tiles.json 的 opts 字段
                m.insert(QStringLiteral("props"),
                         o.value(QStringLiteral("props")).toArray().toVariantList());
                m_sourceConf.insert(t, sourceConf);
                m_byType.insert(t, m);
                QUrl src;
                if (QFile::exists(tileQml)) {
                    src = root.startsWith(QStringLiteral(":"))
                        ? QUrl(QStringLiteral("qrc") + root + QStringLiteral("/")
                               + t + QStringLiteral("/Tile.qml"))
                        : QUrl::fromLocalFile(tileQml);
                } else {
                    // 纯声明式磁贴：数据 + 渲染全在 manifest，渲染器由外壳提供
                    src = QUrl(QStringLiteral("qrc:/tiles/_generic/Tile.qml"));
                }
                m_sources.insert(t, src);
            }
        }

        // 固定分类顺序，未知分类排其后
        const QStringList order {
            QStringLiteral("信息"), QStringLiteral("应用"), QStringLiteral("工具")
        };
        for (const QString &cat : order) {
            for (auto it = m_byType.constBegin(); it != m_byType.constEnd(); ++it) {
                const QVariantMap m = it.value().toMap();
                if (m.value(QStringLiteral("category")) == cat)
                    m_kinds.append(m);
            }
        }
        for (auto it = m_byType.constBegin(); it != m_byType.constEnd(); ++it) {
            const QVariantMap m = it.value().toMap();
            if (!order.contains(m.value(QStringLiteral("category")).toString()))
                m_kinds.append(m);
        }
    }

    QVariantMap m_byType;
    QVariantMap m_sources;
    QVariantMap m_sourceConf;
    QVariantList m_kinds;
};
