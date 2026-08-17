# Музыкальная карта пресетов Flowtone

Этот документ фиксирует, как музыкальные референсы переводятся в параметры локальной генерации. Flowtone не копирует мелодии, партии, семплы или голоса и не просит модель имитировать конкретного автора. В prompt попадают только общие музыкальные признаки: темп, метр, ритмика, инструменты, гармоническая окраска, плотность, форма и энергия.

## Как выполнен звуковой анализ

Референсы не анализируются в приложении. Один раз во время разработки из открытых записей были взяты короткие фрагменты из начала, середины и конца. Локальный анализ через FFmpeg и librosa измерил:

- предполагаемый tempo;
- количество заметных атак в секунду;
- динамический диапазон между тихими и громкими фрагментами;
- spectral centroid как грубую оценку яркости;
- chroma-распределение как грубую оценку гармонической насыщенности;
- долю перкуссионной энергии.

Темп у ambient, halftime и сильно синкопированной музыки может определяться в половинном или двойном размере. Поэтому числа не копируются в prompt механически: они проверяются вместе с ритмикой и музыкальной формой.

| Группа | Измеренный центр | Ключевой вывод для генерации |
|---|---:|---|
| HÖR: SaltySis | около 112 BPM, 5,6 атак/с | упругий mid-tempo hard-dance, яркий верх, длинное клубное развитие |
| HÖR: ROÜGE | около 144 BPM, 6,9 атак/с | высокая ритмическая плотность, warehouse pressure, короткие сигналы вместо длинной мелодии |
| HÖR: Elen Payne | центр около 152 BPM, пики выше | industrial/hardcore pressure, металлический спектр, непрерывное движение с контролируемыми разрывами |
| FLCL | около 136 BPM, динамика около 4 дБ | яркий плотно сжатый alternative rock, подвижный бас, jangly guitar и fuzzy climax |
| Flipwitch | около 112 BPM, динамика около 10 дБ | живой funk/jazz-fusion, высокая onset density, заметные breakdown/rebuild и гармонические повороты |
| Overlord OP | разные части около 99–162 BPM | не один медленный марш: symphonic rock, villain cabaret, industrial electro и быстрые кульминации |
| Overlord ED | центр около 112 BPM | тёмная элегия, piano/strings/electronic pulse и большой финальный подъём |
| Skyrim concert | динамика около 15 дБ, percussion ratio 0,04 | низко-средний оркестровый спектр, простор, паузы и редкие массивные подъёмы |
| Black Flag shanties | около 129 BPM, средняя chroma 0,31 | человеческий палубный пульс, частые folk cadences и инструментальный call-and-response |
| Cyberpunk radio sample | центр около 123 BPM, 5 атак/с | радиопалитра должна оставаться разножанровой, яркой, плотной и городской |

Аудиофайлы нужны только для временного локального анализа. Они не включаются в Flowtone, не отправляются в репозиторий и не используются как audio-conditioning при генерации.

## HÖR Berlin и энергичная электроника

Присланные сеты относятся к нескольким соседним, но разным веткам клубной музыки:

| Референс | Подтверждённая область | Перевод в Flowtone |
|---|---|---|
| [SaltySis, XONE Exclusive](https://hoer.live/xone-exclusive-saltysis-hor-october-9-2024/) | Rave, Hard Dance, Trance | `Light Rave`: упругий бас, яркие rave-аккорды, trance-арпеджио и воздушные брейки |
| [ROÜGE, 7 Jan 2023](https://hoer.live/rouge-hor-jan-7-2023/) | Techno, Hard Techno | `Hard Techno`: raw-rumble, быстрый warehouse kick, hard groove и короткие тёмные сигналы |
| [Elen Payne, Kindcrime](https://hoer.live/kindcrime-elen-payne-hor-december-12-2024/) | Industrial Techno, Hard Techno, Hardcore | отдельные ветки `Industrial Techno` и `Hardcore`: металл, механический ритм, искажённый kick и холодная кибер-готическая окраска |
| [Elen Payne, Cruelmachine](https://hoer.live/cruelmachine-elen-payne-hor-july-17-2024/) | Hardcore, Hard Techno, Industrial Techno | более жёсткие варианты тех же веток с высокой энергией и контролируемым шумом |

Вывод: «немецкий рейв» не сводится к одному тембру. В каталоге есть упругий 112 BPM hard-dance, rave/trance, hard groove, hard techno, industrial techno и hardcore. Диапазоны разделены между жанрами, чтобы один профиль не превращал все сеты в одинаковый быстрый kick.

## FLCL

Присланный ролик идентифицирован как трек из FLCL OST. Официальная страница лейбла описывает музыку серии как работу японской alternative-rock группы и подчёркивает энергичную рок-основу: [Milan Records — FLCL soundtrack](https://www.milanrecords.com/release/flcl-progressive-alternative-music-by-the-pillows/).

Профиль `Аниме-рок нулевых` использует только общую формулу: около 136 BPM, живые плотные барабаны, подвижный бас-контрапункт, jangly octave guitar и короткий fuzzy/overdrive climax. Конкретные гитарные хуки и форму исходных песен prompt не упоминает.

## Flipwitch

Авторская страница саундтрека описывает музыкальный язык как смесь JRPG, city pop, jazz fusion, soul и EDM; альбом также размечен как funk, hip-hop, electronic и jazz: [MomoJams — Flipwitch OST](https://momojams.bandcamp.com/album/flipwitch-original-game-soundtrack) и [Flipwitch: Mixtape](https://momojams.bandcamp.com/album/flipwitch-mixtape).

Эта смесь разложена на несколько автоматических профилей:

- `Фантомный фанк`: подвижный бас, electric piano, спектральные синтезаторы и игровая драматургия;
- `Игровой джаз-фьюжн`: jazz-fusion ритм-секция и характерные для JRPG гармонические повороты;
- `Приключенческий фьюжн`: slap bass, electric piano и яркий lead synth;
- `Городской блеск`: более спокойная city-pop сторона.

## Тёмная империя

Официальный сайт указывает композитора и показывает диапазон оригинального score: от придворных и деревенских сцен до подавляющей тьмы, войны и крупного боя: [Overlord — official soundtrack information](https://overlord-anime.com/). Для звуковой проверки также использованы [официальные opening и ending от KADOKAWA](https://www.youtube.com/watch?v=gme1ffqskew).

Одного медленного пресета оказалось недостаточно. Официальные openings/endings показывают широкий диапазон tempo и формы, поэтому создан отдельный жанр `Тёмная империя` с шестью архетипами и двенадцатью автоматическими вариантами:

- быстрый symphonic-rock assault;
- crooked villain cabaret со swing pulse;
- industrial electro с orchestral stabs;
- ритуальная корона с organ, low strings и brass clusters;
- тёмная piano/strings elegy с финальным guitar surge;
- завоевательный марш с racing strings и double-time drums.

В production prompt нет названия аниме, тем и исполнителей.

## Skyrim и северная сага

Bethesda описывает музыку Skyrim как одновременно воодушевляющую и ambient, а официальное концертное исполнение использует симфонический оркестр и хор: [Skyrim 10th Anniversary](https://elderscrolls.bethesda.net/en-US/skyrim10) и [The Music of Skyrim in Concert](https://elderscrolls.bethesda.net/en-US/news/5ect8cBQpUq0kAoeOAwyoG/the-music-of-skyrim-in-concert).

Три северных профиля переводят это в общие признаки: модальный мотив и открытые квинты, низкие струнные, solo horn/wooden flute, каменный реверберационный зал и редкий героический подъём. Измеренный широкий динамический диапазон не позволяет превращать всю ветку в постоянную trailer-percussion.

## Cyberpunk radio

CD PROJEKT RED подчёркивает разнообразие более чем 150 игровых радиотреков, а официальные материалы отдельно называют электронную Dark Star, community-driven Growl FM и DJ-oriented Impulse: [официальная заметка о музыке](https://www.cyberpunk.net/en/news/36734/dedicated-cyberpunk-2077-feature-for-content-creators-disable-copyrighted-music), [Update 2.0](https://www.cyberpunk.net/en/news/49060/update-2-0) и [официальный radio soundtrack](https://cyberpunk2077.bandcamp.com/album/cyberpunk-2077-radio-vol-2-original-soundtrack).

Поэтому `Cyberpunk` — не один synthwave-профиль, а набор радионаправлений: industrial rock, acidic club electro, future hip-hop, neon pop, syncopated street club, combat drum and bass, dark ambient, future jazz и chrome metal. Их объединяют городская шероховатость, яркая плотная фактура и технологический контраст, а не конкретные игровые станции или песни.

## Пиратская ветка

По [официальной подборке Ubisoft Music](https://www.youtube.com/watch?v=uw0mldfLWQs) пиратская музыка разбита на морской folk и cinematic adventure:

- инструментальная shanty-логика без голоса: fiddle, concertina, tin whistle и палубный ритм;
- портовая jig/таверна;
- оркестровый морской бой и погоня в шторм;
- тёмный корабль-призрак с hurdy-gurdy и колоколами;
- остров сокровищ и светлый фольклор архипелага.
- трёхчастная cinematic suite: широкая тема, тихая морская середина и мощное возвращение.

Так пресеты покрывают и камерную народную сторону, и активную приключенческую, не повторяя музыку конкретных фильмов или игр.

## Производительность

Звуковой анализ не выполняется на Mac пользователя. Flowtone хранит только короткие строки production traits и выбирает одну из них по seed. Каталог предвычислен один раз при запуске процесса, поэтому выбор профиля не создаёт заметной нагрузки рядом с Stable Audio inference.

Тяжёлой остаётся сама генерация. Она выполняется строго по одному заданию, запускается с utility priority, блокируется при memory pressure, перегреве и Low Power Mode. Выключение генерации отменяет активное задание и завершает отдельный процесс Stable Audio; между заданиями модель не удерживается процессом Flowtone в памяти.

## Контракт каталога

- 28 жанров;
- 314 автоматических вариантов в текущей версии;
- минимум 10 вариантов на каждый жанр;
- у каждого музыкального архетипа есть `ровный эфир` и `живой разгон`;
- автоматический режим выбирает production profile по seed;
- микс объединяет 2–5 разных активных жанров, оставляя первый ведущим по ритму и форме.
