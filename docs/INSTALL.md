# 🚀 Пошаговая установка CDN сервера для Битрикс

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## 📋 Варианты установки

1. **🐳 Docker (РЕКОМЕНДУЕТСЯ)** - быстрая установка с полным стеком
2. **⚙️ Native** - установка напрямую на сервер для максимального контроля

## ⚠️ Предварительные требования

### Общие требования
- **Два физически разных сервера**
- Root или sudo доступ
- SSH доступ между серверами
- Домен для CDN (например, cdn.termokit.ru)

### Минимальные системные требования
- **RAM**: 4 GB (рекомендуется 8 GB)
- **CPU**: 2 cores (рекомендуется 4)
- **Disk**: 50 GB свободного места (рекомендуется 100 GB SSD)
- **OS**: Debian 11/12 или Ubuntu 20.04/22.04
- **Network**: стабильное подключение между серверами

---

# 🐳 DOCKER УСТАНОВКА (Рекомендуется)

## Шаг 1: Установка Docker

```bash
# Установка Docker и Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable --now docker

# Добавление пользователя в группу docker (опционально)
usermod -aG docker $USER
```

## Шаг 2: Подготовка проекта

```bash
# Клонирование репозитория
git clone https://github.com/AAChibilyaev/bitrix-cdn.git
cd bitrix-cdn

# Настройка окружения
cp .env.example .env
nano .env  # Настроить параметры
```

### Пример .env для cdn.termokit.ru:
```bash
# Сервер Битрикс
BITRIX_SERVER_IP=192.168.1.100
BITRIX_SERVER_USER=bitrix
BITRIX_UPLOAD_PATH=/var/www/bitrix/upload

# CDN настройки
CDN_DOMAIN=cdn.termokit.ru
WEBP_QUALITY=85
WEBP_MAX_WIDTH=2048
WEBP_MAX_HEIGHT=2048

# Мониторинг
GRAFANA_USER=admin
GRAFANA_PASSWORD=TErmokit2024CDN!
ADMIN_EMAIL=admin@termokit.ru
```

## Шаг 3: Настройка SSH ключей

```bash
# Генерация SSH ключей
./docker-manage.sh setup

# Копирование публичного ключа на сервер Битрикс
cat docker/ssh/bitrix_mount.pub
# >> Скопируйте в ~/.ssh/authorized_keys на сервере Битрикс
```

## Шаг 4: Запуск системы

```bash
# Production запуск (полный стек)
docker-compose up -d

# Development запуск (упрощенный)
docker-compose -f docker-compose.dev.yml up -d

# Local тестирование
docker-compose -f docker-compose.local.yml up -d
```

## Шаг 5: Проверка работы

```bash
# Статус всех сервисов
./docker-manage.sh status

# Проверка логов
./docker-manage.sh logs -f

# Health check
curl http://localhost/health
```

---

# ⚙️ NATIVE УСТАНОВКА

## Шаг 1: Установка базовых пакетов

```bash
apt update
apt upgrade -y
apt install -y nginx webp sshfs redis-server python3 python3-pip curl htop nano git make

# Python зависимости
pip3 install redis pillow watchdog
```

## Шаг 2: Настройка SSHFS

### 2.1 Создание SSH ключей (если еще нет)
```bash
ssh-keygen -t rsa -b 4096 -f /root/.ssh/bitrix_mount
```

### 2.2 Копирование ключа на сервер Битрикс
```bash
ssh-copy-id -i /root/.ssh/bitrix_mount.pub user@bitrix-server
```

### 2.3 Создание точки монтирования
```bash
mkdir -p /mnt/bitrix
```

### 2.4 Тестовое монтирование
```bash
sshfs -o allow_other,default_permissions,ro,IdentityFile=/root/.ssh/bitrix_mount \
  user@bitrix-server:/path/to/bitrix/upload /mnt/bitrix
```

## Шаг 3: Автоматическое монтирование

### 3.1 Создание systemd сервиса
Скопируйте файл `systemd/sshfs-mount.service` в `/etc/systemd/system/`

### 3.2 Активация сервиса
```bash
systemctl daemon-reload
systemctl enable sshfs-mount
systemctl start sshfs-mount
```

## Шаг 4: Настройка структуры кеша

```bash
# Создание директорий для кеша
mkdir -p /var/cache/webp
mkdir -p /var/log/cdn

# Установка прав
chown -R www-data:www-data /var/cache/webp
chown -R www-data:www-data /var/log/cdn
```

## Шаг 5: Настройка NGINX

### 5.1 Копирование конфигурации
```bash
cp nginx/sites-available/cdn.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/
```

### 5.2 Проверка конфигурации
```bash
nginx -t
```

### 5.3 Перезапуск NGINX
```bash
systemctl restart nginx
```

## Шаг 6: Установка WebP конвертера

### 6.1 Установка Python сервиса
```bash
# Копирование сервиса конвертации
cp docker/webp-converter/converter.py /usr/local/bin/
chmod +x /usr/local/bin/converter.py

# Установка systemd сервиса
cp systemd/webp-converter.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable webp-converter
systemctl start webp-converter
```

### 6.2 Копирование скриптов
```bash
cp scripts/webp-convert.sh /usr/local/bin/
chmod +x /usr/local/bin/webp-convert.sh

# Настройка cron для очистки кеша
crontab -e
# Добавить строку:
0 3 * * * /usr/local/bin/webp-convert.sh cleanup 30
```

## Шаг 7: Настройка мониторинга

### 7.1 Установка Prometheus (опционально)
```bash
# Скачать Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.53.2/prometheus-2.53.2.linux-amd64.tar.gz
tar xvfz prometheus-*.tar.gz
mv prometheus-*/prometheus /usr/local/bin/
mv prometheus-*/promtool /usr/local/bin/

# Настройка
cp monitoring/prometheus.yml /etc/prometheus/
cp systemd/prometheus.service /etc/systemd/system/
systemctl enable prometheus
systemctl start prometheus
```

### 7.2 Health check
```bash
cp monitoring/check-health.sh /usr/local/bin/
chmod +x /usr/local/bin/check-health.sh

# Добавление в cron
crontab -e
*/5 * * * * /usr/local/bin/check-health.sh
```

---

# 🌐 НАСТРОЙКА DNS И SSL

## Шаг 1: DNS конфигурация

Добавьте A-запись для вашего CDN домена:
```
cdn.termokit.ru -> IP_CDN_сервера
```

## Шаг 2: SSL сертификат

### Docker (автоматически через Certbot)
```bash
# SSL уже настроен в docker-compose.yml
# Сертификаты обновляются автоматически каждые 12 часов
```

### Native установка
```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d cdn.termokit.ru
```

---

# 📱 НАСТРОЙКА БИТРИКС СЕРВЕРА

## Вариант 1: В init.php (простой)

В файле `/var/www/bitrix/bitrix/php_interface/init.php` добавить:

```php
<?php
// CDN конфигурация для cdn.termokit.ru
if (!defined("BX_IMG_SERVER")) {
    define("BX_IMG_SERVER", "https://cdn.termokit.ru");
}

// Автоматическая замена URL в HTML
AddEventHandler("main", "OnEndBufferContent", "ReplaceCDNImages");

function ReplaceCDNImages(&$content) {
    // Замена относительных путей на CDN
    $content = preg_replace(
        '/src="([^"]*\\/upload\\/[^"]*\\.(jpg|jpeg|png|gif|bmp)[^"]*)"/i',
        'src="https://cdn.termokit.ru$1"',
        $content
    );
}
?>
```

## Вариант 2: Через .settings.php (продвинутый)

В файле `/var/www/bitrix/.settings.php`:

```php
<?php
return [
    // ... другие настройки
    
    'cdn' => [
        'value' => [
            'enabled' => true,
            'domain' => 'cdn.termokit.ru',
            'protocol' => 'https',
            'paths' => ['/upload/'],
            'fallback' => true
        ],
        'readonly' => false,
    ],
    
    // ... остальные настройки
];
```

---

# ✅ ТЕСТИРОВАНИЕ И ПРОВЕРКА

## Docker тестирование

```bash
# Статус всех сервисов
./docker-manage.sh status

# Проверка mount
docker exec cdn-sshfs mountpoint -q /mnt/bitrix
echo $?  # Должно быть 0

# Проверка WebP конвертации
curl -H "Accept: image/webp" -I http://localhost/upload/test.jpg

# Проверка логов
./docker-manage.sh logs nginx
./docker-manage.sh logs webp-converter
```

## Native тестирование

```bash
# Проверка сервисов
systemctl status nginx
systemctl status sshfs-mount
systemctl status webp-converter

# Проверка mount
ls -la /mnt/bitrix
mountpoint /mnt/bitrix

# Проверка NGINX
curl -I https://cdn.termokit.ru/health

# Проверка WebP
curl -H "Accept: image/webp" https://cdn.termokit.ru/upload/test.jpg
```

---

# 🔧 PRODUCTION ОПТИМИЗАЦИЯ

## Системные настройки
```bash
# Настройка sysctl для высоких нагрузок
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_tw_buckets = 1440000" >> /etc/sysctl.conf
echo "fs.file-max = 100000" >> /etc/sysctl.conf
sysctl -p
```

## NGINX тюнинг
```nginx
# В nginx.conf
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # Кеширование файлов
    open_file_cache max=10000 inactive=20s;
    open_file_cache_valid 30s;
}
```

## Проверочный чек-лист

- [ ] SSHFS примонтирован и работает
- [ ] NGINX запущен без ошибок
- [ ] WebP конвертация работает
- [ ] SSL сертификат установлен
- [ ] Мониторинг настроен
- [ ] Битрикс использует CDN домен
- [ ] Логи пишутся корректно
- [ ] Автоочистка кеша работает

## Устранение неполадок

Если что-то не работает, смотрите:
- `/var/log/nginx/error.log` - ошибки NGINX
- `/var/log/cdn/convert.log` - логи конвертации
- `systemctl status sshfs-mount` - статус mount
- `docs/TROUBLESHOOTING.md` - подробное решение проблем
