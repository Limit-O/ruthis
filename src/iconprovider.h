#pragma once

#include <QIcon>
#include <QImage>
#include <QPixmap>
#include <QQuickImageProvider>
#include <QUrl>

// 图标路由：image://icons/<id>
//   id 为图标主题名（如 utilities-terminal）→ 从已装图标主题取
//   id 为本地文件路径（如 /home/x/icon.png）→ 直接加载用户自定义图标
//   注意：QIcon 主题引擎非线程安全，QML 侧图标 Image 必须同步加载（勿设 asynchronous: true）
class IconProvider : public QQuickImageProvider {
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}

    QPixmap requestPixmap(const QString &id, QSize *size,
                          const QSize &requestedSize) override
    {
        const QSize sz = requestedSize.isEmpty() ? QSize(64, 64) : requestedSize;
        QPixmap pm;

        if (id.startsWith(QLatin1Char('/')) || id.startsWith(QStringLiteral("file://"))) {
            QString path = id;
            if (path.startsWith(QStringLiteral("file://")))
                path = QUrl(path).toLocalFile();
            pm = QPixmap::fromImage(QImage(path));
        } else {
            QIcon icon = QIcon::fromTheme(id);
            if (icon.isNull())
                icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
            pm = icon.pixmap(sz);
        }

        if (pm.isNull()) {
            pm = QPixmap(sz);
            pm.fill(Qt::transparent);
        }
        if (size)
            *size = pm.size();
        return pm;
    }
};
