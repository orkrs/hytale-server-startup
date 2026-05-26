#!/bin/bash
# ============================================================
#  Hytale Server Setup & Launch Script
#  Умный скрипт для установки и запуска Hytale Dedicated Server
#  на Ubuntu VDS
#
#  Запуск:  bash setup.sh
#           bash setup.sh --update    (обновить плагины)
#           bash setup.sh --backup    (сделать бэкап мира)
#           bash setup.sh --status    (статус сервера)
#           bash setup.sh --stop      (остановить сервер)
# ============================================================

set -e

# ─── Настройки ───
SERVER_DIR="/opt/hytale-server"
ASSETS_ZIP="$SERVER_DIR/Assets.zip"
ASSETS_DIR="$SERVER_DIR/HytaleAssets"
SERVER_JAR="$SERVER_DIR/HytaleServer.jar"
MODS_DIR="$SERVER_DIR/mods"
UNIVERSE_DIR="$SERVER_DIR/universe"
BACKUP_DIR="$SERVER_DIR/backups"
JAVA_PATH="/usr/lib/jvm/temurin-25-jdk-amd64/bin/java"
SCREEN_NAME="hytale"
SERVER_PORT=5520

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── Функции ───

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Проверка root-прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Запусти скрипт от root: sudo bash setup.sh"
        exit 1
    fi
}

# Установка Java 25 (Temurin/Adoptium)
install_java() {
    if [ -f "$JAVA_PATH" ]; then
        JAVA_VER=$("$JAVA_PATH" -version 2>&1 | head -1)
        log_info "Java уже установлена: $JAVA_VER"
        return
    fi

    log_step "Установка Java 25 (Temurin)..."

    # Установка зависимостей
    apt-get update -qq
    apt-get install -y -qq wget apt-transport-https gpg

    # Добавление репозитория Adoptium
    mkdir -p /etc/apt/keyrings
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg

    # Определение дистрибутива
    DISTRO=$(. /etc/os-release && echo "$VERSION_CODENAME")
    if [ -z "$DISTRO" ]; then
        DISTRO="jammy"  # fallback для Ubuntu 22.04
    fi

    echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $DISTRO main" > /etc/apt/sources.list.d/adoptium.list

    apt-get update -qq
    apt-get install -y -qq temurin-25-jdk

    # Проверка
    if [ -f "$JAVA_PATH" ]; then
        JAVA_VER=$("$JAVA_PATH" -version 2>&1 | head -1)
        log_info "Java установлена: $JAVA_VER"
    else
        # Поиск Java 25 в другом месте
        JAVA_PATH=$(find /usr/lib/jvm -name "java" -path "*25*" 2>/dev/null | head -1)
        if [ -z "$JAVA_PATH" ]; then
            log_error "Не удалось установить Java 25"
            exit 1
        fi
        log_info "Java найдена: $JAVA_PATH"
    fi
}

# Установка дополнительных пакетов
install_dependencies() {
    log_step "Установка зависимостей..."
    apt-get install -y -qq screen curl unzip jq net-tools
    log_info "Зависимости установлены"
}

# Создание структуры директорий
create_directories() {
    log_step "Создание структуры директорий..."
    mkdir -p "$SERVER_DIR" "$MODS_DIR" "$UNIVERSE_DIR" "$BACKUP_DIR"
    log_info "Директории созданы в $SERVER_DIR"
}

# Проверка наличия Assets.zip
check_assets() {
    if [ -f "$ASSETS_ZIP" ]; then
        ASSET_SIZE=$(du -h "$ASSETS_ZIP" | cut -f1)
        log_info "Assets.zip найден (размер: $ASSET_SIZE)"
        return 0
    fi
    return 1
}

# Проверка наличия Server JAR
check_server_jar() {
    if [ -f "$SERVER_JAR" ]; then
        JAR_SIZE=$(du -h "$SERVER_JAR" | cut -f1)
        log_info "HytaleServer.jar найден (размер: $JAR_SIZE)"
        return 0
    fi
    return 1
}

# Инструкция по загрузке файлов
show_upload_instructions() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Файлы сервера не найдены!                                ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  Загрузи следующие файлы в: $SERVER_DIR    ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  1. Assets.zip    (~3.3 GB) — ассеты сервера              ║${NC}"
    echo -e "${YELLOW}║  2. HytaleServer.jar — JAR сервера                        ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  Способы загрузки:                                         ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  A) С локальной машины через SCP:                         ║${NC}"
    echo -e "${YELLOW}║     scp Assets.zip user@$(curl -s ifconfig.me):$SERVER_DIR/        ║${NC}"
    echo -e "${YELLOW}║     scp HytaleServer.jar user@$(curl -s ifconfig.me):$SERVER_DIR/  ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  B) Через wget если есть прямая ссылка:                   ║${NC}"
    echo -e "${YELLOW}║     wget -O $SERVER_DIR/Assets.zip <URL>                   ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║  После загрузки запусти скрипт повторно:                   ║${NC}"
    echo -e "${YELLOW}║     sudo bash setup.sh                                     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Распаковка ассетов (если ещё не распакованы)
extract_assets() {
    if [ -d "$ASSETS_DIR/Server" ] && [ -f "$ASSETS_DIR/manifest.json" ]; then
        log_info "Ассеты уже распакованы в $ASSETS_DIR"
        return
    fi

    if [ ! -f "$ASSETS_ZIP" ]; then
        log_error "Assets.zip не найден!"
        return 1
    fi

    log_step "Распаковка ассетов (это может занять несколько минут)..."
    mkdir -p "$ASSETS_DIR"
    unzip -q -o "$ASSETS_ZIP" -d "$ASSETS_DIR"
    log_info "Ассеты распакованы в $ASSETS_DIR"
}

# Проверка что сервер уже запущен
is_server_running() {
    screen -list | grep -q "$SCREEN_NAME"
}

# Запуск сервера
start_server() {
    if is_server_running; then
        log_warn "Сервер уже запущен!"
        log_info "Для подключения к консоли: screen -r $SCREEN_NAME"
        log_info "Для отключения от консоли: Ctrl+A, затем D"
        return
    fi

    # Проверка файлов
    local has_assets=false
    local has_jar=false

    if [ -f "$ASSETS_ZIP" ]; then
        has_assets=true
    fi
    if [ -d "$ASSETS_DIR/Server" ] && [ -f "$ASSETS_DIR/manifest.json" ]; then
        has_assets=true
    fi
    if [ -f "$SERVER_JAR" ]; then
        has_jar=true
    fi

    if [ "$has_jar" = false ]; then
        log_error "HytaleServer.jar не найден в $SERVER_DIR"
        show_upload_instructions
        return 1
    fi

    if [ "$has_assets" = false ]; then
        log_error "Ассеты не найдены!"
        show_upload_instructions
        return 1
    fi

    # Распаковка если нужно
    if [ -f "$ASSETS_ZIP" ] && [ ! -d "$ASSETS_DIR/Server" ]; then
        extract_assets
    fi

    # Определяем путь к ассетам (zip или распакованные)
    local assets_arg
    if [ -f "$ASSETS_ZIP" ]; then
        assets_arg="--assets $ASSETS_ZIP"
    else
        assets_arg="--assets $ASSETS_DIR"
    fi

    # Определяем путь к Java
    local java_bin="$JAVA_PATH"
    if [ ! -f "$java_bin" ]; then
        java_bin=$(which java 2>/dev/null || echo "")
        if [ -z "$java_bin" ]; then
            log_error "Java не найдена!"
            return 1
        fi
    fi

    local java_ver=$("$java_bin" -version 2>&1 | head -1)
    log_info "Используется: $java_ver"

    # Проверка плагинов
    local mod_count=$(find "$MODS_DIR" -name "*.jar" 2>/dev/null | wc -l)
    if [ "$mod_count" -gt 0 ]; then
        log_info "Найдено плагинов: $mod_count"
        for mod in "$MODS_DIR"/*.jar; do
            log_info "  → $(basename "$mod")"
        done
    fi

    # Запуск сервера в screen
    log_step "Запуск Hytale Server на порту $SERVER_PORT..."

    screen -dmS "$SCREEN_NAME" bash -c "
        cd '$SERVER_DIR'
        exec '$java_bin' \
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
            -jar '$SERVER_JAR' \
            $assets_arg \
            --bind 0.0.0.0:$SERVER_PORT \
            --universe '$UNIVERSE_DIR' \
            2>&1
    "

    # Ждём пока сервер запустится
    log_info "Ожидание запуска сервера..."
    local attempts=0
    local max_attempts=60

    while [ $attempts -lt $max_attempts ]; do
        sleep 2
        attempts=$((attempts + 1))

        # Проверяем что процесс жив
        if ! is_server_running; then
            log_error "Сервер упал при запуске! Проверь логи: screen -r $SCREEN_NAME"
            return 1
        fi

        # Проверяем порт
        if ss -ulnp | grep -q ":$SERVER_PORT "; then
            log_info "Сервер слушает порт $SERVER_PORT"
            break
        fi

        echo -n "."
    done

    echo ""

    if [ $attempts -ge $max_attempts ]; then
        log_warn "Сервер запускается дольше обычного. Проверь: screen -r $SCREEN_NAME"
    fi

    # Получаем IP
    local local_ip=$(hostname -I | awk '{print $1}')
    local external_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "неизвестен")

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Hytale Server запущен!                                    ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Локальный IP:    $local_ip:$SERVER_PORT                          ║${NC}"
    echo -e "${GREEN}║  Внешний IP:      $external_ip:$SERVER_PORT                       ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  Подключение к консоли:  screen -r $SCREEN_NAME                   ║${NC}"
    echo -e "${GREEN}║  Отключение от консоли:  Ctrl+A, D                         ║${NC}"
    echo -e "${GREEN}║  Остановка сервера:      sudo bash setup.sh --stop        ║${NC}"
    echo -e "${GREEN}║  Статус сервера:         sudo bash setup.sh --status       ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  Для авторизации введи в консоли сервера:                  ║${NC}"
    echo -e "${GREEN}║    /auth login device                                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Предлагаем подключиться к консоли
    read -p "Подключиться к консоли сервера сейчас? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Подключение к консоли... (Ctrl+A, D чтобы отключиться)"
        sleep 1
        screen -r "$SCREEN_NAME"
    fi
}

# Остановка сервера
stop_server() {
    if ! is_server_running; then
        log_warn "Сервер не запущен"
        return
    fi

    log_step "Остановка сервера..."
    screen -S "$SCREEN_NAME" -X stuff "stop$(printf \\r)"
    sleep 5

    # Принудительная остановка если не остановился
    if is_server_running; then
        log_warn "Сервер не остановился, принудительная остановка..."
        screen -S "$SCREEN_NAME" -X quit
    fi

    log_info "Сервер остановлен"
}

# Статус сервера
server_status() {
    echo ""
    echo -e "${BLUE}═══ Статус Hytale Server ═══${NC}"

    if is_server_running; then
        echo -e "Статус: ${GREEN}ЗАПУЩЕН${NC}"
    else
        echo -e "Статус: ${RED}ОСТАНОВЛЕН${NC}"
    fi

    # Проверка порта
    if ss -ulnp | grep -q ":$SERVER_PORT "; then
        echo -e "Порт $SERVER_PORT: ${GREEN}СЛУШАЕТ${NC}"
    else
        echo -e "Порт $SERVER_PORT: ${RED}НЕ СЛУШАЕТ${NC}"
    fi

    # Файлы
    if [ -f "$SERVER_JAR" ]; then
        echo -e "Server JAR: ${GREEN}НАЙДЕН${NC} ($(du -h "$SERVER_JAR" | cut -f1))"
    else
        echo -e "Server JAR: ${RED}НЕ НАЙДЕН${NC}"
    fi

    if [ -f "$ASSETS_ZIP" ]; then
        echo -e "Assets.zip: ${GREEN}НАЙДЕН${NC} ($(du -h "$ASSETS_ZIP" | cut -f1))"
    elif [ -d "$ASSETS_DIR/Server" ]; then
        echo -e "Ассеты: ${GREEN}РАСПАКОВАНЫ${NC} в $ASSETS_DIR"
    else
        echo -e "Ассеты: ${RED}НЕ НАЙДЕНЫ${NC}"
    fi

    # Плагины
    local mod_count=$(find "$MODS_DIR" -name "*.jar" 2>/dev/null | wc -l)
    echo -e "Плагины: $mod_count"

    # Использование ресурсов
    local hytale_pid=$(pgrep -f "HytaleServer" 2>/dev/null || echo "")
    if [ -n "$hytale_pid" ]; then
        local mem_usage=$(ps -p "$hytale_pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
        local cpu_usage=$(ps -p "$hytale_pid" -o %cpu= 2>/dev/null | awk '{printf "%.1f%%", $1}')
        echo -e "RAM: $mem_usage | CPU: $cpu_usage"
    fi

    # IP
    local external_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "неизвестен")
    echo -e "Внешний IP: $external_ip:$SERVER_PORT"
    echo ""
}

# Бэкап мира
backup_world() {
    if ! is_server_running; then
        log_warn "Сервер не запущен, бэкап может быть неполным"
    fi

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/universe_$timestamp.tar.gz"

    log_step "Создание бэкапа мира..."
    tar -czf "$backup_file" -C "$SERVER_DIR" "universe/" 2>/dev/null

    if [ -f "$backup_file" ]; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_info "Бэкап создан: $backup_file ($backup_size)"

        # Удаляем старые бэкапы (оставляем последние 5)
        local backup_count=$(ls -1 "$BACKUP_DIR"/universe_*.tar.gz 2>/dev/null | wc -l)
        if [ "$backup_count" -gt 5 ]; then
            ls -1t "$BACKUP_DIR"/universe_*.tar.gz | tail -n +6 | xargs rm -f
            log_info "Старые бэкапы удалены (оставлено 5)"
        fi
    else
        log_error "Не удалось создать бэкап"
    fi
}

# Обновление плагинов (из локальной папки mods/)
update_plugins() {
    log_step "Проверка плагинов..."

    if [ ! -d "$MODS_DIR" ]; then
        log_warn "Папка mods/ не существует"
        return
    fi

    local mod_count=$(find "$MODS_DIR" -name "*.jar" 2>/dev/null | wc -l)
    if [ "$mod_count" -eq 0 ]; then
        log_warn "Плагины не найдены в $MODS_DIR"
        log_info "Загрузи .jar плагины в: $MODS_DIR"
        return
    fi

    log_info "Найдено плагинов: $mod_count"
    for mod in "$MODS_DIR"/*.jar; do
        log_info "  → $(basename "$mod") ($(du -h "$mod" | cut -f1))"
    done

    if is_server_running; then
        log_warn "Для обновления плагинов нужно перезапустить сервер"
        read -p "Перезапустить сейчас? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_server
            sleep 2
            start_server
        fi
    fi
}

# Настройка файрвола
setup_firewall() {
    log_step "Настройка файрвола..."

    if command -v ufw &> /dev/null; then
        ufw allow "$SERVER_PORT"/udp comment "Hytale Server"
        ufw reload
        log_info "Порт $SERVER_PORT/UDP открыт в UFW"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT
        log_info "Порт $SERVER_PORT/UDP открыт в iptables"
    else
        log_warn "Файрвол не найден. Открой порт $SERVER_PORT/UDP вручную"
    fi
}

# ─── Основная логика ───

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Hytale Server Setup & Launch Script v1.0            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root

    case "${1:-}" in
        --stop)
            stop_server
            exit 0
            ;;
        --status)
            server_status
            exit 0
            ;;
        --backup)
            backup_world
            exit 0
            ;;
        --update)
            update_plugins
            exit 0
            ;;
        --help|-h)
            echo "Использование:"
            echo "  sudo bash setup.sh            — установка и запуск сервера"
            echo "  sudo bash setup.sh --stop     — остановить сервер"
            echo "  sudo bash setup.sh --status   — статус сервера"
            echo "  sudo bash setup.sh --backup   — бэкап мира"
            echo "  sudo bash setup.sh --update   — обновить плагины"
            echo "  sudo bash setup.sh --help     — эта справка"
            exit 0
            ;;
        "")
            # Основной поток — установка и запуск
            ;;
        *)
            log_error "Неизвестный аргумент: $1"
            echo "Используй --help для справки"
            exit 1
            ;;
    esac

    # Проверяем что уже установлено
    local java_installed=false
    local assets_found=false
    local jar_found=false
    local server_configured=false

    if [ -f "$JAVA_PATH" ] || command -v java &> /dev/null; then
        java_installed=true
    fi
    if [ -f "$ASSETS_ZIP" ] || [ -d "$ASSETS_DIR/Server" ]; then
        assets_found=true
    fi
    if [ -f "$SERVER_JAR" ]; then
        jar_found=true
    fi
    if [ -f "$SERVER_DIR/config.json" ]; then
        server_configured=true
    fi

    # Если всё уже настроено — просто запускаем
    if [ "$java_installed" = true ] && [ "$assets_found" = true ] && [ "$jar_found" = true ]; then
        log_info "Сервер уже настроен, запуск..."
        setup_firewall
        start_server
        exit 0
    fi

    # Иначе — полная установка
    log_step "Начинаем установку..."

    install_java
    install_dependencies
    create_directories
    setup_firewall

    # Проверяем наличие файлов
    if ! check_assets || ! check_server_jar; then
        show_upload_instructions
        exit 0
    fi

    extract_assets
    start_server
}

main "$@"
