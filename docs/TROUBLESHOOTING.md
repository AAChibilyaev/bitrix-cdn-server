# Устранение неполадок CDN сервера

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## Частые проблемы и решения

### 1. SSHFS Mount проблемы

#### Проблема: Mount point не работает

**Симптомы:**
- Команда `ls /mnt/bitrix` зависает
- Ошибка "Transport endpoint is not connected"

**Решение:**
```bash
# Принудительное размонтирование
fusermount -uz /mnt/bitrix

# Проверка процессов
ps aux | grep sshfs
kill -9 <PID> # если есть зависшие процессы

# Перемонтирование
systemctl restart sshfs-mount

# Проверка
ls /mnt/bitrix
```

#### Проблема: Permission denied при монтировании

**Решение:**
```bash
# Проверка SSH ключа
ssh -i /root/.ssh/bitrix_mount user@bitrix-server

# Проверка прав на ключ
chmod 600 /root/.ssh/bitrix_mount
chmod 644 /root/.ssh/bitrix_mount.pub

# Проверка на сервере Битрикс
# В ~/.ssh/authorized_keys должен быть публичный ключ
```

#### Проблема: Mount отваливается периодически

**Решение:**
```bash
# Добавить в /etc/fstab для автомонтирования
user@bitrix-server:/path/to/upload /mnt/bitrix fuse.sshfs _netdev,allow_other,default_permissions,ro,IdentityFile=/root/.ssh/bitrix_mount,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 0 0

# Или использовать autofs для автоматического монтирования по требованию
apt install autofs
```

### 2. NGINX проблемы

#### Проблема: 404 ошибки для изображений

**Проверка:**
```bash
# Проверка конфигурации
nginx -t

# Проверка путей
ls -la /mnt/bitrix/
ls -la /var/cache/webp/

# Проверка логов
tail -f /var/log/nginx/error.log
```

**Решение:**

- Проверить правильность путей в nginx.conf
- Убедиться что root директива указывает на /mnt/bitrix
- Проверить права доступа

#### Проблема: WebP не отдается

**Проверка:**
```bash
# Тест с заголовком Accept
curl -H "Accept: image/webp" -I https://cdn.domain.ru/test.jpg

# Проверка конвертации
/usr/local/bin/webp-convert.sh convert /mnt/bitrix/test.jpg
```

**Решение:**

- Проверить установлен ли cwebp: `which cwebp`
- Проверить права на запись в /var/cache/webp
- Проверить логику в nginx.conf

### 3. Проблемы конвертации

#### Проблема: cwebp command not found

**Решение:**
```bash
# Установка webp tools
apt update
apt install webp

# Проверка
cwebp -version
```

#### Проблема: Конвертация медленная

**Решение:**
```bash
# Уменьшить качество в скрипте
# Изменить QUALITY=85 на QUALITY=75

# Использовать nice для понижения приоритета
nice -n 19 /usr/local/bin/webp-convert.sh batch

# Ограничить параллельные процессы
# Добавить в скрипт проверку количества процессов
```

#### Проблема: Кеш быстро растет

**Решение:**
```bash
# Настроить автоочистку
crontab -e
# Добавить:
0 2 * * * /usr/local/bin/webp-convert.sh cleanup 7

# Ручная очистка
find /var/cache/webp -type f -name "*.webp" -mtime +7 -delete
```

### 4. Проблемы производительности

#### Проблема: Высокая нагрузка при конвертации

**Мониторинг:**
```bash
htop
iotop
```

**Решение:**

```bash
# Ограничить количество worker процессов NGINX
# В nginx.conf:
worker_processes 2;

# Использовать кеширование NGINX
location ~* \.(webp)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}

# Настроить лимиты системы
ulimit -n 65535
```

#### Проблема: Медленная отдача файлов

**Решение:**
```bash
# Оптимизация SSHFS
# В mount команде добавить:
-o cache=yes,kernel_cache,compression=no,large_read

# Включить sendfile в NGINX
sendfile on;
tcp_nopush on;
tcp_nodelay on;

# Увеличить буферы
client_body_buffer_size 128k;
client_max_body_size 100m;
```

### 5. Сетевые проблемы

#### Проблема: Соединение между серверами медленное

**Диагностика:**
```bash
# Тест скорости
iperf3 -s # на одном сервере
iperf3 -c server_ip # на другом

# Проверка маршрута
traceroute bitrix-server

# Проверка MTU
ping -M do -s 1472 bitrix-server
```

**Решение:**

- Использовать private network если возможно
- Отключить compression в SSHFS для локальной сети
- Оптимизировать TCP настройки

### 6. Проблемы безопасности

#### Проблема: Доступ к служебным файлам

**Проверка:**
```bash
curl https://cdn.domain.ru/bitrix/php_interface/dbconn.php
# Должно вернуть 403 Forbidden
```

**Решение:**

В nginx.conf добавить:
```nginx
location ~* ^/(bitrix|local)/(modules|php_interface|stack_cache|managed_cache|sessions|tmp|templates|updates|backup|webstat|upload/1c_[^/]+) {
    deny all;
}
```

### 7. Проблемы с Битрикс

#### Проблема: Битрикс не использует CDN

**Проверка:**
- Посмотреть исходный код страницы
- Проверить URL изображений

**Решение:**
```php
// В /bitrix/php_interface/init.php
if (!defined("BX_IMG_SERVER")) {
    define("BX_IMG_SERVER", "https://cdn.domain.ru");
}

// Или в .settings.php
return [
    'cdn' => [
        'value' => [
            'enabled' => true,
            'domain' => 'cdn.domain.ru',
            'protocol' => 'https'
        ],
        'readonly' => false,
    ],
];
```

### 8. Логи для диагностики

#### Основные логи:
```bash
# NGINX логи
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/cdn.access.log

# Логи конвертации
tail -f /var/log/cdn/convert.log

# Логи монтирования
tail -f /var/log/cdn/mount.log

# Системные логи
journalctl -u sshfs-mount -f
journalctl -u nginx -f

# Syslog
tail -f /var/log/syslog | grep -E "sshfs|nginx|webp"
```

### 9. Команды для диагностики

```bash
# Проверка всех сервисов
systemctl status nginx
systemctl status sshfs-mount

# Проверка mount
mount | grep sshfs
df -h /mnt/bitrix

# Проверка процессов
ps aux | grep -E "nginx|sshfs|cwebp"

# Проверка портов
netstat -tlnp | grep -E ":80|:443"

# Проверка соединений
ss -tan | grep ESTABLISHED

# Проверка DNS
dig cdn.domain.ru
nslookup cdn.domain.ru
```

### 10. Восстановление после сбоя

#### Полный рестарт системы:
```bash
#!/bin/bash
# Emergency restart script

# Остановка сервисов
systemctl stop nginx
systemctl stop sshfs-mount

# Очистка
fusermount -uz /mnt/bitrix
killall -9 sshfs 2>/dev/null

# Запуск
systemctl start sshfs-mount
sleep 5
systemctl start nginx

# Проверка
/usr/local/bin/check-health.sh
```

### 11. Контакты для поддержки

При критических проблемах:
1. Проверить этот документ
2. Проверить логи
3. Запустить health check: `/usr/local/bin/check-health.sh`
4. Если не помогло - откатиться на основной сервер (изменить DNS)

## Чек-лист быстрой диагностики

- [ ] Mount работает: `ls /mnt/bitrix`
- [ ] NGINX работает: `systemctl status nginx`
- [ ] Конвертация работает: `cwebp -version`
- [ ] Кеш доступен: `ls -la /var/cache/webp`
- [ ] Сеть работает: `ping bitrix-server`
- [ ] DNS работает: `dig cdn.domain.ru`
- [ ] SSL работает: `curl -I https://cdn.domain.ru`
- [ ] WebP отдается: `curl -H "Accept: image/webp" -I https://cdn.domain.ru/test.jpg`
