# Flowtone Implementation Guide

## Current vertical slice

Текущий milestone проверяет границы между приложением и inference runtime. Он не выдаёт synthetic engine за музыкальную модель.

```text
SwiftUI App
    └── FlowtoneCore
        ├── StationConfiguration + PromptComposer
        ├── GenrePromptCatalog + TempoPlanner
        ├── ModelRecommender + ResourcePolicy
        ├── GenerationScheduler (actor, one job)
        ├── TrackTitleGenerator (local deterministic names)
        ├── TrackLibrary (compact JSON index + local audio files)
        ├── RadioPlaybackQueue (current + 2 ready)
        ├── AudioPlaybackController (two AVAudioPlayerNode instances)
        ├── EqualPowerCrossfade
        ├── ModelRuntimeCatalog
        └── GenerationEngine
            ├── SyntheticAudioEngine (development only)
            └── StableAudioMLXEngine (official CLI process adapter)
```

## Build and test

```bash
swift build
swift test
```

Тесты используют официальный пакет [swift-testing](https://github.com/swiftlang/swift-testing), закреплённый на revision для Swift 6.3.3. На машине только с Command Line Tools linker получает системный `_TestingInterop` из стандартного CLT path.

## Development audio smoke test

```bash
swift run flowtone-spike \
  --engine synthetic \
  --duration 5 \
  --seed 42 \
  --genres ambient,lo-fi \
  --tempo 82 \
  --vibe "rain outside"
```

Synthetic engine создаёт простой stereo WAV 44.1 kHz. Его задача — проверить scheduler, file contract и playback без большой загрузки.

## Local radio library

Коллекция хранится в `~/Library/Application Support/Flowtone/Library`:

```text
Library/
├── library-v1.json
├── Audio/
└── Incoming/
```

Compact JSON index хранит название, жанры, лайк, временный статус, размер, длительность, model engine, seed и playback metadata. Перед генерацией Flowtone резервирует место под следующий 120-секундный WAV. Если запись не помещается, приложение показывает системное предупреждение, прекращает создавать новые файлы и продолжает играть коллекцию. Генерация возобновляется после ручной очистки или увеличения лимита; автоматического удаления постоянных записей ради новой генерации нет.

В режиме «Полное радио» новые записи помечаются временными: сохраняются текущая, предыдущая и подготовленная очередь; лайк делает трек постоянным. В режиме «Радио с записью» каждый результат остаётся в коллекции до ручной очистки. При старте незавершённые файлы из `Incoming/` удаляются.

Текущий и оба подготовленных трека защищены от ручного удаления и массовой очистки. Player заранее
планирует следующий файл, а `AudioPlaybackController` определяет момент перехода по render time.
SwiftUI-таймер только вызывает наблюдение за render clock; он не рассчитывает позицию аудио.

Названия создаются локально и детерминированно из genre + station pace + mood + vibe-hash + seed. Это одна связная фраза длиной не более десяти слов; сырой vibe не копируется в заголовок. Старые обрезанные, составные и повторяющиеся titles, а также index records без `title`, получают стабильное fallback-название при декодировании. Длинная строка прокручивается с паузой в начале и конце.

`TempoPlanner` выбирает BPM из жанровых диапазонов, смещает его по темпу эфира и иногда даёт ограниченное отклонение. «Энергично» смещает выбор на две типичные ступени выше и всегда включает high-motion arrangement: атака, подвижный бас, fills, вариации мотива, breakdown, возврат темы и выраженную кульминацию при стабильном тональном центре.

`GenrePromptCatalog` задаёт ритм, тембры и фактуру 350 автоматических звуковых профилей для 29 жанров. Каждый жанр имеет минимум десять профилей; Synthwave имеет 30, Pirate и Space Rock — по 16. `GenreMixPlanner` детерминированно выбирает по seed от двух до пяти разных активных жанров, а `PromptComposer` сохраняет первый жанр ведущим по ритму и форме.

Player поддерживает seek, начало/конец, ±15 секунд, previous/next по session history, случайный порядок и запуск выбранного трека из коллекции. Genre cards в статистике переключают архив на отфильтрованные треки и показывают сбрасываемый genre chip. Vinyl drag перемещает ту же audio position; forward/reverse preview использует чередующиеся player nodes, короткие PCM-буферы с envelope и varispeed. Пластинка вращается через видимый 60-Гц timeline, останавливается на pause и не перерисовывается в невидимом или свёрнутом окне; тонарм идёт к центру по реальному progress.

## Resource and rendering policy

- `GenerationScheduler` — actor с одной utility-priority generation job; параллельные модели не запускаются.
- Stable Audio работает отдельным process на один трек. При выключении генерации process отменяется, после завершения модели не остаются резидентными в приложении.
- Synthetic smoke engine пишет WAV блоками по 4096 frames в `.partial`, а не держит весь двухминутный файл в RAM.
- До старта проверяются thermal state, Low Power Mode и memory pressure. Сигнал памяти во время работы отменяет job, дожидается process termination и чистит `Incoming/`; playback продолжается.
- Аудиодвижок держит только current/next scheduling state; scratch загружает примерно 110 мс PCM с 12-мс envelope и меняет grain не чаще раза в 50 мс. Library rows и genre statistics используют lazy containers.
- Кольца винила рисуются одним `Canvas`, а не отдельной иерархией shape views. Marquee работает на 15 fps, винил — на 60 fps только пока окно видно и трек играет.
- Единственные циклы ограничены размером очереди, числом WAV frames или количеством UI-дорожек; бесконечного polling loop нет.

## Windows 10/11 x64

Windows-приложение находится в `windows/` и воспроизводит тот же продуктовый сценарий: параметры станции, 29 жанров, локальная коллекция, очередь `current + 2`, equal-power crossfade до 6 секунд, transport, интерактивная пластинка и управление моделями без Terminal. Desktop shell использует Electron, а официальный Windows inference path — Stable Audio 3 TFLite/LiteRT с XNNPACK на CPU.

В v1.2.5 публичный runtime не выполняет автоподбор: на любом поддержанном ПК он отдаёт и запускает только экономную Small:

| Профиль | Условие рекомендации | DiT / decoder / precision |
|---|---|---|
| Small · экономная | все поддержанные ПК | `sm-music` / `same-s` / `w8a8-dyn` |

GPU определяется и показывается пользователю только как диагностика. Она не меняет модель. Установка автоматически подключает Small; удаление не затрагивает музыкальную коллекцию.

macOS перед активацией нового экземпляра завершает другую запущенную Flowtone с bundle identifier `com.flowtone.app`. Windows development launch до смены test `userData` закрывает stale installed `Flowtone.exe`, затем все варианты используют lock из общего default user-data namespace. Поэтому старая установленная и актуальная command-line копии не образуют два независимых окна.

Runtime и `uv` закреплены по версии и SHA-256. Managed Python 3.11, LiteRT, Hugging Face cache и веса находятся в пользовательской папке Flowtone. После установки generation process работает offline, запускается строго по одному и завершается после каждого трека. При нехватке памяти или уходе Windows в сон process tree отменяется.

Миграция с Windows `v1.1.1` отдельно проверяет `models/tokenizer.model`, который upstream считает bundled и поэтому не включает в weight manifest. Если старый runtime содержит Python и скрипты, но tokenizer потерян, Flowtone докачивает только официальный файл из закреплённой source revision и проверяет его SHA-256. Загрузчик SentencePiece патчится на `LoadFromSerializedProto(model_path.read_bytes())`, поэтому нативная библиотека не открывает путь с кириллическим именем профиля. Неполная установка не подключается; в Model Manager появляется действие «Восстановить».

Renderer дополнительно классифицирует runtime errors до показа: tokenizer/Traceback превращаются в короткое русское действие, произвольное сообщение ограничено 220 символами. Status занимает не более двух строк, toast — трёх, model error имеет ограниченную прокрутку; внутренние пути и stack trace не растягивают stage или modal.

Видимая пластинка обновляется с целевой частотой 60 Гц, как на macOS. Цикл перерисовки полностью останавливается на паузе, при сворачивании и скрытии окна. Заголовок обновляется не чаще 15 Гц; аудио и фоновая генерация не зависят от UI animation loop.

Проверка и локальный запуск shell:

```powershell
cd windows
npm ci
npm run check
npm test
npm start
```

Windows installer собирается командой `npm run dist:win`. В CI сборка выполняется на `windows-latest`, после чего запускается упакованный `win-unpacked/Flowtone.exe` из пути с кириллицей. Smoke кликает три тумблера, проверяет нулевую root-прокрутку, неизменную геометрию shell/sidebar/stage и точный 50%-индикатор. JSON и screenshot сохраняются как Actions artifact.

Это эффективно ловит Windows-only ошибки Electron, путей, focus/scroll и упаковки без локального Windows-ПК. Но Windows Server runner не заменяет hardware beta на Windows 10/11 с реальным аудиоустройством, CPU/GPU и полной генерацией.

## Stable Audio MLX

Flowtone следует официальному [`optimized/mlx`](https://github.com/Stability-AI/stable-audio-3/tree/main/optimized/mlx) runtime. Adapter запускает executable напрямую через `Process`; prompt не передаётся shell и не интерполируется.

Установка выполняется из окна «Настроить модель»:

1. Откройте [Stable Audio 3 Small-Music на Hugging Face](https://huggingface.co/stabilityai/stable-audio-3-small-music), [optimized MLX bundle](https://huggingface.co/stabilityai/stable-audio-3-optimized), [Stable Audio Community License](https://stability.ai/license) и [Gemma Terms](https://ai.google.dev/gemma/terms).
2. Лично прочитайте и примите применимые условия. Локальная отметка Flowtone подтверждает только это действие и не принимает внешние terms от имени пользователя.
3. Нажмите «Подтвердить и скачать модель». Flowtone проверит установочные archives, установит Stable Audio 3 Small и автоматически подключит её после завершения.

Installer не просит и не хранит Hugging Face token: официальный `stabilityai/stable-audio-3-optimized` bundle доступен для anonymous download, но остаётся под Stability AI Community License и Gemma Terms. Ни токен, ни пользовательские prompts не записываются в installation log.

Supply-chain contract:

- Stability AI source закреплён на revision `a0b57f5483c4588f827f3552b7d5c6ca2a9687be`; source ZIP проверяется по SHA-256 до распаковки.
- `uv` закреплён на version `0.12.5`; официальный arm64 archive проверяется по опубликованному SHA-256.
- Flowtone не выполняет `curl | bash`: проверенный `uv` напрямую создаёт Python environment, после чего official `scripts/install.py` скачивает только `sm-music`; upstream bootstrap не вызывается.
- Прямые runtime dependencies закреплены на версиях, прошедших M4/16 GB smoke: MLX 0.32.0, NumPy 2.4.6, SentencePiece 0.2.2, huggingface_hub 1.27.0 и SoundFile 0.14.0.
- Python, MLX runtime, HF cache и веса находятся только в `~/Library/Application Support/Flowtone/`; app bundle и Git их не содержат.
- Ошибка или cancel удаляет incomplete runtime/launcher, но сохраняет уже скачанные weights в локальном cache для следующей попытки.
- Готовность требует executable launcher, official MLX scripts, `.venv/bin/python` и все четыре Small-Music files. Launcher вызывает `scripts/sa3_mlx.py` напрямую и не зависит от установленного в системе `uv`. После этого adapter принудительно выставляет `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1` и `HF_DATASETS_OFFLINE=1`.

Фиксированный launcher path:

```text
~/Library/Application Support/Flowtone/stable-audio-mlx
```

На macOS автоматическая установка поддерживает Apple Silicon. Stable Audio 3 Small требует не менее 4 ГБ свободного места. На Windows используется экономный CPU/LiteRT-профиль.

Для разработки с уже установленным runtime:

1. Убедитесь, что условия Stable Audio и Gemma подходят вашему использованию.
2. Откройте официальный [Stable Audio 3 repository](https://github.com/Stability-AI/stable-audio-3) и его [MLX instructions](https://github.com/Stability-AI/stable-audio-3/tree/main/optimized/mlx).

После установки:

```bash
swift run flowtone-spike \
  --engine stable-audio \
  --sa3-executable "./Models/stable-audio-3/optimized/mlx/sa3" \
  --duration 30 \
  --genres ambient,lo-fi \
  --tempo 82 \
  --vibe "rain outside"
```

## Reproducible Stable Audio benchmark

После автоматической или ручной установки запустите harness. Он не скачивает weights и не меняет runtime. Runtime запускается с `HF_HUB_OFFLINE=1` и `TRANSFORMERS_OFFLINE=1`, поэтому missing cached weights должны завершить run ошибкой, а не вызвать network provisioning. По умолчанию harness использует `~/Library/Application Support/Flowtone/stable-audio-mlx`, фиксированные prompt, negative prompt, 30 seconds, seed `424242`, MLX model flags `--dit sm-music --decoder same-s` и `--steps 8`.

```bash
scripts/benchmark-stable-audio.sh
```

По умолчанию WAV записывается в `${TMPDIR:-/tmp}/flowtone-stable-audio-benchmark.wav`; script не перезаписывает существующий файл. Для другой runtime или output path:

```bash
scripts/benchmark-stable-audio.sh \
  --executable "/absolute/path/to/stable-audio-3/optimized/mlx/sa3" \
  --output /tmp/flowtone-stable-audio-benchmark-run-1.wav
```

Успех печатается одной стабильной machine-readable строкой с `status=passed`, seed, requested seconds, wall time, размером и output path. Script проверяет executable до запуска и nonempty WAV после него. Сравнивайте runs на одинаковой версии runtime, macOS, питании и свободной памяти; benchmark пока не устанавливает production performance target.

Release-приложение не включает synthetic fallback. Если executable отсутствует или не имеет права
на запуск, интерфейс честно показывает, что Stable Audio 3 не установлена, и продолжает играть
готовую локальную коллекцию. Для ACE-Step используется отдельный локальный helper process; prompt передаётся JSON-запросом, а не командной строкой shell.

Официальный CLI contract, который формирует adapter:

```text
sa3 --prompt <prompt> --negative-prompt <negative> \
    --dit sm-music --decoder same-s --seconds <1...120> \
    --steps 8 --seed <seed> --out <absolute WAV path>
```

## Current limitations

- Полный Xcode не установлен; SwiftPM build/test работает через Command Line Tools.
- Веса не входят в Git/сборку. На тестовом M4/16 ГБ official Small-Music MLX runtime установлен вне репозитория; offline 30-second benchmark прошёл за 7.68 с process wall / 4.81 с model wall с stage peak 1.69 ГБ.
- Есть automatic verified installer для public optimized Small-Music MLX bundle; локальная UI-отметка не принимает external terms. Model weights не bundled, token не требуется и не хранится.
- Альтернативные adapters оставлены в коде как отложенная идея, но публичный runtime v1.2.5 их не инициализирует, не показывает и не запускает.
- Скрипт создаёт `.app`, затем целиком ad-hoc подписывает готовый bundle и запускает strict deep verification. Developer ID signing/notarization остаются вне scope и требуют credentials.
- Системная memory-pressure защита подключена через `DispatchSource`; её пороги остаются системными.
- `leaks` smoke на работающем debug-приложении показал стабильные 24 272 байта после повторного замера через 10 секунд; app-owned Flowtone frames в отчёте не обнаружены, оставшиеся roots относятся к SwiftUI/AVFoundation listener bindings.
- Экранная запись UI подтверждает 60 fps stream для вращения винила; при скрытом окне timeline paused.

## Next implementation slice

1. Проверить лёгкий runtime на M1/M2 с 8–16 ГБ.
2. Вернуться к измерениям альтернативных моделей только после отдельного решения владельца; v1.2.5 публично использует только Stable Audio 3 Small.
3. Developer ID signing/notarization остаются вне scope ad-hoc repository artifact; рассмотреть их только после отдельного решения владельца и получения credentials.

## Unsigned app bundle

```bash
scripts/package-app.sh /tmp/flowtone-package
open /tmp/flowtone-package/Flowtone.app
```

Скрипт отказывается перезаписывать существующий bundle, включает `Assets/AppIcon.icns`, выполняет ad-hoc signing после добавления resources и не выполняет Developer ID signing/notarization.

При каждом `push` CI проверяет macOS и Windows и сохраняет временные artifacts. Тег вида `v1.2.5` создаёт GitHub Release с постоянными файлами `Flowtone-macOS-arm64.zip`, `Flowtone-Setup-Windows-x64.exe` и отдельными SHA-256. Ни `.app`, ни `.exe`, ни ZIP в Git не коммитятся.
