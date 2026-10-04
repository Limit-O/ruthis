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

// 磁贴注册表：磁贴即插件，一切磁贴都从磁盘目录加载（不编入二进制）。
//   搜索目录内每个 <type>/ 子目录 = 一枚磁贴：
//     manifest.json（必须）+ Tile.qml（组件式）或 manifest.source（声明式），
//     二者皆无则不算磁贴。后加入的搜索目录覆盖先加入的同名类型。
//   搜索目录：
//     ~/.local/share/ruthis/tiles/   用户磁贴（官方磁贴安装于此，见 scripts/install-tiles.sh）
//     --dev 时追加源码 tiles/ 目录，改完即热重载
//   manifest 字段：
//     name（显示名）、category（添加菜单分组）、size:[w,h]（默认尺寸）、
//     icon（kenney 名或完整 image://icons id）、api（接口版本），
//     props:[{key,name,type(text|select|toggle),options,default}]（组件私有设置）、
//     source（声明式数据源，见 docs/tiles.md）
class TileRegistry : public QObject {
    Q_OBJECT
public:
    explicit TileRegistry(QObject *parent = nullptr)
        : QObject(parent)
    {
        addSearchDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                     + QStringLiteral("/tiles"));
    }

    // 追加搜索目录，后加入者优先（同名类型覆盖）。--dev 会追加源码 tiles/ 目录。
    Q_INVOKABLE void addSearchDir(const QString &dir)
    {
        scan(dir);
        rebuildKinds();
    }

    // 添加菜单数据源：[{type,name,category,w,h,icon,props}]，已按固定分类排序
    Q_INVOKABLE QVariantList kinds() const { return m_kinds; }

    // addTile 取默认尺寸/名称/props；未知类型返回空表
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
    void scan(const QString &root)
    {
        const QDir dir(root);
        if (!dir.exists())
            return;
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
            m.insert(QStringLiteral("props"),
                     o.value(QStringLiteral("props")).toArray().toVariantList());
            m_sourceConf.insert(t, sourceConf);
            m_byType.insert(t, m);
            QUrl src;
            if (QFile::exists(tileQml)) {
                src = QUrl::fromLocalFile(tileQml);
            } else {
                // 纯声明式磁贴：数据 + 渲染全在 manifest，渲染器由外壳提供
                src = QUrl(QStringLiteral("qrc:/tiles/_generic/Tile.qml"));
            }
            m_sources.insert(t, src);
        }
    }

    void rebuildKinds()
    {
        m_kinds.clear();
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
