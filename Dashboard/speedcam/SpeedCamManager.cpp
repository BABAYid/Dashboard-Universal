#include "SpeedCamManager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QElapsedTimer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QHash>
#include <QLocale>
#include <QSettings>
#include <QStandardPaths>
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
// Индекс «название берём из демо-камеры, а не из базы».
constexpr quint16 kSimulatedNameIdx = 0xFFFF;

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

// Строка из файла: числа всегда ASCII, а вот комментарии PocketGIS в
// Windows-1251 (в UTF-8 они превращаются в «кракозябры»). Сначала пробуем
// UTF-8, при ошибке раскодируем кириллицу по таблице cp1251.
QString decodeText(const QByteArray &bytes)
{
    const QString utf8 = QString::fromUtf8(bytes);
    if (!utf8.contains(QChar::ReplacementCharacter))
        return utf8;

    QString out;
    out.reserve(bytes.size());
    for (char ch : bytes) {
        const uchar c = static_cast<uchar>(ch);
        if (c < 0x80) {
            out.append(QChar(c));
        } else if (c >= 0xC0) {
            out.append(QChar(0x0410 + (c - 0xC0)));   // А..я
        } else {
            switch (c) {
            case 0xA8: out.append(QChar(0x0401)); break;   // Ё
            case 0xB8: out.append(QChar(0x0451)); break;   // ё
            case 0xAB: out.append(QChar(0x00AB)); break;   // «
            case 0xBB: out.append(QChar(0x00BB)); break;   // »
            case 0x96: out.append(QChar(0x2013)); break;   // –
            case 0x97: out.append(QChar(0x2014)); break;   // —
            case 0x85: out.append(QChar(0x2026)); break;   // …
            default:   out.append(QLatin1Char(' ')); break;
            }
        }
    }
    return out;
}

struct ParsedLine
{
    double lat = 0.0;
    double lon = 0.0;
    qint16 speed = 0;
    qint16 direction = -1;
    qint16 warnDistance = 0;
    quint8 type = 0;
    quint8 dirType = 0;
    QString typeName;   // из комментария PocketGIS
    QString model;      // модель комплекса из комментария
};

bool isIntegerToken(const QByteArray &token)
{
    if (token.isEmpty())
        return false;
    for (char ch : token) {
        if ((ch < '0' || ch > '9') && ch != '-' && ch != '+')
            return false;
    }
    return true;
}

// Разбор строки базы. Понимает и компактный iGO (X,Y,TYPE,SPEED,...), и
// PocketGIS (IDX,X,Y,TYPE,SPEED,DIRTYPE,DIRECTION,DISTANCE,ANGLE // id|тип|модель).
bool parseLine(const QByteArray &rawLine, ParsedLine *out)
{
    QByteArray line = rawLine;
    while (line.endsWith('\n') || line.endsWith('\r') || line.endsWith(' '))
        line.chop(1);
    if (line.isEmpty() || line.startsWith('#'))
        return false;

    // Комментарий PocketGIS: «// id | Тип | Модель»
    QByteArray body = line;
    const int commentPos = body.indexOf("//");
    if (commentPos >= 0) {
        const QByteArray comment = body.mid(commentPos + 2).trimmed();
        body = body.left(commentPos);
        const QString decoded = decodeText(comment);
        const QStringList parts = decoded.split(QLatin1Char('|'));
        if (parts.size() >= 2)
            out->typeName = parts.at(1).trimmed();
        if (parts.size() >= 3)
            out->model = parts.at(2).trimmed();
    }

    body = body.trimmed();
    if (body.isEmpty())
        return false;

    QByteArray normalized = body;
    normalized.replace(';', ',');
    normalized.replace('\t', ',');
    const QList<QByteArray> fields = normalized.split(',');
    if (fields.size() < 4)
        return false;

    auto field = [&fields](int index) -> QByteArray {
        return index < fields.size() ? fields.at(index).trimmed() : QByteArray();
    };

    double lon = 0.0;
    double lat = 0.0;
    int typeValue = 1;
    int speedValue = 0;
    int dirTypeValue = 0;
    int directionValue = -1;
    int distanceValue = 0;

    // PocketGIS: первое поле — целый ID точки, дальше X и Y, как в iGO:
    // X — ДОЛГОТА, Y — ШИРОТА. Перепутать нельзя: в базе есть точки с
    // долготой 140° (Дальний Восток), а широта больше 90° не бывает.
    bool pocketGis = false;
    if (fields.size() >= 6 && isIntegerToken(field(0))) {
        bool okLonFirst = false, okLatSecond = false;
        const double x = field(1).toDouble(&okLonFirst);
        const double y = field(2).toDouble(&okLatSecond);
        if (okLonFirst && okLatSecond && std::fabs(x) <= 180.0 && std::fabs(y) <= 90.0
            && field(1).contains('.') && field(2).contains('.')) {
            pocketGis = true;
            lon = x;
            lat = y;
            typeValue = field(3).toInt();
            speedValue = field(4).toInt();
            dirTypeValue = field(5).toInt();
            directionValue = field(6).isEmpty() ? -1 : field(6).toInt();
            distanceValue = field(7).toInt();
        }
    }

    if (!pocketGis) {
        bool okX = false, okY = false;
        const double x = field(0).toDouble(&okX);
        const double y = field(1).toDouble(&okY);
        if (!okX || !okY)
            return false;
        lon = x;
        lat = y;
        typeValue = field(2).isEmpty() ? 1 : field(2).toInt();
        speedValue = field(3).toInt();
        dirTypeValue = field(4).isEmpty() ? 0 : field(4).toInt();
        directionValue = field(5).isEmpty() ? -1 : field(5).toInt();
    }

    // Перепутанные колонки превратились бы в камеры посреди океана.
    if (std::fabs(lat) > 90.0 || std::fabs(lon) > 180.0)
        return false;
    // Точка «0,0» — это «нет данных GPS», а не камера в Гвинейском заливе.
    if (std::fabs(lat) < 0.5 && std::fabs(lon) < 0.5)
        return false;

    out->lat = lat;
    out->lon = lon;
    out->type = static_cast<quint8>(qBound(0, typeValue, 255));
    out->speed = static_cast<qint16>(qBound(0, speedValue, 400));
    // DIRTYPE: 0 — без направления, 1 — направленная. Прочие значения
    // (в выгрузках PocketGIS встречается 2) считаем «без направления»:
    // лучше лишний раз предупредить, чем пропустить камеру.
    out->dirType = static_cast<quint8>(dirTypeValue == 1 ? 1 : 0);
    out->direction = static_cast<qint16>((directionValue >= 0 && directionValue <= 359)
                                             ? directionValue : -1);
    out->warnDistance = static_cast<qint16>(qBound(0, distanceValue, 3000));
    return true;
}

// Дата из заголовка PocketGIS: «// OpenSpeedcam 03-11-2026 19:41».
QString parseExportDate(const QByteArray &line)
{
    const QString text = decodeText(line);
    const int pos = text.indexOf(QStringLiteral("OpenSpeedcam"));
    if (pos < 0)
        return QString();
    const QString rest = text.mid(pos + int(QStringLiteral("OpenSpeedcam").size())).trimmed();
    const QStringList tokens = rest.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const QString &token : tokens) {
        const QDate date = QDate::fromString(token, QStringLiteral("dd-MM-yyyy"));
        if (date.isValid())
            return date.toString(QStringLiteral("dd.MM.yyyy"));
    }
    return QString();
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

    // Что указано явно (DASHBOARD_SPEEDCAM или настройка speedcam/path) —
    // то и читаем, без подстановки других файлов: иначе пустая база молча
    // подменялась бы соседним файлом, и понять, что именно загрузилось,
    // было бы невозможно.
    const QString explicitPath = explicitPathFromConfig();
    if (!explicitPath.isEmpty()) {
        m_pendingPaths = QStringList{explicitPath};
    } else {
        m_pendingPaths = resolvePaths();
    }
    if (m_pendingPaths.isEmpty()) {
        m_sourcePath.clear();
        m_sourceFormat.clear();
        m_statusText = tr("база камер не найдена (speedcam.txt / PocketGis.txt)");
        emit sourcePathChanged();
        emit statusTextChanged();
        m_loaded = true;
        emit loadedChanged();
        qInfo() << "Камеры: файл базы не найден, предупреждения отключены";
        return;
    }

    qInfo() << "Камеры: ищу базу, кандидатов" << m_pendingPaths.size();
    m_loading = true;
    emit loadingChanged();
    loadNextCandidate();
}

// Пробуем кандидатов по очереди: пустой файл-заглушка не должен «затенять»
// настоящую базу, которая лежит рядом (например, PocketGis.txt в корне).
void SpeedCamManager::loadNextCandidate()
{
    while (!m_pendingPaths.isEmpty()) {
        const QString path = m_pendingPaths.takeFirst();
        qInfo() << "Камеры: читаю базу" << path;

        auto *watcher = new QFutureWatcher<bool>(this);
        m_watcher = watcher;
        connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher]() {
            const bool ok = watcher->result();
            watcher->deleteLater();
            m_watcher = nullptr;

            if (ok) {
                int points = 0;
                {
                    QReadLocker locker(&m_lock);
                    points = m_db.points.size();
                    m_sourcePath = m_db.path;
                    m_sourceFormat = m_db.format;
                    m_loaded = true;
                }
                if (points > 0 || m_pendingPaths.isEmpty()) {
                    m_loading = false;
                    emit loadingChanged();
                    m_count = points + m_simulated.size();
                    emit countChanged();
                    emit loadedChanged();
                    emit sourcePathChanged();
                    buildStatusText();
                    emit statusTextChanged();
                    qInfo() << "Камеры: загружено точек" << points
                            << "формат" << m_sourceFormat;
                    return;
                }
                qInfo() << "Камеры: база пустая, ищу следующий файл";
            }
            loadNextCandidate();
        });
        watcher->setFuture(QtConcurrent::run([this, path]() { return loadSync(path); }));
        return;
    }

    // Кандидаты кончились, рабочей базы нет.
    m_loading = false;
    m_loaded = true;
    emit loadingChanged();
    emit loadedChanged();
    buildStatusText();
    emit statusTextChanged();
    qWarning() << "Камеры: рабочая база не найдена";
}

void SpeedCamManager::reload()
{
    if (m_loading.load())
        return;
    start();
}

// Порядок поиска файла описан в docs/speedcam.md: сначала явные указания
// (переменная окружения, настройка), затем домашние папки, затем репозиторий,
// а в самом конце — корень репозитория, куда кладут выгрузку PocketGis.txt.
QString SpeedCamManager::explicitPathFromConfig()
{
    const QByteArray envPath = qgetenv("DASHBOARD_SPEEDCAM");
    if (!envPath.isEmpty()) {
        const QFileInfo info(QString::fromLocal8Bit(envPath));
        if (info.exists() && info.isFile())
            return info.absoluteFilePath();
    }
    const QString configured = QSettings().value(QStringLiteral("speedcam/path")).toString();
    const QFileInfo info(configured);
    if (!configured.isEmpty() && info.exists() && info.isFile())
        return info.absoluteFilePath();
    return QString();
}

QStringList SpeedCamManager::resolvePaths()
{
    QStringList candidates;
    auto addIfExists = [&candidates](const QString &path) {
        if (path.isEmpty())
            return;
        const QFileInfo info(path);
        if (info.exists() && info.isFile() && !candidates.contains(info.absoluteFilePath()))
            candidates << info.absoluteFilePath();
    };

    const QString stateDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    addIfExists(stateDir + QStringLiteral("/speedcam.txt"));
    addIfExists(QDir::homePath() + QStringLiteral("/.local/state/audi-dashboard/speedcam.txt"));
    addIfExists(QDir::homePath() + QStringLiteral("/.local/share/AudiDashboard/speedcam.txt"));

    // Запуск из папки сборки: build/../Dashboard/assets/speedcam/
    const QString appDir = QCoreApplication::applicationDirPath();
    addIfExists(appDir + QStringLiteral("/../Dashboard/assets/speedcam/speedcam.txt"));
    addIfExists(appDir + QStringLiteral("/../../Dashboard/assets/speedcam/speedcam.txt"));
    addIfExists(appDir + QStringLiteral("/assets/speedcam/speedcam.txt"));

    // Репозиторий: и папка базы, и выгрузка PocketGIS в корне.
    const QString cwd = QDir::currentPath();
    addIfExists(cwd + QStringLiteral("/Dashboard/assets/speedcam/speedcam.txt"));
    addIfExists(cwd + QStringLiteral("/Dashboard/assets/speedcam/PocketGis.txt"));
    addIfExists(cwd + QStringLiteral("/PocketGis.txt"));
    addIfExists(appDir + QStringLiteral("/../PocketGis.txt"));

    return candidates;
}

// Фоновый поток: читаем файл и строим сеточный индекс.
bool SpeedCamManager::loadSync(const QString &path)
{
    QElapsedTimer timer;
    timer.start();

    Database db;
    db.path = path;

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "Камеры: не удалось открыть" << path << file.errorString();
        return false;
    }

    // Названия типов и моделей повторяются тысячекратно — храним по разу.
    QHash<QString, quint16> typeNameIds;
    QHash<QString, quint16> modelIds;

    db.points.reserve(250000);
    db.grid.reserve(120000);

    while (!file.atEnd()) {
        const QByteArray raw = file.readLine();
        const QByteArray trimmed = raw.trimmed();
        if (trimmed.isEmpty())
            continue;

        if (trimmed.startsWith("IDX") || trimmed.startsWith("idx")) {
            // Заголовок выгрузки PocketGIS: заодно достаём дату базы.
            if (db.format.isEmpty())
                db.format = QStringLiteral("PocketGIS");
            const QString date = parseExportDate(raw);
            if (!date.isEmpty())
                db.sourceDate = date;
            continue;
        }
        if (trimmed.startsWith('#'))
            continue;

        ParsedLine parsed;
        if (!parseLine(raw, &parsed)) {
            ++db.skippedLines;
            if (db.skippedLines <= 3)
                qWarning() << "Камеры: пропущена строка" << db.skippedLines << raw.left(120);
            continue;
        }

        quint16 nameIdx = 0;
        if (parsed.typeName.isEmpty()) {
            // iGO-файл: названия типов берём из встроенной таблицы.
            const QString fallback = defaultTypeName(parsed.type);
            auto it = typeNameIds.constFind(fallback);
            if (it != typeNameIds.constEnd()) {
                nameIdx = it.value();
            } else {
                nameIdx = static_cast<quint16>(db.typeNames.size());
                db.typeNames.append(fallback);
                typeNameIds.insert(fallback, nameIdx);
            }
        } else {
            auto it = typeNameIds.constFind(parsed.typeName);
            if (it != typeNameIds.constEnd()) {
                nameIdx = it.value();
            } else {
                nameIdx = static_cast<quint16>(db.typeNames.size());
                db.typeNames.append(parsed.typeName);
                typeNameIds.insert(parsed.typeName, nameIdx);
            }
        }

        quint16 modelIdx = 0;
        if (!parsed.model.isEmpty()) {
            auto it = modelIds.constFind(parsed.model);
            if (it != modelIds.constEnd()) {
                modelIdx = it.value();
            } else {
                modelIdx = static_cast<quint16>(db.models.size());
                db.models.append(parsed.model);
                modelIds.insert(parsed.model, modelIdx);
            }
        }

        const int index = db.points.size();
        Point p;
        p.lat = parsed.lat;
        p.lon = parsed.lon;
        p.speed = parsed.speed;
        p.type = parsed.type;
        p.dirType = parsed.dirType;
        p.direction = parsed.direction;
        p.warnDistance = parsed.warnDistance;
        p.typeNameIdx = nameIdx;
        p.modelIdx = modelIdx;
        db.points.append(p);
        db.grid[cellKey(cellIndex(p.lat), cellIndex(p.lon))].append(index);
    }

    if (db.format.isEmpty())
        db.format = QStringLiteral("iGO speedcam.txt");

    const int points = db.points.size();
    QWriteLocker locker(&m_lock);
    m_db = std::move(db);
    qInfo() << "Камеры: база прочитана за" << timer.elapsed() << "мс, точек" << points;
    return true;
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

    bool empty = false;
    {
        QReadLocker locker(&m_lock);
        empty = m_db.points.isEmpty() && m_simulated.isEmpty();
    }
    if (!m_warningDistance || empty) {
        updateWarning(false, Point{}, 0.0, false);
        return;
    }

    // Демо-камера держится впереди по курсу, пока её не убрали.
    if (m_simFollow) {
        const double rad = deg2rad(std::isfinite(course) ? course : 0.0);
        Point p;
        p.type = 1;
        p.speed = static_cast<qint16>(qBound(0, m_simFollowSpeed, 400));
        p.dirType = 0;
        p.direction = -1;
        p.typeNameIdx = kSimulatedNameIdx;
        p.lat = lat + (m_simFollowDistance * std::cos(rad)) / 111320.0;
        p.lon = lon + (m_simFollowDistance * std::sin(rad)) /
                          (111320.0 * std::max(0.05, std::cos(deg2rad(lat))));
        QWriteLocker locker(&m_lock);
        m_simulated.clear();
        m_simulated.append(p);
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
    const int latCell = cellIndex(lat);
    const int lonCell = cellIndex(lon);

    double bestDistance = m_warningDistance + 1.0;
    bool bestAhead = false;
    Point best;
    bool haveBest = false;

    auto consider = [&](const Point &p, double dist) {
        // У точки может быть своя дистанция предупреждения (в PocketGIS —
        // колонка DISTANCE: 100 м для «лежачего полицейского», 500 м для
        // камеры). Берём меньшую из неё и общей настройки.
        const double limit = (p.warnDistance > 0 && p.warnDistance < m_warningDistance)
                                 ? p.warnDistance
                                 : m_warningDistance;
        if (dist > limit || dist >= bestDistance)
            return;

        // Направленная камера стреляет в поток, идущий в её сторону: встречную
        // камеру показывать не нужно, иначе предупреждения сыпятся всю дорогу.
        if (p.dirType == 1 && p.direction >= 0 && std::isfinite(course) &&
            angleDiff(course, p.direction) > kDirectionToleranceDeg) {
            return;
        }

        // Камера должна быть впереди по нашему курсу. Если курс неизвестен
        // (нет данных GPS), направление не проверяем — лучше предупредить.
        bool ahead = true;
        if (std::isfinite(course)) {
            const double toCamera = bearing(lat, lon, p.lat, p.lon);
            ahead = angleDiff(course, toCamera) <= kAheadToleranceDeg;
            if (!ahead)
                return;   // проехали — предупреждение снимается
        }

        best = p;
        bestDistance = dist;
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
        m_cameraModel.clear();
        m_cameraSpeedLimit = 0;
        m_cameraDistance = 0.0;
        m_cameraHeader.clear();
        m_cameraRangeText.clear();
        m_cameraSpeeding = false;
        m_cameraAhead = false;
        m_lastEmittedKey = 0;
        m_lastEmittedDistance = -1.0;
        m_lastWarningSpeed = -1.0e9;
        emit cameraChanged();
        emit cameraGone();
        return;
    }

    const bool newCamera = (key != m_lastEmittedKey);
    const bool distanceChanged = std::fabs(distance - m_lastEmittedDistance) >= kDistanceEpsilon;
    const bool speedChanged = std::fabs(m_lastSpeed - m_lastWarningSpeed) > 0.5;
    if (!newCamera && !distanceChanged && !speedChanged && active == wasActive)
        return;

    QString typeName;
    QString model;
    {
        QReadLocker locker(&m_lock);
        if (point.typeNameIdx == kSimulatedNameIdx) {
            typeName = m_simTypeName;
            model = m_simModel;
        } else {
            if (point.typeNameIdx < m_db.typeNames.size())
                typeName = m_db.typeNames.at(point.typeNameIdx);
            if (point.modelIdx < m_db.models.size())
                model = m_db.models.at(point.modelIdx);
        }
    }
    if (typeName.isEmpty())
        typeName = defaultTypeName(point.type);

    m_cameraActive = true;
    m_cameraTypeName = typeName;
    m_cameraModel = model;
    m_cameraSpeedLimit = point.speed;
    m_cameraDistance = distance;
    m_cameraAhead = ahead;
    m_cameraSpeeding = (point.speed > 0) && (m_lastSpeed > 0.0) && (m_lastSpeed > point.speed + 0.5);
    if (point.speed > 0) {
        m_cameraHeader = tr("КАМЕРА: %1 км/ч").arg(point.speed);
    } else {
        m_cameraHeader = typeName.toUpper();
    }
    m_cameraRangeText = tr("ДО КАМЕРЫ: %1").arg(formatDistance(distance));

    m_lastEmittedKey = key;
    m_lastEmittedDistance = distance;
    m_lastWarningSpeed = m_lastSpeed;

    emit cameraChanged();
    if (newCamera || !wasActive) {
        qInfo() << "Камеры: впереди" << m_cameraTypeName << m_cameraModel
                << "ограничение" << m_cameraSpeedLimit << "км/ч, до неё"
                << qRound(distance) << "м" << (m_cameraSpeeding ? "(превышение)" : "");
        emit cameraApproaching(m_cameraTypeName, m_cameraSpeedLimit, distance);
    }
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
    p.typeNameIdx = kSimulatedNameIdx;
    p.lat = lat + (distanceMeters * std::cos(courseRad)) / 111320.0;
    p.lon = lon + (distanceMeters * std::sin(courseRad)) /
                      (111320.0 * std::max(0.05, std::cos(deg2rad(lat))));

    m_simFollow = true;
    m_simFollowDistance = distanceMeters;
    m_simFollowSpeed = p.speed;
    m_simTypeName = tr("Статическая камера (демо)");
    m_simModel = tr("проверка");

    int points = 0;
    {
        QWriteLocker locker(&m_lock);
        m_simulated.clear();
        m_simulated.append(p);
        points = m_db.points.size();
    }
    m_count = points + 1;
    emit countChanged();
    buildStatusText();
    emit statusTextChanged();

    qInfo() << "Камеры: демо-камера поставлена в" << distanceMeters << "м впереди,"
            << "ограничение" << speedLimit << "км/ч";

    checkPosition(lat, lon, m_lastCourse, m_lastSpeed);
}

void SpeedCamManager::clearSimulated()
{
    m_simFollow = false;
    int points = 0;
    {
        QWriteLocker locker(&m_lock);
        m_simulated.clear();
        points = m_db.points.size();
    }
    m_count = points;
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
    const int clamped = qBound(50, meters, 2000);
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
    QString date;
    {
        QReadLocker locker(&m_lock);
        date = m_db.sourceDate;
    }
    if (date.isEmpty() && !m_sourcePath.isEmpty()) {
        const QDateTime modified = QFileInfo(m_sourcePath).lastModified();
        if (modified.isValid())
            date = modified.toString(QStringLiteral("dd.MM.yyyy HH:mm"));
    }
    if (!date.isEmpty())
        text += tr(", %1").arg(date);
    m_statusText = text;
}

// Названия типов по кодам OpenSpeedcam. Используются, если в файле нет
// комментария с названием (компактный iGO-формат).
QString SpeedCamManager::defaultTypeName(int type)
{
    switch (type) {
    case 0:
    case 1: return tr("Статическая камера");
    case 2:
    case 3: return tr("Контроль проезда на красный");
    case 5: return tr("Мобильная засада");
    case 11: return tr("Контроль движения по полосе");
    case 20: return tr("Стационарный пост ДПС");
    case 21: return tr("Железнодорожный переезд");
    case 22: return tr("Пешеходный переход");
    case 100: return tr("Начало населённого пункта");
    case 101: return tr("Ограничение скорости");
    case 102: return tr("Искусственная неровность");
    case 103: return tr("Плохая дорога");
    case 104: return tr("Опасный поворот");
    case 105: return tr("Опасный перекрёсток");
    case 106: return tr("Другая опасность");
    case 107: return tr("Обгон запрещён");
    default: return tr("Камера");
    }
}

QString SpeedCamManager::formatDistance(double meters)
{
    const int rounded = static_cast<int>(std::lround(meters / 10.0) * 10);
    if (rounded < 1000)
        return tr("%1 м").arg(rounded);
    return tr("%1 км").arg(QString::number(meters / 1000.0, 'f', 1));
}
