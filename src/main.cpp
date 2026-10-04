#include <QCommandLineParser>
#include <QDateTime>
#include <QDir>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QSurfaceFormat>
#include <QTimer>

#include <LayerShellQt/Window>

#include "applist.h"
#include "audioinfo.h"
#include "datasource.h"
#include "iconprovider.h"
#include "launcher.h"
#include "mediainfo.h"
#include "sysinfo.h"
#include "tilestore.h"
#include "tileregistry.h"
#include "windowsbridge.h"

// 本会话的终端会吞掉 stderr，QML/Qt 警告统一改写进调试日志文件
static void fileMessageHandler(QtMsgType type, const QMessageLogContext &,
                               const QString &msg)
{
    static const char *levels[] = { "debug", "warn", "crit", "fatal" };
    QFile f(QStringLiteral("/tmp/ruthis-debug.log"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Append))
        f.write(QStringLiteral("[%1] %2\n").arg(QLatin1String(levels[type]), msg).toUtf8());
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(fileMessageHandler);
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("ruthis"));

    // 更名迁移：把旧 ~/.config/wanwu 的磁贴与设置搬过来
    const QDir oldCfg(QDir::homePath() + QStringLiteral("/.config/wanwu"));
    const QDir newCfg(QDir::homePath() + QStringLiteral("/.config/ruthis"));
    if (oldCfg.exists() && !newCfg.exists())
        QDir::home().rename(oldCfg.absolutePath(), newCfg.absolutePath());

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("ruthis — 万物磁贴桌面"));
    parser.addHelpOption();
    const QCommandLineOption desktopOption(
        QStringList{QStringLiteral("d"), QStringLiteral("desktop")},
        QStringLiteral("以 layer-shell 桌面层模式运行"));
    parser.addOption(desktopOption);
    const QCommandLineOption openSettingsOption(
        QStringLiteral("open-settings"),
        QStringLiteral("启动时打开设置面板（调试用）"));
    parser.addOption(openSettingsOption);
    const QCommandLineOption openAddOption(
        QStringLiteral("open-add"),
        QStringLiteral("启动时打开添加磁贴面板（调试用）"));
    parser.addOption(openAddOption);
    const QCommandLineOption openFlipOption(
        QStringLiteral("open-flip"),
        QStringLiteral("启动时进入图层翻转模式（调试用）"));
    parser.addOption(openFlipOption);
    const QCommandLineOption devOption(
        QStringLiteral("dev"),
        QStringLiteral("从源码目录加载 QML，改动即热重载（开发用）"));
    parser.addOption(devOption);
    const QCommandLineOption testMenuOption(
        QStringLiteral("test-menu"),
        QStringLiteral("调试：合成右键打开菜单并点按置顶项，自截两帧验证"));
    parser.addOption(testMenuOption);
    parser.process(app);
    const bool desktopMode = parser.isSet(desktopOption);

    QQuickView view;
    QSurfaceFormat fmt = view.format();
    fmt.setAlphaBufferSize(8);
    view.setFormat(fmt);
    view.setTitle(QStringLiteral("ruthis"));
    view.setColor(Qt::transparent);
    view.setResizeMode(QQuickView::SizeRootObjectToView);

    Launcher launcher;
    TileStore store;
    SysInfo sysInfo;
    AppList appList;
    WindowsBridge bridge;
    MediaInfo mediaInfo;
    AudioInfo audioInfo;
    TileRegistry tileRegistry;
    // --dev 时把源码磁贴目录加进搜索路径（优先于用户目录），改完即热重载
    if (parser.isSet(devOption))
        tileRegistry.addSearchDir(QStringLiteral(RUTHIS_SOURCE_DIR)
                                  + QStringLiteral("/tiles"));
    TileSources tileSources(&tileRegistry);
    view.rootContext()->setContextProperty(QStringLiteral("Launcher"), &launcher);
    view.rootContext()->setContextProperty(QStringLiteral("Store"), &store);
    view.rootContext()->setContextProperty(QStringLiteral("SysInfo"), &sysInfo);
    view.rootContext()->setContextProperty(QStringLiteral("Apps"), &appList);
    view.rootContext()->setContextProperty(QStringLiteral("Bridge"), &bridge);
    view.rootContext()->setContextProperty(QStringLiteral("Media"), &mediaInfo);
    view.rootContext()->setContextProperty(QStringLiteral("Audio"), &audioInfo);
    view.rootContext()->setContextProperty(QStringLiteral("TileRegistry"), &tileRegistry);
    view.rootContext()->setContextProperty(QStringLiteral("Sources"), &tileSources);
    view.rootContext()->setContextProperty(QStringLiteral("DesktopMode"), desktopMode);
    view.rootContext()->setContextProperty(QStringLiteral("AppWindow"), &view);

    if (desktopMode) {
        // 必须在窗口 show 之前接管，QQuickView 由此变成 layer-shell surface
        auto *layer = LayerShellQt::Window::get(&view);
        layer->setLayer(LayerShellQt::Window::LayerBackground);
        // scope="desktop"：KWin 据此把窗口类型判为 Desktop（桌面背景），
        // Overview/桌面网格等效果才会把它当壁纸背景而非普通窗口缩放
        layer->setScope(QStringLiteral("desktop"));
        // 上游头文件漏了 Q_DECLARE_OPERATORS_FOR_FLAGS，位或会退化成 int，需显式构造 QFlags
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)
                          | LayerShellQt::Window::AnchorBottom
                          | LayerShellQt::Window::AnchorLeft
                          | LayerShellQt::Window::AnchorRight);
        layer->setExclusiveZone(-1);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    }

    // provider 必须先于 setSource 注册：QML 里同步加载的 image://icons/ 请求
    // 会在 setSource 创建场景的当场发出，晚注册会让图标全部静默加载失败
    view.engine()->addImageProvider(QStringLiteral("icons"), new IconProvider);
    const QUrl source = parser.isSet(devOption)
        ? QUrl::fromLocalFile(QStringLiteral(RUTHIS_SOURCE_DIR) + QStringLiteral("/src/Main.qml"))
        : QUrl(QStringLiteral("qrc:/src/Main.qml"));
    view.setSource(source);

    if (parser.isSet(devOption)) {
        // 热重载：编辑器常以"替换文件"方式保存，inode 会变，触发后要重新挂监视
        const QString qmlPath =
            QStringLiteral(RUTHIS_SOURCE_DIR) + QStringLiteral("/src/Main.qml");
        auto *watcher = new QFileSystemWatcher(&app);
        watcher->addPath(qmlPath);
        // 磁贴插件目录也在监视范围内
        const QDir tilesDir(QStringLiteral(RUTHIS_SOURCE_DIR) + QStringLiteral("/tiles"));
        for (const QString &sub : tilesDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            const QString tqml = tilesDir.filePath(sub + QStringLiteral("/Tile.qml"));
            if (QFile::exists(tqml))
                watcher->addPath(tqml);
        }
        QObject::connect(watcher, &QFileSystemWatcher::fileChanged, &app,
                         [&view, &app, qmlPath](const QString &path) {
                             view.engine()->clearComponentCache();
                             view.setSource(QUrl::fromLocalFile(qmlPath));
                             QFileSystemWatcher *w = app.findChild<QFileSystemWatcher *>();
                             if (w && !w->files().contains(path))
                                 w->addPath(path);
                         });
    }

    if (desktopMode) {
        view.showFullScreen();
    } else {
        view.resize(1280, 800);
        view.show();
    }

    // --test-menu：向窗口投递真实鼠标事件，验证"右键→菜单→置顶"整条链路
    if (parser.isSet(testMenuOption)) {
        // QML 无参函数经 QMetaMethod 调用（invokeMethod 的 char* 重载 Qt 6.11 已不匹配）
        const auto callQml = [&view](const char *sig) -> QVariant {
            QVariant ret;
            QQuickItem *rootItem = view.rootObject();
            const int idx = rootItem->metaObject()->indexOfMethod(sig);
            if (idx >= 0)
                rootItem->metaObject()->method(idx).invoke(rootItem, Q_RETURN_ARG(QVariant, ret));
            return ret;
        };
        const auto click = [&view](const QPointF &p, Qt::MouseButton button) {
            QMouseEvent press(QEvent::MouseButtonPress, p, p, button, button, Qt::NoModifier);
            QGuiApplication::sendEvent(&view, &press);
            QMouseEvent release(QEvent::MouseButtonRelease, p, p, button, Qt::NoButton, Qt::NoModifier);
            QGuiApplication::sendEvent(&view, &release);
        };
        QTimer::singleShot(800, &view, [&]() {
            const QVariantList c = callQml("debugTileCenter()").toList();
            if (c.size() != 2) {
                qWarning() << "debugTileCenter 失败";
                QCoreApplication::quit();
                return;
            }
            click(QPointF(c[0].toReal(), c[1].toReal()), Qt::RightButton);
            QTimer::singleShot(500, &view, [&]() {
                view.grabWindow().save(QStringLiteral("/tmp/ruthis-menu.png"));
                const QVariantList b = callQml("debugPinBtnCenter()").toList();
                if (b.size() != 2) {
                    qWarning() << "菜单未打开（debugPinBtnCenter 失败）";
                    QCoreApplication::quit();
                    return;
                }
                click(QPointF(b[0].toReal(), b[1].toReal()), Qt::LeftButton);
                QTimer::singleShot(500, &view, [&]() {
                    view.grabWindow().save(QStringLiteral("/tmp/ruthis-menu2.png"));
                    QCoreApplication::quit();
                });
            });
        });
    }
    return app.exec();
}
