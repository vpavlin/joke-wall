#pragma once

#include <QFutureWatcher>
#include <QJsonObject>
#include <QObject>
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
    Q_PROPERTY(QString      adminId       READ adminId       NOTIFY adminIdChanged)
    Q_PROPERTY(QString      lastError     READ lastError     NOTIFY lastErrorChanged)
    Q_PROPERTY(QString      lastTxHash    READ lastTxHash    NOTIFY lastTxHashChanged)

public:
    explicit JokeWallBackend(LogosAPI* api, QObject* parent = nullptr);
    ~JokeWallBackend() override;

    QString      description()   const { return m_description; }
    bool         isActive()      const { return m_isActive; }
    int          jokeCount()     const { return m_jokeCount; }
    QVariantList jokes()         const { return m_jokes; }
    bool         sessionExists() const { return m_sessionExists; }
    bool         busy()          const { return m_busy; }
    bool         polling()       const { return m_polling; }
    QString      adminId()       const { return m_adminAccountId; }
    QString      lastError()     const { return m_lastError; }
    QString      lastTxHash()    const { return m_lastTxHash; }

    Q_INVOKABLE void createSession(const QString& adminAccountId, const QString& description);
    Q_INVOKABLE void submitJoke(const QString& adminAccountId, const QString& submitterAccountId,
                                const QString& content);
    Q_INVOKABLE void vote(const QString& adminAccountId, const QString& voterAccountId,
                          int jokeIndex);
    Q_INVOKABLE void closeSession(const QString& adminAccountId);
    Q_INVOKABLE void refreshState();
    Q_INVOKABLE void setAdminId(const QString& adminAccountId);
    Q_INVOKABLE void setSessionPda(const QString& sessionPda);

signals:
    void descriptionChanged();
    void isActiveChanged();
    void jokeCountChanged();
    void jokesChanged();
    void sessionExistsChanged();
    void busyChanged();
    void pollingChanged();
    void adminIdChanged();
    void lastErrorChanged();
    void lastTxHashChanged();
    void txSuccess(const QString& operation, const QString& txHash);
    void txError(const QString& operation, const QString& error);

private:
    void dispatchFfi(const QString& operation, std::function<QString()> fn);
    void handleFfiResult(const QString& operation, const QString& result);
    void applyStateJson(const QJsonObject& state);
    QJsonObject baseArgs() const;

    QString m_walletPath;
    QString m_sequencerUrl;
    QString m_programIdHex;
    QString m_adminAccountId;
    QString m_sessionPda;

    QString      m_description;
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
