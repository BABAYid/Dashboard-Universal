// ============================================================================
//  Тест базы камер (SpeedCamManager): разбор speedcam.txt, гаверсинус,
//  фильтры «впереди/по направлению камеры» и демо-камера.
//
//  Сборка и запуск:
//      cmake -S Dashboard -B build -DDASHBOARD_BUILD_TESTS=ON
//      cmake --build build --target test_speedcam
//      ./build/test_speedcam
// ============================================================================

#include "SpeedCamManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QTemporaryDir>
#include <QTextStream>
#include <QTimer>
#include <QtMath>

static int g_failures = 0;

static void check(bool ok, const QString &what)
{
    if (ok)
        qInfo().noquote() << "  ок  " << what;
    else {
        ++g_failures;
        qWarning().noquote() << "  ОШИБКА:" << what;
    }
}

static void checkNear(double actual, double expected, double tolerance, const QString &what)
{
    const bool ok = std::fabs(actual - expected) <= tolerance;
    check(ok, ok ? what
                 : QStringLiteral("%1 — получено %2, ожидалось %3 ± %4")
                       .arg(what).arg(actual).arg(expected).arg(tolerance));
}

// Широта/долгота точки на заданном расстоянии (метры) по азимуту (градусы).
static void offset(double lat, double lon, double meters, double bearingDeg,
                   double *outLat, double *outLon)
{
    const double rad = qDegreesToRadians(bearingDeg);
    *outLat = lat + (meters * std::cos(rad)) / 111320.0;
    *outLon = lon + (meters * std::sin(rad)) / (111320.0 * std::cos(qDegreesToRadians(lat)));
}

static QString writeBase(const QTemporaryDir &dir, const QString &name, const QStringList &lines)
{
    const QString path = dir.filePath(name);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return QString();
    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    for (const QString &line : lines)
        out << line << '\n';
    return path;
}

// Загружает базу в отдельный экземпляр менеджера и ждёт окончания чтения
// (файл читается в фоновом потоке, поэтому ждём сигнал, а не sleep).
static SpeedCamManager *loadManager(const QString &path)
{
    qputenv("DASHBOARD_SPEEDCAM", path.toLocal8Bit());
    auto *manager = new SpeedCamManager(nullptr);
    QEventLoop loop;
    QObject::connect(manager, &SpeedCamManager::loadedChanged, &loop, &QEventLoop::quit);
    QTimer::singleShot(5000, &loop, &QEventLoop::quit);   // страховка от зависания
    manager->start();
    if (manager->loading())
        loop.exec();
    return manager;
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("AudiDashboardTest"));
    QCoreApplication::setApplicationName(QStringLiteral("SpeedCamTest"));

    QTemporaryDir dir;
    if (!dir.isValid()) {
        qWarning() << "Не удалось создать временную папку";
        return 1;
    }

    const double lat0 = 55.7520;
    const double lon0 = 37.6175;

    // ---------------------------------------------------------------- разбор
    qInfo().noquote() << "Разбор файла и загрузка в фоне";
    {
        const QString path = writeBase(dir, QStringLiteral("parse.txt"), {
            QStringLiteral("# комментарий"),
            QStringLiteral(""),
            QStringLiteral("37.6200,55.7550,1,60,1,90"),     // полная строка
            QStringLiteral("37,6210;55,7560;2;40"),          // точка с запятой, 4 поля
            QStringLiteral("мусор,строка,без,чисел"),
            QStringLiteral("37.6300,55.7600,5,0"),           // без ограничения
        });
        SpeedCamManager *m = loadManager(path);
        check(m->loaded(), QStringLiteral("база загружена"));
        check(m->count() == 3, QStringLiteral("точек 3 (мусор и комментарии отброшены)"));
        check(m->statusText().contains(QStringLiteral("3")),
              QStringLiteral("в статусе есть число точек: %1").arg(m->statusText()));
        delete m;
    }

    // ------------------------------------------------- расстояние и скорость
    qInfo().noquote() << "Расстояние до камеры и превышение";
    {
        double camLat, camLon;
        offset(lat0, lon0, 334.0, 0.0, &camLat, &camLon);   // ровно на север
        const QString path = writeBase(dir, QStringLiteral("north.txt"), {
            QStringLiteral("%1,%2,1,60,0,0").arg(camLon, 0, 'f', 6).arg(camLat, 0, 'f', 6),
        });
        SpeedCamManager *m = loadManager(path);

        m->checkPosition(lat0, lon0, 0.0, 80.0);            // едем на север 80 км/ч
        check(m->cameraActive(), QStringLiteral("камера в 334 м впереди — предупреждение есть"));
        checkNear(m->cameraDistance(), 334.0, 5.0, QStringLiteral("расстояние по гаверсинусу"));
        check(m->cameraSpeedLimit() == 60, QStringLiteral("ограничение 60 км/ч"));
        check(m->cameraSpeeding(), QStringLiteral("80 км/ч > 60 — превышение отмечено"));
        check(m->cameraHeader().contains(QStringLiteral("60")),
              QStringLiteral("заголовок: %1").arg(m->cameraHeader()));
        check(m->cameraRangeText().contains(QStringLiteral("330")) ||
              m->cameraRangeText().contains(QStringLiteral("340")),
              QStringLiteral("подпись расстояния: %1").arg(m->cameraRangeText()));

        m->checkPosition(lat0, lon0, 0.0, 50.0);            // тот же участок, 50 км/ч
        check(!m->cameraSpeeding(), QStringLiteral("50 км/ч < 60 — превышения нет"));

        // Камера осталась позади: едем на юг, камера за спиной → предупреждения быть не должно.
        m->checkPosition(lat0, lon0, 180.0, 50.0);
        check(!m->cameraActive(), QStringLiteral("камера позади — предупреждение исчезло"));
        delete m;
    }

    // ---------------------------------------------------------- радиус 500 м
    qInfo().noquote() << "Порог срабатывания";
    {
        double camLat, camLon;
        offset(lat0, lon0, 600.0, 0.0, &camLat, &camLon);
        const QString path = writeBase(dir, QStringLiteral("far.txt"), {
            QStringLiteral("%1,%2,1,60,0,0").arg(camLon, 0, 'f', 6).arg(camLat, 0, 'f', 6),
        });
        SpeedCamManager *m = loadManager(path);

        m->checkPosition(lat0, lon0, 0.0, 60.0);
        check(!m->cameraActive(), QStringLiteral("600 м — ещё далеко, предупреждения нет"));

        m->setWarningDistance(800);
        m->checkPosition(lat0, lon0, 0.0, 60.0);
        check(m->cameraActive(), QStringLiteral("с порогом 800 м камера в 600 м показана"));

        m->setWarningDistance(200);
        m->checkPosition(lat0, lon0, 0.0, 60.0);
        check(!m->cameraActive(), QStringLiteral("с порогом 200 м камера в 600 м не показана"));
        delete m;
    }

    // ------------------------------------------------- направленные камеры
    qInfo().noquote() << "Направленные камеры";
    {
        double camLat, camLon;
        offset(lat0, lon0, 334.0, 0.0, &camLat, &camLon);
        const QString unidirectional = writeBase(dir, QStringLiteral("dir1.txt"), {
            QStringLiteral("%1,%2,1,60,1,180").arg(camLon, 0, 'f', 6).arg(camLat, 0, 'f', 6),
        });
        SpeedCamManager *m = loadManager(unidirectional);
        // Едем на восток: камера впереди-слева, но стреляет в южном направлении.
        m->checkPosition(lat0, lon0, 90.0, 60.0);
        check(!m->cameraActive(),
              QStringLiteral("камера «в спину потоку» (азимут 180) на восток не срабатывает"));
        delete m;

        const QString plain = writeBase(dir, QStringLiteral("dir0.txt"), {
            QStringLiteral("%1,%2,1,60,0,0").arg(camLon, 0, 'f', 6).arg(camLat, 0, 'f', 6),
        });
        m = loadManager(plain);
        m->checkPosition(lat0, lon0, 90.0, 60.0);
        check(m->cameraActive(), QStringLiteral("та же камера без направления срабатывает"));
        delete m;
    }

    // --------------------------------------------------------- демо-камера
    qInfo().noquote() << "Демо-камера (симуляция)";
    {
        const QString path = writeBase(dir, QStringLiteral("empty.txt"), {
            QStringLiteral("# пустая база"),
        });
        SpeedCamManager *m = loadManager(path);
        check(m->count() == 0, QStringLiteral("пустая база — 0 точек"));

        m->checkPosition(lat0, lon0, 0.0, 40.0);            // запомнили позицию
        m->simulateCameraAhead(50, 400);
        check(m->cameraActive(), QStringLiteral("демо-камера сразу показана"));
        checkNear(m->cameraDistance(), 400.0, 10.0, QStringLiteral("демо-камера в 400 м"));
        check(m->cameraSpeedLimit() == 50, QStringLiteral("ограничение демо-камеры 50"));
        check(!m->cameraSpeeding(), QStringLiteral("40 км/ч < 50 — превышения нет"));

        m->clearSimulated();
        check(!m->cameraActive(), QStringLiteral("демо-камера убрана — предупреждения нет"));
        delete m;
    }

    if (g_failures == 0)
        qInfo().noquote() << "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ";
    else
        qWarning().noquote() << "ПРОВАЛЕНО ПРОВЕРОК:" << g_failures;
    return g_failures == 0 ? 0 : 1;
}
