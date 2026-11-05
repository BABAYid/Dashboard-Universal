#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QReadWriteLock>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QtNumeric>

#include <atomic>

class QFutureWatcherBase;

// ============================================================================
//  База камер и предупреждения о них (функция «Smart Driver»).
//
//  Понимает два формата, оба — выгрузки OpenSpeedcam (см. docs/speedcam.md):
//
//  1) iGO «speedcam.txt» (компактный, его ставит update_speedcam.sh):
//         X(долгота),Y(широта),TYPE,SPEED[,DIRTYPE,DIRECTION]
//  2) PocketGIS (то, что отдаёт сервис экспорта OpenSpeedcam как есть):
//         IDX,X,Y,TYPE,SPEED,DIRTYPE,DIRECTION,DISTANCE,ANGLE // id | тип | модель
//     с заголовком «IDX,...,ANGLE // OpenSpeedcam 03-11-2026 19:41».
//     Формат определяется по строке: если первое поле — целое без дробной
//     части, а координаты стоят во 2-м и 3-м полях, это PocketGIS.
//
//  Из базы берутся: координаты, ограничение, направление (DIRTYPE=1 —
//  камера стреляет в одну сторону), рекомендованная дистанция предупреждения
//  и название типа с моделью комплекса («Кордон», «Стрелка+», …).
//
//  Позиция приходит по CAN (кадры 0x520/0x521, протокол 1.3) и передаётся
//  в checkPosition() при каждом обновлении координат: там считается расстояние
//  по формуле гаверсинуса до ближайшей камеры, и если она ближе порога и
//  находится впереди по курсу — поднимается предупреждение.
//
//  Производительность:
//    • файл читается в ФОНОВОМ потоке (QtConcurrent): база на 200+ тысяч
//      точек не должна задерживать первый кадр приборки;
//    • поиск идёт не перебором всех точек, а по сетке ~0.02° (около 2 км):
//      на каждый вызов просматриваются 9 ячеек вокруг машины;
//    • названия типов и моделей хранятся один раз (интернированы), точки
//      ссылаются на них индексами — иначе 200 тысяч одинаковых строк
//      «Статическая камера» съели бы десятки мегабайт;
//    • данные меняются только при перезагрузке базы, поэтому чтение — под
//      QReadWriteLock.
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
    Q_PROPERTY(QString sourceFormat READ sourceFormat NOTIFY statusTextChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

    // --- предупреждение о камере ---
    Q_PROPERTY(bool cameraActive READ cameraActive NOTIFY cameraChanged)
    Q_PROPERTY(QString cameraTypeName READ cameraTypeName NOTIFY cameraChanged)   // «Статическая камера»
    Q_PROPERTY(QString cameraModel READ cameraModel NOTIFY cameraChanged)         // «Кордон», «Стрелка+»
    // Код типа из базы (см. таблицу в docs/speedcam_stats.md) и признак
    // «это камера, а не опасность»: по ним QML выбирает значок и цвет, не
    // разбирая русский текст названия.
    Q_PROPERTY(int cameraType READ cameraType NOTIFY cameraChanged)
    Q_PROPERTY(bool cameraIsSpeedControl READ cameraIsSpeedControl NOTIFY cameraChanged)
    Q_PROPERTY(int cameraSpeedLimit READ cameraSpeedLimit NOTIFY cameraChanged)
    Q_PROPERTY(double cameraDistance READ cameraDistance NOTIFY cameraChanged)    // метры
    Q_PROPERTY(QString cameraHeader READ cameraHeader NOTIFY cameraChanged)       // «КАМЕРА: 60 км/ч»
    Q_PROPERTY(QString cameraRangeText READ cameraRangeText NOTIFY cameraChanged) // «ДО КАМЕРЫ: 350 м»
    Q_PROPERTY(bool cameraSpeeding READ cameraSpeeding NOTIFY cameraChanged)      // едем быстрее камеры
    Q_PROPERTY(bool cameraAhead READ cameraAhead NOTIFY cameraChanged)
    // Включена ли демо-камера (клавиша C, кнопка в настройках). Отдельное
    // свойство: при загруженной реальной базе cameraActive может быть true
    // из-за настоящей камеры, и по нему нельзя понять, что показывает кнопка.
    Q_PROPERTY(bool demoCameraActive READ demoCameraActive NOTIFY cameraChanged)

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
    // Пока её не убрали, она держится впереди (едет вместе с машиной).
    Q_INVOKABLE void simulateCameraAhead(int speedLimit = 60, double distanceMeters = 420.0);
    Q_INVOKABLE void clearSimulated();

    bool loaded() const { return m_loaded.load(); }
    bool loading() const { return m_loading.load(); }
    int count() const { return m_count.load(); }
    QString sourcePath() const { return m_sourcePath; }
    QString sourceFormat() const { return m_sourceFormat; }
    QString statusText() const { return m_statusText; }

    bool cameraActive() const { return m_cameraActive; }
    QString cameraTypeName() const { return m_cameraTypeName; }
    QString cameraModel() const { return m_cameraModel; }
    int cameraType() const { return m_cameraType; }
    // 1 — камера скорости, 3 — красный свет, 5 — засада, 11 — полоса,
    // 20 — пост ДПС. Остальные коды — предупреждения об опасностях.
    bool cameraIsSpeedControl() const
    {
        return m_cameraType == 1 || m_cameraType == 3 || m_cameraType == 5
            || m_cameraType == 11 || m_cameraType == 20;
    }
    int cameraSpeedLimit() const { return m_cameraSpeedLimit; }
    double cameraDistance() const { return m_cameraDistance; }
    QString cameraHeader() const { return m_cameraHeader; }
    QString cameraRangeText() const { return m_cameraRangeText; }
    bool cameraSpeeding() const { return m_cameraSpeeding; }
    bool cameraAhead() const { return m_cameraAhead; }
    bool demoCameraActive() const { return m_simFollow; }

    int warningDistance() const { return m_warningDistance; }
    void setWarningDistance(int meters);

signals:
    // Камера (или опасность) впереди: при появлении новой камеры. В QML по
    // этому сигналу играет бип, поэтому он не повторяется на каждый кадр GPS.
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
        qint16 speed = 0;         // км/ч, 0 — не задано
        qint16 direction = -1;    // азимут камеры, -1 — нет данных
        qint16 warnDistance = 0;  // своя дистанция предупреждения (PocketGIS)
        quint8 type = 0;
        quint8 dirType = 0;       // 0 — без направления, 1 — направленная
        quint16 typeNameIdx = 0;  // индекс в Database::typeNames
        quint16 modelIdx = 0;     // индекс в Database::models
    };

    struct Database
    {
        QVector<Point> points;
        QHash<quint64, QVector<int>> grid;   // ячейка сетки → индексы точек
        QVector<QString> typeNames;          // интернированные названия типов
        QVector<QString> models;             // интернированные модели комплексов
        int skippedLines = 0;
        QString path;
        QString format;      // «PocketGIS» или «iGO speedcam.txt»
        QString sourceDate;  // дата из заголовка PocketGIS («03.11.2026»)
    };

    // Чтение файла — выполняется в фоновом потоке.
    bool loadSync(const QString &path);
    static QStringList resolvePaths();
    static QString explicitPathFromConfig();

    bool findNearest(double lat, double lon, double course,
                     Point *out, double *outDistance, bool *outAhead) const;

    void updateWarning(bool active, const Point &point, double distance, bool ahead);
    void buildStatusText();
    void loadNextCandidate();

    static QString defaultTypeName(int type);
    static QString formatDistance(double meters);

    mutable QReadWriteLock m_lock;   // mutable: чтение из const-методов
    Database m_db;
    QVector<Point> m_simulated;      // инжектированные камеры (демо/тесты)
    QString m_simTypeName;           // название типа для демо-камеры
    QString m_simModel;              // модель для демо-камеры
    // Демо-камера «едет» вместе с машиной: пока её не убрали, она держится
    // в m_simFollowDistance впереди по курсу. Иначе в --mock машина уезжает
    // от неё за полминуты и предупреждение пропадает само — на стенде это
    // выглядит как «кнопка не работает».
    bool m_simFollow = false;
    double m_simFollowDistance = 420.0;
    int m_simFollowSpeed = 60;

    std::atomic<bool> m_loaded{false};
    std::atomic<bool> m_loading{false};
    std::atomic<int> m_count{0};

    QStringList m_pendingPaths;      // кандидаты, ещё не опрошенные
    QString m_sourcePath;
    QString m_sourceFormat;
    QString m_statusText;

    bool m_cameraActive = false;
    QString m_cameraTypeName;
    QString m_cameraModel;
    int m_cameraType = 0;
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
    double m_lastWarningSpeed = -1.0e9;   // скорость, при которой считалось превышение
    quint64 m_lastEmittedKey = 0;

    QFutureWatcherBase *m_watcher = nullptr;
};
