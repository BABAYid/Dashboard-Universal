#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QFontDatabase>
#include <QCommandLineParser>
#include <QTimer>
#include <QQuickImageProvider>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutex>
#include <QMutexLocker>
#include <QDebug>
#include <QVector>

#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "can/CanBackend.h"
#include "gps/GpsBackend.h"
#include "network/NetworkServer.h"
#include "media/MediaBackend.h"
#include "speedcam/SpeedCamManager.h"
#include "WeatherProvider.h"

// Путь к ресурсам QML-модуля Dashboard (см. qt_add_qml_module в CMakeLists.txt)
static const char *kFontResource = ":/qt/qml/Dashboard/fonts/KdamThmorPro-Regular.ttf";

namespace {

// ---- Структурированные логи ----
// Пишем строки вида «2026-11-18 23:50:45.123 [INFO] текст» в файл
// (DASHBOARD_LOG_FILE, обычно /run/dashboard/app.log — tmpfs) с ротацией
// по 5 МБ → app.log.1. Утром по такому логу видно, что произошло, без
// поиска по журналу systemd. Консоль остаётся (run.sh, отладка).
QFile *g_logFile = nullptr;
QString g_logPath;
QMutex g_logMutex;
constexpr qint64 kMaxLogBytes = 5 * 1024 * 1024;

const char *levelName(QtMsgType type)
{
    switch (type) {
    case QtDebugMsg:    return "DEBUG";
    case QtInfoMsg:     return "INFO";
    case QtWarningMsg:  return "WARN";
    case QtCriticalMsg: return "ERROR";
    case QtFatalMsg:    return "FATAL";
    }
    return "INFO";
}

void rotateLog()
{
    if (!g_logFile)
        return;
    g_logFile->close();
    QFile::remove(g_logPath + QStringLiteral(".1"));
    QFile::rename(g_logPath, g_logPath + QStringLiteral(".1"));
    g_logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
}

void messageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    Q_UNUSED(ctx);
    const QString line = QStringLiteral("%1 [%2] %3\n")
        .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz")),
             QString::fromLatin1(levelName(type)), msg);
    {
        QMutexLocker lock(&g_logMutex);
        if (g_logFile && g_logFile->isOpen()) {
            if (g_logFile->size() > kMaxLogBytes)
                rotateLog();
            g_logFile->write(line.toUtf8());
            g_logFile->flush();
        }
    }
    fputs(line.toLocal8Bit().constData(), stderr);
}

// ---- sd_notify: READY/STOPPING/WATCHDOG для systemd ----
// Без libsystemd: короткая датаграмма в unix-сокет из $NOTIFY_SOCKET.
// Нужно, чтобы в unit работали Type=notify и WatchdogSec.
void systemdNotify(const QByteArray &state)
{
    const QByteArray socket = qgetenv("NOTIFY_SOCKET");
    if (socket.isEmpty())
        return;
    const int fd = ::socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return;
    sockaddr_un addr {};
    addr.sun_family = AF_UNIX;
    QByteArray path = socket;
    if (path.startsWith('@')) {          // абстрактное пространство имён
        addr.sun_path[0] = '\0';
        const int n = qMin<int>(path.size() - 1, sizeof(addr.sun_path) - 2);
        std::memcpy(addr.sun_path + 1, path.constData() + 1, n);
    } else {
        const int n = qMin<int>(path.size(), sizeof(addr.sun_path) - 1);
        std::memcpy(addr.sun_path, path.constData(), n);
    }
    ::sendto(fd, state.constData(), state.size(), MSG_NOSIGNAL,
             reinterpret_cast<sockaddr *>(&addr), sizeof(addr));
    ::close(fd);
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("AudiDashboard"));
    QCoreApplication::setApplicationName(QStringLiteral("Dashboard"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.2"));

    // ---- Структурированные логи ----
    // DASHBOARD_LOG_FILE=/run/dashboard/app.log (tmpfs, ротация 5 МБ → .1).
    // Без переменной пишем только в консоль, как раньше.
    {
        const QByteArray logPath = qgetenv("DASHBOARD_LOG_FILE");
        if (!logPath.isEmpty()) {
            g_logPath = QString::fromLocal8Bit(logPath);
            QDir().mkpath(QFileInfo(g_logPath).absolutePath());
            g_logFile = new QFile(g_logPath);
            if (g_logFile->open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
                qInstallMessageHandler(messageHandler);
                qInfo().noquote() << "Логи: файл" << g_logPath;
            } else {
                delete g_logFile;
                g_logFile = nullptr;
                qWarning() << "Логи: не открыть" << g_logPath << "— только консоль";
            }
        }
    }

    // Watchdog systemd: кормим раз в 10 с (в unit WatchdogSec=30).
    {
        auto *watchdog = new QTimer(&app);
        watchdog->setInterval(10000);
        QObject::connect(watchdog, &QTimer::timeout, []() { systemdNotify("WATCHDOG=1"); });
        watchdog->start();
    }
    QObject::connect(&app, &QCoreApplication::aboutToQuit,
                     []() { systemdNotify("STOPPING=1"); });

    // ---- WebGL в QtWebEngine (карта MapLibre) ----
    // MapLibre GL JS без WebGL не рисует ничего: карта есть, а вместо воды,
    // дорог и домов — пустой фон. Chromium по умолчанию блокирует WebGL на
    // программном рендерере (llvmpipe/Mesa) и на «подозрительных» GPU:
    // в консоли видно "ContextResult::kFatalFailure: WebGL1 blocklisted",
    // и MapLibre падает с "Failed to initialize WebGL".
    // Поэтому разрешаем WebGL на блокированных устройствах. Флаг задаётся
    // здесь, а не только в run.sh: приборка на плате стартует из systemd,
    // где run.sh не участвует. Если QTWEBENGINE_CHROMIUM_FLAGS уже задан
    // пользователем — дописываем флаг к нему, не затирая.
    {
        QByteArray flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
        if (!flags.contains("--ignore-gpu-blocklist")) {
            if (!flags.isEmpty())
                flags += ' ';
            flags += "--ignore-gpu-blocklist";
            qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);
        }
    }

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

    // GPS от gpsd (TCP 2947). Приёмника ещё нет — на столе тот же протокол
    // отдаёт tools/gps_test_server.py; при появлении железа достаточно
    // поднять gpsd на плате, код не меняется.
    GpsBackend *gps = GpsBackend::instance();
    gps->start();

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
        // DASHBOARD_DEMO_CAMERA_TYPE — код типа для проверки вида опасности
        // (102 — искусственная неровность, 22 — пешеходный переход и т. д.).
        const int typeCode = qEnvironmentVariableIntValue("DASHBOARD_DEMO_CAMERA_TYPE");
        QTimer::singleShot(5000, speedcam, [limit, typeCode]() {
            SpeedCamManager::instance()->simulateCameraAhead(limit > 0 ? limit : 60, 420,
                                                             typeCode > 0 ? typeCode : 1);
        });
    }

    QObject::connect(can, &CanBackend::gpsPositionUpdated, speedcam,
                     [speedcam](double lat, double lon, double course, double speedKmh) {
                         speedcam->checkPosition(lat, lon, course, speedKmh);
                     });
    // Основной источник координат для камер — gpsd (резерв по CAN выше
    // остаётся для совместимости, в обычной сборке кадры 0x520/0x521 не идут).
    QObject::connect(gps, &GpsBackend::positionUpdated, speedcam,
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
    // Сеть по контракту docs/integration.md: HTTP + WebSocket на одном порту.
    // Поднимаем до загрузки QML, чтобы первые же кадры телеметрии ушли клиенту.
    engine.addImageProvider(QStringLiteral("mapframe"),
                            NetworkServer::createImageProvider());
    const int netPort = NetworkServer::instance()->start();
    if (netPort <= 0)
        qWarning() << "Сеть: сервер не поднялся, интеграция с мультимедиа недоступна";
    else
        qInfo() << "Сеть: порт" << netPort;

    engine.loadFromModule("Dashboard", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    // Отладка на стенде: DASHBOARD_DEMO_TURN=left|right включает демо-поворотник
    // (то же, что стрелки на клавиатуре) — нужно для снимков и проверки
    // мигания 3D-огней без клавиатуры.
    // DASHBOARD_DEMO_LIGHTS=1 — включить фары на 3D-модели (для снимков).
    if (qEnvironmentVariableIsSet("DASHBOARD_DEMO_LIGHTS")) {
        if (auto *root = engine.rootObjects().constFirst())
            root->setProperty("debugHeadlights", true);
    }

    if (qEnvironmentVariableIsSet("DASHBOARD_DEMO_LOWBEAM")) {
        if (auto *root = engine.rootObjects().constFirst())
            root->setProperty("debugLowBeam", true);
    }

    // DASHBOARD_SKIN=genesis — запустить со вторым скином (docs/skin.md).
    // Нужно для снимков и приёмки: скины переключаются клавишей F8, а для
    // автоматической проверки нужен способ задать его при старте.
    if (qEnvironmentVariableIsSet("DASHBOARD_SKIN")) {
        if (auto *root = engine.rootObjects().constFirst()) {
            const QString skin = QString::fromLocal8Bit(qgetenv("DASHBOARD_SKIN"));
            if (skin == QStringLiteral("genesis") || skin == QStringLiteral("classic"))
                root->setProperty("skin", skin);
        }
    }

    // DASHBOARD_DEMO_MODE=5 и DASHBOARD_DEMO_SUSP=1|-1 — открыть 6-й вид
    // (подвеска) и сразу поднять/опустить кузов: удобно для снимков.
    if (qEnvironmentVariableIsSet("DASHBOARD_DEMO_MODE")) {
        if (auto *root = engine.rootObjects().constFirst()) {
            root->setProperty("centerMode", qEnvironmentVariableIntValue("DASHBOARD_DEMO_MODE"));
            if (qEnvironmentVariableIsSet("DASHBOARD_DEMO_SUSP"))
                root->setProperty("suspensionLevel", qEnvironmentVariableIntValue("DASHBOARD_DEMO_SUSP"));
        }
    }

    // DASHBOARD_INPUT_DEMO="nav,90,right,5" — проиграть события джойстика.
    // Формат: имена действий через запятую; число после имени — пауза до
    // СЛЕДУЮЩЕГО события, в 100 мс. События идут настоящим путём: собирается
    // кадр 0x530 и уходит в CanBackend::feedFrame, то есть проверяется и
    // разбор протокола, и слой ввода, а не отдельная демо-ветка в QML.
    // Имена — как у InputController: nav, back, media, radio, menu, option,
    // up, down, left, right, press, next, prev.
    const QByteArray inputDemo = qgetenv("DASHBOARD_INPUT_DEMO");
    if (!inputDemo.isEmpty()) {
        // Число в строке — пауза ПЕРЕД следующим событием, в 100 мс. Так можно
        // сдвинуть проигрыш за стартовую заставку: "100,nav" = нажать NAV
        // через 10 с, когда приборы уже проявились.
        struct Event { QByteArray name; int atMs; };
        QVector<Event> events;
        int atMs = 300;                 // первое событие — через 300 мс
        constexpr int kDefaultGapMs = 300;   // пауза между событиями по умолчанию
        const QList<QByteArray> parts = inputDemo.split(',');
        for (const QByteArray &raw : parts) {
            const QByteArray token = raw.trimmed();
            bool isNumber = false;
            const int units = token.toInt(&isNumber);
            if (isNumber) {
                atMs += units * 100;
                continue;
            }
            if (token.isEmpty())
                continue;
            events.push_back({ token, atMs });
            atMs += kDefaultGapMs;
        }

        // Имя действия → код кнопки протокола 1.4 (0 — энкодер).
        const auto codeOf = [](const QByteArray &name) -> int {
            if (name == "menu")   return 1;
            if (name == "back")   return 2;
            if (name == "option") return 3;
            if (name == "radio")  return 4;
            if (name == "media")  return 5;
            if (name == "nav")    return 6;
            if (name == "tel")    return 7;
            if (name == "up")     return 8;
            if (name == "down")   return 9;
            if (name == "left")   return 10;
            if (name == "right")  return 11;
            if (name == "press")  return 12;
            if (name == "next")   return -1;   // энкодер вперёд
            if (name == "prev")   return -2;   // энкодер назад
            return 0;
        };

        static quint8 inputCounter = 0;
        for (const Event &ev : events) {
            const int code = codeOf(ev.name);
            if (code == 0) {
                qWarning() << "DASHBOARD_INPUT_DEMO: неизвестное действие" << ev.name;
                continue;
            }
            QTimer::singleShot(ev.atMs, &app, [code]() {
                QByteArray frame(8, '\0');
                frame[0] = static_cast<char>(code < 0 ? 0x02 : 0x01);
                frame[1] = static_cast<char>(code < 0 ? 0 : code);
                frame[2] = static_cast<char>(code == -1 ? 1
                                          : code == -2 ? -1
                                          : 1);   // кнопка нажата
                frame[3] = static_cast<char>(inputCounter++);
                qInfo() << "Ввод (демо): кадр 0x530" << frame.toHex(' ');
                CanBackend::instance()->feedFrame(0x530, frame);
            });
        }
        qInfo() << "DASHBOARD_INPUT_DEMO: событий в очереди" << events.size();
    }

    const QByteArray demoTurn = qgetenv("DASHBOARD_DEMO_TURN").toLower();
    if (!demoTurn.isEmpty()) {
        if (auto *root = engine.rootObjects().constFirst()) {
            if (demoTurn == "left")
                root->setProperty("demoLeftTurn", true);
            else if (demoTurn == "right")
                root->setProperty("demoRightTurn", true);
        }
    }

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
                                 // Первый кадр на экране — сервис «готов»
                                 // (Type=notify в systemd).
                                 systemdNotify("READY=1");
                                 QMetaObject::invokeMethod(root, [root]() {
                                     root->setProperty("firstFrameRendered", true);
                                 }, Qt::QueuedConnection);
                             }, Qt::DirectConnection);
        }
    }
    return app.exec();
}
