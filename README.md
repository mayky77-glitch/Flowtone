# Flowtone

Flowtone — бесплатное приложение для Windows и macOS с открытым репозиторием, которое локально генерирует инструментальную музыку и воспроизводит её как непрерывную персональную радиостанцию.

Пользователь выбирает жанры, темп эфира («Спокойно / Ровно / Энергично») и настроение, при желании описывает вайб текстом, затем запускает станцию. Точный BPM и жанровый профиль выбираются автоматически с контролируемым разнообразием. Flowtone заранее создаёт треки и продолжает воспроизведение из коллекции, если генерация выключена или компьютер временно перегружен.

## Скачать

- [Windows 10/11 x64 — скачать установщик `.exe`](https://github.com/mayky77-glitch/Flowtone/releases/latest/download/Flowtone-Setup-Windows-x64.exe)
- [macOS Apple Silicon — скачать приложение `.zip`](https://github.com/mayky77-glitch/Flowtone/releases/latest/download/Flowtone-macOS-arm64.zip)
- [Все версии и контрольные суммы](https://github.com/mayky77-glitch/Flowtone/releases/latest)

Сборки пока не подписаны коммерческим сертификатом. Поэтому Windows SmartScreen или macOS Gatekeeper могут попросить отдельно подтвердить первый запуск. Скачивайте Flowtone только из раздела Releases этого репозитория.

## Статус

Реализованы рабочие локальные приложения для macOS и Windows:

- нативный SwiftUI shell;
- Windows 10/11 x64 shell с тем же сценарием, визуальным языком и частотой анимации 60 Гц;
- core-модели станции и prompt composer;
- рекомендация model tier по памяти Mac и отдельный Windows-подбор по RAM/CPU;
- resource policy и последовательный generation scheduler;
- synthetic WAV engine для end-to-end проверки без model weights;
- process adapter для официального Stable Audio 3 MLX CLI;
- `AVAudioEngine` с двумя player nodes, render-clock polling и equal-power crossfade;
- точная шкала времени, назад/вперёд, ±15 секунд, начало/конец и session history;
- интерактивная пластинка с плавным forward/reverse scratch-preview и тонармом по реальной позиции;
- адаптивная 60-Гц анимация пластинки, которая останавливается на паузе и в невидимом окне;
- очередь `current + 2 ready`, автоповтор и подмена нового трека в хвосте;
- режимы «Полное радио» (временное окно треков) и «Радио с записью»;
- случайный порядок без близких повторов, session history и безопасное удаление текущего трека;
- архив с отдельными вкладками треков и статистики, лайки, удаление и массовая очистка;
- отдельный раздел «Любимые» и запуск любого трека из коллекции;
- локальные автоназвания до десяти слов из жанра, настроения, темпа эфира и вайба;
- 29 жанров, 350 автоматических звуковых профилей и изменение настроек во время сессии;
- случайный микс 2–5 жанров, расширенные Fantasy, Pirate, Synthwave, Space Rock, Cyberpunk и Berlin-rave направления;
- genre-aware prompt-профили и автоматический BPM с контролируемым разнообразием;
- остановка записи новых треков и всплывающее предупреждение при заполнении лимита;
- последовательная генерация с потоковой записью WAV, очисткой временного кэша и отменой при memory pressure;
- автоматическая установка и подключение Stable Audio 3 Small без Terminal: official pinned runtime, SHA-256 verification, progress/cancel и offline generation;
- четыре Windows-профиля Stable Audio 3 TFLite: автоматический выбор по RAM/CPU, ручная установка и удаление, автоматическое подключение доступной модели;
- один фоновый generation process, ограниченные потоки, контроль свободной памяти и полная остановка анимации в скрытом окне Windows;
- выбранная владельцем тёплая retro-иконка с пластинкой;
- MIT-лицензия исходного кода, unsigned `.app`/`.exe` packagers, CI обеих платформ и GitHub Release по тегу.

Настоящие model weights в репозиторий, `.app` и `.exe` не входят. После личного прочтения official model/license pages приложение само скачивает public optimized bundle и подключает его; token не нужен и не сохраняется. На Windows Flowtone рекомендует один из четырёх профилей по объёму RAM и числу CPU-потоков, но пользователь всегда может установить, удалить или выбрать другой. Каждый production generation process запускается отдельно, а после одного трека освобождает память модели.

- [Product Requirements Document](docs/PRD.md)
- [Музыкальная карта пресетов](docs/MUSIC-PRESETS.md)
- Целевые платформы: Windows 10/11 x64 и Apple Silicon M1 или новее
- Базовый local engine: Stable Audio 3 Small-Music
- Экспериментальный quality engine: ACE-Step 1.5

## Принципы

- Инструментальная музыка без вокала.
- Генерация и пользовательские данные остаются на устройстве.
- Никакой обязательной подписки или облачного API.
- Непрерывное воспроизведение важнее обязательной уникальности каждого трека.
- Приоритет низкой средней нагрузки и предсказуемой работы системы.

## Что ещё нужно проверить перед стабильным выпуском

1. Реализовать и проверить ACE-Step adapter для quality tier.
2. Профилировать лёгкий tier на M1/M2 с 8–16 ГБ; текущий benchmark относится только к M4/16 ГБ.
3. Провести аппаратные тесты Windows-профилей на нескольких CPU/GPU и объёмах RAM.
4. Signing/notarization не входят в scope текущих unsigned сборок и потребуют отдельного решения владельца.

## Быстрый старт для разработки macOS

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
Stable Audio выполняется из окна «Настроить модель» и описано в [implementation guide](docs/IMPLEMENTATION.md).
В собранный `.app` автоматически включается выбранная иконка из `Assets/AppIcon.icns`.

## Быстрый старт для разработки Windows

Требования: Windows 10/11 x64 и Node.js 24.

```powershell
cd windows
npm ci
npm run check
npm test
npm start
```

Установщик создаётся командой `npm run dist:win`. Папка `windows/dist/` не добавляется в Git; релизный `.exe` собирается на Windows runner и публикуется автоматически по тегу.

## Лицензирование

Исходный код Flowtone распространяется по [MIT License](LICENSE). Model weights и условия Stable Audio 3 не входят в MIT и остаются на условиях правообладателей.

## Сборки и публикация

Каждый `push` проверяет обе платформы и сохраняет временные Actions artifacts на 14 дней. Тег вида `v1.1.0` дополнительно создаёт GitHub Release с постоянными файлами `Flowtone-Setup-Windows-x64.exe`, `Flowtone-macOS-arm64.zip` и SHA-256 для каждого файла. Подробная Windows-инструкция находится в [docs/INSTALL-WINDOWS-RU.md](docs/INSTALL-WINDOWS-RU.md).

Сборки не подписаны и не notarized. Система может потребовать явного подтверждения пользователя при первом запуске. Не скачивайте Flowtone из непроверенных источников.
