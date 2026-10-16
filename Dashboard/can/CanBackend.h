#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QElapsedTimer>
#include <QString>

class QSocketNotifier;
class QTimer;

// ============================================================================
//  Приём данных по CAN и передача их в QML.
//
//  Транспорт — «сырой» SocketCAN (PF_CAN / SOCK_RAW), без QtSerialBus:
//  на nanoPC-T6 модуль Qt6::SerialBus может отсутствовать, а формат кадра
//  у нас фиксированный (классический CAN, 8 байт, 11-битный ID).
//
//  Протокол: can_protocol_v1.1.txt
//    0x100 — скорость и обороты
//    0x200 — лампы и индикаторы (битовые маски)
//    0x300 — датчики (температура, топливо, напряжение, расход)
//    0x400 — АКПП (режим, передача, LOCK, провода S1/S2/SL)
//
//  Режимы работы:
//    • реальный CAN   — интерфейс задаётся setInterfaceName() (по умолчанию can0)
//    • mock           — setMockMode(true), кадры генерируются внутри и проходят
//                       через тот же разбор, что и настоящие (удобно без железа)
//
//  Класс зарегистрирован как синглтон QML: в Main.qml доступен как CanBackend.
// ============================================================================
class CanBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // --- состояние связи ---
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool dataValid READ dataValid NOTIFY dataValidChanged)
    Q_PROPERTY(QString sourceName READ sourceName NOTIFY sourceNameChanged)
    Q_PROPERTY(int framesReceived READ framesReceived NOTIFY framesReceivedChanged)

    // --- 0x100 ---
    Q_PROPERTY(double speed READ speed NOTIFY speedChanged)              // км/ч
    Q_PROPERTY(int rpm READ rpm NOTIFY rpmChanged)                       // об/мин

    // --- 0x300 ---
    Q_PROPERTY(double fuelLevel READ fuelLevel NOTIFY fuelLevelChanged)        // %
    Q_PROPERTY(double engineTemp READ engineTemp NOTIFY engineTempChanged)     // °C
    Q_PROPERTY(double voltage READ voltage NOTIFY voltageChanged)              // В
    Q_PROPERTY(double outsideTemp READ outsideTemp NOTIFY outsideTempChanged)  // °C
    Q_PROPERTY(double fuelRate READ fuelRate NOTIFY fuelRateChanged)           // л/100 км
    Q_PROPERTY(bool oilPressureAlarm READ oilPressureAlarm NOTIFY oilPressureAlarmChanged)

    // --- 0x200, байт 0: свет ---
    Q_PROPERTY(bool leftTurn READ leftTurn NOTIFY leftTurnChanged)
    Q_PROPERTY(bool rightTurn READ rightTurn NOTIFY rightTurnChanged)
    Q_PROPERTY(bool highBeam READ highBeam NOTIFY highBeamChanged)
    Q_PROPERTY(bool lowBeam READ lowBeam NOTIFY lowBeamChanged)
    Q_PROPERTY(bool positionLights READ positionLights NOTIFY positionLightsChanged)
    Q_PROPERTY(bool fogLights READ fogLights NOTIFY fogLightsChanged)
    Q_PROPERTY(bool reverseLights READ reverseLights NOTIFY reverseLightsChanged)
    Q_PROPERTY(bool brakeLights READ brakeLights NOTIFY brakeLightsChanged)

    // --- 0x200, байт 1: индикаторы ---
    Q_PROPERTY(bool checkEngine READ checkEngine NOTIFY checkEngineChanged)
    Q_PROPERTY(bool absWarning READ absWarning NOTIFY absWarningChanged)
    Q_PROPERTY(bool handBrake READ handBrake NOTIFY handBrakeChanged)
    Q_PROPERTY(bool seatBeltUnfastened READ seatBeltUnfastened NOTIFY seatBeltUnfastenedChanged)

    // --- 0x400: АКПП ---
    Q_PROPERTY(QString gearMode READ gearMode NOTIFY gearModeChanged)     // P/R/N/D1..D4/L
    Q_PROPERTY(bool gearLock READ gearLock NOTIFY gearLockChanged)        // LOCK (SL)

    // --- маршрутный компьютер (считается по пробегу и расходу) ---
    Q_PROPERTY(double journeyKm READ journeyKm NOTIFY journeyKmChanged)              // км за поездку
    Q_PROPERTY(double fuelUsed READ fuelUsed NOTIFY fuelUsedChanged)                // литров за поездку
    Q_PROPERTY(double avgConsumption READ avgConsumption NOTIFY avgConsumptionChanged)  // л/100 км
    Q_PROPERTY(double avgSpeed READ avgSpeed NOTIFY avgSpeedChanged)                // км/ч
    Q_PROPERTY(double rangeKm READ rangeKm NOTIFY rangeKmChanged)                   // запас хода, км
    Q_PROPERTY(int journeySeconds READ journeySeconds NOTIFY journeySecondsChanged)
    Q_PROPERTY(double tankCapacity READ tankCapacity WRITE setTankCapacity NOTIFY tankCapacityChanged)

    // --- 0x7F0: статус блока сбора (протокол 1.1) ---
    Q_PROPERTY(bool deviceAlive READ deviceAlive NOTIFY deviceAliveChanged)
    Q_PROPERTY(QString deviceFirmware READ deviceFirmware NOTIFY deviceFirmwareChanged)
    Q_PROPERTY(uint deviceUptimeSec READ deviceUptimeSec NOTIFY deviceUptimeSecChanged)
    Q_PROPERTY(int deviceRestarts READ deviceRestarts NOTIFY deviceRestartsChanged)
    Q_PROPERTY(int deviceBusErrors READ deviceBusErrors NOTIFY deviceBusErrorsChanged)

    // --- 0x500: газовое оборудование (протокол 1.2) ---
    // Машина двухтопливная (бензин и газ). Блок сбора отдаёт признак «едем на
    // газе» и сырое напряжение датчика уровня газа 0…5 В, а проценты считает
    // приборка: 0 В — пустой баллон, 5 В — полный. Так задумано, чтобы кривую
    // под конкретный датчик владелец мог задать в настройках панели, не
    // перепрошивая ESP32.
    Q_PROPERTY(bool gasMode READ gasMode NOTIFY gasModeChanged)
    Q_PROPERTY(bool gasSensorValid READ gasSensorValid NOTIFY gasSensorValidChanged)
    Q_PROPERTY(double gasSensorVolts READ gasSensorVolts NOTIFY gasSensorVoltsChanged)
    Q_PROPERTY(int gasLevelPercent READ gasLevelPercent NOTIFY gasLevelPercentChanged)

    // --- пробег (в CAN-протоколе его нет, считаем сами и храним в настройках) ---
    Q_PROPERTY(double odometer READ odometer NOTIFY odometerChanged)      // км, всего
    Q_PROPERTY(double tripA READ tripA NOTIFY tripAChanged)               // км
    Q_PROPERTY(double tripB READ tripB NOTIFY tripBChanged)               // км

public:
    // Внимание: конструктор намеренно объявлен БЕЗ аргумента по умолчанию.
    // Qt при регистрации QML-синглтона сначала проверяет, можно ли создать
    // объект конструктором по умолчанию, и только потом — статический create().
    // Если бы класс был default-constructible, QML создал бы ВТОРОЙ экземпляр,
    // не связанный с тем, что запускает main.cpp (данные бы не приходили).
    explicit CanBackend(QObject *parent);
    ~CanBackend() override;

    // Синглтон: доступен и из main.cpp (до загрузки QML), и из QML.
    static CanBackend *instance();
    static CanBackend *create(QQmlEngine *, QJSEngine *) { return instance(); }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void resetJourney();   // обнулить маршрутный компьютер
    Q_INVOKABLE void resetTripA();
    Q_INVOKABLE void resetTripB();

    // Задать пробег вручную: показываем владельцу ввести показание старой
    // приборки при замене панели. Значение сразу пишется в QSettings.
    Q_INVOKABLE void setOdometer(double km);

    // Подать кадр напрямую (минуя шину): используется тестами разбора протокола
    // и позволяет проигрывать записанный трафик без железа.
    Q_INVOKABLE void feedFrame(int id, const QByteArray &data);

    void setInterfaceName(const QString &name) { m_interfaceName = name; }
    void setMockMode(bool on) { m_mockMode = on; }

    bool connected() const { return m_connected; }
    bool dataValid() const { return m_dataValid; }
    QString sourceName() const { return m_sourceName; }
    int framesReceived() const { return m_framesReceived; }

    double speed() const { return m_speed; }
    int rpm() const { return m_rpm; }
    double fuelLevel() const { return m_fuelLevel; }
    double engineTemp() const { return m_engineTemp; }
    double voltage() const { return m_voltage; }
    double outsideTemp() const { return m_outsideTemp; }
    double fuelRate() const { return m_fuelRate; }
    bool oilPressureAlarm() const { return m_oilPressureAlarm; }

    bool leftTurn() const { return m_leftTurn; }
    bool rightTurn() const { return m_rightTurn; }
    bool highBeam() const { return m_highBeam; }
    bool lowBeam() const { return m_lowBeam; }
    bool positionLights() const { return m_positionLights; }
    bool fogLights() const { return m_fogLights; }
    bool reverseLights() const { return m_reverseLights; }
    bool brakeLights() const { return m_brakeLights; }

    bool checkEngine() const { return m_checkEngine; }
    bool absWarning() const { return m_absWarning; }
    bool handBrake() const { return m_handBrake; }
    bool seatBeltUnfastened() const { return m_seatBeltUnfastened; }

    QString gearMode() const { return m_gearMode; }
    bool gearLock() const { return m_gearLock; }

    double odometer() const { return m_odometer; }
    double tripA() const { return m_tripA; }
    double tripB() const { return m_tripB; }

    double journeyKm() const { return m_journeyKm; }
    double fuelUsed() const { return m_fuelUsed; }
    double avgConsumption() const { return m_avgConsumption; }
    double avgSpeed() const { return m_avgSpeed; }
    double rangeKm() const { return m_rangeKm; }
    int journeySeconds() const { return m_journeySeconds; }
    double tankCapacity() const { return m_tankCapacity; }
    void setTankCapacity(double litres) { m_tankCapacity = litres; }

    bool deviceAlive() const { return m_deviceAlive; }
    QString deviceFirmware() const { return m_deviceFirmware; }
    uint deviceUptimeSec() const { return m_deviceUptimeSec; }
    int deviceRestarts() const { return m_deviceRestarts; }
    int deviceBusErrors() const { return m_deviceBusErrors; }

    bool gasMode() const { return m_gasMode; }
    bool gasSensorValid() const { return m_gasSensorValid; }
    double gasSensorVolts() const { return m_gasSensorMv / 1000.0; }
    int gasLevelPercent() const { return m_gasLevelPercent; }

signals:
    void connectedChanged();
    void dataValidChanged();
    void sourceNameChanged();
    void framesReceivedChanged();
    void speedChanged();
    void rpmChanged();
    void fuelLevelChanged();
    void engineTempChanged();
    void voltageChanged();
    void outsideTempChanged();
    void fuelRateChanged();
    void oilPressureAlarmChanged();
    void leftTurnChanged();
    void rightTurnChanged();
    void highBeamChanged();
    void lowBeamChanged();
    void positionLightsChanged();
    void fogLightsChanged();
    void reverseLightsChanged();
    void brakeLightsChanged();
    void checkEngineChanged();
    void absWarningChanged();
    void handBrakeChanged();
    void seatBeltUnfastenedChanged();
    void gearModeChanged();
    void gearLockChanged();
    void odometerChanged();
    void tripAChanged();
    void tripBChanged();
    void journeyKmChanged();
    void fuelUsedChanged();
    void avgConsumptionChanged();
    void avgSpeedChanged();
    void rangeKmChanged();
    void journeySecondsChanged();
    void tankCapacityChanged();
    void deviceAliveChanged();
    void deviceFirmwareChanged();
    void deviceUptimeSecChanged();
    void deviceRestartsChanged();
    void deviceBusErrorsChanged();
    void gasModeChanged();
    void gasSensorValidChanged();
    void gasSensorVoltsChanged();
    void gasLevelPercentChanged();

private:
    void openSocket();
    void readFrames();
    void handleFrame(quint32 id, const quint8 *data, int len);
    void handleMotionFrame(const quint8 *d);
    void handleStatusFrame(const quint8 *d);
    void handleSensorFrame(const quint8 *d);
    void handleGearboxFrame(const quint8 *d);
    void handleDeviceStatusFrame(const quint8 *d);
    void updateDataValidity();
    void publishJourney();
    void accountDistance();
    void loadDistance();
    void saveDistance();
    void startMock();
    void generateMockFrames();

    // Изменение значения с эмиссией сигнала только при реальном изменении
    template <typename T, typename Signal>
    void set(T &field, const T &value, Signal signal)
    {
        if (field == value)
            return;
        field = value;
        emit (this->*signal)();
    }

    QString m_interfaceName = QStringLiteral("can0");
    bool m_mockMode = false;
    int m_socket = -1;
    QSocketNotifier *m_notifier = nullptr;
    QTimer *m_mockTimer = nullptr;
    QTimer *m_watchdog = nullptr;
    QTimer *m_saveTimer = nullptr;

    bool m_connected = false;
    bool m_dataValid = false;
    QString m_sourceName = QStringLiteral("нет связи");
    int m_framesReceived = 0;
    QElapsedTimer m_sinceLastFrame;   // для контроля устаревания данных
    QElapsedTimer m_sinceLastSpeed;   // для подсчёта пробега

    double m_speed = 0;
    int m_rpm = 0;
    double m_fuelLevel = 0;
    double m_engineTemp = 0;
    double m_voltage = 0;
    double m_outsideTemp = 0;
    double m_fuelRate = 0;
    bool m_oilPressureAlarm = false;

    bool m_leftTurn = false;
    bool m_rightTurn = false;
    bool m_highBeam = false;
    bool m_lowBeam = false;
    bool m_positionLights = false;
    bool m_fogLights = false;
    bool m_reverseLights = false;
    bool m_brakeLights = false;

    bool m_checkEngine = false;
    bool m_absWarning = false;
    bool m_handBrake = false;
    bool m_seatBeltUnfastened = false;

    QString m_gearMode = QStringLiteral("P");
    bool m_gearLock = false;

    double m_odometer = 0;
    double m_tripA = 0;
    double m_tripB = 0;

    // Маршрутный компьютер. Накопители (m_journeyKmAcc, m_fuelUsedAcc) обновляются
    // молча на каждом кадре, а в QML отдаются раз в секунду — иначе приборка
    // перерисовывала бы показания 20 раз в секунду без всякой пользы.
    double m_journeyKmAcc = 0;
    double m_fuelUsedAcc = 0;
    double m_journeyKm = 0;
    double m_fuelUsed = 0;
    double m_avgConsumption = 0;
    double m_avgSpeed = 0;
    double m_rangeKm = 0;
    int m_journeySeconds = 0;
    double m_tankCapacity = 60.0;
    QElapsedTimer m_journeyClock;
    int m_publishTick = 0;

    // Статус блока сбора (кадр 0x7F0)
    bool m_deviceAlive = false;
    QString m_deviceFirmware;
    uint m_deviceUptimeSec = 0;
    int m_deviceRestarts = 0;
    int m_deviceBusErrors = 0;
    int m_lastStatusCounter = -1;      // счётчик предыдущего кадра статуса
    quint32 m_lastUptime = 0;
    QElapsedTimer m_sinceDeviceStatus;
    int m_mockLastStatusSecond = -1;   // для отправки 0x7F0 раз в секунду в демо-режиме
    int m_mockStatusCounter = 0;
};
