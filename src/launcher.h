#pragma once

#include <QDir>
#include <QProcess>

#include <functional>

class Launcher : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void launch(const QString &program) const
    {
        QProcess::startDetached(program, QStringList{});
    }

    // 用 kdialog 弹出 KDE 原生文件选择对话框（Dolphin 那套）
    Q_INVOKABLE void pickImageFile()
    {
        startPick(QStringLiteral("选择壁纸图片"),
                  QStringLiteral("*.png *.jpg *.jpeg *.webp *.bmp"),
                  [this](const QString &p) { emit filePicked(p); });
    }

    Q_INVOKABLE void pickIconFile()
    {
        startPick(QStringLiteral("选择图标图片"),
                  QStringLiteral("*.png *.jpg *.jpeg *.svg *.svgz *.webp *.bmp"),
                  [this](const QString &p) { emit iconPicked(p); });
    }

signals:
    void filePicked(const QString &path);
    void iconPicked(const QString &path);

private:
    void startPick(const QString &title, const QString &filter,
                   const std::function<void(const QString &)> &onPicked)
    {
        auto *proc = new QProcess(this);
        connect(proc, &QProcess::finished, this,
            [onPicked, proc](int code, QProcess::ExitStatus) {
                if (code == 0) {
                    const QString path = QString::fromLocal8Bit(
                        proc->readAllStandardOutput()).trimmed();
                    if (!path.isEmpty())
                        onPicked(path);
                }
                proc->deleteLater();
            });
        proc->start(QStringLiteral("kdialog"),
            {QStringLiteral("--title"), title,
             QStringLiteral("--getopenfilename"), QDir::homePath(), filter});
    }
};
