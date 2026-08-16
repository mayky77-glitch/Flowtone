# Flowtone

Flowtone — бесплатное open-source приложение для macOS, которое локально генерирует инструментальную музыку и воспроизводит её как непрерывную персональную радиостанцию.

Пользователь выбирает жанры, энергию, темп и настроение, при желании описывает вайб текстом, затем запускает станцию. Flowtone заранее создаёт треки, хранит их локально и продолжает воспроизведение из коллекции, если генерация выключена или Mac временно перегружен.

## Статус

Реализован первый development slice:

- нативный SwiftUI shell;
- core-модели станции и prompt composer;
- рекомендация model tier по памяти Mac;
- resource policy и последовательный generation scheduler;
- synthetic WAV engine для end-to-end проверки без model weights;
- process adapter для официального Stable Audio 3 MLX CLI;
- непрерывная очередь из локальной коллекции с автоповтором;
- статистика места по жанрам, лайки, удаление и массовая очистка;
- локальные автоназвания из жанра, настроения, энергии и вайба;
- 20 жанров и изменение настроек во время сессии;
- CLI spike и unit tests.

Настоящие model weights в репозиторий не входят и в текущем milestone не загружались.

- [Product Requirements Document](docs/PRD.md)
- Целевая платформа: Apple Silicon M1 и новее
- Базовый local engine: Stable Audio 3 Small-Music
- Экспериментальный quality engine: ACE-Step 1.5

## Принципы

- Инструментальная музыка без вокала.
- Генерация и пользовательские данные остаются на Mac.
- Никакой обязательной подписки или облачного API.
- Непрерывное воспроизведение важнее обязательной уникальности каждого трека.
- Приоритет низкой средней нагрузки и предсказуемой работы системы.

## План

1. Запустить Stable Audio 3 Small benchmark после принятия model terms.
2. Подключить настоящий engine к UI вместо development preview.
3. Заменить file-level transition на `AVAudioEngine` с буфером current + 2 ready и crossfade.
4. Добавить model downloader и явный license gate.
5. Собрать подписанный и notarized `.dmg`.

## Быстрый старт для разработки

Требования: Apple Silicon Mac, macOS 14+, Swift 6.3 Command Line Tools.

```bash
swift build
swift test
swift run flowtone-spike --hardware
swift run flowtone-spike --engine synthetic --duration 5
swift run Flowtone
```

Подключение настоящего Stable Audio описано в [implementation guide](docs/IMPLEMENTATION.md).

## Лицензирование

Лицензия исходного кода пока не выбрана. Веса моделей распространяются на собственных условиях и не становятся open source автоматически вместе с кодом Flowtone.
