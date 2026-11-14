#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QString>

// ============================================================================
//  Недавние пункты назначения (последние 10), сохраняются между запусками.
//
//  QML-синглтон (как CanBackend): в Main.qml доступен как RecentDestinations.
//  Хранилище — QSettings (ключ nav/recent, JSON-массив
//  [{"name":..,"lat":..,"lon":..}]), то есть обычный файл настроек
//  приложения (~/.config/AudiDashboard/Dashboard.conf).
//
//  Зачем C++, а не QML: Qt.labs.settings в сборке отсутствует, а только
//  QML-объект не умеет надёжно сохраняться при выходе (без прямой записи
//  в файл). QSettings пишет сам и читает на старте.
// ============================================================================
class RecentDestinations : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Список {name, lat, lon}, новые первыми.
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)

public:
    explicit RecentDestinations(QObject *parent = nullptr);

    static RecentDestinations *instance();
    static RecentDestinations *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QVariantList items() const { return m_items; }

    // Запомнить пункт назначения: без дублей (имя + координаты), максимум 10.
    Q_INVOKABLE void add(const QString &name, double lat, double lon);
    Q_INVOKABLE void clear();

    void load();
    void save() const;

signals:
    void itemsChanged();

private:
    QVariantList m_items;
};
