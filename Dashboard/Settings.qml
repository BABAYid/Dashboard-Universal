import QtQuick 2.15
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0

Window {
    id: settingsWindow
    width: 480
    height: 320
    visible: false
    title: "Калибровка приборов"
    modality: Qt.ApplicationModal
    color: "#1A1A1A"

    // Свойства для коэффициентов (передаются из Main.qml)
    property real speedFactor: 1.0
    property real rpmFactor: 1.0
    property real fuelFactor: 1.0
    property real tempFactor: 1.0

    // Сигнал при применении настроек
    signal settingsApplied(real sf, real rf, real ff, real tf)

    // Сохранение настроек
    Settings {
        id: appSettings
        property real savedSpeedFactor: 1.0
        property real savedRpmFactor: 1.0
        property real savedFuelFactor: 1.0
        property real savedTempFactor: 1.0
    }

    // Загружаем сохранённые значения при старте
    Component.onCompleted: {
        speedFactor = appSettings.savedSpeedFactor
        rpmFactor = appSettings.savedRpmFactor
        fuelFactor = appSettings.savedFuelFactor
        tempFactor = appSettings.savedTempFactor
        updateInputs()
    }

    function updateInputs() {
        speedInput.text = speedFactor.toFixed(2)
        rpmInput.text = rpmFactor.toFixed(2)
        fuelInput.text = fuelFactor.toFixed(2)
        tempInput.text = tempFactor.toFixed(2)
    }

    // Фон
    Rectangle {
        anchors.fill: parent
        color: "#1A1A1A"
        radius: 10
        border.color: "#444"
        border.width: 1
    }

    Column {
        anchors.centerIn: parent
        spacing: 12

        Text {
            text: "Настройка коэффициентов"
            color: "white"
            font.pixelSize: 22
            font.bold: true
            font.family: "DIN Condensed"
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Скорость
        Row {
            spacing: 15
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                text: "Скорость:"
                color: "white"
                font.pixelSize: 18
                font.family: "DIN Condensed"
                width: 120
            }
            TextField {
                id: speedInput
                width: 100
                text: "1.00"
                validator: DoubleValidator { bottom: 0.1; top: 10.0 }
                color: "white"
                font.pixelSize: 16
                background: Rectangle {
                    color: "#2A2A2A"
                    radius: 4
                    border.color: "#555"
                }
            }
        }

        // Обороты
        Row {
            spacing: 15
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                text: "Обороты:"
                color: "white"
                font.pixelSize: 18
                font.family: "DIN Condensed"
                width: 120
            }
            TextField {
                id: rpmInput
                width: 100
                text: "1.00"
                validator: DoubleValidator { bottom: 0.1; top: 10.0 }
                color: "white"
                font.pixelSize: 16
                background: Rectangle {
                    color: "#2A2A2A"
                    radius: 4
                    border.color: "#555"
                }
            }
        }

        // Топливо
        Row {
            spacing: 15
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                text: "Топливо:"
                color: "white"
                font.pixelSize: 18
                font.family: "DIN Condensed"
                width: 120
            }
            TextField {
                id: fuelInput
                width: 100
                text: "1.00"
                validator: DoubleValidator { bottom: 0.1; top: 10.0 }
                color: "white"
                font.pixelSize: 16
                background: Rectangle {
                    color: "#2A2A2A"
                    radius: 4
                    border.color: "#555"
                }
            }
        }

        // Температура
        Row {
            spacing: 15
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                text: "Температура:"
                color: "white"
                font.pixelSize: 18
                font.family: "DIN Condensed"
                width: 120
            }
            TextField {
                id: tempInput
                width: 100
                text: "1.00"
                validator: DoubleValidator { bottom: 0.1; top: 10.0 }
                color: "white"
                font.pixelSize: 16
                background: Rectangle {
                    color: "#2A2A2A"
                    radius: 4
                    border.color: "#555"
                }
            }
        }

        Row {
            spacing: 20
            anchors.horizontalCenter: parent.horizontalCenter

            Button {
                text: "Сохранить"
                width: 120
                height: 40
                background: Rectangle {
                    color: "#2A7A3A"
                    radius: 6
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "DIN Condensed"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    speedFactor = parseFloat(speedInput.text) || 1.0
                    rpmFactor = parseFloat(rpmInput.text) || 1.0
                    fuelFactor = parseFloat(fuelInput.text) || 1.0
                    tempFactor = parseFloat(tempInput.text) || 1.0

                    appSettings.savedSpeedFactor = speedFactor
                    appSettings.savedRpmFactor = rpmFactor
                    appSettings.savedFuelFactor = fuelFactor
                    appSettings.savedTempFactor = tempFactor

                    settingsApplied(speedFactor, rpmFactor, fuelFactor, tempFactor)
                    settingsWindow.close()
                }
            }

            Button {
                text: "Отмена"
                width: 120
                height: 40
                background: Rectangle {
                    color: "#4A4A4A"
                    radius: 6
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    font.family: "DIN Condensed"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    // Восстанавливаем значения из сохранённых
                    speedFactor = appSettings.savedSpeedFactor
                    rpmFactor = appSettings.savedRpmFactor
                    fuelFactor = appSettings.savedFuelFactor
                    tempFactor = appSettings.savedTempFactor
                    updateInputs()
                    settingsWindow.close()
                }
            }
        }
    }
}
