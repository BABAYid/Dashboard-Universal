#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QFontDatabase>
#include <QCommandLineParser>
#include <QTimer>
#include <QDebug>

#include "can/CanBackend.h"
#include "media/MediaBackend.h"
#include "speedcam/SpeedCamManager.h"
#include "WeatherProvider.h"

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

    QCommandLineOption canOption(
        QStringLiteral("can"),
        QStringLiteral("Имя CAN-интерфейса SocketCAN (по умолчанию can0)."),
        QStringLiteral("iface"), QStringLiteral("can0"));
    parser.addOption(canOption);

    QCommandLineOption mockOption(
        QStringLiteral("mock"),
        QStringLiteral("Демо-режим: данные генерируются программно, CAN не нужен."));
    parser.addOption(mockOption);

    // Отключает кинематографичный запуск с 3D-машиной: на слабом железе
    // (или если 3D не завёлся) приборка стартует по-старому, за 2.5 с.
    // QML читает флаг сам из аргументов приложения (см. Main.qml); здесь он
    // объявлен, чтобы попал в --help и QCommandLineParser его принял.
    QCommandLineOption no3dOption(
        QStringLiteral("no-3d"),
        QStringLiteral("Не запускать 3D-заставку с машиной при старте."));
    parser.addOption(no3dOption);

    parser.process(app);

    // Поднимаем приём данных до загрузки QML, чтобы окно сразу получило значения.
    CanBackend *can = CanBackend::instance();
    can->setInterfaceName(parser.value(canOption));
    can->setMockMode(parser.isSet(mockOption));
    can->start();

    // Погода за окном: Open-Meteo раз в 10 минут; в --mock — демо-цикл
    // дождь → снег → ясно, чтобы эффект было видно без сети.
    WeatherProvider *weather = WeatherProvider::instance();
    weather->setMockMode(parser.isSet(mockOption));
    weather->start();

    // Что играет в мультимедиа-центре: маленький JSON по сети, опрос раз
    // в секунду. Без медиацентра (стол, отладка) виджет просто пишет
    // «нет данных»; в --mock показываются выдуманные треки.
    MediaBackend *media = MediaBackend::instance();
    media->setMockMode(parser.isSet(mockOption));
    media->start();

    // База камер (Smart Driver). Файл читается в фоновом потоке, поэтому
    // запуск приборки не задерживается даже на большой базе.
    // Связка с GPS: каждое обновление позиции по CAN (кадры 0x520/0x521)
    // передаётся в checkPosition() — там считается расстояние до камеры.
    SpeedCamManager *speedcam = SpeedCamManager::instance();
    speedcam->start();
    // Отладка на стенде: DASHBOARD_DEMO_CAMERA=1 через 5 секунд ставит
    // демо-камеру впереди машины — то же, что кнопка «Симулировать камеру»
    // в настройках и клавиша C. Нужно для проверки предупреждения без
    // реальной базы и без клавиатуры (например, со снимком экрана).
    // Значение переменной — ограничение демо-камеры (по умолчанию 60 км/ч);
    // DASHBOARD_DEMO_CAMERA=200 даёт «без превышения», чтобы баннер не мигал.
    if (qEnvironmentVariableIsSet("DASHBOARD_DEMO_CAMERA")) {
        const int limit = qEnvironmentVariableIntValue("DASHBOARD_DEMO_CAMERA");
        QTimer::singleShot(5000, speedcam, [limit]() {
            SpeedCamManager::instance()->simulateCameraAhead(limit > 0 ? limit : 60, 420);
        });
    }

    QObject::connect(can, &CanBackend::gpsPositionUpdated, speedcam,
                     [speedcam](double lat, double lon, double course, double speedKmh) {
                         speedcam->checkPosition(lat, lon, course, speedKmh);
                     });

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

    // Отладочный снимок экрана: DASHBOARD_SHOT=/путь/файл.png сохраняет окно
    // и завершает работу. DASHBOARD_SHOT_DELAY — задержка в мс (по умолчанию 3000).
    // Удобно для проверки макета на устройстве без монитора.
    const QByteArray shotPath = qgetenv("DASHBOARD_SHOT");
    if (!shotPath.isEmpty()) {
        const int delay = qgetenv("DASHBOARD_SHOT_DELAY").toInt();
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QTimer::singleShot(delay > 0 ? delay : 3000, &app, [window, shotPath]() {
            bool ok = false;
            if (window)
                ok = window->grabWindow().save(QString::fromLocal8Bit(shotPath));
            qInfo() << "Снимок экрана:" << shotPath << (ok ? "сохранён" : "НЕ сохранён");
            QCoreApplication::quit();
        });
    }

    // Первый отрисованный кадр: сообщаем QML, что картинка реально появилась
    // на экране. На слабом железе (программный OpenGL) первый кадр приходит
    // через несколько секунд, а стартовая 3D-заставка длится 4 с — если
    // запускать её сразу при загрузке QML, зритель видит уже готовую приборку
    // и заставку не видит вовсе (казалось, что 3D-анимация пропала).
    // afterRendering приходит из потока рендера — ставим свойство у корневого
    // объекта через queer-вызов, в потоке GUI.
    if (auto *root = engine.rootObjects().constFirst()) {
        if (auto *win = qobject_cast<QQuickWindow *>(root)) {
            QObject::connect(win, &QQuickWindow::afterRendering, win,
                             [root]() {
                                 static bool alreadyReported = false;
                                 if (alreadyReported)
                                     return;
                                 alreadyReported = true;
                                 QMetaObject::invokeMethod(root, [root]() {
                                     root->setProperty("firstFrameRendered", true);
                                 }, Qt::QueuedConnection);
                             }, Qt::DirectConnection);
        }
    }
    return app.exec();
}
