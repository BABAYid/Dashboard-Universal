#include "RecentDestinations.h"

#include <QCoreApplication>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

namespace {
constexpr int kMaxItems = 10;
constexpr double kEps = 1e-6;
const QString kKey = QStringLiteral("nav/recent");

QString jsonOf(const QVariantList &items)
{
    QJsonArray arr;
    for (const QVariant &v : items) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o.insert(QStringLiteral("name"), m.value(QStringLiteral("name")).toString());
        o.insert(QStringLiteral("lat"), m.value(QStringLiteral("lat")).toDouble());
        o.insert(QStringLiteral("lon"), m.value(QStringLiteral("lon")).toDouble());
        arr.append(o);
    }
    return QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}
} // namespace

RecentDestinations::RecentDestinations(QObject *parent)
    : QObject(parent)
{
    load();
}

RecentDestinations *RecentDestinations::instance()
{
    static RecentDestinations *store = nullptr;
    if (!store)
        store = new RecentDestinations(qApp);
    return store;
}

void RecentDestinations::load()
{
    QSettings settings;
    const QString raw = settings.value(kKey).toString();
    if (raw.isEmpty())
        return;
    const QJsonDocument doc = QJsonDocument::fromJson(raw.toUtf8());
    if (!doc.isArray())
        return;
    m_items.clear();
    for (const QJsonValue &v : doc.array()) {
        const QJsonObject o = v.toObject();
        QVariantMap m;
        m.insert(QStringLiteral("name"), o.value(QStringLiteral("name")).toString());
        m.insert(QStringLiteral("lat"), o.value(QStringLiteral("lat")).toDouble());
        m.insert(QStringLiteral("lon"), o.value(QStringLiteral("lon")).toDouble());
        m_items.append(m);
    }
    if (m_items.size() > kMaxItems)
        m_items = m_items.mid(0, kMaxItems);
    emit itemsChanged();
}

void RecentDestinations::save() const
{
    QSettings settings;
    settings.setValue(kKey, jsonOf(m_items));
}

void RecentDestinations::add(const QString &name, double lat, double lon)
{
    QVariantList out;
    for (const QVariant &v : m_items) {
        const QVariantMap m = v.toMap();
        const bool same = m.value(QStringLiteral("name")).toString() == name
            && qAbs(m.value(QStringLiteral("lat")).toDouble() - lat) < kEps
            && qAbs(m.value(QStringLiteral("lon")).toDouble() - lon) < kEps;
        if (!same)
            out.append(v);
    }
    QVariantMap item;
    item.insert(QStringLiteral("name"), name);
    item.insert(QStringLiteral("lat"), lat);
    item.insert(QStringLiteral("lon"), lon);
    out.prepend(item);
    if (out.size() > kMaxItems)
        out = out.mid(0, kMaxItems);
    m_items = out;
    save();
    emit itemsChanged();
}

void RecentDestinations::clear()
{
    m_items.clear();
    save();
    emit itemsChanged();
}
