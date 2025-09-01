# Пошаговая установка CDN сервера для Битрикс

## Предварительные требования

- Debian 11 или 12 (чистая установка)
- Root или sudo доступ
- SSH доступ к серверу с Битрикс
- Домен для CDN (например, cdn.yourdomain.ru)

## Шаг 1: Установка базовых пакетов

```bash
apt update
apt upgrade -y
apt install -y nginx webp sshfs imagemagick curl htop nano
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

## Шаг 6: Установка скриптов конвертации

### 6.1 Копирование скриптов
```bash
cp scripts/webp-convert.sh /usr/local/bin/
chmod +x /usr/local/bin/webp-convert.sh
```

### 6.2 Настройка cron для очистки кеша
```bash
crontab -e
# Добавить строку:
0 3 * * * /usr/local/bin/cleanup-cache.sh
```

## Шаг 7: Настройка мониторинга

### 7.1 Установка скрипта проверки
```bash
cp monitoring/check-mount.sh /usr/local/bin/
chmod +x /usr/local/bin/check-mount.sh
```

### 7.2 Добавление в cron
```bash
*/5 * * * * /usr/local/bin/check-mount.sh
```

## Шаг 8: Настройка DNS

Добавьте A-запись для вашего CDN домена:
```
cdn.yourdomain.ru -> IP_второго_сервера
```

## Шаг 9: SSL сертификат (Let's Encrypt)

```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d cdn.yourdomain.ru
```

## Шаг 10: Настройка Битрикс

### 10.1 В файле `/bitrix/php_interface/init.php` добавить:

```php
define("BX_IMG_SERVER", "https://cdn.yourdomain.ru");
```

### 10.2 Или через настройки в `.settings.php`:

```php
'cdn' => [
    'value' => [
        'enabled' => true,
        'domain' => 'cdn.yourdomain.ru',
        'protocol' => 'https'
    ]
]
```

## Шаг 11: Тестирование

### 11.1 Проверка mount
```bash
ls -la /mnt/bitrix
```

### 11.2 Проверка NGINX
```bash
curl -I https://cdn.yourdomain.ru/test.jpg
```

### 11.3 Проверка WebP конвертации
```bash
curl -H "Accept: image/webp" https://cdn.yourdomain.ru/test.jpg
```

## Шаг 12: Оптимизация производительности

### 12.1 Настройка NGINX
- Включить HTTP/2
- Настроить gzip/brotli
- Оптимизировать worker_processes

### 12.2 Настройка sysctl
```bash
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_tw_buckets = 1440000" >> /etc/sysctl.conf
sysctl -p
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
