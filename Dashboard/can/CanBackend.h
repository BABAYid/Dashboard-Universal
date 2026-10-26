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
    Q_PROPERTY(double avgConsumption5min READ avgConsumption5min NOTIFY avgConsumption5minChanged)  // л/100 км за 5 мин
    Q_PROPERTY(double avgSpeed READ avgSpeed NOTIFY avgSpeedChanged)                // км/ч
    Q_PROPERTY(double rangeKm READ rangeKm NOTIFY rangeKmChanged)                   // запас хода, км
    Q_PROPERTY(bool rangeKmValid READ rangeKmValid NOTIFY rangeKmValidChanged)      // запас достоверен
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

    // --- 0x510: климат (протокол 1.3) ---
    // Родная панель климата управляет заслонками и вентилятором сама, блок
    // сбора только читает её состояние. Если кадры не приходят, valid = false,
    // и интерфейс пишет «нет данных», а не выдуманную уставку. Числа, которых
    // нет, отдаём NaN (в QML это проверяется через Number.isNaN).
    Q_PROPERTY(bool climateValid READ climateValid NOTIFY climateValidChanged)
    Q_PROPERTY(bool climateAc READ climateAc NOTIFY climateAcChanged)
    Q_PROPERTY(bool climateAuto READ climateAuto NOTIFY climateAutoChanged)
    Q_PROPERTY(bool climateRecirculation READ climateRecirculation NOTIFY climateRecirculationChanged)
    Q_PROPERTY(bool climateDefrost READ climateDefrost NOTIFY climateDefrostChanged)
    Q_PROPERTY(bool climateFanAuto READ climateFanAuto NOTIFY climateFanAutoChanged)
    Q_PROPERTY(double climateSetpoint READ climateSetpoint NOTIFY climateSetpointChanged)           // °C
    Q_PROPERTY(int climateFanLevel READ climateFanLevel NOTIFY climateFanLevelChanged)             // 0…7, -1 = нет данных
    Q_PROPERTY(QString climateAirflow READ climateAirflow NOTIFY climateAirflowChanged)           // «лицо+ноги»
    Q_PROPERTY(double climateCabinTemp READ climateCabinTemp NOTIFY climateCabinTempChanged)       // °C
    Q_PROPERTY(double climateEvaporatorTemp READ climateEvaporatorTemp NOTIFY climateEvaporatorTempChanged)  // °C
    Q_PROPERTY(double climateSetpointRight READ climateSetpointRight NOTIFY climateSetpointRightChanged)      // °C

    // --- 0x520 / 0x521: GPS (протокол 1.3) ---
    // Приёмник один на всю систему — на блоке сбора. Приборка показывает
    // машину на карте и раздаёт координаты мультимедиа по сети.
    Q_PROPERTY(bool gpsValid READ gpsValid NOTIFY gpsValidChanged)              // есть фикс и данные свежие
    Q_PROPERTY(double gpsLatitude READ gpsLatitude NOTIFY gpsLatitudeChanged)   // градусы
    Q_PROPERTY(double gpsLongitude READ gpsLongitude NOTIFY gpsLongitudeChanged)
    Q_PROPERTY(double gpsCourse READ gpsCourse NOTIFY gpsCourseChanged)         // °, NaN = нет данных
    Q_PROPERTY(int gpsSpeed READ gpsSpeed NOTIFY gpsSpeedChanged)               // км/ч, -1 = нет данных
    Q_PROPERTY(int gpsSatellites READ gpsSatellites NOTIFY gpsSatellitesChanged)
    Q_PROPERTY(double gpsHdop READ gpsHdop NOTIFY gpsHdopChanged)               // точность, NaN = нет данных
    Q_PROPERTY(int gpsFixType READ gpsFixType NOTIFY gpsFixTypeChanged)         // 0 нет, 1 — 2D, 2 — 3D
    Q_PROPERTY(QString gpsUtcTime READ gpsUtcTime NOTIFY gpsUtcTimeChanged)     // «14:35:20» или пусто

    // --- пробег (в CAN-протоколе его нет, считаем сами и храним в настройках) ---
    Q_PROPERTY(double odometer READ odometer NOTIFY odometerChanged)      // км, всего
    Q_PROPERTY(double tripA READ tripA NOTIFY tripAChanged)               // км
    Q_PROPERTY(double tripB READ tripB NOTIFY tripBChanged)               // км

    // --- история напряжения АКБ для графика: 300 замеров по секунде (5 минут) ---
    // Список от старых к новым. Невалидные замеры — NaN: на графике это разрыв,
    // а не выдуманное значение.
    Q_PROPERTY(QVariantList voltageHistory READ voltageHistory NOTIFY voltageHistoryChanged)

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

    // Подать один сэмпл мгновенного расхода в окно среднего расхода (л/100 км).
    // Нужно тестам: без этого окно за 5 минут пришлось бы проверять реальными
    // секундами ожидания. В обычной работе сэмплы берутся из кадров 0x300.
    Q_INVOKABLE void feedConsumptionSample(double rate);

    // Подать один замер напряжения в историю для графика. Тоже для тестов:
    // 300 секунд ожидания в тесте не нужны.
    Q_INVOKABLE void feedVoltageSample(double volts);

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
    QVariantList voltageHistory() const { return m_voltageHistoryList; }
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

    // Средний расход за последние 5 минут (скользящее окно 300 сэмплов по 1 с).
    // Именно от него считается запас хода: «как я еду сейчас» важнее, чем
    // «как я ехал всю поездку».
    double avgConsumption5min() const { return m_avgConsumption5min; }

    // Запас хода в километрах и признак, что он достоверен. Пока валидного
    // расхода не было, запас не показывается (в QML это «—»), и предупреждение
    // о низком запасе не загорается: ноль здесь значит «неизвестно».
    double rangeKm() const { return m_rangeKm; }
    bool rangeKmValid() const { return m_rangeKmValid; }

    double avgSpeed() const { return m_avgSpeed; }
    int journeySeconds() const { return m_journeySeconds; }
    double tankCapacity() const { return m_tankCapacity; }
    void setTankCapacity(double litres);

    bool deviceAlive() const { return m_deviceAlive; }
    QString deviceFirmware() const { return m_deviceFirmware; }
    uint deviceUptimeSec() const { return m_deviceUptimeSec; }
    int deviceRestarts() const { return m_deviceRestarts; }
    int deviceBusErrors() const { return m_deviceBusErrors; }

    bool gasMode() const { return m_gasMode; }
    bool gasSensorValid() const { return m_gasSensorValid; }
    double gasSensorVolts() const { return m_gasSensorMv / 1000.0; }
    int gasLevelPercent() const { return m_gasLevelPercent; }

    bool climateValid() const { return m_climateValid; }
    bool climateAc() const { return m_climateAc; }
    bool climateAuto() const { return m_climateAuto; }
    bool climateRecirculation() const { return m_climateRecirculation; }
    bool climateDefrost() const { return m_climateDefrost; }
    bool climateFanAuto() const { return m_climateFanAuto; }
    double climateSetpoint() const { return m_climateSetpoint; }
    int climateFanLevel() const { return m_climateFanLevel; }
    QString climateAirflow() const { return m_climateAirflow; }
    double climateCabinTemp() const { return m_climateCabinTemp; }
    double climateEvaporatorTemp() const { return m_climateEvaporatorTemp; }
    double climateSetpointRight() const { return m_climateSetpointRight; }

    bool gpsValid() const { return m_gpsValid; }
    double gpsLatitude() const { return m_gpsLatitude; }
    double gpsLongitude() const { return m_gpsLongitude; }
    double gpsCourse() const { return m_gpsCourse; }
    int gpsSpeed() const { return m_gpsSpeed; }
    int gpsSatellites() const { return m_gpsSatellites; }
    double gpsHdop() const { return m_gpsHdop; }
    int gpsFixType() const { return m_gpsFixType; }
    QString gpsUtcTime() const { return m_gpsUtcTime; }

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
    void voltageHistoryChanged();
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
    void avgConsumption5minChanged();
    void avgSpeedChanged();
    void rangeKmChanged();
    void rangeKmValidChanged();
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
    void climateValidChanged();
    void climateAcChanged();
    void climateAutoChanged();
    void climateRecirculationChanged();
    void climateDefrostChanged();
    void climateFanAutoChanged();
    void climateSetpointChanged();
    void climateFanLevelChanged();
    void climateAirflowChanged();
    void climateCabinTempChanged();
    void climateEvaporatorTempChanged();
    void climateSetpointRightChanged();
    void gpsValidChanged();
    void gpsLatitudeChanged();
    void gpsLongitudeChanged();
    void gpsCourseChanged();
    void gpsSpeedChanged();
    void gpsSatellitesChanged();
    void gpsHdopChanged();
    void gpsFixTypeChanged();
    void gpsUtcTimeChanged();

private:
    void openSocket();
    void readFrames();
    void handleFrame(quint32 id, const quint8 *data, int len);
    void handleMotionFrame(const quint8 *d);
    void handleStatusFrame(const quint8 *d);
    void handleSensorFrame(const quint8 *d);
    void handleGearboxFrame(const quint8 *d);
    void handleDeviceStatusFrame(const quint8 *d);
    void handleGasFrame(const quint8 *d);
    void handleClimateFrame(const quint8 *d);
    void handleGpsPositionFrame(const quint8 *d);
    void handleGpsMotionFrame(const quint8 *d);
    void updateDataValidity();
    void publishJourney();
    void updateConsumptionWindow(double ratePer100km);
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
    bool m_rangeKmValid = false;       // был ли хоть один достоверный расчёт
    int m_journeySeconds = 0;
    double m_tankCapacity = 60.0;
    QElapsedTimer m_journeyClock;
    int m_publishTick = 0;

    // Скользящее окно среднего расхода: 300 сэмплов по 1 секунде (5 минут).
    // Храним кольцом, чтобы не двигать массив на каждом сэмпле.
    static constexpr int kConsumptionWindow = 300;
    double m_consumptionSamples[kConsumptionWindow] = {};
    int m_consumptionIndex = 0;        // куда писать следующий сэмпл
    int m_consumptionCount = 0;        // сколько сэмплов уже набрано (до 300)
    double m_avgConsumption5min = 0;

    // История напряжения АКБ для графика на экране «Напряжение»: кольцо на 300
    // замеров по секунде (5 минут). В QML отдаём готовый список от старых
    // к новым — на 300 значений в секунду это ничтожная работа, зато QML не
    // пересчитывает индексы сам.
    static constexpr int kVoltageHistorySize = 300;
    double m_voltageHistory[kVoltageHistorySize] = {};
    int m_voltageIndex = 0;
    int m_voltageCount = 0;
    QVariantList m_voltageHistoryList;
    void pushVoltageSample(double volts);

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

    // Газовое оборудование (кадр 0x500, протокол 1.2).
    // m_sinceGasFrame нужен для правила свежести: если кадров газа нет дольше
    // 1500 мс, приборка считает, что данных о газе нет, и показывает бензин.
    bool m_gasMode = false;
    bool m_gasSensorValid = false;
    int m_gasSensorMv = 0;             // сырое напряжение датчика, мВ
    int m_gasLevelPercent = 0;         // 0 В — пусто, 5 В — полный
    QElapsedTimer m_sinceGasFrame;

    // Климат (кадр 0x510, протокол 1.3). Значения, которых нет, отдаются как
    // NaN (double) и -1 (int), чтобы QML мог нарисовать «—» вместо нуля.
    bool m_climateValid = false;
    bool m_climateAc = false;
    bool m_climateAuto = false;
    bool m_climateRecirculation = false;
    bool m_climateDefrost = false;
    bool m_climateFanAuto = false;
    double m_climateSetpoint = 0;
    int m_climateFanLevel = -1;
    QString m_climateAirflow;
    double m_climateCabinTemp = 0;
    double m_climateEvaporatorTemp = 0;
    double m_climateSetpointRight = 0;
    QElapsedTimer m_sinceClimateFrame;

    // GPS (кадры 0x520 и 0x521, протокол 1.3)
    bool m_gpsValid = false;
    bool m_gpsFix = false;
    double m_gpsLatitude = 0;
    double m_gpsLongitude = 0;
    double m_gpsCourse = 0;
    int m_gpsSpeed = -1;
    int m_gpsSatellites = 0;
    double m_gpsHdop = 0;
    int m_gpsFixType = 0;
    QString m_gpsUtcTime;
    QElapsedTimer m_sinceGpsFrame;
};
