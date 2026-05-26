# Hytale Server Setup v2.2

Полностью автоматическая установка и запуск **Hytale Dedicated Server 0.5.0** на Ubuntu VDS (Java 25).

## Быстрый старт

**Одна команда — и сервер запущен:**

```bash
curl -fsSL https://raw.githubusercontent.com/orkrs/hytale-server-startup/main/setup.sh | sudo bash
```

## Что делает скрипт

### При первом запуске (всё автоматически):
1. ✅ Устанавливает **Java 25** (Temurin/Adoptium)
2. ✅ Устанавливает зависимости (screen, curl, jq, unzip, net-tools)
3. ✅ Создаёт структуру директорий в `/opt/hytale-server/`
4. ✅ Открывает порт **5520/UDP** в файрволе (UFW/iptables)
5. ✅ **Оптимизирует сетевые буферы** UDP/QUIC ядра Linux (`rmem_max`/`wmem_max` = 25 МБ)
6. ✅ Скачивает **Hytale Downloader** (официальный CLI, Linux-бинарник)
7. ✅ Через downloader скачивает **HytaleServer.jar** и **Assets.zip** (~3.5 ГБ)
   - ⚠ При первом запуске downloader попросит OAuth-авторизацию (ссылка + код в браузер)
8. ✅ **Автоматически определяет ресурсы VDS** (ОЗУ, CPU) и подбирает оптимальные JVM-параметры
9. ✅ Генерирует **config.json** (Hytale 0.5.0) с оптимальными настройками
10. ✅ Запускает сервер в screen-сессии с Java 25 native access

### При повторных запусках:
- Проверяет что всё установлено
- Просто запускает сервер

## Требования

- Ubuntu 20.04+ / 22.04+ (или совместимый Debian-based)
- Минимум **2 GB RAM** (рекомендуется 4+ ГБ)
- ~6 GB свободного места
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

# Статус (RAM, CPU, порт, плагины)
sudo bash setup.sh --status

# Бэкап мира (хранит последние 5)
sudo bash setup.sh --backup

# Обновить сервер до последней версии release
sudo bash setup.sh --update

# Справка
sudo bash setup.sh --help
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
sudo bash setup.sh
```

## Порты

- **5520/UDP** — основной порт (QUIC)

Если VDS за NAT/файрволом — убедись что UDP порт 5520 открыт в панели управления VDS.

## Структура файлов

```
/opt/hytale-server/
├── Assets.zip              # Ассеты сервера (~3.3 GB)
├── HytaleServer.jar        # JAR сервера
├── HytaleServer.aot        # AOT-кэш (автогенерация)
├── config.json             # Конфигурация (автогенерация)
├── mods/                   # Плагины (.jar)
├── universe/               # Мир и данные игроков
├── backups/                # Бэкапы (последние 5)
└── .downloader/            # Hytale Downloader
```

## Динамическое распределение ресурсов

Скрипт автоматически определяет конфигурацию VDS и подбирает JVM-параметры:

| Конфигурация | ОЗУ | CPU | GC | -Xmx |
|---|---|---|---|---|
| Минимальная | < 2 ГБ | 1 ядро | SerialGC | 1024M |
| Рекомендуемая | 2–4.5 ГБ | 2+ ядра | G1GC (оптимизированный) | 75% ОЗУ |
| Мощная | ≥ 5 ГБ | 4+ ядер | Generational ZGC | 75% ОЗУ |

### Пример (4 ГБ ОЗУ, 2 ядра):
```
-Xmx3072M
-XX:+UseG1GC
-XX:MaxGCPauseMillis=20
-XX:InitiatingHeapOccupancyPercent=45
-XX:G1ReservePercent=15
-XX:MaxMetaspaceSize=256M
--enable-native-access=ALL-UNNAMED
```

### Пример (2 ГБ ОЗУ, 1 ядро):
```
-Xmx1024M
-XX:+UseSerialGC
--enable-native-access=ALL-UNNAMED
```

## Оптимизация сети (UDP/QUIC)

Скрипт автоматически настраивает ядро Linux для стабильной работы QUIC:

```bash
# /etc/sysctl.conf
net.core.rmem_max = 26214400   # 25 МБ буфер приёма
net.core.wmem_max = 26214400   # 25 МБ буфер отправки
```

Это предотвращает отбрасывание UDP-пакетов при высоком онлайне.

## config.json (Hytale 0.5.0)

При первом запуске скрипт генерирует `config.json` с оптимальными настройками:

```json
{
    "MaxPlayers": 20,
    "MaxViewRadius": 4,
    "ServerPort": 5520,
    "ServerAddress": "0.0.0.0",
    "Modules": {
        "Hytale:Farming": { "Enabled": false },
        "Hytale:NPCEditor": { "Enabled": false },
        "Hytale:BuilderTools": { "Enabled": false },
        "Hytale:ObjectiveShop": { "Enabled": false },
        "Hytale:LANDiscovery": { "Enabled": false },
        "Hytale:CreativeHub": { "Enabled": false }
    }
}
```

> **Важно:** В Hytale 0.5.0 модули используют BSON-формат `{ "Enabled": false }`, а не простой булевый флаг. Неправильный формат вызывает `BsonInvalidOperationException`.

### Ручное редактирование

```bash
nano /opt/hytale-server/config.json
# После изменений — перезапуск:
sudo bash setup.sh
```

## Ручная загрузка файлов (если downloader не сработал)

```bash
# С локальной машины через SCP:
scp Assets.zip root@<IP>:/opt/hytale-server/
scp HytaleServer.jar root@<IP>:/opt/hytale-server/

# Или на сервере через wget:
wget -O /opt/hytale-server/Assets.zip <URL>
wget -O /opt/hytale-server/HytaleServer.jar <URL>

# Затем запусти скрипт повторно:
sudo bash setup.sh
```

## Обновление сервера

```bash
sudo bash setup.sh --update
```

Скрипт:
1. Останавливает сервер
2. Создаёт бэкап мира
3. Запускает downloader с флагом `--patchline release` (всегда последняя версия)
4. Распаковывает новый архив

## Бэкапы

```bash
# Ручной бэкап
sudo bash setup.sh --backup
```

Бэкапы хранятся в `/opt/hytale-server/backups/` (последние 5). Автобэкап при каждом `--update`.

## Устранение неполадок

### Сервер не запускается
```bash
# Проверь статус
sudo bash setup.sh --status

# Посмотри логи screen-сессии
screen -r hytale
```

### Java 25 restricted access warnings
Уже исправлено флагом `--enable-native-access=ALL-UNNAMED`. Если видишь warnings — убедись что используешь последнюю версию скрипта.

### BsonInvalidOperationException в config.json
Убедись что модули записаны в формате `{ "Enabled": false }`, а не просто `false`.

### Потеря UDP-пакетов / лаги
Проверь что sysctl настройки применены:
```bash
sysctl net.core.rmem_max net.core.wmem_max
# Ожидаемый вывод:
# net.core.rmem_max = 26214400
# net.core.wmem_max = 26214400
```

### OOM Killer убивает сервер
Скрипт автоматически ограничивает `-Xmx` до 75% ОЗУ. Если проблема сохраняется — уменьши `MaxPlayers` в `config.json`.
