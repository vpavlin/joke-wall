#include "JokeWallBackend.h"

#include <QCoreApplication>
#include <QFuture>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThreadPool>
#include <QtConcurrent/QtConcurrent>

// C FFI — resolved at runtime via dlopen (the .so is co-located with the plugin).
extern "C" {
    char* joke_wall_create_session(const char* args_json);
    char* joke_wall_submit_joke(const char* args_json);
    char* joke_wall_vote(const char* args_json);
    char* joke_wall_close_session(const char* args_json);
    char* joke_wall_fetch_state_json(const char* args_json);
    void  joke_wall_free_string(char* s);
}

static QString callFfiRaw(char* (*fn)(const char*), const QJsonObject& args) {
    QByteArray json = QJsonDocument(args).toJson(QJsonDocument::Compact);
    char* raw = fn(json.constData());
    if (!raw) return R"({"success":false,"error":"null return from FFI"})";
    QString result = QString::fromUtf8(raw);
    joke_wall_free_string(raw);
    return result;
}

JokeWallBackend::JokeWallBackend(LogosAPI* /*api*/, QObject* parent)
    : QObject(parent)
    , m_walletPath(qEnvironmentVariable("NSSA_WALLET_HOME_DIR", ".scaffold/wallet"))
    , m_sequencerUrl(qEnvironmentVariable("NSSA_SEQUENCER_URL", "http://127.0.0.1:3040"))
    , m_programIdHex(qEnvironmentVariable("JOKE_WALL_PROGRAM_ID_HEX"))
    , m_pollTimer(new QTimer(this))
{
    connect(m_pollTimer, &QTimer::timeout, this, &JokeWallBackend::refreshState);
    m_pollTimer->start(5000);
    QTimer::singleShot(500, this, &JokeWallBackend::refreshState);
}

JokeWallBackend::~JokeWallBackend() = default;

QJsonObject JokeWallBackend::baseArgs() const {
    return QJsonObject{
        {"wallet_path",    m_walletPath},
        {"sequencer_url",  m_sequencerUrl},
        {"program_id_hex", m_programIdHex},
    };
}

void JokeWallBackend::dispatchFfi(const QString& operation, std::function<QString()> fn) {
    if (m_busy) return;
    m_busy = true;
    emit busyChanged();

    auto* watcher = new QFutureWatcher<QString>(this);
    connect(watcher, &QFutureWatcher<QString>::finished, this, [this, watcher, operation]() {
        handleFfiResult(operation, watcher->result());
        watcher->deleteLater();
        m_busy = false;
        emit busyChanged();
    });
    watcher->setFuture(QtConcurrent::run(fn));
}

void JokeWallBackend::handleFfiResult(const QString& operation, const QString& result) {
    QJsonObject obj = QJsonDocument::fromJson(result.toUtf8()).object();
    if (!obj.value("success").toBool()) {
        m_lastError = obj.value("error").toString(result);
        emit lastErrorChanged();
        emit txError(operation, m_lastError);
        return;
    }
    m_lastError.clear();
    emit lastErrorChanged();

    if (obj.contains("tx_hash")) {
        m_lastTxHash = obj.value("tx_hash").toString();
        emit lastTxHashChanged();
        emit txSuccess(operation, m_lastTxHash);
        QTimer::singleShot(1000, this, &JokeWallBackend::refreshState);
    }

    if (obj.contains("state")) {
        applyStateJson(obj.value("state").toObject());
    }
}

void JokeWallBackend::applyStateJson(const QJsonObject& s) {
    QString description = s.value("description").toString();
    bool    isActive    = s.value("is_active").toBool();
    int     jokeCount   = static_cast<int>(s.value("joke_count").toDouble(0));
    bool    exists      = !s.value("admin").toString().isEmpty();

    QVariantList jokes;
    for (const auto& jv : s.value("jokes").toArray()) {
        QJsonObject jo = jv.toObject();
        jokes << QVariantMap{
            {"index",      jo.value("index").toInt()},
            {"content",    jo.value("content").toString()},
            {"vote_count", static_cast<int>(jo.value("vote_count").toDouble(0))},
            {"submitter",  jo.value("submitter").toString().left(12) + "…"},
        };
    }

    if (m_description   != description) { m_description   = description; emit descriptionChanged(); }
    if (m_isActive      != isActive)    { m_isActive      = isActive;    emit isActiveChanged(); }
    if (m_jokeCount     != jokeCount)   { m_jokeCount     = jokeCount;   emit jokeCountChanged(); }
    if (m_sessionExists != exists)      { m_sessionExists = exists;      emit sessionExistsChanged(); }
    m_jokes = jokes;
    emit jokesChanged();
}

// ── Public invokables ─────────────────────────────────────────────────────────

void JokeWallBackend::createSession(const QString& adminAccountId, const QString& description) {
    QJsonObject args = baseArgs();
    args["admin"]       = adminAccountId;
    args["description"] = description;
    dispatchFfi("create_session", [args]() {
        return callFfiRaw(joke_wall_create_session, args);
    });
}

void JokeWallBackend::submitJoke(const QString& adminAccountId,
                                  const QString& submitterAccountId,
                                  const QString& content) {
    QJsonObject args = baseArgs();
    args["admin"]     = adminAccountId;
    args["submitter"] = submitterAccountId;
    args["content"]   = content;
    dispatchFfi("submit_joke", [args]() {
        return callFfiRaw(joke_wall_submit_joke, args);
    });
}

void JokeWallBackend::vote(const QString& adminAccountId,
                            const QString& voterAccountId,
                            int jokeIndex) {
    QJsonObject args = baseArgs();
    args["admin"]      = adminAccountId;
    args["voter"]      = voterAccountId;
    args["joke_index"] = jokeIndex;
    dispatchFfi("vote", [args]() {
        return callFfiRaw(joke_wall_vote, args);
    });
}

void JokeWallBackend::closeSession(const QString& adminAccountId) {
    QJsonObject args = baseArgs();
    args["admin"] = adminAccountId;
    dispatchFfi("close_session", [args]() {
        return callFfiRaw(joke_wall_close_session, args);
    });
}

void JokeWallBackend::refreshState() {
    if (m_programIdHex.isEmpty() || m_busy) return;
    QJsonObject args = baseArgs();
    QThreadPool::globalInstance()->start([this, args]() {
        QString result = callFfiRaw(joke_wall_fetch_state_json, args);
        QMetaObject::invokeMethod(this, [this, result]() {
            QJsonObject obj = QJsonDocument::fromJson(result.toUtf8()).object();
            if (obj.value("success").toBool() && obj.contains("state")) {
                m_lastError.clear();
                emit lastErrorChanged();
                applyStateJson(obj.value("state").toObject());
            } else if (!obj.value("success").toBool()) {
                m_lastError = "poll: " + obj.value("error").toString(result);
                emit lastErrorChanged();
            }
        }, Qt::QueuedConnection);
    });
}
