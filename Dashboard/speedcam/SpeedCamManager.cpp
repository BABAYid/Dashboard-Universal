#include "SpeedCamManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QHash>
#include <QLocale>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>
#include <QtConcurrent/QtConcurrent>

#include <cmath>

namespace {

// Размер ячейки сетки в градусах. 0.02° по широте — это ~2.2 км, то есть
// на запрос предупреждения (500 м) хватает окрестности 3×3 ячейки.
constexpr double kCellSize = 0.02;
// Радиус Земли для гаверсинуса, метры.
constexpr double kEarthRadius = 6371000.0;
// Допуск «камера впереди» по курсу: ±100° — с запасом на повороты и кривые
// дороги, но камера, оставшаяся сзади, уже не показывается.
constexpr double kAheadToleranceDeg = 100.0;
// Допуск совпадения направления камеры с нашим курсом (для направленных камер).
constexpr double kDirectionToleranceDeg = 50.0;
// Минимальное изменение расстояния, после которого имеет смысл обновлять текст.
constexpr double kDistanceEpsilon = 3.0;

double deg2rad(double deg) { return deg * M_PI / 180.0; }
double rad2deg(double rad) { return rad * 180.0 / M_PI; }

// Расстояние по большому кругу (формула гаверсинуса), метры.
double haversine(double lat1, double lon1, double lat2, double lon2)
{
    const double dLat = deg2rad(lat2 - lat1);
    const double dLon = deg2rad(lon2 - lon1);
    const double a = std::sin(dLat / 2) * std::sin(dLat / 2) +
                     std::cos(deg2rad(lat1)) * std::cos(deg2rad(lat2)) *
                         std::sin(dLon / 2) * std::sin(dLon / 2);
    return 2.0 * kEarthRadius * std::asin(std::min(1.0, std::sqrt(a)));
}

// Азимут от точки 1 к точке 2, градусы 0..360 (0 — на север).
double bearing(double lat1, double lon1, double lat2, double lon2)
{
    const double y = std::sin(deg2rad(lon2 - lon1)) * std::cos(deg2rad(lat2));
    const double x = std::cos(deg2rad(lat1)) * std::sin(deg2rad(lat2)) -
                     std::sin(deg2rad(lat1)) * std::cos(deg2rad(lat2)) *
                         std::cos(deg2rad(lon2 - lon1));
    return std::fmod(rad2deg(std::atan2(y, x)) + 360.0, 360.0);
}

// Минимальный угол между направлениями, 0..180.
double angleDiff(double a, double b)
{
    double d = std::fmod(std::fabs(a - b), 360.0);
    return d > 180.0 ? 360.0 - d : d;
}

int cellIndex(double degrees)
{
    return static_cast<int>(std::floor(degrees / kCellSize));
}

quint64 cellKey(int latCell, int lonCell)
{
    return (static_cast<quint64>(static_cast<quint32>(latCell)) << 32) |
           static_cast<quint64>(static_cast<quint32>(lonCell));
}

// Разбор строки базы. Понимает запятую, точку с запятой и табуляцию,
// комментарии «#», заголовок «IDX,X,Y,TYPE,...» и мусорные строки.
bool parseLine(const QString &raw, double *lat, double *lon, qint16 *speed,
               qint16 *direction, quint8 *type, quint8 *dirType)
{
    const QString line = raw.trimmed();
    if (line.isEmpty() || line.startsWith(QLatin1Char('#')) || line.startsWith(QLatin1Char(';')))
        return false;

    QString normalized = line;
    normalized.replace(QLatin1Char(';'), QLatin1Char(','));
    normalized.replace(QLatin1Char('\t'), QLatin1Char(','));

    QStringList fields = normalized.split(QLatin1Char(','), Qt::SkipEmptyParts);
    if (fields.size() < 4)
        return false;

    // Заголовок файла вида «IDX,X,Y,TYPE,SPEED,...» — пропускаем.
    bool okX = false, okY = false;
    const double x = fields.at(0).trimmed().toDouble(&okX);
    const double y = fields.at(1).trimmed().toDouble(&okY);
    if (!okX || !okY)
        return false;

    // X — долгота, Y — широта. Проверяем правдоподобие: иначе перепутанные
    // колонки превратятся в камеры посреди океана.
    const double lonDeg = x;
    const double latDeg = y;
    if (std::fabs(latDeg) > 90.0 || std::fabs(lonDeg) > 180.0)
        return false;

    bool ok = false;
    int typeValue = fields.at(2).trimmed().toInt(&ok);
    if (!ok)
        typeValue = 1;
    int speedValue = fields.at(3).trimmed().toInt(&ok);
    if (!ok)
        speedValue = 0;

    int dirTypeValue = 0;
    int directionValue = -1;
    if (fields.size() >= 6) {
        dirTypeValue = fields.at(4).trimmed().toInt(&ok);
        if (!ok)
            dirTypeValue = 0;
        directionValue = fields.at(5).trimmed().toInt(&ok);
        if (!ok || directionValue < 0 || directionValue > 359)
            directionValue = -1;
    }

    *lat = latDeg;
    *lon = lonDeg;
    *type = static_cast<quint8>(qBound(0, typeValue, 255));
    *speed = static_cast<qint16>(qBound(0, speedValue, 400));
    *dirType = static_cast<quint8>(dirTypeValue != 0 ? 1 : 0);
    *direction = static_cast<qint16>(directionValue);
    return true;
}

} // namespace

// ---------------------------------------------------------------------------
//  Жизненный цикл
// ---------------------------------------------------------------------------
SpeedCamManager::SpeedCamManager(QObject *parent)
    : QObject(parent)
{
    m_statusText = tr("база камер не загружена");
}

SpeedCamManager::~SpeedCamManager()
{
    if (m_watcher) {
        m_watcher->waitForFinished();
        delete m_watcher;
    }
}

SpeedCamManager *SpeedCamManager::instance()
{
    static SpeedCamManager *self = new SpeedCamManager(nullptr);
    return self;
}

void SpeedCamManager::start()
{
    if (m_loading.load())
        return;

    const QString path = resolvePath();
    if (path.isEmpty()) {
        m_sourcePath.clear();
        m_statusText = tr("база камер не найдена (speedcam.txt)");
        emit sourcePathChanged();
        emit statusTextChanged();
        qInfo() << "Камеры: файл базы не найден, предупреждения отключены";
        return;
    }

    m_sourcePath = path;
    emit sourcePathChanged();
    m_loading = true;
    emit loadingChanged();

    qInfo() << "Камеры: читаю базу" << path;

    auto *watcher = new QFutureWatcher<void>(this);
    m_watcher = watcher;
    connect(watcher, &QFutureWatcherBase::finished, this, [this]() {
        m_loading = false;
        emit loadingChanged();
        m_loaded = true;
        emit loadedChanged();
        m_count = m_db.points.size() + m_simulated.size();
        emit countChanged();
        buildStatusText();
        emit statusTextChanged();
        qInfo() << "Камеры: загружено точек" << m_db.points.size()
                << "пропущено строк" << m_db.skippedLines;
    });
    watcher->setFuture(QtConcurrent::run([this, path]() { loadSync(path); }));
}

void SpeedCamManager::reload()
{
    if (m_loading.load())
        return;
    start();
}

// Порядок поиска файла описан в docs/speedcam.md: сначала явные указания
// (переменная окружения, настройка), затем домашние папки, затем репозиторий.
QString SpeedCamManager::resolvePath()
{
    QStringList candidates;

    const QByteArray envPath = qgetenv("DASHBOARD_SPEEDCAM");
    if (!envPath.isEmpty())
        candidates << QString::fromLocal8Bit(envPath);

    const QString configured = QSettings().value(QStringLiteral("speedcam/path")).toString();
    if (!configured.isEmpty())
        candidates << configured;

    const QString fileName = QStringLiteral("speedcam.txt");
    const QString stateDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (!stateDir.isEmpty())
        candidates << stateDir + QStringLiteral("/speedcam.txt");
    candidates << QDir::homePath() + QStringLiteral("/.local/state/audi-dashboard/") + fileName;
    candidates << QDir::homePath() + QStringLiteral("/.local/share/AudiDashboard/") + fileName;

    // Запуск из папки сборки: build/../Dashboard/assets/speedcam/speedcam.txt
    const QString appDir = QCoreApplication::applicationDirPath();
    candidates << appDir + QStringLiteral("/../Dashboard/assets/speedcam/") + fileName;
    candidates << appDir + QStringLiteral("/../../Dashboard/assets/speedcam/") + fileName;
    candidates << appDir + QStringLiteral("/assets/speedcam/") + fileName;

    // Запуск из корня репозитория (./build/appDashboard при cwd = корень).
    candidates << QDir::currentPath() + QStringLiteral("/Dashboard/assets/speedcam/") + fileName;

    for (const QString &path : candidates) {
        const QFileInfo info(path);
        if (info.exists() && info.isFile())
            return info.absoluteFilePath();
    }
    return QString();
}

// Фоновый поток: читаем файл и строим сеточный индекс.
void SpeedCamManager::loadSync(const QString &path)
{
    Database db;
    db.path = path;

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "Камеры: не удалось открыть" << path << file.errorString();
        return;
    }
    db.fileMtime = QFileInfo(path).lastModified().toSecsSinceEpoch();

    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);

    db.points.reserve(200000);
    while (!stream.atEnd()) {
        const QString line = stream.readLine();
        double lat = 0.0, lon = 0.0;
        qint16 speed = 0, direction = -1;
        quint8 type = 0, dirType = 0;
        if (!parseLine(line, &lat, &lon, &speed, &direction, &type, &dirType)) {
            if (!line.trimmed().isEmpty())
                ++db.skippedLines;
            continue;
        }
        const int index = db.points.size();
        Point p;
        p.lat = lat;
        p.lon = lon;
        p.speed = speed;
        p.type = type;
        p.dirType = dirType;
        p.direction = direction;
        db.points.append(p);
        db.grid[cellKey(cellIndex(lat), cellIndex(lon))].append(index);
    }

    QWriteLocker locker(&m_lock);
    m_db = std::move(db);
}

// ---------------------------------------------------------------------------
//  Проверка позиции
// ---------------------------------------------------------------------------
void SpeedCamManager::checkPosition(double lat, double lon, double course, double speedKmh)
{
    if (!std::isfinite(lat) || !std::isfinite(lon))
        return;

    m_lastLat = lat;
    m_lastLon = lon;
    m_lastCourse = course;
    m_lastSpeed = speedKmh;

    if (!m_warningDistance || (m_db.points.isEmpty() && m_simulated.isEmpty())) {
        updateWarning(false, Point{}, 0.0, false);
        return;
    }

    Point found;
    double foundDistance = 0.0;
    bool foundAhead = false;
    if (!findNearest(lat, lon, course, &found, &foundDistance, &foundAhead)) {
        updateWarning(false, Point{}, 0.0, false);
        return;
    }

    updateWarning(true, found, foundDistance, foundAhead);
}

// Ищем ближайшую камеру впереди. Просматриваем 3×3 ячейки сетки вокруг машины
// (около 6 км охвата) плюс демо-камеры. Перебор всех точек не нужен.
bool SpeedCamManager::findNearest(double lat, double lon, double course,
                                  Point *out, double *outDistance, bool *outAhead) const
{
    const double limit = m_warningDistance;
    const int latCell = cellIndex(lat);
    const int lonCell = cellIndex(lon);

    double bestDistance = limit + 1.0;
    bool bestAhead = false;
    Point best;
    bool haveBest = false;

    auto consider = [&](const Point &p, double dist) {
        if (dist > limit || dist >= bestDistance)
            return;

        // Направленная камера стреляет в поток, идущий в её сторону: встречную
        // камеру показывать не нужно, иначе предупреждения сыпятся всю дорогу.
        if (p.dirType == 1 && p.direction >= 0 && std::isfinite(course) &&
            angleDiff(course, p.direction) > kDirectionToleranceDeg) {
            return;
        }

        // Камера впереди по нашему курсу (если курс известен).
        bool ahead = true;
        if (std::isfinite(course)) {
            const double toCamera = bearing(lat, lon, p.lat, p.lon);
            ahead = angleDiff(course, toCamera) <= kAheadToleranceDeg;
        }

        // Небольшой приоритет камере впереди: если рядом есть камера позади,
        // она не должна перебивать камеру, к которой мы едем.
        const double score = ahead ? dist : dist + limit;
        if (haveBest && score >= bestDistance)
            return;

        best = p;
        bestDistance = score;
        bestAhead = ahead;
        *outDistance = dist;
        haveBest = true;
    };

    // Всё под одним замком на чтение: база может подмениться при обновлении
    // из фонового потока, и индексы не должны «съехать» между проходами.
    {
        QReadLocker locker(&m_lock);
        for (int dLat = -1; dLat <= 1; ++dLat) {
            for (int dLon = -1; dLon <= 1; ++dLon) {
                const auto it = m_db.grid.constFind(cellKey(latCell + dLat, lonCell + dLon));
                if (it == m_db.grid.constEnd())
                    continue;
                for (int index : it.value()) {
                    const Point &p = m_db.points.at(index);
                    consider(p, haversine(lat, lon, p.lat, p.lon));
                }
            }
        }
        for (const Point &p : m_simulated)
            consider(p, haversine(lat, lon, p.lat, p.lon));
    }

    if (!haveBest)
        return false;

    *out = best;
    *outAhead = bestAhead;
    return true;
}

void SpeedCamManager::updateWarning(bool active, const Point &point, double distance, bool ahead)
{
    const bool wasActive = m_cameraActive;
    const quint64 key = active
        ? (static_cast<quint64>(qRound64(point.lat * 1.0e6)) << 32) ^
          static_cast<quint64>(qRound64(point.lon * 1.0e6))
        : 0;

    if (!active) {
        if (!wasActive)
            return;
        m_cameraActive = false;
        m_cameraTypeName.clear();
        m_cameraSpeedLimit = 0;
        m_cameraDistance = 0.0;
        m_cameraHeader.clear();
        m_cameraRangeText.clear();
        m_cameraSpeeding = false;
        m_cameraAhead = false;
        m_lastEmittedKey = 0;
        m_lastEmittedDistance = -1.0;
        emit cameraChanged();
        emit cameraGone();
        return;
    }

    const bool newCamera = (key != m_lastEmittedKey);
    const bool distanceChanged = std::fabs(distance - m_lastEmittedDistance) >= kDistanceEpsilon;
    if (!newCamera && !distanceChanged && active == wasActive)
        return;

    m_cameraActive = true;
    m_cameraTypeName = typeName(point.type);
    m_cameraSpeedLimit = point.speed;
    m_cameraDistance = distance;
    m_cameraAhead = ahead;
    m_cameraSpeeding = (point.speed > 0) && (m_lastSpeed > 0.0) && (m_lastSpeed > point.speed + 0.5);
    m_cameraHeader = point.speed > 0
        ? tr("КАМЕРА: %1 км/ч").arg(point.speed)
        : tr("КАМЕРА");
    m_cameraRangeText = tr("ДО КАМЕРЫ: %1").arg(formatDistance(distance));

    m_lastEmittedKey = key;
    m_lastEmittedDistance = distance;

    emit cameraChanged();
    if (newCamera || !wasActive)
        emit cameraApproaching(m_cameraTypeName, m_cameraSpeedLimit, distance);
}

// ---------------------------------------------------------------------------
//  Демо-камера
// ---------------------------------------------------------------------------
void SpeedCamManager::simulateCameraAhead(int speedLimit, double distanceMeters)
{
    // Ставим камеру в distanceMeters впереди машины: по курсу, а если курса
    // нет — строго на север. По той же логике, что и в тестах навигаторов.
    const double lat = std::isfinite(m_lastLat) ? m_lastLat : 55.7520;
    const double lon = std::isfinite(m_lastLon) ? m_lastLon : 37.6175;
    const double course = std::isfinite(m_lastCourse) ? m_lastCourse : 0.0;
    const double courseRad = deg2rad(course);

    Point p;
    p.type = 1;
    p.speed = static_cast<qint16>(qBound(0, speedLimit, 400));
    p.dirType = 0;
    p.direction = -1;
    p.lat = lat + (distanceMeters * std::cos(courseRad)) / 111320.0;
    p.lon = lon + (distanceMeters * std::sin(courseRad)) /
                      (111320.0 * std::max(0.05, std::cos(deg2rad(lat))));

    {
        QWriteLocker locker(&m_lock);
        m_simulated.clear();
        m_simulated.append(p);
    }
    m_count = m_db.points.size() + m_simulated.size();
    emit countChanged();
    buildStatusText();
    emit statusTextChanged();

    qInfo() << "Камеры: демо-камера поставлена в" << distanceMeters << "м впереди,"
            << "ограничение" << speedLimit << "км/ч";

    checkPosition(lat, lon, m_lastCourse, m_lastSpeed);
}

void SpeedCamManager::clearSimulated()
{
    {
        QWriteLocker locker(&m_lock);
        m_simulated.clear();
    }
    m_count = m_db.points.size();
    emit countChanged();
    buildStatusText();
    emit statusTextChanged();

    if (!m_db.points.isEmpty() && std::isfinite(m_lastLat))
        checkPosition(m_lastLat, m_lastLon, m_lastCourse, m_lastSpeed);
    else
        updateWarning(false, Point{}, 0.0, false);
    qInfo() << "Камеры: демо-камера убрана";
}

// ---------------------------------------------------------------------------
//  Мелочи
// ---------------------------------------------------------------------------
void SpeedCamManager::setWarningDistance(int meters)
{
    const int clamped = qBound(50, meters, 5000);
    if (clamped == m_warningDistance)
        return;
    m_warningDistance = clamped;
    emit warningDistanceChanged();
}

void SpeedCamManager::buildStatusText()
{
    const QString file = m_sourcePath.isEmpty()
        ? tr("файл не найден")
        : QFileInfo(m_sourcePath).fileName();

    if (m_count.load() <= 0) {
        m_statusText = tr("база камер пуста (%1)").arg(file);
        return;
    }

    QString text = tr("база: %1 точек").arg(QLocale().toString(m_count.load()));
    if (!m_sourcePath.isEmpty()) {
        const QDateTime modified = QFileInfo(m_sourcePath).lastModified();
        if (modified.isValid())
            text += tr(", обновлена %1").arg(modified.toString(QStringLiteral("dd.MM.yyyy HH:mm")));
    }
    m_statusText = text;
}

QString SpeedCamManager::typeName(quint8 type)
{
    // Коды типов в базе iGO/OpenSpeedcam. Неизвестный код — просто «КАМЕРА»:
    // важнее расстояние и ограничение, а не точное название комплекса.
    switch (type) {
    case 0:
    case 1: return tr("КАМЕРА КОНТРОЛЯ СКОРОСТИ");
    case 2: return tr("КАМЕРА НА КРАСНЫЙ СВЕТ");
    case 3: return tr("КОНТРОЛЬ ПОЛОСЫ ДВИЖЕНИЯ");
    case 4: return tr("КАМЕРА СРЕДНЕЙ СКОРОСТИ");
    case 5: return tr("МОБИЛЬНАЯ ЗАСАДА");
    case 6: return tr("МУЛЯЖ КАМЕРЫ");
    case 7: return tr("КОНТРОЛЬ ПЕРЕКРЁСТКА");
    case 8: return tr("КОНТРОЛЬ Ж/Д ПЕРЕЕЗДА");
    default: return tr("КАМЕРА");
    }
}

QString SpeedCamManager::formatDistance(double meters)
{
    const int rounded = static_cast<int>(std::lround(meters / 10.0) * 10);
    if (rounded < 1000)
        return tr("%1 м").arg(rounded);
    return tr("%1 км").arg(QString::number(meters / 1000.0, 'f', 1));
}
