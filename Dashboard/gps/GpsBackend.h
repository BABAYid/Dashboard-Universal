#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QElapsedTimer>
#include <QString>

class QTcpSocket;
class QTimer;

// ============================================================================
//  GPS на приборке: приёмник один, данные берём у gpsd.
//
//  Транспорт — обычный TCP на локальный gpsd (по умолчанию 127.0.0.1:2947,
//  переопределяется DASHBOARD_GPSD="host:port"). gpsd разбирает NMEA сам,
//  настраивает частоту приёмника (10 Гц для u-blox M10) и отдаёт JSON:
//     {"class":"TPV","mode":3,"lat":..,"lon":..,"track":..,"speed":..}
//     {"class":"SKY","hdop":0.9,"satellites":[...]}
//
//  Почему gpsd, а не прямой разбор NMEA из /dev/ttyUSB0:
//    • одна точка владения данными — и для карты, и для камер, и для
//      сетевого слоя (Android получает car.gps);
//    • gpsd сам держит горячий реконнект приёмника и настраивает частоту;
//    • при смене приёмника (USB-донгл ↔ UART на плате) код не меняется.
//
//  Без приёмника (на столе) тот же протокол по TCP отдаёт тестовый сервер:
//      python3 tools/gps_test_server.py            # порт 2947
//  Приборка ходит к нему без изменений, а при появлении железа достаточно
//  запустить на плате `gpsd -n /dev/ttyUSB0`.
//
//  Устаревание: контракт (docs/integration.md, car.gps) разрешает клиенту
//  держать последнюю позицию не дольше 5 с; после этого valid = false.
//
//  Класс зарегистрирован как синглтон QML: в Main.qml доступен как GpsBackend.
// ============================================================================
class GpsBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // --- состояние приёма ---
    Q_PROPERTY(bool valid READ valid NOTIFY validChanged)            // свежий фикс (≤5 с)
    Q_PROPERTY(int ageMs READ ageMs NOTIFY ageMsChanged)             // возраст координат, мс
    Q_PROPERTY(QString sourceName READ sourceName NOTIFY sourceNameChanged)

    // --- координаты и движение ---
    Q_PROPERTY(double latitude READ latitude NOTIFY latitudeChanged)   // °
    Q_PROPERTY(double longitude READ longitude NOTIFY longitudeChanged)
    Q_PROPERTY(double course READ course NOTIFY courseChanged)        // °, NaN = нет
    Q_PROPERTY(double speedKmh READ speedKmh NOTIFY speedKmhChanged)  // км/ч, NaN = нет

    // --- качество ---
    Q_PROPERTY(int fixType READ fixType NOTIFY fixTypeChanged)        // 0 нет, 2 — 2D, 3 — 3D
    Q_PROPERTY(int satellites READ satellites NOTIFY satellitesChanged)
    Q_PROPERTY(double hdop READ hdop NOTIFY hdopChanged)              // NaN = нет
    Q_PROPERTY(QString utcTime READ utcTime NOTIFY utcTimeChanged)    // как пришло от gpsd

public:
    explicit GpsBackend(QObject *parent = nullptr);
    ~GpsBackend() override;

    static GpsBackend *instance();
    static GpsBackend *create(QQmlEngine *, QJSEngine *) { return instance(); }

    // Начать приём (вызывается из main.cpp до загрузки QML, как CanBackend).
    Q_INVOKABLE void start();

    bool valid() const { return m_valid; }
    int ageMs() const { return m_ageMs; }
    QString sourceName() const { return m_source; }
    double latitude() const { return m_lat; }
    double longitude() const { return m_lon; }
    double course() const { return m_course; }
    double speedKmh() const { return m_speedKmh; }
    int fixType() const { return m_fixType; }
    int satellites() const { return m_satellites; }
    double hdop() const { return m_hdop; }
    QString utcTime() const { return m_utc; }

signals:
    // Каждый TPV с фиксом: удобно для карты и проверки камер.
    void positionUpdated(double lat, double lon, double course, double speedKmh);
    void validChanged();
    void ageMsChanged();
    void sourceNameChanged();
    void latitudeChanged();
    void longitudeChanged();
    void courseChanged();
    void speedKmhChanged();
    void fixTypeChanged();
    void satellitesChanged();
    void hdopChanged();
    void utcTimeChanged();

private slots:
    void onConnected();
    void onReadyRead();
    void onDisconnected();
    void onSocketError();
    void checkStaleness();
    void tryReconnect();

private:
    void openConnection();
    void parseLine(const QByteArray &line);
    void applyTpv(const QJsonObject &tpv);
    void applySky(const QJsonObject &sky);
    void setValid(bool on);

    QTcpSocket *m_socket = nullptr;
    QTimer *m_tick = nullptr;      // раз в секунду: возраст/устаревание
    QTimer *m_retry = nullptr;     // повтор connect, если gpsd ещё не поднят

    QString m_host = QStringLiteral("127.0.0.1");
    quint16 m_port = 2947;
    QString m_source = QStringLiteral("нет связи");

    QElapsedTimer m_lastFix;
    bool m_hasFix = false;
    bool m_valid = false;
    int m_ageMs = -1;

    double m_lat = qQNaN();
    double m_lon = qQNaN();
    double m_course = qQNaN();
    double m_speedKmh = qQNaN();
    double m_hdop = qQNaN();
    int m_fixType = 0;
    int m_satellites = 0;
    QString m_utc;
};
