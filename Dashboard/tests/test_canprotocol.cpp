// ============================================================================
//  Тест разбора CAN-протокола (can_protocol_v1.2.txt).
//
//  Проверяются примеры кадров прямо из документации плюс граничные случаи:
//  определение передачи по проводам S1/S2, режимы АКПП, отрицательная
//  наружная температура, газовое оборудование (кадр 0x500 и перевод напряжения
//  датчика уровня газа в проценты), короткие кадры.
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
        // Второй аргумент — сколько секунд наблюдать (по умолчанию 20)
        const int watchSeconds = (argc > 2) ? QByteArray(argv[2]).toInt() : 20;
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
                              << " кадров=" << backend.framesReceived()
                              << " расход=" << backend.fuelRate()
                              << " прошивка=" << backend.deviceFirmware()
                              << " работает=" << backend.deviceUptimeSec() << "с"
                              << " перезапусков=" << backend.deviceRestarts();
            if (seconds % 10 == 0)
                qInfo().nospace() << "      маршрут: " << backend.journeyKm() << " км, "
                                  << backend.fuelUsed() << " л, средний "
                                  << backend.avgConsumption() << " л/100, запас хода "
                                  << backend.rangeKm() << " км, средняя скорость "
                                  << backend.avgSpeed() << " км/ч";
            if (seconds >= watchSeconds)
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
    can.feedFrame(0x300, frame({0x5A, 0x2A, 0x8E, 0xFB, 0x00, 0x00, 0x55}));
    checkNum(can.engineTemp(), 90.0, "температура двигателя 90 °C");
    checkNum(can.fuelLevel(), 42.0, "уровень топлива 42 %");
    checkNum(can.voltage(), 14.2, "напряжение 14.2 В");
    checkNum(can.outsideTemp(), -5.0, "наружная температура -5 °C (int8)");
    check(!can.oilPressureAlarm(), "давление масла в норме");
    checkNum(can.fuelRate(), 8.5, "мгновенный расход 8.5 л/100 км");

    // Значение, которое физически не помещалось в однобайтовый формат
    // версии 1.0 протокола — за это расход и перенесли в uint16
    can.feedFrame(0x300, frame({0x5A, 0x2A, 0x8E, 0xFB, 0x00, 0x03, 0xE7}));
    checkNum(can.fuelRate(), 99.9, "расход 99.9 л/100 км (999 = 0x03E7, в 1.0 не влезал)");

    qInfo() << "0x300 — авария по давлению масла";
    can.feedFrame(0x300, frame({0x5A, 0x2A, 0x8E, 0x14, 0x01, 0x00, 0x55}));
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

    // ---- 0x7F0: статус блока сбора (добавлен в протоколе 1.1) ----
    qInfo() << "0x7F0 — статус блока сбора";
    auto deviceFrame = [](int counter, int version, quint32 uptime, int errors) {
        QByteArray a(8, '\0');
        a[0] = static_cast<char>(counter);
        a[1] = static_cast<char>(version);
        a[2] = static_cast<char>((uptime >> 24) & 0xFF);
        a[3] = static_cast<char>((uptime >> 16) & 0xFF);
        a[4] = static_cast<char>((uptime >> 8) & 0xFF);
        a[5] = static_cast<char>(uptime & 0xFF);
        a[6] = static_cast<char>(errors);
        quint8 xorSum = 0;
        for (int i = 0; i < 7; ++i)
            xorSum ^= static_cast<quint8>(a[i]);
        a[7] = static_cast<char>(xorSum);
        return a;
    };

    can.feedFrame(0x7F0, deviceFrame(0, 0x11, 3600, 3));
    check(can.deviceAlive(), "кадр статуса принят (признак жизни)");
    check(can.deviceFirmware() == QLatin1String("1.1"),
          QStringLiteral("версия прошивки 1.1, получено %1").arg(can.deviceFirmware()));
    check(can.deviceUptimeSec() == 3600u,
          QStringLiteral("время работы 3600 с, получено %1").arg(can.deviceUptimeSec()));
    check(can.deviceBusErrors() == 3,
          QStringLiteral("ошибок шины 3, получено %1").arg(can.deviceBusErrors()));
    check(can.deviceRestarts() == 0, "перезапусков нет");

    can.feedFrame(0x7F0, deviceFrame(1, 0x11, 3601, 3));
    check(can.deviceRestarts() == 0, "последовательный счётчик — не перезапуск");

    can.feedFrame(0x7F0, deviceFrame(5, 0x11, 4, 0));
    check(can.deviceRestarts() == 1,
          QStringLiteral("перезапуск блока обнаружен, получено %1").arg(can.deviceRestarts()));
    check(can.deviceUptimeSec() == 4u, "время работы сброшено — блок перезапустился");

    QByteArray broken = deviceFrame(6, 0x11, 10, 0);
    broken[7] = static_cast<char>(static_cast<quint8>(broken[7]) ^ 0xFF);
    can.feedFrame(0x7F0, broken);
    check(can.deviceRestarts() == 1, "кадр с неверной контрольной суммой не считается");
    check(can.deviceUptimeSec() == 4u, "значения из повреждённого кадра не применены");

    qInfo() << "0x500 — газовое оборудование (новое в 1.2)";
    can.feedFrame(0x500, frame({0x03, 0x09, 0x2E}));   // газ включён, датчик 2350 мВ
    check(can.gasMode(), "режим газа включён");
    check(can.gasSensorValid(), "датчик уровня газа исправен");
    checkNum(can.gasSensorVolts(), 2.35, "напряжение датчика 2.35 В");
    check(can.gasLevelPercent() == 47,
          QStringLiteral("остаток газа 47 %, получено %1 %").arg(can.gasLevelPercent()));

    can.feedFrame(0x500, frame({0x03, 0x00, 0x00}));
    check(can.gasLevelPercent() == 0, "0 В — пустой баллон");

    can.feedFrame(0x500, frame({0x03, 0x13, 0x88}));   // 5000 мВ
    check(can.gasLevelPercent() == 100, "5 В — полный баллон");

    can.feedFrame(0x500, frame({0x03, 0xFF, 0xFF}));   // больше 5 В
    check(can.gasLevelPercent() == 100,
          QStringLiteral("напряжение выше 5 В считается полным баллоном, получено %1 %")
              .arg(can.gasLevelPercent()));

    can.feedFrame(0x500, frame({0x01, 0x0C, 0x80}));   // датчик не отвечает
    check(can.gasMode(), "режим газа определяется и при неисправном датчике");
    check(!can.gasSensorValid(), "неисправный датчик отмечен");
    check(can.gasLevelPercent() == 0, "при неисправном датчике остаток не показывается");

    can.feedFrame(0x500, frame({0x02, 0x09, 0x2E}));   // бензин, датчик исправен
    check(!can.gasMode(), "переключение обратно на бензин");
    check(can.gasSensorValid(), "датчик исправен и на бензине");
    check(can.gasLevelPercent() == 47, "остаток газа читается и на бензине");

    const int gasFramesBefore = can.framesReceived();
    can.feedFrame(0x500, QByteArray(4, '\0'));
    check(can.framesReceived() == gasFramesBefore, "короткий кадр 0x500 игнорируется");

    qInfo() << "Запас хода: средний расход за 5 минут";
    check(!can.rangeKmValid(), "до первого расхода запас хода недостоверен");

    // Уровень 42 % при баке 60 л → 25.2 л. Расход 8.5 л/100 км →
    // запас = 25.2 / 8.5 × 100 ≈ 296 км
    can.feedFrame(0x300, frame({90, 42, 142, 0, 0, 0, 85}));
    can.feedConsumptionSample(8.5);
    check(can.rangeKmValid(), "запас хода стал достоверным");
    checkNum(qRound(can.rangeKm()), 296.0, "запас хода 296 км при 42 % и 8.5 л/100 км");
    checkNum(can.avgConsumption5min(), 8.5, "средний расход за 5 минут 8.5 л/100 км");

    // Стоянка: мгновенный расход ноль — запас не обнуляется и не мигает
    const double rangeWhileParked = can.rangeKm();
    for (int i = 0; i < 10; ++i)
        can.feedConsumptionSample(0.0);
    checkNum(can.rangeKm(), rangeWhileParked,
             "на стоянке запас остаётся последним достоверным значением");

    // Окно на 300 сэмплов: старые вытесняются новыми
    for (int i = 0; i < 300; ++i)
        can.feedConsumptionSample(12.0);
    checkNum(can.avgConsumption5min(), 12.0, "окно целиком заполнилось новым расходом");
    checkNum(qRound(can.rangeKm()), 210.0, "запас пересчитан: 25.2 л ÷ 12 л/100 км × 100");

    // Объём бака — настройка пользователя: 42 % от 80 л → 33.6 л → 280 км
    can.setTankCapacity(80.0);
    checkNum(can.tankCapacity(), 80.0, "объём бака изменён на 80 л");
    can.feedConsumptionSample(12.0);
    checkNum(qRound(can.rangeKm()), 280.0, "запас учёл новый объём бака");

    can.setTankCapacity(-5.0);
    checkNum(can.tankCapacity(), 80.0, "неправдоподобный объём бака игнорируется");

    qInfo() << "История напряжения: кольцевой буфер на 5 минут";
    for (int i = 0; i < 300; ++i)
        can.feedVoltageSample(12.0 + i * 0.001);
    check(can.voltageHistory().size() == 300, "набралось ровно 300 замеров");
    checkNum(can.voltageHistory().last().toDouble(), 12.0 + 299 * 0.001,
             "последний замер в списке — самый свежий");

    can.feedVoltageSample(13.9);
    check(can.voltageHistory().size() == 300,
          "буфер не растёт выше 300 — старое вытесняется");
    checkNum(can.voltageHistory().last().toDouble(), 13.9, "новый замер попал в конец");
    checkNum(can.voltageHistory().first().toDouble(), 12.0 + 1 * 0.001,
             "самый старый замер вытеснен");

    can.feedVoltageSample(qQNaN());
    check(qIsNaN(can.voltageHistory().last().toDouble()),
          "нет данных — в истории NaN (на графике это разрыв)");

    // ---- 0x510: климат (протокол 1.3) ----
    qInfo() << "0x510 — климат (новое в 1.3)";
    can.feedFrame(0x510, frame({0x21, 0x2D, 0x03, 0x04, 0x18, 0x80, 0x00, 0x00}));
    check(can.climateValid(), "данные климата достоверны");
    check(can.climateAc(), "кондиционер включён");
    check(!can.climateAuto(), "AUTO выключен");
    checkNum(can.climateSetpoint(), 22.5, "уставка 22.5 °C (байт 0x2D = 45)");
    check(can.climateFanLevel() == 3, QStringLiteral("вентилятор 3, получено %1").arg(can.climateFanLevel()));
    check(can.climateAirflow() == QLatin1String("лицо"),
          QStringLiteral("поток «лицо», получено «%1»").arg(can.climateAirflow()));
    checkNum(can.climateCabinTemp(), 24.0, "в салоне 24 °C");
    check(qIsNaN(can.climateEvaporatorTemp()), "испаритель — нет данных (0x80 → NaN)");

    can.feedFrame(0x510, frame({0x02, 0x00, 0xFF, 0x08, 0x80, 0x80, 0x00, 0x00}));
    check(!can.climateValid(), "бит достоверности снят — климат недостоверен");
    check(can.climateAuto(), "AUTO включён");
    check(can.climateFanLevel() == -1, "вентилятор — нет данных (-1)");
    check(qIsNaN(can.climateSetpoint()), "уставка — нет данных (0 → NaN)");
    check(can.climateAirflow() == QLatin1String("авто"), "поток выбирает автоматика");

    // ---- 0x520 и 0x521: GPS (протокол 1.3) ----
    qInfo() << "0x520 — GPS: положение (новое в 1.3)";
    can.feedFrame(0x520, frame({0x21, 0x3B, 0xA8, 0xF0, 0x16, 0x6B, 0xF1, 0xC8}));
    checkNum(can.gpsLatitude(), 55.7558, "широта 55.7558");
    checkNum(can.gpsLongitude(), 37.6173, "долгота 37.6173");

    qInfo() << "0x521 — GPS: движение и качество";
    can.feedFrame(0x521, frame({0x43, 0x3C, 0x0B, 0x48, 0x14, 0x23, 0x0E, 0x03}));
    check(can.gpsValid(), "фикс есть, данные свежие");
    checkNum(can.gpsCourse(), 134.0, "курс 134° (байт 67 × 2)");
    check(can.gpsSpeed() == 60, QStringLiteral("скорость по GPS 60, получено %1").arg(can.gpsSpeed()));
    checkNum(can.gpsHdop(), 1.1, "HDOP 1.1");
    check(can.gpsSatellites() == 8, QStringLiteral("спутников 8, получено %1").arg(can.gpsSatellites()));
    check(can.gpsFixType() == 2, "фикс 3D");
    check(can.gpsUtcTime() == QLatin1String("14:35:20"),
          QStringLiteral("время UTC 14:35:20, получено «%1»").arg(can.gpsUtcTime()));

    can.feedFrame(0x521, frame({0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00}));
    check(!can.gpsValid(), "фикса нет — данные недостоверны");
    check(can.gpsSpeed() == -1, "скорость по GPS — нет данных");
    check(qIsNaN(can.gpsCourse()), "курс — нет данных");
    check(can.gpsFixType() == 0, "тип фикса — нет фикса");

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
