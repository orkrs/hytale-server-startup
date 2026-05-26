# Hytale Server Setup

Автоматическая установка и запуск Hytale Dedicated Server на Ubuntu VDS.

## Быстрый старт

```bash
# Скачать и запустить (всё в одной команде)
curl -fsSL https://raw.githubusercontent.com/orkrs/hytale-server-startup/main/setup.sh | sudo bash
```

## Требования

- Ubuntu 22.04+ (или совместимый дистрибутив)
- Минимум 4 GB RAM
- ~5 GB свободного места (3.3 GB ассеты + сервер)
- Root-доступ

## Установка

### 1. Клонируй репозиторий

```bash
git clone https://github.com/orkrs/hytale-server-startup.git
cd hytale-server-startup
```

### 2. Загрузи файлы сервера

Помести в папку `/opt/hytale-server/`:
- `Assets.zip` (~3.3 GB) — ассеты сервера
- `HytaleServer.jar` — JAR сервера

Или скопируй с локальной машины:

```bash
scp Assets.zip user@<IP>:/opt/hytale-server/
scp HytaleServer.jar user@<IP>:/opt/hytale-server/
```

### 3. Запусти скрипт

```bash
sudo bash setup.sh
```

Скрипт автоматически:
- Установит Java 25 (Temurin)
- Установит зависимости (screen, curl, jq)
- Распакует ассеты
- Откроет порт в файрволе
- Запустит сервер в screen-сессии

## Управление сервером

```bash
# Запуск / перезапуск
sudo bash setup.sh

# Остановка
sudo bash setup.sh --stop

# Статус
sudo bash setup.sh --status

# Бэкап мира
sudo bash setup.sh --backup

# Обновить плагины
sudo bash setup.sh --update
```

## Подключение к консоли

```bash
# Подключиться
screen -r hytale

# Отключиться (не останавливая сервер)
Ctrl+A, D
```

## Авторизация

После первого запуска в консоли сервера:

```
/auth login device
```

Следуй инструкциям — открой ссылку в браузере и введи код.

Для сохранения токена (чтобы не авторизоваться заново):

```
/auth persistence encrypted
```

## Подключение клиента

1. Запусти Hytale клиент
2. Multiplayer → Direct Connect
3. Введи: `<IP_сервера>:5520`

## Порты

- **5520/UDP** — основной порт сервера (QUIC)

Если сервер за роутером — пробрось UDP порт 5520.

## Структура файлов

```
/opt/hytale-server/
├── Assets.zip          # Ассеты сервера
├── HytaleAssets/       # Распакованные ассеты
├── HytaleServer.jar    # JAR сервера
├── mods/               # Плагины (.jar)
├── universe/           # Мир и данные игроков
├── backups/            # Бэкапы
└── config.json         # Конфигурация сервера
```

## Добавление плагинов

Просто загрузи `.jar` файл плагина в `/opt/hytale-server/mods/` и перезапусти сервер:

```bash
scp my-plugin.jar user@<IP>:/opt/hytale-server/mods/
sudo bash setup.sh --update
```
