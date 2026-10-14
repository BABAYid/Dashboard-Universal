#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QFontDatabase>
#include <QCommandLineParser>
#include <QDebug>

// Путь к ресурсам QML-модуля Dashboard (см. qt_add_qml_module в CMakeLists.txt)
static const char *kFontResource = ":/qt/qml/Dashboard/fonts/KdamThmorPro-Regular.ttf";

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("AudiDashboard"));
    QCoreApplication::setApplicationName(QStringLiteral("Dashboard"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.2"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Приборная панель Audi (Qt6/QML)"));
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption fullscreenOption(
        {QStringLiteral("f"), QStringLiteral("fullscreen")},
        QStringLiteral("Полноэкранный режим без рамки (для установки в автомобиль)."));
    parser.addOption(fullscreenOption);

    parser.process(app);

    // Шрифт приборки. Регистрируем в приложении целиком: раньше это делал FontLoader
    // в Main.qml и писал в несуществующее свойство Window.font (ошибка QML).
    // Внимание: Kdam Thmor Pro без кириллицы, поэтому он не ставится шрифтом
    // по умолчанию — в QML он подключается явно через font.family.
    const int fontId = QFontDatabase::addApplicationFont(QString::fromLatin1(kFontResource));
    if (fontId < 0)
        qWarning() << "Не удалось загрузить шрифт" << kFontResource;
    else
        qInfo() << "Шрифт приборки загружен:" << QFontDatabase::applicationFontFamilies(fontId);

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("Dashboard", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    if (parser.isSet(fullscreenOption)) {
        if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()))
            window->showFullScreen();
    }

    return app.exec();
}
