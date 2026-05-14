#include "JokeWallBackend.h"

#include <QCoreApplication>
#include <QFuture>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThreadPool>
#include <QtConcurrent/QtConcurrent>

extern "C" {
    char* joke_wall_create_session(const char* args_json);
    char* joke_wall_submit_joke(const char* args_json);
    char* joke_wall_vote(const char* args_json);
    char* joke_wall_close_session(const char* args_json);
    char* joke_wall_fetch_state_json(const char* args_json);
    char* joke_wall_generate_account(const char* args_json);
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
    , m_settings("JokeWall", "JokeWall")
    , m_walletPath(qEnvironmentVariable("NSSA_WALLET_HOME_DIR", ".scaffold/wallet"))
    , m_sequencerUrl(qEnvironmentVariable("NSSA_SEQUENCER_URL", "http://127.0.0.1:3040"))
    , m_programIdHex(qEnvironmentVariable("JOKE_WALL_PROGRAM_ID_HEX"))
    , m_pollTimer(new QTimer(this))
{
    // Load persisted accounts and sessions
    m_adminId     = m_settings.value("adminId").toString();
    m_submitterId = m_settings.value("submitterId").toString();
    m_voterId     = m_settings.value("voterId").toString();

    int sessionCount = m_settings.beginReadArray("sessions");
    for (int i = 0; i < sessionCount; ++i) {
        m_settings.setArrayIndex(i);
        m_sessions << QVariantMap{
            {"pda",        m_settings.value("pda").toString()},
            {"label",      m_settings.value("label").toString()},
            {"is_active",  false},
            {"description",""},
            {"joke_count", 0},
        };
    }
    m_settings.endArray();

    m_currentSessionPda = m_settings.value("currentSessionPda").toString();
    // Auto-select first session if none selected
    if (m_currentSessionPda.isEmpty() && !m_sessions.isEmpty())
        m_currentSessionPda = m_sessions.first().toMap().value("pda").toString();

    connect(m_pollTimer, &QTimer::timeout, this, &JokeWallBackend::refreshState);
    m_pollTimer->start(5000);
    QTimer::singleShot(500, this, &JokeWallBackend::refreshState);
}

JokeWallBackend::~JokeWallBackend() = default;

void JokeWallBackend::saveSettings() {
    m_settings.setValue("adminId",          m_adminId);
    m_settings.setValue("submitterId",      m_submitterId);
    m_settings.setValue("voterId",          m_voterId);
    m_settings.setValue("currentSessionPda", m_currentSessionPda);

    m_settings.beginWriteArray("sessions");
    int i = 0;
    for (const auto& sv : m_sessions) {
        QVariantMap s = sv.toMap();
        m_settings.setArrayIndex(i++);
        m_settings.setValue("pda",   s.value("pda"));
        m_settings.setValue("label", s.value("label"));
    }
    m_settings.endArray();
}

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
        QTimer::singleShot(1500, this, &JokeWallBackend::refreshState);
    }

    if (obj.contains("account_id")) {
        // generate_account result — caller handles it via txSuccess signal
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

    struct JokeItem { int index; QString content; int vote_count; QString submitter; };
    QList<JokeItem> raw;
    for (const auto& jv : s.value("jokes").toArray()) {
        QJsonObject jo = jv.toObject();
        raw.append({
            jo.value("index").toInt(),
            jo.value("content").toString(),
            static_cast<int>(jo.value("vote_count").toDouble(0)),
            jo.value("submitter").toString().left(12) + "…",
        });
    }
    std::stable_sort(raw.begin(), raw.end(), [](const JokeItem& a, const JokeItem& b) {
        return a.vote_count > b.vote_count;
    });

    QVariantList jokes;
    int rank = 1;
    for (const auto& j : raw) {
        jokes << QVariantMap{
            {"index",      j.index},
            {"content",    j.content},
            {"vote_count", j.vote_count},
            {"submitter",  j.submitter},
            {"rank",       rank++},
        };
    }

    if (m_description   != description) { m_description   = description; emit descriptionChanged(); }
    if (m_isActive      != isActive)    { m_isActive      = isActive;    emit isActiveChanged(); }
    if (m_jokeCount     != jokeCount)   { m_jokeCount     = jokeCount;   emit jokeCountChanged(); }
    if (m_sessionExists != exists)      { m_sessionExists = exists;      emit sessionExistsChanged(); }
    m_jokes = jokes;
    emit jokesChanged();

    // Update the matching session in the sessions list
    for (auto& sv : m_sessions) {
        QVariantMap sm = sv.toMap();
        if (sm.value("pda").toString() == m_currentSessionPda) {
            sm["is_active"]  = isActive;
            sm["description"]= description;
            sm["joke_count"] = jokeCount;
            sv = sm;
            emit sessionsChanged();
            break;
        }
    }
}

// ── Account setters ───────────────────────────────────────────────────────────

void JokeWallBackend::setAdminId(const QString& id) {
    m_adminId = id.trimmed();
    emit adminIdChanged();
    saveSettings();
}

void JokeWallBackend::setSubmitterId(const QString& id) {
    m_submitterId = id.trimmed();
    emit submitterIdChanged();
    saveSettings();
}

void JokeWallBackend::setVoterId(const QString& id) {
    m_voterId = id.trimmed();
    emit voterIdChanged();
    saveSettings();
}

// ── Account generation ────────────────────────────────────────────────────────

void JokeWallBackend::generateAccount(const QString& role) {
    if (m_busy) return;
    m_busy = true;
    emit busyChanged();

    QJsonObject args = baseArgs();
    auto* watcher = new QFutureWatcher<QString>(this);
    connect(watcher, &QFutureWatcher<QString>::finished, this, [this, watcher, role]() {
        QString result = watcher->result();
        watcher->deleteLater();
        m_busy = false;
        emit busyChanged();

        QJsonObject obj = QJsonDocument::fromJson(result.toUtf8()).object();
        if (!obj.value("success").toBool()) {
            m_lastError = obj.value("error").toString(result);
            emit lastErrorChanged();
            return;
        }
        m_lastError.clear();
        emit lastErrorChanged();

        QString accountId = obj.value("account_id").toString();
        if (role == "admin") {
            m_adminId = accountId;
            emit adminIdChanged();
        } else if (role == "submitter") {
            m_submitterId = accountId;
            emit submitterIdChanged();
        } else if (role == "voter") {
            m_voterId = accountId;
            emit voterIdChanged();
        }
        saveSettings();
    });
    watcher->setFuture(QtConcurrent::run([args]() {
        return callFfiRaw(joke_wall_generate_account, args);
    }));
}

void JokeWallBackend::generateAdmin()     { generateAccount("admin"); }
void JokeWallBackend::generateSubmitter() { generateAccount("submitter"); }
void JokeWallBackend::generateVoter()     { generateAccount("voter"); }

// ── Session management ────────────────────────────────────────────────────────

void JokeWallBackend::addSession(const QString& pda, const QString& label) {
    QString p = pda.trimmed();
    if (p.isEmpty()) return;
    for (const auto& sv : m_sessions)
        if (sv.toMap().value("pda").toString() == p) return; // already present

    m_sessions << QVariantMap{
        {"pda",        p},
        {"label",      label.trimmed().isEmpty() ? p.left(16) + "…" : label.trimmed()},
        {"is_active",  false},
        {"description",""},
        {"joke_count", 0},
    };
    emit sessionsChanged();
    saveSettings();

    if (m_currentSessionPda.isEmpty())
        selectSession(p);
}

void JokeWallBackend::removeSession(const QString& pda) {
    QString p = pda.trimmed();
    for (int i = 0; i < m_sessions.size(); ++i) {
        if (m_sessions.at(i).toMap().value("pda").toString() == p) {
            m_sessions.removeAt(i);
            emit sessionsChanged();
            if (m_currentSessionPda == p) {
                m_currentSessionPda = m_sessions.isEmpty()
                    ? QString()
                    : m_sessions.first().toMap().value("pda").toString();
                emit currentSessionPdaChanged();
            }
            saveSettings();
            return;
        }
    }
}

void JokeWallBackend::selectSession(const QString& pda) {
    if (m_currentSessionPda == pda) return;
    m_currentSessionPda = pda.trimmed();
    emit currentSessionPdaChanged();
    saveSettings();

    // Reset displayed state immediately
    m_description = ""; emit descriptionChanged();
    m_isActive = false;  emit isActiveChanged();
    m_jokeCount = 0;     emit jokeCountChanged();
    m_sessionExists = false; emit sessionExistsChanged();
    m_jokes.clear();     emit jokesChanged();

    QTimer::singleShot(0, this, &JokeWallBackend::refreshState);
}

// ── Transactions ──────────────────────────────────────────────────────────────

void JokeWallBackend::createSession(const QString& description) {
    if (m_adminId.isEmpty()) { m_lastError = "Admin account not set"; emit lastErrorChanged(); return; }
    QJsonObject args = baseArgs();
    args["admin"]       = m_adminId;
    args["description"] = description;
    dispatchFfi("create_session", [args]() {
        return callFfiRaw(joke_wall_create_session, args);
    });
}

void JokeWallBackend::submitJoke(const QString& content) {
    if (m_adminId.isEmpty() || m_submitterId.isEmpty()) {
        m_lastError = "Admin and submitter accounts required";
        emit lastErrorChanged(); return;
    }
    QJsonObject args = baseArgs();
    args["admin"]     = m_adminId;
    args["submitter"] = m_submitterId;
    args["content"]   = content;
    dispatchFfi("submit_joke", [args]() {
        return callFfiRaw(joke_wall_submit_joke, args);
    });
}

void JokeWallBackend::vote(int jokeIndex) {
    if (m_adminId.isEmpty() || m_voterId.isEmpty()) {
        m_lastError = "Admin and voter accounts required";
        emit lastErrorChanged(); return;
    }
    QJsonObject args = baseArgs();
    args["admin"]      = m_adminId;
    args["voter"]      = m_voterId;
    args["joke_index"] = jokeIndex;
    dispatchFfi("vote", [args]() {
        return callFfiRaw(joke_wall_vote, args);
    });
}

void JokeWallBackend::closeSession() {
    if (m_adminId.isEmpty()) { m_lastError = "Admin account not set"; emit lastErrorChanged(); return; }
    QJsonObject args = baseArgs();
    args["admin"] = m_adminId;
    dispatchFfi("close_session", [args]() {
        return callFfiRaw(joke_wall_close_session, args);
    });
}

void JokeWallBackend::refreshState() {
    if (m_programIdHex.isEmpty() || m_currentSessionPda.isEmpty() || m_busy || m_polling) return;
    QJsonObject args = baseArgs();
    args["session_pda"] = m_currentSessionPda;
    m_polling = true;
    emit pollingChanged();
    QThreadPool::globalInstance()->start([this, args]() {
        QString result = callFfiRaw(joke_wall_fetch_state_json, args);
        QMetaObject::invokeMethod(this, [this, result]() {
            m_polling = false;
            emit pollingChanged();
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
