# Битрикс CDN Сервер для обработки изображений

## Описание проекта
Настройка второго сервера (Debian) как CDN для автоматической конвертации изображений в WebP формат для сайта на Битрикс.

## 🚀 Два способа установки

### Вариант 1: Docker (Рекомендуется)
Быстрое развертывание через Docker Compose с автоматической настройкой всех компонентов.

### Вариант 2: Native Installation
Традиционная установка напрямую на сервер для максимального контроля.

---

## 🐳 Docker установка

### Требования
- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM минимум
- 50GB свободного места

### Быстрый старт

1. **Клонировать репозиторий**
```bash
git clone <repository>
cd bitrix-cdn-server
```

2. **Настроить окружение**
```bash
cp .env.example .env
nano .env  # Заполнить параметры
```

3. **Первоначальная настройка**
```bash
chmod +x docker-manage.sh
./docker-manage.sh setup
```

4. **Запустить сервисы**
```bash
# Production версия с мониторингом
docker-compose up -d

# Или development версия
docker-compose -f docker-compose.dev.yml up -d
```

5. **Проверить статус**
```bash
./docker-manage.sh status
```

### Docker компоненты

- **nginx** - Веб-сервер с поддержкой WebP
- **webp-converter** - Сервис конвертации изображений
- **sshfs** - Монтирование файлов с Битрикс
- **redis** - Кеширование метаданных
- **varnish** - HTTP кеш (опционально)
- **prometheus** - Сбор метрик
- **grafana** - Визуализация метрик

### Управление Docker

```bash
# Основные команды
./docker-manage.sh start    # Запустить
./docker-manage.sh stop     # Остановить
./docker-manage.sh restart  # Перезапустить
./docker-manage.sh status   # Статус
./docker-manage.sh logs -f  # Логи

# Обслуживание
./docker-manage.sh clean    # Очистить кеш
./docker-manage.sh stats    # Статистика
./docker-manage.sh backup   # Резервная копия

# Отладка
./docker-manage.sh shell nginx     # Shell в контейнере
./docker-manage.sh shell converter # Shell в конвертере
```

### Мониторинг

После запуска доступны:
- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **Redis Commander**: http://localhost:8081

---

## 💻 Native установка

### Быстрая установка
```bash
cd bitrix-cdn-server
chmod +x scripts/install.sh
./scripts/install.sh
```

### Управление через Makefile
```bash
make install  # Установить
make health   # Проверка здоровья
make stats    # Статистика
make clean    # Очистка кеша
make monitor  # Мониторинг
```

---

## 🏗️ Архитектура решения

### Серверы
- **Сервер 1**: Битрикс в Docker (PHP, MySQL) 
- **Сервер 2**: Debian с NGINX для обработки и кеширования изображений

### Интеграция
- SSHFS mount для доступа к файлам Битрикс
- On-the-fly конвертация в WebP
- Локальное кеширование обработанных изображений

## Структура проекта

```
bitrix-cdn-server/
├── docker-compose.yml          # Production конфигурация
├── docker-compose.dev.yml      # Development конфигурация
├── .env.example                # Шаблон настроек
├── docker-manage.sh            # Скрипт управления Docker
├── Makefile                    # Команды для native установки
│
├── docker/                     # Docker конфигурации
│   ├── nginx/                  # NGINX конфиги
│   ├── webp-converter/         # Конвертер WebP
│   ├── sshfs/                  # SSHFS монтирование
│   ├── varnish/                # Varnish кеш
│   ├── prometheus/             # Метрики
│   └── grafana/                # Дашборды
│
├── nginx/                      # Native NGINX конфиги
│   ├── sites-available/
│   └── snippets/
│
├── scripts/                    # Native скрипты
│   ├── install.sh              # Установщик
│   ├── mount.sh                # SSHFS монтирование
│   └── webp-convert.sh         # Конвертер
│
├── systemd/                    # Systemd сервисы
├── monitoring/                 # Мониторинг скрипты
└── docs/                       # Документация
    ├── INSTALL.md
    └── TROUBLESHOOTING.md
```

## Основные компоненты

### 1. SSHFS Mount
- Монтирование папки `/upload/` с сервера Битрикс
- Read-only доступ для безопасности
- Автоматический remount при сбоях

### 2. NGINX Image Server
- Перехват запросов к изображениям
- Проверка поддержки WebP в браузере
- Lazy конвертация при первом запросе
- Отдача из кеша при повторных запросах

### 3. WebP Converter
- Python/Bash конвертер
- Использование cwebp для конвертации
- Сохранение качества 85-90%
- Пропуск уже оптимизированных файлов

### 4. Cache Management
- Локальное хранение WebP версий
- Redis для метаданных
- Автоочистка файлов старше 30 дней
- Синхронизация с удалением оригиналов

## Требования

### Для Docker
- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM
- 50GB диск

### Для Native
- Debian 11/12
- NGINX 1.18+
- webp tools
- sshfs
- ImageMagick

### Сетевые требования
- SSH доступ между серверами
- Открытые порты: 80, 443
- Private network между серверами (рекомендуется)

## Настройка Битрикс

Добавить в `/bitrix/php_interface/init.php`:
```php
define("BX_IMG_SERVER", "https://cdn.yourdomain.ru");
```

Или через `.settings.php`:
```php
'cdn' => [
    'value' => [
        'enabled' => true,
        'domain' => 'cdn.yourdomain.ru',
        'protocol' => 'https'
    ]
]
```

## Мониторинг

### Docker мониторинг
- Grafana дашборды
- Prometheus метрики
- Health checks
- Централизованные логи

### Native мониторинг
- Проверка mount point каждую минуту
- Логирование конвертаций
- Email алерты при проблемах
- NGINX status page

## Безопасность

- SSH ключи для mount (без паролей)
- Ограничение по IP для SSH
- Read-only mount
- Rate limiting в NGINX
- Fail2ban для защиты от брутфорса
- Изолированные Docker контейнеры

## Производительность

- WebP экономит 30-50% размера файлов
- Кеширование уменьшает нагрузку на CPU
- HTTP/2 для быстрой загрузки
- Gzip/Brotli для текстовых файлов
- Varnish для дополнительного кеширования
- Redis для быстрого доступа к метаданным

## SSL сертификаты

### Docker
```bash
./docker-manage.sh ssl
```

### Native
```bash
certbot --nginx -d cdn.yourdomain.ru
```

## Резервное копирование

### Docker
```bash
./docker-manage.sh backup
```

### Native
```bash
make backup
```

## Устранение неполадок

### Docker
```bash
# Проверка логов
./docker-manage.sh logs -f

# Проверка здоровья
./docker-manage.sh status

# Shell в контейнере
./docker-manage.sh shell nginx
```

### Native
```bash
# Проверка здоровья
make health

# Просмотр логов
make logs

# Мониторинг
make monitor
```

Подробнее см. `docs/TROUBLESHOOTING.md`

## Поддержка

При проблемах:
1. Проверить документацию в `docs/`
2. Запустить health check
3. Проверить логи
4. При критических проблемах - откатиться на основной сервер

## Лицензия

MIT

## Автор

Alexandr Chibilyaev (AAC)
