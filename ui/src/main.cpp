// Standalone test harness — loads JokeWallPlugin directly without Basecamp.
// Usage:
//   QML_PATH=ui/qml ./joke_wall_app
//   NSSA_WALLET_HOME_DIR=.scaffold/wallet NSSA_SEQUENCER_URL=http://127.0.0.1:3040 \
//   JOKE_WALL_PROGRAM_ID_HEX=<64-hex> QML_PATH=ui/qml ./joke_wall_app

#include "JokeWallPlugin.h"

#include <QApplication>
#include <QMainWindow>

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    app.setApplicationName("JokeWall");
    app.setApplicationVersion("0.1.0");

    JokeWallPlugin plugin;

    QMainWindow window;
    window.setWindowTitle("JokeWall — Basecamp module preview");
    window.resize(520, 700);

    QWidget* view = plugin.createWidget(nullptr);
    window.setCentralWidget(view);
    window.show();

    return app.exec();
}
