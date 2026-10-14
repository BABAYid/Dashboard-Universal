// ============================================================================
//  Тест разбора CAN-протокола (can_protocol_v1.txt).
//
//  Проверяются примеры кадров прямо из документации плюс граничные случаи:
//  определение передачи по проводам S1/S2, режимы АКПП, отрицательная
//  наружная температура, короткие кадры.
//
//  Сборка и запуск:
//      cmake -S Dashboard -B build -DDASHBOARD_BUILD_TESTS=ON
//      cmake --build build --target test_canprotocol
//      ./build/test_canprotocol
// ============================================================================

#include "CanBackend.h"

#include <QCoreApplication>
#include <QByteArray>
#include <QDebug>
#include <QtMath>
#include <QTimer>

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

static void checkNum(double actual, double expected, const QString &what)
{
    const bool ok = qFuzzyCompare(actual + 1.0, expected + 1.0);
    check(ok, ok ? what
                 : QStringLiteral("%1 — получено %2, ожидалось %3")
                       .arg(what).arg(actual).arg(expected));
}

static QByteArray frame(std::initializer_list<int> bytes)
{
    QByteArray a(8, '\0');
    int i = 0;
    for (int b : bytes) {
        if (i < 8)
            a[i++] = static_cast<char>(b);
    }
    return a;
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("AudiDashboard"));
    QCoreApplication::setApplicationName(QStringLiteral("DashboardTest"));

    // Режим наблюдения за демо-генератором: печатает состояние раз в секунду
    if (argc > 1 && QByteArray(argv[1]) == "--mock-watch") {
        CanBackend backend(nullptr);
        backend.setMockMode(true);
        backend.start();
        int seconds = 0;
        QTimer tick;
        tick.setInterval(1000);
        QObject::connect(&tick, &QTimer::timeout, [&]() {
            ++seconds;
            qInfo().nospace() << seconds << " с: скорость=" << backend.speed()
                              << " об=" << backend.rpm()
                              << " передача=" << backend.gearMode()
                              << " темп=" << backend.engineTemp()
                              << " бак=" << backend.fuelLevel()
                              << " В=" << backend.voltage()
                              << " габариты=" << backend.positionLights()
                              << " лев=" << backend.leftTurn()
                              << " прав=" << backend.rightTurn()
                              << " кадров=" << backend.framesReceived();
            if (seconds >= 20)
                QCoreApplication::quit();
        });
        tick.start();
        return app.exec();
    }

    CanBackend can(nullptr);

    qInfo() << "0x100 — скорость и обороты (пример из документации)";
    can.feedFrame(0x100, frame({0x66, 0x09, 0x92}));
    checkNum(can.speed(), 102.0, "скорость 102 км/ч");
    check(can.rpm() == 2450, QStringLiteral("обороты 2450, получено %1").arg(can.rpm()));

    qInfo() << "0x200 — лампы (пример: правый поворотник, ближний свет, ABS)";
    can.feedFrame(0x200, frame({0x0A, 0x02}));
    check(can.rightTurn(), "правый поворотник включён");
    check(can.lowBeam(), "ближний свет включён");
    check(can.absWarning(), "ABS активен");
    check(!can.leftTurn(), "левый поворотник выключен");
    check(!can.highBeam(), "дальний свет выключен");
    check(!can.checkEngine(), "Check Engine не активен");

    qInfo() << "0x200 — индикаторы состояния (байт 1)";
    can.feedFrame(0x200, frame({0x10, 0x2D}));   // габариты + чек/ABS/ручник/ремень/LOCK
    check(can.positionLights(), "габариты включены");
    check(can.checkEngine(), "Check Engine активен");
    check(can.handBrake(), "ручник включён");
    check(can.seatBeltUnfastened(), "ремень не пристёгнут");
    check(can.gearLock(), "LOCK (SL) активен");

    qInfo() << "0x300 — датчики (пример из документации)";
    can.feedFrame(0x300, frame({0x5A, 0x2A, 0x8E, 0xFB, 0x00, 0x55}));
    checkNum(can.engineTemp(), 90.0, "температура двигателя 90 °C");
    checkNum(can.fuelLevel(), 42.0, "уровень топлива 42 %");
    checkNum(can.voltage(), 14.2, "напряжение 14.2 В");
    checkNum(can.outsideTemp(), -5.0, "наружная температура -5 °C (int8)");
    check(!can.oilPressureAlarm(), "давление масла в норме");
    checkNum(can.fuelRate(), 8.5, "мгновенный расход 8.5 л/100 км");

    qInfo() << "0x300 — авария по давлению масла";
    can.feedFrame(0x300, frame({0x5A, 0x2A, 0x8E, 0x14, 0x01, 0x55}));
    check(can.oilPressureAlarm(), "авария по давлению масла");
    checkNum(can.outsideTemp(), 20.0, "наружная температура +20 °C");

    qInfo() << "0x400 — АКПП (пример: режим D, передача D2)";
    can.feedFrame(0x400, frame({0x03, 0x02, 0x00, 0x01, 0x01, 0x00}));
    check(can.gearMode() == QLatin1String("D2"),
          QStringLiteral("режим D2, получено %1").arg(can.gearMode()));
    check(!can.gearLock(), "LOCK выключен");

    qInfo() << "0x400 — определение передачи по проводам S1/S2 (байт 1 = 0)";
    struct S1S2Case { int s1; int s2; const char *expected; };
    const S1S2Case cases[] = {
        {1, 0, "D1"},
        {1, 1, "D2"},
        {0, 1, "D3"},
        {0, 0, "D4"},
    };
    for (const S1S2Case &c : cases) {
        can.feedFrame(0x400, frame({0x03, 0x00, 0x00, c.s1, c.s2, 0x00}));
        check(can.gearMode() == QLatin1String(c.expected),
              QStringLiteral("S1=%1, S2=%2 → %3 (получено %4)")
                  .arg(c.s1).arg(c.s2).arg(QLatin1String(c.expected), can.gearMode()));
    }

    qInfo() << "0x400 — остальные режимы АКПП";
    struct ModeCase { int byte; const char *expected; };
    const ModeCase modes[] = {{0, "P"}, {1, "R"}, {2, "N"}, {4, "L"}};
    for (const ModeCase &m : modes) {
        can.feedFrame(0x400, frame({m.byte, 0x00, 0x01, 0x00, 0x00, 0x00}));
        check(can.gearMode() == QLatin1String(m.expected),
              QStringLiteral("байт 0 = %1 → %2 (получено %3)")
                  .arg(m.byte).arg(QLatin1String(m.expected), can.gearMode()));
    }
    check(can.gearLock(), "LOCK включён (байт 2 = 1)");

    qInfo() << "Граничные случаи";
    can.feedFrame(0x100, frame({0xC8, 0x1F, 0x40}));   // 200 км/ч, 8000 об/мин
    checkNum(can.speed(), 200.0, "скорость 200 км/ч");
    check(can.rpm() == 8000, QStringLiteral("обороты 8000, получено %1").arg(can.rpm()));

    const int before = can.framesReceived();
    can.feedFrame(0x100, QByteArray(4, '\0'));
    check(can.framesReceived() == before, "короткий кадр (4 байта) игнорируется");
    checkNum(can.speed(), 200.0, "значение после короткого кадра не изменилось");

    can.feedFrame(0x777, frame({0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}));
    checkNum(can.speed(), 200.0, "неизвестный ID не влияет на данные");

    qInfo() << "";
    if (g_failures == 0)
        qInfo() << "Все проверки пройдены.";
    else
        qWarning() << "Провалено проверок:" << g_failures;

    return g_failures == 0 ? 0 : 1;
}
