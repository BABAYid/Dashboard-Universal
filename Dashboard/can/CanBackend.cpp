#include "CanBackend.h"

#include <QDebug>
#include <QSettings>
#include <QCoreApplication>
#include <QSocketNotifier>
#include <QTimer>
#include <QtMath>
#include <cmath>

#if defined(Q_OS_LINUX)
#  include <sys/socket.h>
#  include <sys/ioctl.h>
#  include <net/if.h>
#  include <linux/can.h>
#  include <linux/can/raw.h>
#  include <unistd.h>
#  include <cerrno>
#  include <cstring>
#endif

namespace {
// ID сообщений (can_protocol_v1.1.txt)
constexpr quint32 kIdMotion  = 0x100;   // скорость и обороты
constexpr quint32 kIdStatus  = 0x200;   // лампы и индикаторы
constexpr quint32 kIdSensors = 0x300;   // датчики
constexpr quint32 kIdGearbox = 0x400;   // АКПП
constexpr quint32 kIdDevice  = 0x7F0;   // статус блока сбора (протокол 1.1)

// Данные считаются устаревшими, если кадров нет дольше этого времени
constexpr int kDataTimeoutMs = 1500;
// Статус блока сбора приходит раз в секунду, поэтому таймаут больше
constexpr int kDeviceTimeoutMs = 3000;
// Период проверки связи
constexpr int kWatchdogMs = 250;
// Как часто пытаться открыть CAN-интерфейс заново
constexpr int kReconnectEveryTicks = 20;   // 20 * 250 мс = 5 с
// Период сохранения пробега
constexpr int kSavePeriodMs = 10000;
}   // namespace

CanBackend::CanBackend(QObject *parent)
    : QObject(parent)
{
    m_watchdog = new QTimer(this);
    m_watchdog->setInterval(kWatchdogMs);
    connect(m_watchdog, &QTimer::timeout, this, &CanBackend::updateDataValidity);

    m_saveTimer = new QTimer(this);
    m_saveTimer->setInterval(kSavePeriodMs);
    connect(m_saveTimer, &QTimer::timeout, this, &CanBackend::saveDistance);

    m_sinceLastFrame.start();
    m_sinceLastSpeed.start();
    m_sinceDeviceStatus.start();
}

CanBackend::~CanBackend()
{
    saveDistance();
    stop();
}

CanBackend *CanBackend::instance()
{
    // Объект живёт в куче и принадлежит приложению: если сделать его
    // статической переменной, деструктор отработает уже после разрушения
    // QGuiApplication (QSettings/QTimer в этот момент использовать нельзя).
    static CanBackend *backend = nullptr;
    if (!backend)
        backend = new CanBackend(qApp);
    return backend;
}

// ---------------------------------------------------------------- запуск/стоп

void CanBackend::start()
{
    // Пробег читаем здесь, а не в конструкторе: режим (mock/реальный CAN)
    // задаётся из main.cpp уже после создания синглтона.
    loadDistance();

    if (m_mockMode) {
        startMock();
        return;
    }

    openSocket();

    if (!m_watchdog->isActive())
        m_watchdog->start();
    if (!m_saveTimer->isActive())
        m_saveTimer->start();
}

void CanBackend::stop()
{
    m_watchdog->stop();
    m_saveTimer->stop();

    if (m_mockTimer) {
        m_mockTimer->stop();
        m_mockTimer->deleteLater();
        m_mockTimer = nullptr;
    }

#if defined(Q_OS_LINUX)
    if (m_notifier) {
        m_notifier->setEnabled(false);
        delete m_notifier;
        m_notifier = nullptr;
    }
    if (m_socket >= 0) {
        ::close(m_socket);
        m_socket = -1;
    }
#endif

    set(m_connected, false, &CanBackend::connectedChanged);
    set(m_dataValid, false, &CanBackend::dataValidChanged);
}

// ------------------------------------------------------------------ SocketCAN

void CanBackend::openSocket()
{
#if defined(Q_OS_LINUX)
    if (m_socket >= 0)
        return;

    // Неблокирующий сокет обязателен: читаем по сигналу QSocketNotifier
    const int fd = ::socket(PF_CAN, SOCK_RAW | SOCK_NONBLOCK, CAN_RAW);
    if (fd < 0) {
        m_sourceName = QStringLiteral("ошибка socket()");
        emit sourceNameChanged();
        return;
    }

    struct ifreq ifr;
    std::memset(&ifr, 0, sizeof(ifr));
    const QByteArray name = m_interfaceName.toLocal8Bit();
    std::strncpy(ifr.ifr_name, name.constData(), IFNAMSIZ - 1);

    if (::ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        // Интерфейса ещё нет — это нормально, если ESP32/шина поднимаются позже
        ::close(fd);
        m_sourceName = QStringLiteral("%1: нет интерфейса").arg(m_interfaceName);
        emit sourceNameChanged();
        return;
    }

    struct sockaddr_can addr;
    std::memset(&addr, 0, sizeof(addr));
    addr.can_family = AF_CAN;
    addr.can_ifindex = ifr.ifr_ifindex;

    if (::bind(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) < 0) {
        qWarning() << "CAN: не удалось подключиться к" << m_interfaceName << std::strerror(errno);
        ::close(fd);
        m_sourceName = QStringLiteral("%1: ошибка bind").arg(m_interfaceName);
        emit sourceNameChanged();
        return;
    }

    m_socket = fd;
    m_notifier = new QSocketNotifier(m_socket, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &CanBackend::readFrames);

    m_sourceName = m_interfaceName;
    emit sourceNameChanged();
    set(m_connected, true, &CanBackend::connectedChanged);
    qInfo() << "CAN: интерфейс" << m_interfaceName << "открыт";
#else
    m_sourceName = QStringLiteral("SocketCAN доступен только в Linux");
    emit sourceNameChanged();
#endif
}

void CanBackend::readFrames()
{
#if defined(Q_OS_LINUX)
    struct can_frame frame;
    for (;;) {
        const ssize_t n = ::read(m_socket, &frame, sizeof(frame));
        if (n < static_cast<ssize_t>(sizeof(frame)))
            break;   // кадров больше нет (EAGAIN) или ошибка

        if (frame.can_id & CAN_EFF_FLAG)
            continue;   // работаем только с 11-битными ID
        if (frame.can_dlc < 8)
            continue;   // по протоколу все пакеты 8 байт

        handleFrame(frame.can_id & CAN_SFF_MASK, frame.data, frame.can_dlc);
    }
#endif
}

// ------------------------------------------------------------------- разбор

void CanBackend::handleFrame(quint32 id, const quint8 *d, int len)
{
    if (len < 8)
        return;

    m_sinceLastFrame.restart();
    set(m_framesReceived, m_framesReceived + 1, &CanBackend::framesReceivedChanged);
    set(m_dataValid, true, &CanBackend::dataValidChanged);

    switch (id) {
    case kIdMotion:  handleMotionFrame(d);  break;
    case kIdStatus:  handleStatusFrame(d);  break;
    case kIdSensors: handleSensorFrame(d);  break;
    case kIdGearbox: handleGearboxFrame(d); break;
    case kIdDevice:  handleDeviceStatusFrame(d); break;
    default: break;   // неизвестные ID игнорируем
    }
}

// 0x100: байт0 — скорость (км/ч), байт1..2 — обороты (uint16, старший-младший)
void CanBackend::handleMotionFrame(const quint8 *d)
{
    accountDistance();

    set(m_speed, static_cast<double>(d[0]), &CanBackend::speedChanged);
    const int rpm = (static_cast<int>(d[1]) << 8) | static_cast<int>(d[2]);
    set(m_rpm, rpm, &CanBackend::rpmChanged);
}

// 0x200: байт0 — свет, байт1 — индикаторы
void CanBackend::handleStatusFrame(const quint8 *d)
{
    const quint8 lights = d[0];
    set(m_leftTurn,       bool(lights & 0x01), &CanBackend::leftTurnChanged);
    set(m_rightTurn,      bool(lights & 0x02), &CanBackend::rightTurnChanged);
    set(m_highBeam,       bool(lights & 0x04), &CanBackend::highBeamChanged);
    set(m_lowBeam,        bool(lights & 0x08), &CanBackend::lowBeamChanged);
    set(m_positionLights, bool(lights & 0x10), &CanBackend::positionLightsChanged);
    set(m_fogLights,      bool(lights & 0x20), &CanBackend::fogLightsChanged);
    set(m_reverseLights,  bool(lights & 0x40), &CanBackend::reverseLightsChanged);
    set(m_brakeLights,    bool(lights & 0x80), &CanBackend::brakeLightsChanged);

    const quint8 flags = d[1];
    set(m_checkEngine,        bool(flags & 0x01), &CanBackend::checkEngineChanged);
    set(m_absWarning,         bool(flags & 0x02), &CanBackend::absWarningChanged);
    set(m_handBrake,          bool(flags & 0x04), &CanBackend::handBrakeChanged);
    set(m_seatBeltUnfastened, bool(flags & 0x08), &CanBackend::seatBeltUnfastenedChanged);
    const bool oil = flags & 0x10;
    set(m_oilPressureAlarm, oil, &CanBackend::oilPressureAlarmChanged);
    set(m_gearLock,           bool(flags & 0x20), &CanBackend::gearLockChanged);
}

// 0x300: температура, топливо, напряжение, наружная температура, масло, расход
void CanBackend::handleSensorFrame(const quint8 *d)
{
    set(m_engineTemp,  static_cast<double>(d[0]),           &CanBackend::engineTempChanged);
    set(m_fuelLevel,   static_cast<double>(d[1]),           &CanBackend::fuelLevelChanged);
    set(m_voltage,     static_cast<double>(d[2]) / 10.0,    &CanBackend::voltageChanged);
    set(m_outsideTemp, static_cast<double>(static_cast<qint8>(d[3])), &CanBackend::outsideTempChanged);
    set(m_oilPressureAlarm, d[4] != 0,                      &CanBackend::oilPressureAlarmChanged);

    // Расход — uint16 (байты 5-6), значение x10. В версии 1.0 протокола он
    // занимал один байт, и заявленные 99.9 л/100 км в него не помещались.
    const int fuelRateX10 = (static_cast<int>(d[5]) << 8) | static_cast<int>(d[6]);
    set(m_fuelRate, static_cast<double>(fuelRateX10) / 10.0, &CanBackend::fuelRateChanged);
}

// 0x400: режим АКПП, передача, LOCK, провода S1/S2/SL
void CanBackend::handleGearboxFrame(const quint8 *d)
{
    const quint8 mode  = d[0];
    const quint8 gear  = d[1];
    const bool   s1    = d[3] != 0;
    const bool   s2    = d[4] != 0;

    QString gearMode;
    switch (mode) {
    case 1: gearMode = QStringLiteral("R"); break;
    case 2: gearMode = QStringLiteral("N"); break;
    case 4: gearMode = QStringLiteral("L"); break;
    case 3: {
        // Передача: сначала из байта 1, если он пуст — по проводам S1/S2
        int number = gear;
        if (number < 1 || number > 4)
            number = s1 ? (s2 ? 2 : 1) : (s2 ? 3 : 4);
        gearMode = QStringLiteral("D%1").arg(number);
        break;
    }
    default: gearMode = QStringLiteral("P"); break;
    }

    set(m_gearMode, gearMode, &CanBackend::gearModeChanged);
    set(m_gearLock, d[2] != 0, &CanBackend::gearLockChanged);
}

// 0x7F0: статус блока сбора — признак жизни, версия прошивки, время работы,
// ошибки шины, контрольная сумма. Добавлен в протоколе 1.1.
void CanBackend::handleDeviceStatusFrame(const quint8 *d)
{
    // Контрольная сумма: XOR байтов 0..6 должен совпасть с байтом 7
    quint8 xorSum = 0;
    for (int i = 0; i < 7; ++i)
        xorSum ^= d[i];
    if (xorSum != d[7]) {
        qWarning() << "CAN: кадр статуса 0x7F0 повреждён (контрольная сумма не совпала)";
        return;
    }

    m_sinceDeviceStatus.restart();
    set(m_deviceAlive, true, &CanBackend::deviceAliveChanged);

    const quint8 counter = d[0];
    const quint32 uptime = (static_cast<quint32>(d[2]) << 24)
                         | (static_cast<quint32>(d[3]) << 16)
                         | (static_cast<quint32>(d[4]) << 8)
                         | static_cast<quint32>(d[5]);

    // Перезапуск блока: счётчик не продолжил последовательность либо время
    // работы уменьшилось. Без этого кадра отличить перезапуск от зависания
    // было невозможно.
    if (m_lastStatusCounter >= 0) {
        const quint8 expected = static_cast<quint8>((m_lastStatusCounter + 1) & 0xFF);
        if (counter != expected || uptime < m_lastUptime) {
            set(m_deviceRestarts, m_deviceRestarts + 1, &CanBackend::deviceRestartsChanged);
            qWarning() << "Блок сбора перезапустился: счётчик" << m_lastStatusCounter
                       << "→" << counter << ", время работы" << m_lastUptime << "→" << uptime << "с";
        }
    }
    m_lastStatusCounter = counter;
    m_lastUptime = uptime;

    set(m_deviceFirmware,
        QStringLiteral("%1.%2").arg(d[1] >> 4).arg(d[1] & 0x0F),
        &CanBackend::deviceFirmwareChanged);
    set(m_deviceUptimeSec, uptime, &CanBackend::deviceUptimeSecChanged);
    set(m_deviceBusErrors, static_cast<int>(d[6]), &CanBackend::deviceBusErrorsChanged);
}

// ------------------------------------------------------------------ контроль

void CanBackend::updateDataValidity()
{
    static int tick = 0;
    ++tick;

    if (m_sinceLastFrame.elapsed() > kDataTimeoutMs)
        set(m_dataValid, false, &CanBackend::dataValidChanged);

    // Статус блока сбора приходит раз в секунду. Если его нет дольше трёх
    // секунд, значит на блоке сбора прошивка 1.0 (или модуль завис) —
    // сами данные при этом могут продолжать идти.
    if (m_sinceDeviceStatus.elapsed() > kDeviceTimeoutMs)
        set(m_deviceAlive, false, &CanBackend::deviceAliveChanged);

    // Если интерфейса не было при старте — периодически пробуем снова
    if (!m_mockMode && !m_connected && tick % kReconnectEveryTicks == 0)
        openSocket();
}

// Счёт пробега: скорость (км/ч) * время (ч)
void CanBackend::accountDistance()
{
    const qint64 ms = m_sinceLastSpeed.restart();
    if (ms <= 0 || ms > 5000)   // пропуск или первый кадр
        return;

    const double km = m_speed * (static_cast<double>(ms) / 3600000.0);
    if (km <= 0)
        return;

    set(m_odometer, m_odometer + km, &CanBackend::odometerChanged);
    set(m_tripA,    m_tripA + km,    &CanBackend::tripAChanged);
    set(m_tripB,    m_tripB + km,    &CanBackend::tripBChanged);
}

void CanBackend::resetTripA()
{
    set(m_tripA, 0.0, &CanBackend::tripAChanged);
    saveDistance();
}

void CanBackend::resetTripB()
{
    set(m_tripB, 0.0, &CanBackend::tripBChanged);
    saveDistance();
}

// Подача кадра напрямую: используется тестами разбора протокола
void CanBackend::feedFrame(int id, const QByteArray &data)
{
    const quint8 *d = reinterpret_cast<const quint8 *>(data.constData());
    handleFrame(static_cast<quint32>(id), d, qMin(data.size(), 8));
}

void CanBackend::loadDistance()
{
    QSettings s;
    const QString prefix = m_mockMode ? QStringLiteral("mock/") : QString();
    m_odometer = s.value(prefix + "odometer", 0.0).toDouble();
    m_tripA    = s.value(prefix + "tripA", 0.0).toDouble();
    m_tripB    = s.value(prefix + "tripB", 0.0).toDouble();
}

void CanBackend::saveDistance()
{
    QSettings s;
    const QString prefix = m_mockMode ? QStringLiteral("mock/") : QString();
    s.setValue(prefix + "odometer", m_odometer);
    s.setValue(prefix + "tripA", m_tripA);
    s.setValue(prefix + "tripB", m_tripB);
}

// ----------------------------------------------------------------- mock-режим

void CanBackend::startMock()
{
    m_sourceName = QStringLiteral("демо-режим (mock)");
    emit sourceNameChanged();
    set(m_connected, true, &CanBackend::connectedChanged);
    m_sinceLastFrame.start();

    if (!m_mockTimer) {
        m_mockTimer = new QTimer(this);
        m_mockTimer->setInterval(50);   // 20 Гц, как в протоколе
        connect(m_mockTimer, &QTimer::timeout, this, &CanBackend::generateMockFrames);
    }
    m_mockTimer->start();

    if (!m_watchdog->isActive())
        m_watchdog->start();
    if (!m_saveTimer->isActive())
        m_saveTimer->start();

    qInfo() << "CAN: включён демо-режим (mock), кадры генерируются программно";
}

// Генерируем кадры протокола и отдаём их тому же разбору, что и настоящие.
void CanBackend::generateMockFrames()
{
    static QElapsedTimer clock;
    if (!clock.isValid())
        clock.start();
    const double t = clock.elapsed() / 1000.0;
    const double cycle = std::fmod(t, 60.0);   // сценарий длиной 60 с
    // Первые 2 секунды двигатель заглушён — на приборке видно самопроверку ламп
    const bool engineRunning = t > 2.0;

    // --- профиль скорости: разгон, крейсер, торможение, стоянка ---
    double speed = 0;
    if (cycle < 10.0) {
        speed = 0;
    } else if (cycle < 25.0) {
        speed = 90.0 * (cycle - 10.0) / 15.0;
    } else if (cycle < 40.0) {
        speed = 90.0 + 3.0 * std::sin(t);       // лёгкие колебания
    } else if (cycle < 50.0) {
        speed = 90.0 * (50.0 - cycle) / 10.0;
    } else {
        speed = 0;
    }
    speed = qBound(0.0, speed, 220.0);

    // --- передача и обороты ---
    int gear = 4;
    if (speed < 20.0)      gear = 1;
    else if (speed < 40.0) gear = 2;
    else if (speed < 65.0) gear = 3;

    const double idleRpm = 800.0;
    const double ratio = (gear == 1) ? 130.0 : (gear == 2) ? 80.0 : (gear == 3) ? 55.0 : 38.0;
    int rpm = engineRunning ? static_cast<int>(speed > 1.0 ? idleRpm + speed * ratio : idleRpm) : 0;
    rpm = qBound(0, rpm, 8000);

    // --- свет и поворотники (мигание 1.5 Гц) ---
    const bool blink = std::fmod(t, 0.66) < 0.33;
    const bool turningLeft  = cycle >= 12.0 && cycle < 18.0;
    const bool turningRight = cycle >= 28.0 && cycle < 34.0;
    const bool lightsOn = cycle > 3.0;
    const bool braking = cycle >= 40.0 && cycle < 50.0;

    quint8 lights = 0;
    if (turningLeft && blink)  lights |= 0x01;
    if (turningRight && blink) lights |= 0x02;
    if (lightsOn)              lights |= 0x08;   // ближний
    if (lightsOn)              lights |= 0x10;   // габариты
    if (lightsOn && cycle > 30.0 && cycle < 36.0) lights |= 0x20;  // противотуманки
    if (braking)               lights |= 0x80;   // стоп-сигналы

    quint8 flags = 0;
    if (cycle < 6.0)           flags |= 0x08;    // ремень не пристёгнут
    if (speed < 1.0)           flags |= 0x04;    // ручник
    if (speed > 100.0)         flags |= 0x01;    // «чек» — для проверки индикации

    // --- датчики ---
    const double temp = qMin(90.0, 20.0 + t * 0.6);                 // прогрев
    const double fuel = 78.0 - std::fmod(t, 3600.0) / 3600.0 * 8.0; // медленно убывает
    const double volts = engineRunning ? 14.2 + 0.2 * std::sin(t) : 12.3;
    const double outside = 2.0 + 6.0 * std::sin(t / 120.0);         // иногда ниже нуля
    const double rate = speed > 1.0 ? 8.5 + 2.0 * std::sin(t / 5.0) : 0.0;

    // --- кадр 0x100: скорость и обороты ---
    {
        quint8 d[8] = {};
        d[0] = static_cast<quint8>(speed);
        d[1] = static_cast<quint8>((rpm >> 8) & 0xFF);
        d[2] = static_cast<quint8>(rpm & 0xFF);
        handleFrame(kIdMotion, d, 8);
    }

    // --- кадр 0x200: лампы (по протоколу можно реже, но без разницы) ---
    {
        quint8 d[8] = {};
        d[0] = lights;
        d[1] = flags;
        handleFrame(kIdStatus, d, 8);
    }

    // --- кадр 0x300: датчики ---
    {
        quint8 d[8] = {};
        d[0] = static_cast<quint8>(qBound(0.0, temp, 255.0));
        d[1] = static_cast<quint8>(qBound(0.0, fuel, 100.0));
        d[2] = static_cast<quint8>(qBound(0.0, volts * 10.0, 255.0));
        d[3] = static_cast<quint8>(static_cast<qint8>(qBound(-40.0, outside, 60.0)));
        d[4] = 0;
        const int rateX10 = qBound(0, static_cast<int>(rate * 10.0), 999);
        d[5] = static_cast<quint8>((rateX10 >> 8) & 0xFF);   // расход, старший байт
        d[6] = static_cast<quint8>(rateX10 & 0xFF);          // расход, младший байт
        handleFrame(kIdSensors, d, 8);
    }

    // --- кадр 0x400: АКПП ---
    {
        quint8 d[8] = {};
        const bool moving = speed > 1.0;
        d[0] = moving ? 3 : 0;                       // D или P
        d[1] = moving ? static_cast<quint8>(gear) : 0;
        d[2] = 0;                                    // LOCK выключен
        if (moving) {                                // провода по таблице протокола
            d[3] = (gear == 1 || gear == 2) ? 1 : 0; // S1
            d[4] = (gear == 2 || gear == 3) ? 1 : 0; // S2
        }
        handleFrame(kIdGearbox, d, 8);
    }

    // --- кадр 0x7F0: статус блока сбора (раз в секунду) ---
    if (static_cast<int>(t) != m_mockLastStatusSecond) {
        m_mockLastStatusSecond = static_cast<int>(t);
        quint8 d[8] = {};
        d[0] = static_cast<quint8>(m_mockStatusCounter++);
        d[1] = 0x11;                                             // версия прошивки 1.1
        const quint32 uptime = static_cast<quint32>(t);
        d[2] = static_cast<quint8>((uptime >> 24) & 0xFF);
        d[3] = static_cast<quint8>((uptime >> 16) & 0xFF);
        d[4] = static_cast<quint8>((uptime >> 8) & 0xFF);
        d[5] = static_cast<quint8>(uptime & 0xFF);
        d[6] = 0;                                                // ошибок шины нет
        quint8 xorSum = 0;
        for (int i = 0; i < 7; ++i)
            xorSum ^= d[i];
        d[7] = xorSum;
        handleFrame(kIdDevice, d, 8);
    }
}
