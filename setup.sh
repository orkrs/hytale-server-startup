#!/bin/bash
# ============================================================
#  Hytale Server Setup & Launch Script v2.0
#  Полностью автоматическая установка и запуск
#  Hytale Dedicated Server на Ubuntu VDS
#
#  Запуск:  bash setup.sh
#           bash setup.sh --update    (обновить сервер/ассеты)
#           bash setup.sh --backup    (бэкап мира)
#           bash setup.sh --status    (статус)
#           bash setup.sh --stop      (остановить)
#           bash setup.sh --help      (справка)
# ============================================================

set -e

# ─── Настройки ───
SERVER_DIR="/opt/hytale-server"
ASSETS_ZIP="$SERVER_DIR/Assets.zip"
SERVER_JAR="$SERVER_DIR/HytaleServer.jar"
MODS_DIR="$SERVER_DIR/mods"
UNIVERSE_DIR="$SERVER_DIR/universe"
BACKUP_DIR="$SERVER_DIR/backups"
SCREEN_NAME="hytale"
SERVER_PORT=5520
DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
DOWNLOADER_DIR="$SERVER_DIR/.downloader"
DOWNLOADER_ZIP="$DOWNLOADER_DIR/hytale-downloader.zip"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }
log_ok()    { echo -e "${CYAN}[OK]${NC} $1"; }

# ─── Проверка root ───
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Запусти от root: sudo bash setup.sh"
        exit 1
    fi
}

# ─── Определение ОС ───
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
    else
        log_error "Не удалось определить ОС"
        exit 1
    fi
    log_info "ОС: $OS_NAME $OS_VERSION"
}

# ─── Установка Java 25 ───
install_java() {
    # Проверяем уже установленную Java
    if command -v java &> /dev/null; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1)
        local java_major
        java_major=$(java -version 2>&1 | head -1 | grep -oP '\d+' | head -1)
        if [ "$java_major" -ge 25 ] 2>/dev/null; then
            log_ok "Java уже установлена: $java_ver"
            return
        else
            log_warn "Найдена Java $java_major, нужна 25+. Обновляем..."
        fi
    fi

    log_step "Установка Java 25 (Temurin/Adoptium)..."

    apt-get update -qq
    apt-get install -y -qq wget apt-transport-https 2>&1

    # Добавляем репозиторий Adoptium
    mkdir -p /etc/apt/keyrings
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | \
        gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg 2>&1

    local distro
    distro=$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")

    echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] \
https://packages.adoptium.net/artifactory/deb $distro main" > \
        /etc/apt/sources.list.d/adoptium.list

    apt-get update -qq
    apt-get install -y -qq temurin-25-jdk

    local java_ver
    java_ver=$(java -version 2>&1 | head -1)
    log_info "Java установлена: $java_ver"
}

# ─── Установка зависимостей ───
install_deps() {
    log_step "Установка зависимостей..."
    apt-get install -y -qq screen curl unzip jq net-tools 2>&1
    log_info "Зависимости установлены"
}

# ─── Структура директорий ───
create_dirs() {
    mkdir -p "$SERVER_DIR" "$MODS_DIR" "$UNIVERSE_DIR" "$BACKUP_DIR" "$DOWNLOADER_DIR"
}

# ─── Скачивание hytale-downloader ───
download_downloader() {
    if [ -f "$DOWNLOADER_DIR/hytale-downloader" ] || \
       [ -f "$DOWNLOADER_DIR/hytale-downloader-linux-amd64" ]; then
        log_ok "Hytale downloader уже скачан"
        return
    fi

    log_step "Скачивание Hytale Downloader..."
    mkdir -p "$DOWNLOADER_DIR"

    curl -fsSL -o "$DOWNLOADER_ZIP" "$DOWNLOADER_URL"

    unzip -q "$DOWNLOADER_ZIP" -d "$DOWNLOADER_DIR"

    # Находим бинарник и делаем исполняемем
    local bin
    bin=$(find "$DOWNLOADER_DIR" -maxdepth 2 -type f -name "hytale-downloader*" ! -name "*.zip" | head -1)
    if [ -n "$bin" ]; then
        chmod +x "$bin"
        # Создаём симлинк для удобства
        ln -sf "$bin" "$DOWNLOADER_DIR/hytale-downloader"
    fi

    log_info "Downloader скачан и готов"
}

# ─── Поиск бинарника downloader ───
find_downloader_bin() {
    local bin
    bin=$(find "$DOWNLOADER_DIR" -maxdepth 2 -type f -name "hytale-downloader*" ! -name "*.zip" | head -1)
    if [ -n "$bin" ] && [ -x "$bin" ]; then
        echo "$bin"
        return 0
    fi
    return 1
}

# ─── Скачивание файлов сервера через downloader ───
download_server_files() {
    # Проверяем что уже есть
    if [ -f "$SERVER_JAR" ] && [ -f "$ASSETS_ZIP" ]; then
        log_ok "Файлы сервера уже на месте"
        return 0
    fi

    local dl_bin
    dl_bin=$(find_downloader_bin) || {
        log_error "Downloader не найден!"
        return 1
    }

    log_step "Скачивание Hytale Server и ассетов..."
    log_warn "Downloader требует OAuth-авторизацию при первом запуске."
    log_warn "Следуй инструкциям на экране."
    echo ""

    # Запускаем downloader в текущей директории — он скачает файлы
    cd "$SERVER_DIR"
    "$dl_bin" 2>&1

    # Ищем скачанные файлы
    local server_zip
    server_zip=$(find "$SERVER_DIR" -maxdepth 2 -name "HytaleServer*.zip" -o -name "hytale-server*.zip" 2>/dev/null | head -1)

    if [ -n "$server_zip" ] && [ -f "$server_zip" ]; then
        log_info "Распаковка сервера из $server_zip..."
        unzip -q -o "$server_zip" -d "$SERVER_DIR"
    fi

    # Перемещаем файлы если они в подпапке
    if [ -f "$SERVER_DIR/Server/HytaleServer.jar" ]; then
        mv "$SERVER_DIR/Server/HytaleServer.jar" "$SERVER_JAR"
    fi
    if [ -f "$SERVER_DIR/Server/Assets.zip" ]; then
        mv "$SERVER_DIR/Server/Assets.zip" "$ASSETS_ZIP"
    fi

    # Проверяем результат
    local jar_found=false
    local assets_found=false

    [ -f "$SERVER_JAR" ] && jar_found=true
    [ -f "$ASSETS_ZIP" ] && assets_found=true

    # Ищем в подпапках если не нашли
    if [ "$jar_found" = false ]; then
        local found_jar
        found_jar=$(find "$SERVER_DIR" -name "HytaleServer.jar" 2>/dev/null | head -1)
        if [ -n "$found_jar" ]; then
            cp "$found_jar" "$SERVER_JAR"
            jar_found=true
        fi
    fi

    if [ "$assets_found" = false ]; then
        local found_assets
        found_assets=$(find "$SERVER_DIR" -name "Assets.zip" 2>/dev/null | head -1)
        if [ -n "$found_assets" ]; then
            cp "$found_assets" "$ASSETS_ZIP"
            assets_found=true
        fi
    fi

    if [ "$jar_found" = true ] && [ "$assets_found" = true ]; then
        log_info "Файлы сервера скачаны и готовы"
        return 0
    else
        log_error "Не удалось скачать файлы сервера!"
        log_info "JAR: $jar_found | Assets: $assets_found"
        log_info "Попробуй скачать вручную:"
        log_info "  1. Запусти: $(find_downloader_bin)"
        log_info "  2. Или загрузить Assets.zip и HytaleServer.jar в $SERVER_DIR"
        return 1
    fi
}

# ─── Инструкция для ручной загрузки ───
show_manual_instructions() {
    local ext_ip
    ext_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "IP_сервера")
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Автоматическая загрузка не удалась.                      ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  Загрузи файлы вручную в $SERVER_DIR                       ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  С SCP (с локальной машины):                               ║${NC}"
    echo -e "${YELLOW}║    scp Assets.zip root@$ext_ip:$SERVER_DIR/                ║${NC}"
    echo -e "${YELLOW}║    scp HytaleServer.jar root@$ext_ip:$SERVER_DIR/          ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  Или через wget:                                           ║${NC}"
    echo -e "${YELLOW}║    wget -O $SERVER_DIR/Assets.zip <URL>                    ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  После загрузки запусти скрипт повторно:                   ║${NC}"
    echo -e "${YELLOW}║    sudo bash setup.sh                                      ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─── Файрвол ───
setup_firewall() {
    log_step "Настройка файрвола..."

    if command -v ufw &> /dev/null; then
        ufw allow "$SERVER_PORT"/udp comment "Hytale Server" 2>&1
        ufw reload 2>&1
        log_info "Порт $SERVER_PORT/UDP открыт (UFW)"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT 2>&1
        log_info "Порт $SERVER_PORT/UDP открыт (iptables)"
    else
        log_warn "Файрвол не найден. Открой порт $SERVER_PORT/UDP вручную в панели VDS."
    fi
}

# ─── Проверка что сервер запущен ───
is_running() {
    screen -list | grep -q "$SCREEN_NAME"
}

# ─── Запуск сервера ───
start_server() {
    if is_running; then
        log_warn "Сервер уже запущен!"
        log_info "Консоль: screen -r $SCREEN_NAME"
        return
    fi

    # Проверка файлов
    if [ ! -f "$SERVER_JAR" ] || [ ! -f "$ASSETS_ZIP" ]; then
        log_error "Файлы сервера не найдены!"
        log_info "JAR: $([ -f "$SERVER_JAR" ] && echo найден || echo НЕ НАЙДЕН)"
        log_info "Assets: $([ -f "$ASSETS_ZIP" ] && echo найден || echo НЕ НАЙДЕН)"
        show_manual_instructions
        return 1
    fi

    # Плагины
    local mod_count
    mod_count=$(find "$MODS_DIR" -name "*.jar" 2>/dev/null | wc -l)
    if [ "$mod_count" -gt 0 ]; then
        log_info "Плагины: $mod_count шт."
        for mod in "$MODS_DIR"/*.jar; do
            log_info "  → $(basename "$mod")"
        done
    fi

    log_step "Запуск Hytale Server..."

    screen -dmS "$SCREEN_NAME" bash -c "
        cd '$SERVER_DIR'
        exec java \
            -Xmx4G \
            -XX:+UseG1GC \
            -XX:+ParallelRefProcEnabled \
            -XX:MaxGCPauseMillis=200 \
            -XX:+UnlockExperimentalVMOptions \
            -XX:+DisableExplicitGC \
            -XX:G1NewSizePercent=30 \
            -XX:G1MaxNewSizePercent=40 \
            -XX:G1HeapRegionSize=8M \
            -XX:G1ReservePercent=20 \
            -XX:G1HeapWastePercent=5 \
            -XX:G1MixedGCCountTarget=4 \
            -XX:InitiatingHeapOccupancyPercent=15 \
            -XX:G1MixedGCLiveThresholdPercent=90 \
            -XX:G1RSetUpdatingPauseTimePercent=5 \
            -XX:SurvivorRatio=32 \
            -XX:+PerfDisableSharedMem \
            -XX:MaxTenuringThreshold=1 \
            -Djava.net.preferIPv4Stack=true \
            -jar '$SERVER_JAR' \
            --assets '$ASSETS_ZIP' \
            --bind 0.0.0.0:$SERVER_PORT \
            --universe '$UNIVERSE_DIR' \
            2>&1
    "

    # Ожидание запуска
    log_info "Ожидание запуска..."
    local attempts=0
    while [ $attempts -lt 60 ]; do
        sleep 2
        attempts=$((attempts + 1))
        if ! is_running; then
            log_error "Сервер упал при запуске!"
            return 1
        fi
        if ss -ulnp 2>/dev/null | grep -q ":$SERVER_PORT "; then
            break
        fi
        echo -n "."
    done
    echo ""

    # Результат
    if ! ss -ulnp 2>/dev/null | grep -q ":$SERVER_PORT "; then
        log_warn "Сервер запускается дольше обычного."
    fi

    local local_ip
    local_ip=$(hostname -I | awk '{print $1}')
    local ext_ip
    ext_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "неизвестен")

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Hytale Server запущен!                                    ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Локальный:  $local_ip:$SERVER_PORT                          ${NC}"
    echo -e "${GREEN}║  Внешний:    $ext_ip:$SERVER_PORT                            ${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  Консоль:    screen -r $SCREEN_NAME                              ${NC}"
    echo -e "${GREEN}║  Отключиться от консоли: Ctrl+A, D                         ║${NC}"
    echo -e "${GREEN}║  Остановить: sudo bash setup.sh --stop                    ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  ⚠ Авторизация (при первом запуске):                      ║${NC}"
    echo -e "${GREEN}║    1. screen -r $SCREEN_NAME                                     ${NC}"
    echo -e "${GREEN}║    2. /auth login device                                   ║${NC}"
    echo -e "${GREEN}║    3. Открой ссылку в браузере, введи код                 ║${NC}"
    echo -e "${GREEN}║    4. После успеха: /auth persistence encrypted            ║${NC}"
    echo -e "${GREEN}║    5. Ctrl+A, D (отключиться от консоли)                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    read -p "Подключиться к консоли сервера сейчас? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        screen -r "$SCREEN_NAME"
    fi
}

# ─── Остановка ───
stop_server() {
    if ! is_running; then
        log_warn "Сервер не запущен"
        return
    fi
    log_step "Остановка..."
    screen -S "$SCREEN_NAME" -X stuff "stop$(printf \\r)"
    sleep 5
    if is_running; then
        screen -S "$SCREEN_NAME" -X quit 2>&1
    fi
    log_info "Сервер остановлен"
}

# ─── Статус ───
server_status() {
    echo ""
    echo -e "${BLUE}═══ Hytale Server Status ═══${NC}"

    if is_running; then
        echo -e "Статус: ${GREEN}ЗАПУЩЕН${NC}"
    else
        echo -e "Статус: ${RED}ОСТАНОВЛЕН${NC}"
    fi

    if ss -ulnp 2>/dev/null | grep -q ":$SERVER_PORT "; then
        echo -e "Порт $SERVER_PORT/UDP: ${GREEN}СЛУШАЕТ${NC}"
    else
        echo -e "Порт $SERVER_PORT/UDP: ${RED}НЕ СЛУШАЕТ${NC}"
    fi

    [ -f "$SERVER_JAR" ] && \
        echo -e "Server JAR: ${GREEN}ДА${NC} ($(du -h "$SERVER_JAR" | cut -f1))" || \
        echo -e "Server JAR: ${RED}НЕТ${NC}"

    [ -f "$ASSETS_ZIP" ] && \
        echo -e "Assets.zip: ${GREEN}ДА${NC} ($(du -h "$ASSETS_ZIP" | cut -f1))" || \
        echo -e "Assets.zip: ${RED}НЕТ${NC}"

    local mod_count
    mod_count=$(find "$MODS_DIR" -name "*.jar" 2>/dev/null | wc -l)
    echo -e "Плагины: $mod_count"

    local pid
    pid=$(pgrep -f "HytaleServer" 2>/dev/null || echo "")
    if [ -n "$pid" ]; then
        local mem cpu
        mem=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.0f MB", $1/1024}')
        cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{printf "%.1f%%", $1}')
        echo -e "RAM: $mem | CPU: $cpu"
    fi

    local ext_ip
    ext_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "?")
    echo -e "Подключение: $ext_ip:$SERVER_PORT"
    echo ""
}

# ─── Бэкап ───
backup_world() {
    local ts
    ts=$(date +"%Y%m%d_%H%M%S")
    local file="$BACKUP_DIR/universe_$ts.tar.gz"

    log_step "Бэкап мира..."
    tar -czf "$file" -C "$SERVER_DIR" "universe/" 2>/dev/null

    if [ -f "$file" ]; then
        log_info "Бэкап: $file ($(du -h "$file" | cut -f1))"
        # Удаляем старые (оставляем 5)
        local count
        count=$(ls -1 "$BACKUP_DIR"/universe_*.tar.gz 2>/dev/null | wc -l)
        if [ "$count" -gt 5 ]; then
            ls -1t "$BACKUP_DIR"/universe_*.tar.gz | tail -n +6 | xargs rm -f
        fi
    else
        log_error "Ошибка бэкапа"
    fi
}

# ─── Обновление ───
update_server() {
    log_step "Обновление сервера..."

    if is_running; then
        log_warn "Сервер нужно остановить для обновления"
        read -p "Остановить сейчас? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
        stop_server
        sleep 2
    fi

    local dl_bin
    dl_bin=$(find_downloader_bin) || {
        log_error "Downloader не найден"
        return 1
    }

    log_info "Запуск downloader для обновления..."
    cd "$SERVER_DIR"
    "$dl_bin" 2>&1

    # Перемещаем новые файлы
    local found_jar
    found_jar=$(find "$SERVER_DIR" -name "HytaleServer.jar" 2>/dev/null | head -1)
    if [ -n "$found_jar" ] && [ "$found_jar" != "$SERVER_JAR" ]; then
        cp "$found_jar" "$SERVER_JAR"
        log_info "HytaleServer.jar обновлён"
    fi

    local found_assets
    found_assets=$(find "$SERVER_DIR" -name "Assets.zip" 2>/dev/null | head -1)
    if [ -n "$found_assets" ] && [ "$found_assets" != "$ASSETS_ZIP" ]; then
        cp "$found_assets" "$ASSETS_ZIP"
        log_info "Assets.zip обновлён"
    fi

    log_info "Обновление завершено. Запусти сервер: sudo bash setup.sh"
}

# ══════════════════════════════════════════
#  ГЛАВНАЯ ФУНКЦИЯ
# ══════════════════════════════════════════
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Hytale Server Setup & Launch Script v2.0            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    detect_os

    case "${1:-}" in
        --stop)     stop_server; exit 0 ;;
        --status)   server_status; exit 0 ;;
        --backup)   backup_world; exit 0 ;;
        --update)   update_server; exit 0 ;;
        --help|-h)
            echo "Использование:"
            echo "  sudo bash setup.sh            — установка и/или запуск"
            echo "  sudo bash setup.sh --stop     — остановить"
            echo "  sudo bash setup.sh --status   — статус"
            echo "  sudo bash setup.sh --backup   — бэкап мира"
            echo "  sudo bash setup.sh --update   — обновить сервер"
            echo "  sudo bash setup.sh --help     — справка"
            exit 0
            ;;
        "") ;;  # основной поток
        *)
            log_error "Неизвестный аргумент: $1"
            echo "Используй --help"
            exit 1
            ;;
    esac

    # ── Проверяем что уже установлено ──
    local java_ok=false jar_ok=false assets_ok=false

    if command -v java &> /dev/null; then
        local jv
        jv=$(java -version 2>&1 | grep -oP '\d+' | head -1)
        [ "$jv" -ge 25 ] 2>/dev/null && java_ok=true
    fi
    [ -f "$SERVER_JAR" ] && jar_ok=true
    [ -f "$ASSETS_ZIP" ] && assets_ok=true

    # ── Всё готово — просто запускаем ──
    if [ "$java_ok" = true ] && [ "$jar_ok" = true ] && [ "$assets_ok" = true ]; then
        log_info "Всё уже установлено, запуск..."
        start_server
        exit 0
    fi

    # ── Полная установка ──
    log_step "Начинаем установку..."

    install_java
    install_deps
    create_dirs
    setup_firewall

    # Скачиваем downloader
    download_downloader

    # Пытаемся скачать файлы через downloader
    if [ "$jar_ok" = false ] || [ "$assets_ok" = false ]; then
        if ! download_server_files; then
            show_manual_instructions
            exit 0
        fi
    fi

    start_server
}

main "$@"
