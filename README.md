# Flowtone

Flowtone — бесплатное приложение для macOS с открытым репозиторием, которое локально генерирует инструментальную музыку и воспроизводит её как непрерывную персональную радиостанцию.

Пользователь выбирает жанры, энергию и настроение, при желании описывает вайб текстом, затем запускает станцию. Темп выбирается автоматически по жанру, энергии и seed. Flowtone заранее создаёт треки, хранит их локально и продолжает воспроизведение из коллекции, если генерация выключена или Mac временно перегружен.

## Статус

Реализован рабочий локальный development slice:

- нативный SwiftUI shell;
- core-модели станции и prompt composer;
- рекомендация model tier по памяти Mac;
- resource policy и последовательный generation scheduler;
- synthetic WAV engine для end-to-end проверки без model weights;
- process adapter для официального Stable Audio 3 MLX CLI;
- `AVAudioEngine` с двумя player nodes, render-clock polling и equal-power crossfade;
- точная шкала времени, назад/вперёд, ±15 секунд, начало/конец и session history;
- интерактивная пластинка с плавным forward/reverse scratch-preview и тонармом по реальной позиции;
- очередь `current + 2 ready`, автоповтор и подмена нового трека в хвосте;
- архив с отдельными вкладками треков и статистики, лайки, удаление и массовая очистка;
- отдельный раздел «Любимые» и запуск любого трека из коллекции;
- локальные автоназвания из жанра, настроения, энергии и вайба;
- 28 жанров, 314 автоматических звуковых профилей и изменение настроек во время сессии;
- случайный микс 2–5 жанров, расширенные Fantasy, Pirate, Cyberpunk и Berlin-rave направления;
- genre-aware prompt-профили и автоматический BPM с контролируемым разнообразием;
- остановка записи новых треков и всплывающее предупреждение при заполнении лимита;
- автоматическое обнаружение установленного Stable Audio runtime;
- выбранная владельцем тёплая retro-иконка с пластинкой;
- MIT-лицензия исходного кода, unsigned `.app` packager, macOS CI и скачиваемый Actions artifact.

Настоящие model weights в репозиторий и `.app` не входят. На тестовом Mac официальный Stable Audio 3 Small MLX runtime установлен вне Git и прошёл offline benchmark.

- [Product Requirements Document](docs/PRD.md)
- [Музыкальная карта пресетов](docs/MUSIC-PRESETS.md)
- Целевая платформа: Apple Silicon M1 и новее
- Базовый local engine: Stable Audio 3 Small-Music
- Экспериментальный quality engine: ACE-Step 1.5

## Принципы

- Инструментальная музыка без вокала.
- Генерация и пользовательские данные остаются на Mac.
- Никакой обязательной подписки или облачного API.
- Непрерывное воспроизведение важнее обязательной уникальности каждого трека.
- Приоритет низкой средней нагрузки и предсказуемой работы системы.

## Что ещё нужно для model-enabled generation

1. Реализовать и проверить ACE-Step adapter для quality tier.
2. Профилировать лёгкий tier на M1/M2 с 8–16 ГБ; текущий benchmark относится только к M4/16 ГБ.
3. Signing/notarization не входят в scope текущего unsigned Actions artifact и потребуют отдельного решения владельца.

## Быстрый старт для разработки

Требования: Apple Silicon Mac, macOS 14+, Swift 6.3 Command Line Tools.

```bash
swift build
swift test
swift run flowtone-spike --hardware
swift run flowtone-spike --engine synthetic --duration 5
swift run Flowtone
scripts/package-app.sh /tmp/flowtone-package
```

Debug-сборка использует явно помеченный synthetic fallback, если локальная модель не установлена.
Release-сборка генерирует музыку только через найденный Stable Audio runtime. Подключение настоящего
Stable Audio описано в [implementation guide](docs/IMPLEMENTATION.md).
В собранный `.app` автоматически включается выбранная иконка из `Assets/AppIcon.icns`.

## Лицензирование

Исходный код Flowtone распространяется по [MIT License](LICENSE). Model weights и условия Stable Audio 3 не входят в MIT и остаются на условиях правообладателей.

## Unsigned macOS artifact

Каждый `push`, включая tag push, создаёт в GitHub Actions artifact `flowtone-unsigned-macos-app-<commit SHA>` на 14 дней. Artifact содержит `Flowtone-unsigned-macos.app.zip`; ZIP создан через `ditto --keepParent`, поэтому сохраняет macOS app bundle. GitHub Release не создаётся.

Bundle не подписан и не notarized. macOS может потребовать явного подтверждения пользователя при первом запуске. Не скачивайте `.app` или ZIP из непроверенных источников.
