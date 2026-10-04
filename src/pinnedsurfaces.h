#pragma once

// 置顶磁贴覆盖面管理器：每枚置顶磁贴一个独立 LayerTop 小窗。
// 不用全屏透明层+输入 mask——mask 在 KWin 真机上不可靠（会把整个桌面左键吃掉），
// 独立小窗的输入天然限定在自己的矩形内，其余区域命中真实窗口。

#include <QHash>
#include <QMargins>
#include <QObject>
#include <QQmlContext>
#include <QQuickView>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <LayerShellQt/Window>

#include "applist.h"
#include "audioinfo.h"
#include "datasource.h"
#include "iconprovider.h"
#include "launcher.h"
#include "mediainfo.h"
#include "sysinfo.h"
#include "tilestore.h"
#include "windowsbridge.h"
#include "tileregistry.h"

// 每个小窗的数据载体：内容 json 与外观 settings 均可原地更新（免重载窗口）
class PinnedTileData : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString json READ json WRITE setJson NOTIFY jsonChanged)
    Q_PROPERTY(QString settings READ settings WRITE setSettings NOTIFY settingsChanged)
public:
    explicit PinnedTileData(const QString &id, QObject *parent = nullptr)
        : QObject(parent), m_id(id) {}
    QString id() const { return m_id; }
    QString json() const { return m_json; }
    void setJson(const QString &v) { if (m_json != v) { m_json = v; emit jsonChanged(); } }
    QString settings() const { return m_settings; }
    void setSettings(const QString &v) { if (m_settings != v) { m_settings = v; emit settingsChanged(); } }
signals:
    void jsonChanged();
    void settingsChanged();
private:
    QString m_id, m_json, m_settings;
};

class PinnedSurfaces : public QObject {
    Q_OBJECT
public:
    struct Services {
        Launcher *launcher;
        TileStore *store;
        SysInfo *sys;
        AppList *apps;
        WindowsBridge *bridge;
        MediaInfo *media;
        AudioInfo *audio;
        TileRegistry *registry;
        TileSources *sources;
    };

    PinnedSurfaces(bool desktop, const Services &services, QObject *parent = nullptr)
        : QObject(parent), m_desktop(desktop), m_services(services) {}

    // 主面在磁贴/外观变化后调用：增删改对应的置顶小窗
    Q_INVOKABLE void sync(const QVariantList &tiles)
    {
        m_services.store->log(QStringLiteral("[pin] sync %1 -> %2").arg(m_views.size()).arg(tiles.size()));
        QSet<QString> alive;
        for (const auto &v : tiles) {
            const QVariantMap t = v.toMap();
            const QString id = t.value(QStringLiteral("id")).toString();
            alive.insert(id);
            PinnedTileData *data = m_data.value(id, nullptr);
            if (!data) {
                data = new PinnedTileData(id, this);
                m_data.insert(id, data);
            }
            data->setJson(t.value(QStringLiteral("json")).toString());
            data->setSettings(t.value(QStringLiteral("settings")).toString());

            const int x = t.value(QStringLiteral("x")).toInt();
            const int y = t.value(QStringLiteral("y")).toInt();
            const int w = t.value(QStringLiteral("w")).toInt();
            const int h = t.value(QStringLiteral("h")).toInt();
            QQuickView *view = m_views.value(id, nullptr);
            if (!view) {
                view = createView(data, x, y, w, h);
                m_views.insert(id, view);
            }
            if (m_desktop) {
                // 锚定左上角 + margin 定位到网格坐标
                LayerShellQt::Window::get(view)->setMargins(QMargins(x, y, 0, 0));
                view->resize(w, h);
            } else {
                view->setGeometry(x, y, w, h);
            }
        }
        const QStringList ids = m_views.keys();
        for (const QString &id : ids) {
            if (alive.contains(id))
                continue;
            m_views.value(id)->deleteLater();
            m_views.remove(id);
            m_data.value(id)->deleteLater();
            m_data.remove(id);
        }
    }

    // 置顶磁贴上的右键 = 取消置顶回主面
    Q_INVOKABLE void unpin(const QString &id) { emit unpinRequested(id); }

signals:
    void unpinRequested(const QString &id);

private:
    QQuickView *createView(PinnedTileData *data, int x, int y, int w, int h)
    {
        m_services.store->log(QStringLiteral("[pin] create %1 @%2,%3 %4x%5")
                                  .arg(data->id()).arg(x).arg(y).arg(w).arg(h));
        auto *view = new QQuickView();
        QSurfaceFormat fmt = view->format();
        fmt.setAlphaBufferSize(8);
        view->setFormat(fmt);
        view->setColor(Qt::transparent);
        view->setTitle(QStringLiteral("ruthis pinned"));
        view->setResizeMode(QQuickView::SizeRootObjectToView);
        auto *ctx = view->rootContext();
        ctx->setContextProperty(QStringLiteral("OverlayTileData"), data);
        ctx->setContextProperty(QStringLiteral("PinnedSurfaces"), this);
        ctx->setContextProperty(QStringLiteral("DesktopMode"), m_desktop);
        ctx->setContextProperty(QStringLiteral("Launcher"), m_services.launcher);
        ctx->setContextProperty(QStringLiteral("Store"), m_services.store);
        ctx->setContextProperty(QStringLiteral("SysInfo"), m_services.sys);
        ctx->setContextProperty(QStringLiteral("Apps"), m_services.apps);
        ctx->setContextProperty(QStringLiteral("Bridge"), m_services.bridge);
        ctx->setContextProperty(QStringLiteral("Media"), m_services.media);
        ctx->setContextProperty(QStringLiteral("Audio"), m_services.audio);
        ctx->setContextProperty(QStringLiteral("TileRegistry"), m_services.registry);
        ctx->setContextProperty(QStringLiteral("Sources"), m_services.sources);
        view->engine()->addImageProvider(QStringLiteral("icons"), new IconProvider);
        view->setSource(QUrl(QStringLiteral("qrc:/src/TileHost.qml")));
        if (m_desktop) {
            auto *layer = LayerShellQt::Window::get(view);
            layer->setLayer(LayerShellQt::Window::LayerTop);
            layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)
                              | LayerShellQt::Window::AnchorLeft);
            layer->setExclusiveZone(-1);
            layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            view->setGeometry(0, 0, w, h);
            view->showFullScreen();
        } else {
            view->setGeometry(x, y, w, h);
            view->show();
        }
        return view;
    }

    bool m_desktop;
    Services m_services;
    QHash<QString, QQuickView *> m_views;
    QHash<QString, PinnedTileData *> m_data;
};
