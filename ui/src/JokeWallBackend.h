#pragma once

#include <QFutureWatcher>
#include <QJsonObject>
#include <QObject>
#include <QSettings>
#include <QTimer>
#include <QString>
#include <QVariantList>

class LogosAPI;

class JokeWallBackend : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString      description   READ description   NOTIFY descriptionChanged)
    Q_PROPERTY(bool         isActive      READ isActive      NOTIFY isActiveChanged)
    Q_PROPERTY(int          jokeCount     READ jokeCount     NOTIFY jokeCountChanged)
    Q_PROPERTY(QVariantList jokes         READ jokes         NOTIFY jokesChanged)
    Q_PROPERTY(bool         sessionExists READ sessionExists NOTIFY sessionExistsChanged)
    Q_PROPERTY(bool         busy          READ busy          NOTIFY busyChanged)
    Q_PROPERTY(bool         polling       READ polling       NOTIFY pollingChanged)
    Q_PROPERTY(QString      lastError     READ lastError     NOTIFY lastErrorChanged)
    Q_PROPERTY(QString      lastTxHash    READ lastTxHash    NOTIFY lastTxHashChanged)

    // Persisted account IDs
    Q_PROPERTY(QString adminId     READ adminId     WRITE setAdminId     NOTIFY adminIdChanged)
    Q_PROPERTY(QString submitterId READ submitterId WRITE setSubmitterId NOTIFY submitterIdChanged)
    Q_PROPERTY(QString voterId     READ voterId     WRITE setVoterId     NOTIFY voterIdChanged)

    // Sessions list: each item is a QVariantMap { pda, label, is_active, description, joke_count }
    Q_PROPERTY(QVariantList sessions           READ sessions           NOTIFY sessionsChanged)
    Q_PROPERTY(QString      currentSessionPda  READ currentSessionPda  NOTIFY currentSessionPdaChanged)

public:
    explicit JokeWallBackend(LogosAPI* api, QObject* parent = nullptr);
    ~JokeWallBackend() override;

    QString      description()      const { return m_description; }
    bool         isActive()         const { return m_isActive; }
    int          jokeCount()        const { return m_jokeCount; }
    QVariantList jokes()            const { return m_jokes; }
    bool         sessionExists()    const { return m_sessionExists; }
    bool         busy()             const { return m_busy; }
    bool         polling()          const { return m_polling; }
    QString      lastError()        const { return m_lastError; }
    QString      lastTxHash()       const { return m_lastTxHash; }
    QString      adminId()          const { return m_adminId; }
    QString      submitterId()      const { return m_submitterId; }
    QString      voterId()          const { return m_voterId; }
    QVariantList sessions()         const { return m_sessions; }
    QString      currentSessionPda()const { return m_currentSessionPda; }

    Q_INVOKABLE void createSession(const QString& description);
    Q_INVOKABLE void submitJoke(const QString& content);
    Q_INVOKABLE void vote(int jokeIndex);
    Q_INVOKABLE void closeSession();
    Q_INVOKABLE void refreshState();

    Q_INVOKABLE void setAdminId(const QString& id);
    Q_INVOKABLE void setSubmitterId(const QString& id);
    Q_INVOKABLE void setVoterId(const QString& id);

    Q_INVOKABLE void generateAdmin();
    Q_INVOKABLE void generateSubmitter();
    Q_INVOKABLE void generateVoter();

    Q_INVOKABLE void addSession(const QString& pda, const QString& label);
    Q_INVOKABLE void removeSession(const QString& pda);
    Q_INVOKABLE void selectSession(const QString& pda);

signals:
    void descriptionChanged();
    void isActiveChanged();
    void jokeCountChanged();
    void jokesChanged();
    void sessionExistsChanged();
    void busyChanged();
    void pollingChanged();
    void lastErrorChanged();
    void lastTxHashChanged();
    void adminIdChanged();
    void submitterIdChanged();
    void voterIdChanged();
    void sessionsChanged();
    void currentSessionPdaChanged();
    void txSuccess(const QString& operation, const QString& txHash);
    void txError(const QString& operation, const QString& error);

private:
    void dispatchFfi(const QString& operation, std::function<QString()> fn);
    void handleFfiResult(const QString& operation, const QString& result);
    void applyStateJson(const QJsonObject& state);
    void generateAccount(const QString& role);
    void saveSettings();
    QJsonObject baseArgs() const;

    QSettings m_settings;

    QString m_walletPath;
    QString m_sequencerUrl;
    QString m_programIdHex;

    QString m_adminId;
    QString m_submitterId;
    QString m_voterId;
    QString m_currentSessionPda;
    QVariantList m_sessions;

    QString      m_description;
    QString      m_sessionAdminHex;  // admin bytes from session state (hex), for submit/vote
    bool         m_isActive      = false;
    int          m_jokeCount     = 0;
    QVariantList m_jokes;
    bool         m_sessionExists = false;
    bool         m_busy          = false;
    bool         m_polling       = false;
    QString      m_lastError;
    QString      m_lastTxHash;

    QTimer* m_pollTimer;
};
