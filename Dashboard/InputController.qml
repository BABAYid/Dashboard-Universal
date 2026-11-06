pragma ComponentBehavior: Bound
import QtQuick

// ==========================================================================
//  СЛОЙ ВВОДА: джойстик BMW iDrive вместо тачскрина
// ==========================================================================
//
// У панели Tianma нет тачскрина, в машине нет мыши, а почти весь интерфейс
// сейчас управляется кликами. Поэтому ввод приходит отдельным кадром CAN
// (0x530, протокол 1.4) от ESP32, к которому подключён джойстик BMW iDrive:
// кнопки, четыре направления, нажатие и энкодер.
//
// Этот компонент — единственное место, где код кнопки превращается в имя
// действия. Так сделано специально: код из протокола не должен расползаться
// по Main.qml, а при смене джойстика (или добавлении кнопок на руле) правится
// одна таблица. Само действие выполняет Main.qml — у него на руках всё
// состояние интерфейса (режимы, навигация, оверлей настроек).
//
// Что делает каждая кнопка — docs/joystick.md.

QtObject {
    id: ic

    // Коды кнопок в кадре 0x530, байт 1 (протокол 1.4). Значения повторяют
    // BMW-джойстик: именно эти коды присылает ESP32 после разбора 0x267.
    enum Button {
        Menu = 1,
        Back,
        Option,
        Radio,
        Media,
        Nav,
        Tel,
        Up,
        Down,
        Left,
        Right,
        Press
    }

    // Имя действия в терминах интерфейса. emit приходит из:
    //   - CanBackend.buttonEvent / encoderTurned (реальный джойстик);
    //   - клавиш-эмулятора на столе (F1…F12, Insert, «=» и «-»).
    signal command(string name)

    // Код кнопки из протокола → имя действия. Пустая строка = кнопка не
    // назначена; Main.qml такие события игнорирует, чтобы новая кнопка на
    // джойстике не роняла приборку, пока ей не придумали действие.
    function nameOfButton(code) {
        switch (code) {
        case InputController.Button.Menu:   return "menu"
        case InputController.Button.Back:   return "back"
        case InputController.Button.Option: return "option"
        case InputController.Button.Radio:  return "radio"
        case InputController.Button.Media:  return "media"
        case InputController.Button.Nav:    return "nav"
        case InputController.Button.Tel:    return "tel"
        case InputController.Button.Up:     return "up"
        case InputController.Button.Down:   return "down"
        case InputController.Button.Left:   return "left"
        case InputController.Button.Right:  return "right"
        case InputController.Button.Press:  return "press"
        }
        return ""
    }

    // Нажатие кнопки: код из кадра 0x530 → действие. Отпускание не обрабатываем:
    // в приборке пока нет длинных нажатий (когда появятся — здесь же добавится
    // таймер удержания, и Main.qml получит те же имена с суффиксом "Hold").
    function button(code) {
        const name = nameOfButton(code)
        if (name !== "")
            ic.command(name)
    }

    // Поворот энкодера: дельта за одно событие (обычно ±1…±4). Знак важен —
    // «вправо по часовой» листает вперёд, «влево» — назад. Один щелчок даёт
    // одно действие, поэтому дельту не суммируем: приборка успевает.
    function encoder(delta) {
        if (delta > 0)
            ic.command("next")
        else if (delta < 0)
            ic.command("prev")
    }
}
