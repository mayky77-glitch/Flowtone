# Музыкальная карта пресетов Flowtone

Этот документ фиксирует, как музыкальные референсы переводятся в параметры локальной генерации. Flowtone не копирует мелодии, партии, семплы или голоса и не просит модель имитировать конкретного автора. В prompt попадают только общие музыкальные признаки: темп, метр, ритмика, инструменты, гармоническая окраска, плотность, форма и энергия.

## HÖR Berlin и энергичная электроника

Присланные сеты относятся к нескольким соседним, но разным веткам клубной музыки:

| Референс | Подтверждённая область | Перевод в Flowtone |
|---|---|---|
| [SaltySis, XONE Exclusive](https://hoer.live/xone-exclusive-saltysis-hor-october-9-2024/) | Rave, Hard Dance, Trance | `Light Rave`: упругий бас, яркие rave-аккорды, trance-арпеджио и воздушные брейки |
| [ROÜGE, 7 Jan 2023](https://hoer.live/rouge-hor-jan-7-2023/) | Techno, Hard Techno | `Hard Techno`: raw-rumble, быстрый warehouse kick, hard groove и короткие тёмные сигналы |
| [Elen Payne, Kindcrime](https://hoer.live/kindcrime-elen-payne-hor-december-12-2024/) | Industrial Techno, Hard Techno, Hardcore | отдельные ветки `Industrial Techno` и `Hardcore`: металл, механический ритм, искажённый kick и холодная кибер-готическая окраска |
| [Elen Payne, Cruelmachine](https://hoer.live/cruelmachine-elen-payne-hor-july-17-2024/) | Hardcore, Hard Techno, Industrial Techno | более жёсткие варианты тех же веток с высокой энергией и контролируемым шумом |

Вывод: «немецкий рейв» не сводится к одному тембру. В каталоге есть лёгкий rave/hard-dance, hard groove, hard techno, industrial techno и hardcore; пользователь может держать их раздельно либо включить жанровый микс.

## FLCL

Присланный ролик идентифицирован как трек из FLCL OST. Официальная страница лейбла описывает музыку серии как работу японской alternative-rock группы и подчёркивает энергичную рок-основу: [Milan Records — FLCL soundtrack](https://www.milanrecords.com/release/flcl-progressive-alternative-music-by-the-pillows/).

Пресет `Аниме-рок нулевых` использует только общую формулу: живые барабаны, подвижный бас, jangly-гитара в куплетной фактуре, более плотный fuzzy/overdrive слой в кульминации и ощущение стремительного взросления. Конкретные гитарные хуки и форму исходных песен prompt не упоминает.

## Flipwitch

Авторская страница саундтрека описывает музыкальный язык как смесь JRPG, city pop, jazz fusion, soul и EDM; альбом также размечен как funk, hip-hop, electronic и jazz: [MomoJams — Flipwitch OST](https://momojams.bandcamp.com/album/flipwitch-original-game-soundtrack) и [Flipwitch: Mixtape](https://momojams.bandcamp.com/album/flipwitch-mixtape).

Эта смесь разложена на несколько пресетов:

- `Фантомный фанк`: подвижный бас, electric piano, спектральные синтезаторы и игровая драматургия;
- `Игровой джаз-фьюжн`: jazz-fusion ритм-секция и характерные для JRPG гармонические повороты;
- `Приключенческий фьюжн`: slap bass, electric piano и яркий lead synth;
- `Городской блеск`: более спокойная city-pop сторона.

## Overlord и тёмное фэнтези

Официальный сайт указывает композитора и показывает диапазон оригинального score: от придворных и деревенских сцен до подавляющей тьмы, войны и крупного боя: [Overlord — official soundtrack information](https://overlord-anime.com/).

Пресет `Overlord · тёмная империя` не воспроизводит конкретную тему. Его нейтральный production contract: низкие струнные, орган, строгая медь, ритуальные барабаны, монументальная медленная гармония и царственная угроза.

## Skyrim и северная сага

Bethesda описывает музыку Skyrim как одновременно воодушевляющую и ambient, а официальное концертное исполнение использует симфонический оркестр и хор: [Skyrim 10th Anniversary](https://elderscrolls.bethesda.net/en-US/skyrim10) и [The Music of Skyrim in Concert](https://elderscrolls.bethesda.net/en-US/news/5ect8cBQpUq0kAoeOAwyoG/the-music-of-skyrim-in-concert).

Пресет `Skyrim · северная сага` переводит это в общие признаки: нордический модальный мотив, валторны, струнные, большие барабаны, низкая хоровая текстура без слов и чередование открытого горного пространства с героическим подъёмом.

## Cyberpunk radio

CD PROJEKT RED подчёркивает разнообразие более чем 150 игровых радиотреков, а официальные материалы отдельно называют электронную Dark Star, community-driven Growl FM и DJ-oriented Impulse: [официальная заметка о музыке](https://www.cyberpunk.net/en/news/36734/dedicated-cyberpunk-2077-feature-for-content-creators-disable-copyrighted-music) и [Update 2.0](https://www.cyberpunk.net/en/news/49060/update-2-0).

Поэтому `Cyberpunk` — не один synthwave-пресет, а набор радионаправлений: industrial rock, dark club electro, future hip-hop, neon pop, combat drum and bass, dark ambient, future jazz и chrome metal. Их объединяют городская шероховатость, технологическая фактура и высокая контрастность, а не конкретные игровые станции или песни.

## Пиратская ветка

Пиратская музыка разбита на морской folk и cinematic adventure:

- инструментальная shanty-логика без голоса: fiddle, concertina, tin whistle и палубный ритм;
- портовая jig/таверна;
- оркестровый морской бой и погоня в шторм;
- тёмный корабль-призрак с hurdy-gurdy и колоколами;
- остров сокровищ и светлый фольклор архипелага.

Так пресеты покрывают и камерную народную сторону, и активную приключенческую, не повторяя музыку конкретных фильмов или игр.

## Контракт каталога

- 27 жанров;
- 292 пресета в текущей версии;
- минимум 10 вариантов на каждый жанр;
- у каждого музыкального архетипа есть `ровный эфир` и `живой разгон`;
- фиксированный пресет передаётся в prompt; режим `Авто` выбирает его по seed;
- микс объединяет 2–5 разных активных жанров, оставляя первый ведущим по ритму и форме.
