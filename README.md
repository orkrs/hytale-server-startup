# Hytale Server Setup v2.0

Полностью автоматическая установка и запуск Hytale Dedicated Server на Ubuntu VDS.

## Быстрый старт

**Одна команда — и сервер запущен:**

```bash
curl -fsSL https://raw.githubusercontent.com/orkrs/hytale-server-startup/main/setup.sh | sudo bash
```

## Что делает скрипт

### При первом запуске (всё автоматически):
1. ✅ Устанавливает **Java 25** (Temurin/Adoptium)
2. ✅ Устанавливает зависимости (screen, curl, jq, unzip)
3. ✅ Скачивает **Hytale Downloader** (официальный CLI)
4. ✅ Через downloader скачивает **HytaleServer.jar** и **Assets.zip** (~3.3 ГБ)
   - ⚠ При первом запуске downloader попросит OAuth-авторизацию (ссылка + код в браузер)
5. ✅ Открывает порт **5520/UDP** в файрволе
6. ✅ Запускает сервер в screen-сессии
7. ✅ Показывает IP для подключения

### При повторных запусках:
- Проверяет что всё установлено
- Просто запускает сервер

## Требования

- Ubuntu 22.04+ (или совместимый)
- Минимум **4 GB RAM**
- ~5 GB свободного места
- Root-доступ
- Доступ в интернет (для скачивания файлов)

## Установка

### Вариант 1: Одна команда (рекомендуется)

```bash
curl -fsSL https://raw.githubusercontent.com/orkrs/hytale-server-startup/main/setup.sh | sudo bash
```

### Вариант 2: Вручную

```bash
git clone https://github.com/orkrs/hytale-server-startup.git
cd hytale-server-startup
sudo bash setup.sh
```

## Авторизация (при первом запуске)

После загрузки сервера нужно один раз авторизовать его:

```bash
# Подключись к консоли сервера
screen -r hytale

# Введи команду
/auth login device

# Следуй инструкциям:
# 1. Открой ссылку в браузере
# 2. Введи код
# 3. Разреши доступ

# После успешной авторизации — сохрани токен:
/auth persistence encrypted

# Отключись от консоли: Ctrl+A, D
```

После этого сервер будет автоматически авторизоваться при каждом запуске.

## Управление

```bash
# Запуск / перезапуск
sudo bash setup.sh

# Остановка
sudo bash setup.sh --stop

# Статус
sudo bash setup.sh --status

# Бэкап мира
sudo bash setup.sh --backup

# Обновить сервер (через downloader)
sudo bash setup.sh --update
```

## Консоль сервера

```bash
# Подключиться
screen -r hytale

# Отключиться (сервер продолжит работать)
Ctrl+A, D
```

## Подключение клиента

1. Запусти Hytale клиент
2. Multiplayer → Direct Connect
3. Введи: `<IP_сервера>:5520`

## Добавление плагинов

Загрузи `.jar` файл плагина в `/opt/hytale-server/mods/` и перезапусти:

```bash
scp my-plugin.jar root@<IP>:/opt/hytale-server/mods/
sudo bash setup.sh  # авто-перезапуск
```

## Порты

- **5520/UDP** — основной порт (QUIC)

Если VDS за NAT/файрволом — убедись что UDP порт 5520 открыт в панели управления VDS.

## Структура файлов

```
/opt/hytale-server/
├── Assets.zip           # Ассеты сервера (~3.3 GB)
├── HytaleServer.jar     # JAR сервера
├── mods/                # Плагины (.jar)
├── universe/            # Мир и данные игроков
├── backups/             # Бэкапы
├── .downloader/         # Hytale Downloader
├── config.json          # Конфигурация сервера
└── server.log           # Логи
```
