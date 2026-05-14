#include "JokeWallPlugin.h"
#include "JokeWallBackend.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWidget>
#include <QUrl>
#include <cstdlib>

JokeWallPlugin::JokeWallPlugin(QObject* parent) : QObject(parent) {}
JokeWallPlugin::~JokeWallPlugin() = default;

void JokeWallPlugin::initLogos(LogosAPI* api) {
    m_api = api;
}

QWidget* JokeWallPlugin::createWidget(LogosAPI* api) {
    if (api) m_api = api;

    if (!m_backend)
        m_backend = new JokeWallBackend(m_api, this);

    auto* view = new QQuickWidget();
    view->engine()->rootContext()->setContextProperty("backend", m_backend);
    view->setResizeMode(QQuickWidget::SizeRootObjectToView);

    const char* qmlPath = std::getenv("QML_PATH");
    if (qmlPath) {
        view->setSource(QUrl::fromLocalFile(
            QString::fromUtf8(qmlPath) + "/Main.qml"));
    } else {
        view->setSource(QUrl("qrc:/qml/Main.qml"));
    }

    return view;
}

void JokeWallPlugin::destroyWidget(QWidget* widget) {
    delete m_backend;
    m_backend = nullptr;
    delete widget;
}
