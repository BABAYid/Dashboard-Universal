#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QReadWriteLock>
#include <QString>
#include <QVector>
#include <QtNumeric>

#include <atomic>

class QFileSystemWatcher;
class QFutureWatcherBase;

// ============================================================================
//  База камер и предупреждения о них (функция «Smart Driver»).
//
//  Данные берутся из файла speedcam.txt формата iGO/OpenSpeedcam:
//      X(долгота),Y(широта),TYPE,SPEED[,DIRTYPE,DIRECTION]
//  см. docs/speedcam.md. Файл обновляется скриптом update_speedcam.sh
//  (systemd timer раз в сутки) — приборка его только читает.
//
//  Позиция приходит по CAN (кадры 0x520/0x521, протокол 1.3) и передаётся
//  в checkPosition() при каждом обновлении координат: там считается расстояние
//  по формуле гаверсинуса до ближайшей камеры, и если она ближе warningDistance
//  и находится впереди по курсу — поднимается предупреждение.
//
//  Производительность:
//    • файл читается в ФОНОВОМ потоке (QtConcurrent): база на сотни тысяч
//      точек не должна задерживать первый кадр приборки;
//    • поиск идёт не перебором всех точек, а по сетке ~0.02° (около 2 км):
//      на каждый вызов просматриваются 9 ячеек вокруг машины;
//    • данные меняются только при перезагрузке базы, поэтому чтение — под
//      QReadWriteLock, а не под мьютексом.
//
//  Класс зарегистрирован как синглтон QML: в QML доступен как SpeedCamManager
//  (по аналогии с CanBackend, MediaBackend, WeatherProvider).
// ============================================================================
class SpeedCamManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // --- состояние базы ---
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)                 // точек в базе
    Q_PROPERTY(QString sourcePath READ sourcePath NOTIFY sourcePathChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

    // --- предупреждение о камере ---
    Q_PROPERTY(bool cameraActive READ cameraActive NOTIFY cameraChanged)
    Q_PROPERTY(QString cameraTypeName READ cameraTypeName NOTIFY cameraChanged)
    Q_PROPERTY(int cameraSpeedLimit READ cameraSpeedLimit NOTIFY cameraChanged)
    Q_PROPERTY(double cameraDistance READ cameraDistance NOTIFY cameraChanged)   // метры
    Q_PROPERTY(QString cameraHeader READ cameraHeader NOTIFY cameraChanged)      // «КАМЕРА: 60 км/ч»
    Q_PROPERTY(QString cameraRangeText READ cameraRangeText NOTIFY cameraChanged) // «ДО КАМЕРЫ: 350 м»
    Q_PROPERTY(bool cameraSpeeding READ cameraSpeeding NOTIFY cameraChanged)     // едем быстрее камеры
    Q_PROPERTY(bool cameraAhead READ cameraAhead NOTIFY cameraChanged)

    // --- настройки ---
    Q_PROPERTY(int warningDistance READ warningDistance WRITE setWarningDistance
               NOTIFY warningDistanceChanged)   // м, по умолчанию 500

public:
    // Без аргумента по умолчанию — иначе QML создаст второй экземпляр,
    // не связанный с тем, что запускает main.cpp (см. CanBackend).
    explicit SpeedCamManager(QObject *parent);
    ~SpeedCamManager() override;

    static SpeedCamManager *instance();
    static SpeedCamManager *create(QQmlEngine *, QJSEngine *) { return instance(); }

    // Загрузить базу (в фоне) и начать отслеживание положения.
    Q_INVOKABLE void start();
    Q_INVOKABLE void reload();

    // Проверить позицию. course — курс в градусах (NaN, если нет данных),
    // speedKmh — текущая скорость (отрицательная, если неизвестна).
    Q_INVOKABLE void checkPosition(double lat, double lon,
                                   double course = qQNaN(),
                                   double speedKmh = -1.0);

    // Демо/проверка без реальной камеры: поставить «камеру» в distanceMeters
    // впереди машины (по курсу, а если курса нет — на север) и сразу её показать.
    Q_INVOKABLE void simulateCameraAhead(int speedLimit = 60, double distanceMeters = 420.0);
    Q_INVOKABLE void clearSimulated();

    bool loaded() const { return m_loaded.load(); }
    bool loading() const { return m_loading.load(); }
    int count() const { return m_count.load(); }
    QString sourcePath() const { return m_sourcePath; }
    QString statusText() const { return m_statusText; }

    bool cameraActive() const { return m_cameraActive; }
    QString cameraTypeName() const { return m_cameraTypeName; }
    int cameraSpeedLimit() const { return m_cameraSpeedLimit; }
    double cameraDistance() const { return m_cameraDistance; }
    QString cameraHeader() const { return m_cameraHeader; }
    QString cameraRangeText() const { return m_cameraRangeText; }
    bool cameraSpeeding() const { return m_cameraSpeeding; }
    bool cameraAhead() const { return m_cameraAhead; }

    int warningDistance() const { return m_warningDistance; }
    void setWarningDistance(int meters);

signals:
    // Камера (или опасность) впереди. Эмитится при появлении новой камеры
    // и при заметном изменении расстояния — в QML по нему играет бип.
    void cameraApproaching(const QString &typeName, int speedLimit, double distance);
    void cameraGone();

    void loadedChanged();
    void loadingChanged();
    void countChanged();
    void sourcePathChanged();
    void statusTextChanged();
    void cameraChanged();
    void warningDistanceChanged();

private:
    struct Point
    {
        double lat = 0.0;
        double lon = 0.0;
        qint16 speed = 0;      // км/ч, 0 — не задано
        qint16 direction = -1; // азимут камеры, -1 — нет данных
        quint8 type = 0;
        quint8 dirType = 0;    // 0 — ненаправленная, 1 — направленная
    };

    struct Database
    {
        QVector<Point> points;
        QHash<quint64, QVector<int>> grid;   // ячейка сетки → индексы точек
        int skippedLines = 0;
        QString path;
        qint64 fileMtime = 0;
    };

    // Чтение файла — выполняется в фоновом потоке.
    void loadSync(const QString &path);
    static QString resolvePath();

    bool findNearest(double lat, double lon, double course,
                     Point *out, double *outDistance, bool *outAhead) const;

    void updateWarning(bool active, const Point &point, double distance, bool ahead);
    void buildStatusText();

    static QString typeName(quint8 type);
    static QString formatDistance(double meters);

    QReadWriteLock m_lock;
    Database m_db;
    QVector<Point> m_simulated;      // инжектированные камеры (демо/тесты)

    std::atomic<bool> m_loaded{false};
    std::atomic<bool> m_loading{false};
    std::atomic<int> m_count{0};

    QString m_sourcePath;
    QString m_statusText;

    bool m_cameraActive = false;
    QString m_cameraTypeName;
    int m_cameraSpeedLimit = 0;
    double m_cameraDistance = 0.0;
    QString m_cameraHeader;
    QString m_cameraRangeText;
    bool m_cameraSpeeding = false;
    bool m_cameraAhead = false;

    int m_warningDistance = 500;

    // Последняя позиция: нужна демо-камере и чтобы не считать дважды.
    double m_lastLat = qQNaN();
    double m_lastLon = qQNaN();
    double m_lastCourse = qQNaN();
    double m_lastSpeed = -1.0;

    // Чтобы не сыпать сигналами на каждое обновление координат (2 Гц).
    double m_lastEmittedDistance = -1.0;
    quint64 m_lastEmittedKey = 0;

    QFutureWatcherBase *m_watcher = nullptr;
};
