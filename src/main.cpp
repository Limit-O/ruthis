#include <QCommandLineParser>
#include <QDir>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QSurfaceFormat>

#include <LayerShellQt/Window>

#include "applist.h"
#include "iconprovider.h"
#include "launcher.h"
#include "sysinfo.h"
#include "tilestore.h"
#include "windowsbridge.h"

int main(int argc, char *argv[])
{
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
    view.rootContext()->setContextProperty(QStringLiteral("Launcher"), &launcher);
    view.rootContext()->setContextProperty(QStringLiteral("Store"), &store);
    view.rootContext()->setContextProperty(QStringLiteral("SysInfo"), &sysInfo);
    view.rootContext()->setContextProperty(QStringLiteral("Apps"), &appList);
    view.rootContext()->setContextProperty(QStringLiteral("Bridge"), &bridge);
    view.rootContext()->setContextProperty(QStringLiteral("DesktopMode"), desktopMode);
    view.rootContext()->setContextProperty(QStringLiteral("AppWindow"), &view);

    if (desktopMode) {
        // 必须在窗口 show 之前接管，QQuickView 由此变成 layer-shell surface
        auto *layer = LayerShellQt::Window::get(&view);
        layer->setLayer(LayerShellQt::Window::LayerBackground);
        // 上游头文件漏了 Q_DECLARE_OPERATORS_FOR_FLAGS，位或会退化成 int，需显式构造 QFlags
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)
                          | LayerShellQt::Window::AnchorBottom
                          | LayerShellQt::Window::AnchorLeft
                          | LayerShellQt::Window::AnchorRight);
        layer->setExclusiveZone(-1);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    }

    view.setSource(QUrl(QStringLiteral("qrc:/src/Main.qml")));
    view.engine()->addImageProvider(QStringLiteral("icons"), new IconProvider);

    if (desktopMode) {
        view.showFullScreen();
    } else {
        view.resize(1280, 800);
        view.show();
    }
    return app.exec();
}
