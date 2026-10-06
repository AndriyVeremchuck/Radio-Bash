#!/bin/bash

# --- КОНФІГУРАЦІЯ ДОДАТКУ ---
PLAYER="mpv"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
# ANIM_DELAY тепер використовується лише для індикатора завантаження, якщо його додати.
STATUS_FILE="/tmp/radio_status.tmp" # Тимчасовий файл для статусу
MPV_SOCKET="/tmp/mpv_socket" # Сокет для керування mpv

# Включити строгий режим виконання
set -euo pipefail # Вихід при помилках, невизначених змінних, помилках в конвеєрах

# --- КОЛЬОРИ (ВІДКЛЮЧЕНО ЗА ЗАМОВЧУВАННЯМ ДЛЯ СУМІСНОСТІ) ---
ENABLE_COLORS="false" # Змініть на "true", якщо ваш термінал коректно відображає ANSI-коди

# ANSI Коди для кольорів та стилів
if [ "$ENABLE_COLORS" = "true" ]; then
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
    BOLD='\033[1m'
    ITALIC='\033[3m'
    UNDERLINE='\033[4m'
else
    GREEN='' BLUE='' YELLOW='' RED='' PURPLE='' CYAN='' WHITE='' NC='' BOLD='' ITALIC='' UNDERLINE=''
fi

# --- УТИЛІТНІ ФУНКЦІЇ ДЛЯ КЕРУВАННЯ ТЕРМІНАЛОМ ---
# Використовуємо "сирі" ANSI-послідовності замість окремих викликів tput —
# кожен tput форкає новий процес, а при перемальовуванні меню (кожен рядок,
# кожне натискання клавіші) таких викликів були десятки, що й спричиняло
# помітні гальма при навігації. Пряме echo escape-кодів не форкає нічого.
clear_screen() { printf '\033[2J\033[H'; }
save_cursor() { printf '\033[s'; }
restore_cursor() { printf '\033[u'; }
hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
goto_xy() { printf '\033[%d;%dH' "$(($1 + 1))" "$(($2 + 1))"; } # tput cup — 0-based; ANSI CUP — 1-based
erase_line() { printf '\033[K'; } # Очистити від курсора до кінця рядка
get_terminal_height() { tput lines; }
get_terminal_width() { tput cols; } # Розмір вікна все ще читаємо через tput (не в гарячому шляху)

# --- Анімаційний спінер (використовуватиметься для індикації завантаження) ---
SPINNER_FRAMES=( "|" "/" "-" "\\" )
SPINNER_FRAME_COUNT=${#SPINNER_FRAMES[@]}

# --- АКТУАЛЬНІ URL-АДРЕСИ РАДІОСТАНЦІЙ (ПЕРЕВІРЕНО 21.09.2026) ---
declare -A STATIONS
STATIONS[1]="Armiya FM|https://icecast.armyfm.com.ua:8443/ArmyFM"
STATIONS[2]="Hit FM|https://tavr.tvstitch.com/HitFM"
STATIONS[3]="NRJ Ukraine|https://cast.mediaonline.net.ua/nrj"
STATIONS[4]="Melodia FM|https://tavr.tvstitch.com/MelodiaFM"
STATIONS[5]="Buske Radio|https://complex.in.ua/buskfm"
STATIONS[6]="Lviv Duzhe Radio|https://ipradio.net:8443/duzheHD"
STATIONS[7]="Golos Stryia|https://complex.in.ua/struy"
STATIONS[8]="Kremenchuk Автохвиля|https://cast.mediaonline.net.ua/avtoradio320"
STATIONS[9]="ZFM|https://radio.zfm.com.ua:8443/zfm_128"
STATIONS[10]="Berdychiv Rekord FM|https://91.134.147.168:10058/stream"
STATIONS[11]="Radio ROKS|https://tavr.tvstitch.com/RadioROKS"
STATIONS[12]="Radio Relax|https://tavr.tvstitch.com/RadioRelax"
STATIONS[13]="Radio Jazz|https://tavr.tvstitch.com/RadioJazz"
STATIONS[14]="Люкс FM|https://lux.radio.tvstitch.com/kyiv/lux_adv_sd"
STATIONS[15]="Радіо Максимум|https://lux.radio.tvstitch.com/kyiv/max_adv_sd"
STATIONS[16]="Радіо Nostalgie|https://lux.radio.tvstitch.com/kyiv/nst_adv_sd"
STATIONS[17]="Радіо NV|https://online-radio.nv.ua/radionv.mp3"
STATIONS[18]="Наше Радіо|https://tavr.tvstitch.com/NasheRadio"
STATIONS[19]="Lounge FM|https://cast.mediaonline.net.ua/loungefm"
STATIONS[20]="Київ FM 98.0|https://cdn.vsnw.net:8943/kyiv_fm_128k"
STATIONS[21]="Радіо Трек|https://cast.radiotrek.rv.ua:8433/MP3_320"
STATIONS[22]="Прямий FM|https://cast.mediaonline.net.ua/prmfm320"
STATIONS[23]="Radio Gold UA|https://online.radioplayer.ua/RadioGold"
STATIONS[24]="Megapolis FM|https://cast.megapolis.fm/listen/kryvyi_rih/radio.mp3"
STATIONS[25]="Radio ROKS Ballads|https://online.radioroks.ua/RadioROKS_Ballads"
STATIONS[26]="Radio ROKS Український Рок|https://online.radioroks.ua/RadioROKS_Ukr_HD"
STATIONS[27]="Radio Relax International|https://online.radiorelax.ua/RadioRelax_Int"
STATIONS[28]="Radio Relax Cafe|https://online.radiorelax.ua/RadioRelax_Cafe"
STATIONS[29]="Radio Jazz Gold|https://online.radiojazz.ua/RadioJazz_Gold"
STATIONS[30]="Radio Jazz Light|https://online.radiojazz.ua/RadioJazz_Light"
STATIONS[31]="Hit FM Top Hits|https://online.hitfm.ua/HitFM_Top"
STATIONS[32]="Hit FM Найбільші Хіти|https://online.hitfm.ua/HitFM_Best"
STATIONS[33]="Hit FM Українські Хіти|https://online.hitfm.ua/HitFM_Ukr"
STATIONS[34]="Kiss FM Deep|https://online.kissfm.ua/KissFM_Deep"
STATIONS[35]="Melodia FM Romantic|https://online.melodiafm.ua/MelodiaFM_Romantic"
STATIONS[36]="Melodia FM Disco|https://online.melodiafm.ua/MelodiaFM_Disco"
STATIONS[37]="Radio ROCKS Kyiv FM|https://online.radioroks.ua/RadioROKS_HD"
STATIONS[38]="ProgressiveUA|https://92.5.38.24:8000/radio.mp3"
STATIONS[39]="Одесса радио|https://listen6.myradio24.com/odesradio"
STATIONS[40]="Radio Jazz Cover|https://online.radiojazz.ua/RadioJazz_Cover_HD"
STATIONS[41]="Radio Bayraktar|https://tavr.tvstitch.com/RadioBayraktar"
STATIONS[42]="Радіо С4|https://radio.c4.com.ua:8443/320"
STATIONS[43]="REPLAY NEWS - Українська Новинне радіо кожні 5 хвилин|https://replaynewsuk.ice.infomaniak.ch/replaynewsuk-128.mp3"
STATIONS[44]="RadiVo|https://radivo.thx8te.kh.ua/listen/radivo/radio.mp3"
STATIONS[45]="Люкс ФМ – Сучасні хіти|https://lux.radio.tvstitch.com/suchasni-hiti-sd"
STATIONS[46]="Radio Social.net.ua|https://radio.social.net.ua/live.mp3"
STATIONS[47]="Західний полюс West Pole 32k AAC|https://online.z-polus.info/mobile"
STATIONS[48]="Радіо Байрактар|https://online.radiobayraktar.ua/RadioBayraktar_HD"
STATIONS[49]="Люкс ФМ – Українські хіти|https://lux.radio.tvstitch.com/ukrayinski-hiti-sd"
STATIONS[50]="Мелодія Int|https://online.melodiafm.ua/MelodiaFM_Int_Live"
STATIONS[51]="Tim FM Chernihiv|https://tim-fm.tim.ua/mp3"
STATIONS[52]="Сфера-ФМ (Рівне)|https://cdn-br2.live-tv.cloud/sferarvFM/64k/icecast.audio"
STATIONS[53]="Радіо Хартія (Radio Khartia)|https://a9.asurahosting.com/listen/radio_khartia/radio.mp3"
STATIONS[54]="Радіо Новий День|https://stream.zeno.fm/4rv8rzsdyjttv"
STATIONS[55]="Радіо Ми Україна|https://cast.mediaonline.net.ua/wau320"
STATIONS[56]="ZFM+ (Захид ФМ +)|https://radio.zfm.com.ua:8443/zfm"
STATIONS[57]="Наше Радіо 107,9|https://online.nasheradio.ua/NasheRadio_HD"
STATIONS[58]="Радіо Інді.UA|https://online.radioplayer.ua/RadioIndieUA"
STATIONS[59]="Звичайне україномовне радіо|https://whsh4u-panel.com/proxy/yvlxzzdx?mp=/stream"
STATIONS[60]="Радіо Перше|https://live.radio1.com.ua/liveradio64"
STATIONS[61]="Радіо Нікополя|https://stream.nikopolnews.net/listen/radio_nikopol/high"
STATIONS[62]="FreshRock Internet Radio Station|https://stream.freshrock.net/128.mp3"
STATIONS[63]="Радіо РАІ|https://radio.rai.ua:9000/rai"
STATIONS[64]="Радіо Місто над Бугом|https://stream.mistonadbugom.com.ua/radiomistonadbugom"
STATIONS[65]="K-Pop Radio|https://online.radioplayer.ua/KpopRadio"
STATIONS[66]="Lux FM Lviv|https://lux.radio.tvstitch.com/lux_lviv_adv_sd"
STATIONS[67]="Minatrix.FM: Независимое онлайн-радио и сообщество артистов для публикации музыки.|https://minatrix.fm:8002/play"
STATIONS[68]="Misto FM Juda|https://stream.mistofm.com/listen/misto_fm_juda/radio.mp3"
STATIONS[69]="Pihota.FM|https://online.pihota.fm/listen/radio/128"
STATIONS[70]="Power Кременчуг|https://radio.moa.org.ua/power"
STATIONS[71]="Radio «RAID»|https://a9.asurahosting.com/listen/radio_raid/radio.mp3"
STATIONS[72]="radio Italiana(UA)|https://online.radioplayer.ua/RadioItaliana"
STATIONS[73]="Radio ROCKS Новий Рок FM|https://online.radioroks.ua/RadioROKS_NewRock_HD"
STATIONS[74]="Wolf Music Radio|https://a3.asurahosting.com/listen/wolf_music_radio/radio.mp3"
STATIONS[75]="Yantarne FM|https://complex.in.ua/yantarne"
STATIONS[76]="Вільне РАДІО Жовква ФМ|https://cast108372.customer.uar.net/live320"
STATIONS[77]="Жидачів FM|https://complex.in.ua/zhudachiv"
STATIONS[78]="Західний полюс West Pole 64k AAC+|https://online.z-polus.info/mobilehq"
STATIONS[79]="Коростень фм|https://radio.korostenmedia.news/stream"
STATIONS[80]="Люкс ФМ – Золоті хіти|https://lux.radio.tvstitch.com/zoloti-hiti-sd"
STATIONS[81]="Радіо X.ON|https://audio.x-on.com.ua:8443/x-on-aacp-64.aac"
STATIONS[82]="Радіо КРИВБАС|https://onair.kryvbas.fm/RadioKryvbas"
STATIONS[83]="Радіо Накипіло / Radio Nakypilo|https://radiostream.nakypilo.ua/full"
STATIONS[84]="Радіо Сяйво|https://stream.ntktv.ua/syaivo.mp3"
STATIONS[85]="Слобожанське ФМ|https://globalic.stream:1810/stream"
STATIONS[86]="Українські хіти|https://radio.dobreff.com/ukraine.mp3"
STATIONS[87]="Трансляція РКБ|https://noasrv.caster.fm:10001/autodj"
STATIONS[88]="Kiss FM Ukraine HD|https://online.kissfm.ua/KissFM_Ukr_HD?n=964ccd571fe2e9f78518"
STATIONS[89]="Radio 24|https://icecast.luxnet.ua/radio24?n=689336ecfc37bfe2c12f"
STATIONS[90]="The West Pole Radio|https://online.z-polus.info/hq?n=fa19a641b102cca94e89"
STATIONS[91]="TopRadio|https://stream.topradio.in.ua/topradio.mp3?n=a3ea1ee078dcd16e053c"
STATIONS[92]="Броди ФМ|https://complex.in.ua/brodyHD?n=df8d116e41218a9c9f7d"
STATIONS[93]="Єдині новини|https://online-news.radioplayer.ua/RadioNews?n=5b6b6b2156867878ab86"
STATIONS[94]="Явір FM|https://complex.in.ua/Yavir320?n=2bdf39386cdd88b5a346"
STATIONS[95]="Lux FM|https://streamvideo.luxnet.ua/lux/smil:lux.stream.smil/playlist.m3u8"
STATIONS[96]="Радіо Аверс|https://radio.avers.pp.ua/hls_radio/efir.m3u8"
STATIONS[97]="Перше міське радіо (Одеса)|https://live.1tv.od.ua/radio/stream/icecast.audio"
STATIONS[98]="106.5 Kiss FM|https://online.kissfm.ua/KissFM_HD"
STATIONS[99]="Flash Radio|https://online.radioplayer.ua/FlashRadio_HD"
STATIONS[100]="Gachi Station (Ukrainian playlist) #1|https://stream.zeno.fm/bmb6ihzfbpdtv"
STATIONS[101]="KISS FM Digital|https://online.kissfm.ua/KissFM_Digital_HD"
STATIONS[102]="Radio Jazz FM|https://online.radiojazz.ua/RadioJazz_Christmas_Live"
STATIONS[103]="Radio Relax Інструментал 320|https://online.radiorelax.ua/RadioRelax_Instrumental"
STATIONS[104]="Radio ROKS Hard and Heavy 320|https://online.radioroks.ua/RadioROKS_HardnHeavy"
STATIONS[105]="Radio ROKS Рок-Балади|https://online.radioroks.ua/RadioROKS_Ballads_HD"
STATIONS[106]="Relax Українською|https://online.radiorelax.ua/RadioRelax_Ukr_HD"
STATIONS[107]="Ванда FM|https://icecast.xtvmedia.pp.ua/radiowandafm_hq.mp3"
STATIONS[108]="Всесвітня служба радіо|https://radio.ukr.radio/ur4-mp3"
STATIONS[109]="Голос Прикарпаття, Старий Самбір|https://complex.in.ua/stsambirr"
STATIONS[110]="Гуляй Радіо|https://online.radioplayer.ua/GuliayRadio"
STATIONS[111]="Країна FM|https://live2.radioec.com.ua/kiev128s.mp3"
STATIONS[112]="Наше Радіо УкрТоп100|https://online.nasheradio.ua/NasheRadio_Ukr_HD"
STATIONS[113]="Радіо 10|https://radio10.ua/RADIO10-VISLUHAYETE.mp3"
STATIONS[114]="Радіо BakerTilly|https://radio.bakertilly.ua:8000/stream"
STATIONS[115]="Радіо Трускавець FM Live|https://complex.in.ua/truskavets"
STATIONS[116]="Сок FM|https://online-sokfm.pp.ua:8443/SokFM"
STATIONS[117]="Хіт FM|https://online.hitfm.ua/HitFM_HD"
STATIONS[118]="Hit FM Best|https://online.hitfm.ua/HitFM_Best_HD"
STATIONS[119]="Hit FM Ukrainian|https://online.hitfm.ua/HitFM_Ukr_HD"
STATIONS[120]="Radio Jazz Groove|https://online.radiojazz.ua/RadioJazz_Groove_HD"

CURRENT_SELECTION=1
MAX_STATION_INDEX=${#STATIONS[@]}
CURRENT_PAGE=1

# --- ПАРАМЕТРИ АДАПТИВНОЇ СІТКИ СТОВПЧИКІВ ---
# Ширина однієї "клітинки" станції: префікс(2) + номер(3) + ": "(2) + назва(28) + відступ(2)
NAME_WIDTH=28
NUM_WIDTH=3
readonly _CELL_CONTENT_WIDTH=$((2 + NUM_WIDTH + 2 + NAME_WIDTH))
readonly COLUMN_WIDTH=$((_CELL_CONTENT_WIDTH + 2))
MAX_COLUMNS=5 # Не більше стовпчиків, навіть якщо термінал дуже широкий (читабельність)

# Значення нижче перераховуються динамічно функцією recompute_layout()
# залежно від поточного розміру вікна терміналу (tput lines/cols).
TERM_HEIGHT=0
TERM_WIDTH=0
NUM_COLS=1
ROWS_PER_COL=1
PAGE_SIZE=1
MAX_PAGE=1
PAGE_OFFSET=0
GRID_LEFT_MARGIN=0 # Відступ зліва, щоб сітка станцій була по центру екрана

# Перераховує кількість стовпчиків та рядків на сторінці за поточним розміром
# вікна терміналу. Викликається перед кожним показом меню та при зміні
# розміру вікна (WINCH), тому додаток гарно вписується у будь-яке вікно.
recompute_layout() {
    TERM_HEIGHT=$(get_terminal_height)
    TERM_WIDTH=$(get_terminal_width)

    # Резервуємо рядки під заголовок (4) та підвал з керуванням і статусом (~6)
    local reserved_lines=10
    local available_rows=$((TERM_HEIGHT - reserved_lines))
    if (( available_rows < 3 )); then available_rows=3; fi
    ROWS_PER_COL=$available_rows

    local cols_fit=$((TERM_WIDTH / COLUMN_WIDTH))
    if (( cols_fit < 1 )); then cols_fit=1; fi
    if (( cols_fit > MAX_COLUMNS )); then cols_fit=$MAX_COLUMNS; fi
    NUM_COLS=$cols_fit

    # Центруємо сітку стовпчиків по горизонталі відносно ширини терміналу
    local grid_width=$((NUM_COLS * COLUMN_WIDTH))
    GRID_LEFT_MARGIN=$(( (TERM_WIDTH - grid_width) / 2 ))
    if (( GRID_LEFT_MARGIN < 0 )); then GRID_LEFT_MARGIN=0; fi

    PAGE_SIZE=$((NUM_COLS * ROWS_PER_COL))
    MAX_PAGE=$(( (MAX_STATION_INDEX + PAGE_SIZE - 1) / PAGE_SIZE ))
    if (( MAX_PAGE < 1 )); then MAX_PAGE=1; fi
    if (( CURRENT_PAGE > MAX_PAGE )); then CURRENT_PAGE=$MAX_PAGE; fi
    if (( CURRENT_PAGE < 1 )); then CURRENT_PAGE=1; fi

    PAGE_OFFSET=$(( (CURRENT_PAGE - 1) * PAGE_SIZE ))

    # Якщо після зміни розкладки поточний вибір вийшов за межі сторінки —
    # повертаємось на перший пункт, щоб уникнути "порожньої" клітинки.
    if (( CURRENT_SELECTION > PAGE_SIZE )) || (( CURRENT_SELECTION < 1 )); then
        CURRENT_SELECTION=1
    fi
}

# Повертає кількість реальних станцій у стовпчику $1 на поточній сторінці
# (може бути менше ROWS_PER_COL для останнього стовпчика/сторінки).
column_count() {
    local col="$1"
    local start_global=$((PAGE_OFFSET + col * ROWS_PER_COL + 1))
    if (( start_global > MAX_STATION_INDEX )); then
        echo 0
        return
    fi
    local count=$((MAX_STATION_INDEX - start_global + 1))
    if (( count > ROWS_PER_COL )); then count=$ROWS_PER_COL; fi
    echo "$count"
}

# --- ФУНКЦІЇ КЕРУВАННЯ ПРОГРАВАЧЕМ (MPV) ---

# Оновлює файл статусу
update_status_file() {
    printf "PLAYING=%s\n" "$1" > "$STATUS_FILE"
    printf "STATION_NAME='%s'\n" "$2" >> "$STATUS_FILE"
    printf "PAUSED=%s\n" "$3" >> "$STATUS_FILE"
    printf "MUTED=%s\n" "$4" >> "$STATUS_FILE"
}

# Зупиняє поточний процес MPV
stop_player() {
    if [ -n "$PLAYER_PID" ]; then
        kill "$PLAYER_PID" 2>/dev/null || true # kill - ігноруємо помилки, якщо процес вже помер
        wait "$PLAYER_PID" 2>/dev/null || true # wait - ігноруємо помилки
        PLAYER_PID=""
    fi
    if [ -S "$MPV_SOCKET" ]; then
        rm -f "$MPV_SOCKET" 2>/dev/null || true
    fi
    update_status_file "false" "" "false" "false"
}

# Запускає відтворення обраної станції
play_station() {
    local url="$1"
    local name="$2"
    stop_player # Зупиняємо попередній програвач, якщо є

    # Додамо тимчасову індикацію завантаження
    draw_loading_status "Завантаження: ${name}..." &
    LOADING_PID=$!

    # Запуск mpv з параметрами для фонового відтворення без відео
    # --no-terminal щоб mpv не виводив власні логи на екран
    mpv --no-video --input-media-keys=no --user-agent="$USER_AGENT" \
        --no-terminal --input-ipc-server="$MPV_SOCKET" \
        --network-timeout=5 --idle --force-seekable=no "$url" < /dev/null &
    PLAYER_PID=$!

    # Чекаємо трохи, щоб mpv мав час запуститися або згенерувати помилку
    sleep 1

    # Зупиняємо індикацію завантаження
    kill "$LOADING_PID" 2>/dev/null || true
    wait "$LOADING_PID" 2>/dev/null || true # Чекаємо завершення фонового процесу

    # Перевіряємо, чи mpv справді запустився
    if ps -p "$PLAYER_PID" > /dev/null; then
        update_status_file "true" "$name" "false" "false"
    else
        update_status_file "false" "" "false" "false"
        # Можливо, варто додати повідомлення про помилку
        # draw_error_message "Не вдалося запустити станцію: ${name}"
    fi
}

# Функція для відображення індикації завантаження (як окремий потік)
draw_loading_status() {
    local message="$1"
    local spinner_idx=0
    local term_height=$(get_terminal_height)
    local status_line=$((term_height - 1))
    
    # Якщо термінал дуже маленький, обрізаємо статус-рядок, щоб він вміщався
    if [ "$status_line" -lt 0 ]; then status_line=0; fi

    while true; do
        save_cursor
        hide_cursor
        goto_xy "$status_line" 0
        erase_line
        local spinner_char="${SPINNER_FRAMES[$spinner_idx]}"
        echo -n -e "${YELLOW}${BOLD}[${spinner_char}] ${message}${NC}"
        restore_cursor
        spinner_idx=$(( (spinner_idx + 1) % SPINNER_FRAME_COUNT ))
        sleep 0.1
    done
}


# Перемикає паузу/відтворення
toggle_pause() {
    if [ -n "$PLAYER_PID" ] && [ -S "$MPV_SOCKET" ]; then
        echo '{ "command": ["cycle", "pause"] }' | socat - "$MPV_SOCKET" 2>/dev/null || true
        # Оновлюємо статус
        source "$STATUS_FILE" # Перечитуємо поточний статус
        if [ "$PAUSED" == "true" ]; then # Якщо був на паузі, то тепер відтворюється
            update_status_file "true" "$STATION_NAME" "false" "$MUTED"
        else # Якщо відтворювався, то тепер на паузі
            update_status_file "true" "$STATION_NAME" "true" "$MUTED"
        fi
    fi
}

# Перемикає увімкнення/вимкнення звуку
toggle_mute() {
    if [ -n "$PLAYER_PID" ] && [ -S "$MPV_SOCKET" ]; then
        echo '{ "command": ["cycle", "mute"] }' | socat - "$MPV_SOCKET" 2>/dev/null || true
        # Оновлюємо статус
        source "$STATUS_FILE" # Перечитуємо поточний статус
        if [ "$MUTED" == "true" ]; then # Якщо був вимкнений, то тепер увімкнений
            update_status_file "true" "$STATION_NAME" "$PAUSED" "false"
        else # Якщо увімкнений, то тепер вимкнений
            update_status_file "true" "$STATION_NAME" "$PAUSED" "true"
        fi
    fi
}

# --- ФУНКЦІЇ ДЛЯ ВІДОБРАЖЕННЯ МЕНЮ ---
# Відображає основне меню, станції та статус
show_menu() {
    clear_screen # Повне очищення ВСЬОГО екрану
    hide_cursor  # Приховуємо курсор на час малювання

    local current_line=1 # Початковий рядок для виводу

    # Заголовок
    goto_xy $current_line 0; echo -e "${BOLD}${BLUE}--- Радіо Термінал (Bash) ---${NC}"
    current_line=$((current_line + 1))
    goto_xy $current_line 0; echo -e "${BLUE}-----------------------------------${NC}"
    current_line=$((current_line + 1))
    goto_xy $current_line 0; echo -e "${BOLD}Сторінка ${CURRENT_PAGE}/${MAX_PAGE} (${NUM_COLS} стовп.) — ↑↓←→ циклічна навігація, ENTER — вибір:${NC}"
    current_line=$((current_line + 2)) # Відступ перед списком станцій

    local menu_start_line=$current_line # Рядок, з якого починається список станцій

    local current_playing_name=""
    local PLAYING="false"
    local PAUSED="false"
    local MUTED="false"
    if [ -f "$STATUS_FILE" ]; then
        source "$STATUS_FILE"
        current_playing_name="$STATION_NAME"
    fi

    # Вивід станцій поточної сторінки у NUM_COLS стовпчиках по ROWS_PER_COL
    # пунктів — обидва значення підлаштовані під розмір вікна терміналу.
    local global_selection=$((PAGE_OFFSET + CURRENT_SELECTION))
    for row in $(seq 0 $((ROWS_PER_COL - 1))); do
        local line=""
        for col in $(seq 0 $((NUM_COLS - 1))); do
            local idx=$((PAGE_OFFSET + col * ROWS_PER_COL + row + 1))
            if (( idx <= MAX_STATION_INDEX )) && [ -n "${STATIONS[$idx]+x}" ]; then
                local info="${STATIONS[$idx]}"
                local name="${info%%|*}"
                local display="${name:0:${NAME_WIDTH}}"
                local color="${CYAN}"
                local prefix="  "

                if [ "$idx" -eq "$global_selection" ]; then
                    color="${WHITE}${BOLD}"
                    prefix="> "
                fi
                if [ "$name" = "$current_playing_name" ] && [ "$PLAYING" = "true" ]; then
                    color="${GREEN}${BOLD}"
                fi

                local num_str
                num_str=$(printf "%${NUM_WIDTH}d" "$idx")
                local plain_cell="${prefix}${num_str}: ${display}"
                # printf "%-Ns" рахує байти, а не символи, тому кирилиця (2 байти
                # на символ у UTF-8) ламає вирівнювання. Рахуємо відступ вручну
                # за довжиною рядка в СИМВОЛАХ (${#рядок} коректно рахує символи).
                local pad=$((COLUMN_WIDTH - ${#plain_cell}))
                if (( pad < 0 )); then pad=0; fi
                line+="${color}${plain_cell}${NC}$(printf '%*s' "$pad" '')"
            else
                line+="$(printf '%*s' "$COLUMN_WIDTH" '')"
            fi
        done
        goto_xy $((menu_start_line + row)) "$GRID_LEFT_MARGIN"
        erase_line
        echo -n -e "$line"
    done
    # Вивід елементів керування
    local controls_start_line=$((menu_start_line + ROWS_PER_COL))
    goto_xy $controls_start_line 0; echo "" # Додатковий відступ
    controls_start_line=$((controls_start_line + 1))
    goto_xy $controls_start_line 0; echo -e "${BOLD}Керування:${NC}"
    controls_start_line=$((controls_start_line + 1))
    goto_xy $controls_start_line 0; echo -e "  ${GREEN}Space${NC}: Пауза | ${RED}S${NC}: Стоп | ${YELLOW}M${NC}: Звук | ${PURPLE}Q${NC}: Вихід | ${CYAN}↑↓←→${NC}: циклічна навігація | ${CYAN}Tab/N${NC}: Сторінка"
    controls_start_line=$((controls_start_line + 1))
    goto_xy $controls_start_line 0; echo -e "${BLUE}-----------------------------------${NC}"
    
    # Вивід статусного рядка
    local status_display_line=$((controls_start_line + 1))
    goto_xy "$status_display_line" 0
    erase_line # Очищаємо статусний рядок перед виводом
    
    local display_text=""
    if [ "$PLAYING" = "true" ]; then
        if [ "$PAUSED" = "true" ]; then
            display_text="${YELLOW}${BOLD}ПАУЗА${NC} "
        elif [ "$MUTED" = "true" ]; then
            display_text="${YELLOW}${BOLD}ЗВУК ВИМКНЕНО${NC} "
        else
            display_text="${GREEN}${BOLD}ГРАЄ${NC} "
        fi
        display_text+="Наразі грає: ${CYAN}${current_playing_name}${NC}"
    else
        display_text="${YELLOW}Наразі нічого не грає. Оберіть станцію.${NC}"
    fi
    echo -n -e "${display_text}"

    # Повертаємо курсор для введення користувача
    goto_xy $((status_display_line + 1)) 0 # Курсор після статусного рядка
    show_cursor # Показуємо курсор після малювання
}

# --- ГОЛОВНИЙ ЦИКЛ ДОДАТКУ ТА ОБРОБКА ВИХОДУ ---

# Функція для очищення ресурсів при виході
cleanup() {
    stop_player # Зупиняємо mpv
    # Якщо був запущений процес завантаження, зупиняємо його
    if [ -n "${LOADING_PID:-}" ]; then # Перевірка існування змінної
        kill "${LOADING_PID}" 2>/dev/null || true
        wait "${LOADING_PID}" 2>/dev/null || true
    fi
    rm -f "$MPV_SOCKET" "$STATUS_FILE" 2>/dev/null || true # Видаляємо тимчасові файли
    show_cursor # Показуємо курсор
    clear_screen # Очищаємо термінал
    echo -e "${PURPLE}Вихід з радіо. Бувай!${NC}" # Прощальне повідомлення
    exit 0 # Завершуємо скрипт
}

# Перехоплюємо сигнали завершення, щоб виконати cleanup
trap cleanup SIGINT SIGTERM SIGHUP
# Перехоплюємо сигнал зміни розміру вікна терміналу
trap 'recompute_layout; show_menu' WINCH

# Ініціалізація: встановлюємо початковий статус
update_status_file "false" "" "false" "false"

# Розкладку рахуємо один раз на старті — далі лише при зміні розміру вікна
# (WINCH), а не на кожне натискання клавіші, бо tput lines/cols форкають
# процес і це помітно гальмувало навігацію.
recompute_layout

# --- ОСНОВНИЙ ЦИКЛ КЕРУВАННЯ ---
while true; do
    show_menu # Відображаємо меню та статус
    
    # Читаємо ввід користувача
    read -rsn3 choice_char
    
    case "$choice_char" in
        "q"|"Q")
            cleanup
            ;;
        " "|"p"|"P")
            toggle_pause
            ;;
        "m"|"M")
            toggle_mute
            ;;
        "s"|"S")
            stop_player
            ;;
        $'\x1b[A') # Стрілка вгору — циклічно в межах поточного стовпчика
            col_index=$(( (CURRENT_SELECTION - 1) / ROWS_PER_COL ))
            row_index=$(( (CURRENT_SELECTION - 1) % ROWS_PER_COL ))
            count=$(column_count "$col_index")
            if (( count > 0 )); then
                row_index=$(( (row_index - 1 + count) % count ))
                CURRENT_SELECTION=$((col_index * ROWS_PER_COL + row_index + 1))
            fi
            ;;
        $'\x1b[B') # Стрілка вниз — циклічно в межах поточного стовпчика
            col_index=$(( (CURRENT_SELECTION - 1) / ROWS_PER_COL ))
            row_index=$(( (CURRENT_SELECTION - 1) % ROWS_PER_COL ))
            count=$(column_count "$col_index")
            if (( count > 0 )); then
                row_index=$(( (row_index + 1) % count ))
                CURRENT_SELECTION=$((col_index * ROWS_PER_COL + row_index + 1))
            fi
            ;;
        $'\x1b[D') # Стрілка вліво — циклічний перехід між стовпчиками (з останнього на перший)
            col_index=$(( (CURRENT_SELECTION - 1) / ROWS_PER_COL ))
            row_index=$(( (CURRENT_SELECTION - 1) % ROWS_PER_COL ))
            new_col=$col_index
            count=0
            for (( i = 0; i < NUM_COLS; i++ )); do
                new_col=$(( (new_col - 1 + NUM_COLS) % NUM_COLS ))
                count=$(column_count "$new_col")
                if (( count > 0 )); then break; fi
            done
            if (( count > 0 )); then
                if (( row_index >= count )); then row_index=$((count - 1)); fi
                CURRENT_SELECTION=$((new_col * ROWS_PER_COL + row_index + 1))
            fi
            ;;
        $'\x1b[C') # Стрілка вправо — циклічний перехід між стовпчиками (з останнього на перший)
            col_index=$(( (CURRENT_SELECTION - 1) / ROWS_PER_COL ))
            row_index=$(( (CURRENT_SELECTION - 1) % ROWS_PER_COL ))
            new_col=$col_index
            count=0
            for (( i = 0; i < NUM_COLS; i++ )); do
                new_col=$(( (new_col + 1) % NUM_COLS ))
                count=$(column_count "$new_col")
                if (( count > 0 )); then break; fi
            done
            if (( count > 0 )); then
                if (( row_index >= count )); then row_index=$((count - 1)); fi
                CURRENT_SELECTION=$((new_col * ROWS_PER_COL + row_index + 1))
            fi
            ;;
        $'\t'|"n"|"N") # Tab або N — циклічно перемкнути сторінку
            CURRENT_PAGE=$((CURRENT_PAGE % MAX_PAGE + 1))
            CURRENT_SELECTION=1
            ;;
        "") # Enter
            global_index=$((PAGE_OFFSET + CURRENT_SELECTION))
            station_info="${STATIONS[$global_index]}"
            name="${station_info%%|*}"
            url="${station_info##*|}"
            play_station "$url" "$name"
            ;;
        *) # Обробка вводу цифр (глобальний номер станції 1..MAX_STATION_INDEX)
            if [[ "$choice_char" =~ ^[0-9]+$ ]] && (( choice_char >= 1 && choice_char <= MAX_STATION_INDEX )); then
                CURRENT_PAGE=$(( (choice_char - 1) / PAGE_SIZE + 1 ))
                CURRENT_SELECTION=$(( (choice_char - 1) % PAGE_SIZE + 1 ))
                station_info="${STATIONS[$choice_char]}"
                name="${station_info%%|*}"
                url="${station_info##*|}"
                play_station "$url" "$name"
            fi
            ;;
    esac
done
