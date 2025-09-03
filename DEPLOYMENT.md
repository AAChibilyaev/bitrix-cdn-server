# 🚀 Развертывание Bitrix CDN Server

## ⚠️ КРИТИЧЕСКИ ВАЖНО: Архитектура из 2-х серверов!

Это решение требует **ДВА ФИЗИЧЕСКИ РАЗНЫХ СЕРВЕРА**:

```
┌─────────────────────────┐         ┌──────────────────────────┐
│  СЕРВЕР 1 (БИТРИКС)     │ <-----> │  СЕРВЕР 2 (CDN)         │
│  • Ваш текущий сайт     │   SSH   │  • Этот проект          │
│  • Хранит оригиналы     │         │  • Только WebP кеш      │
│  • IP: 192.168.1.10     │         │  • IP: 192.168.1.20     │
└─────────────────────────┘         └──────────────────────────┘
```

## 📋 Предварительные требования

### Сервер 1 (Битрикс) - уже существующий:
- ✅ Работающий сайт на 1С-Битрикс
- ✅ SSH доступ с правами на чтение `/var/www/bitrix/upload/`
- ✅ Открыт порт 22 для Сервера 2

### Сервер 2 (CDN) - новый сервер:
- ✅ Debian 11/12 или Ubuntu 20.04/22.04
- ✅ Минимум 2 CPU, 4GB RAM, 50GB SSD
- ✅ Docker и Docker Compose установлены
- ✅ Домен cdn.termokit.ru направлен на этот сервер
- ✅ Порты 80, 443 открыты

## 🔧 Пошаговая инструкция развертывания

### ШАГ 1: Подготовка Сервера 2 (CDN)

```bash
# 1.1 Установка Docker (если еще нет)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Перелогиньтесь для применения прав

# 1.2 Установка Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 1.3 Клонирование проекта
git clone https://github.com/yourusername/bitrix-cdn-server.git
cd bitrix-cdn-server
```

### ШАГ 2: Настройка SSH соединения между серверами

```bash
# 2.1 На Сервере 2 (CDN) - генерация SSH ключа
./docker-manage.sh setup
# Или вручную:
ssh-keygen -t rsa -b 4096 -f docker/ssh/bitrix_mount -N ""

# 2.2 Скопируйте публичный ключ
cat docker/ssh/bitrix_mount.pub
```

```bash
# 2.3 На Сервере 1 (Битрикс) - добавьте ключ
sudo su - www-data  # или пользователь под которым работает сайт
mkdir -p ~/.ssh
echo "ВСТАВЬТЕ_СЮДА_ПУБЛИЧНЫЙ_КЛЮЧ" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 2.4 Проверка подключения с Сервера 2
ssh -i docker/ssh/bitrix_mount www-data@192.168.1.10 "ls /var/www/bitrix/upload/"
# Должны увидеть список файлов
```

### ШАГ 3: Конфигурация окружения

```bash
# 3.1 На Сервере 2 (CDN) - создание .env файла
cp .env.example .env
nano .env
```

Отредактируйте параметры:
```env
# Подключение к Серверу 1 (Битрикс)
BITRIX_SERVER_IP=192.168.1.10          # IP вашего Битрикс сервера
BITRIX_SERVER_USER=www-data            # Пользователь на Битрикс сервере
BITRIX_UPLOAD_PATH=/var/www/bitrix/upload  # Путь к upload на Битрикс

# Настройки CDN
CDN_DOMAIN=cdn.termokit.ru             # Ваш CDN домен
CDN_SERVER_IP=192.168.1.20             # IP этого CDN сервера

# WebP настройки
WEBP_QUALITY=85                         # Качество WebP (1-100)
CACHE_CLEANUP_DAYS=30                   # Автоочистка кеша старше N дней

# Мониторинг
ADMIN_EMAIL=admin@termokit.ru
GRAFANA_PASSWORD=SecurePassword123!
REDIS_PASSWORD=RedisPassword456!

# SSL (для Let's Encrypt)
LETSENCRYPT_EMAIL=admin@termokit.ru
```

### ШАГ 4: Запуск CDN сервера

```bash
# 4.1 Проверка конфигураций
./validate-all.sh
# Все проверки должны пройти успешно

# 4.2 Запуск сервисов
docker-compose up -d

# 4.3 Проверка статуса
./docker-manage.sh status

# 4.4 Просмотр логов
docker-compose logs -f
```

### ШАГ 5: Настройка SSL сертификата

```bash
# 5.1 Первоначальный запуск для получения сертификата
docker-compose run --rm certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email admin@termokit.ru \
  --agree-tos \
  --no-eff-email \
  -d cdn.termokit.ru

# 5.2 Раскомментируйте SSL настройки в docker/nginx/conf.d/cdn.conf
nano docker/nginx/conf.d/cdn.conf
# Раскомментируйте строки с ssl_certificate

# 5.3 Перезапуск NGINX
docker-compose restart nginx
```

### ШАГ 6: Интеграция с Битрикс (на Сервере 1)

```php
// 6.1 Добавьте в /bitrix/php_interface/init.php
define("BX_IMG_SERVER", "https://cdn.termokit.ru");

// 6.2 Для автоматической замены URL изображений
AddEventHandler("main", "OnEndBufferContent", "ReplaceCDNImages");
function ReplaceCDNImages(&$content) {
    $content = str_replace(
        'src="/upload/',
        'src="https://cdn.termokit.ru/upload/',
        $content
    );
    $content = preg_replace(
        '/url\(["\']?\/upload\//i',
        'url("https://cdn.termokit.ru/upload/',
        $content
    );
}
```

### ШАГ 7: Проверка работы

```bash
# 7.1 Проверка SSHFS монтирования (на Сервере 2)
docker exec cdn-sshfs ls -la /mnt/bitrix/upload/
# Должны увидеть файлы с Битрикс сервера

# 7.2 Проверка конвертации WebP
curl -H "Accept: image/webp" https://cdn.termokit.ru/upload/iblock/123/test.jpg
# В логах должна появиться конвертация

# 7.3 Проверка кеша
ls -la /var/lib/docker/volumes/bitrix-cdn-server_webp-cache/_data/
# Должны появиться .webp файлы

# 7.4 Мониторинг
# Откройте в браузере:
# Grafana: http://cdn.termokit.ru:3000 (admin/admin)
# Prometheus: http://cdn.termokit.ru:9090
```

## 🔍 Валидация развертывания

Выполните полную проверку:
```bash
./validate-all.sh
```

Должны увидеть:
```
✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО!
Проект готов к развертыванию на cdn.termokit.ru
```

## ⚠️ Частые проблемы при развертывании

### Проблема: SSHFS не может подключиться
```bash
# Проверьте SSH подключение
ssh -i docker/ssh/bitrix_mount www-data@BITRIX_IP "echo OK"

# Проверьте права на ключ
chmod 600 docker/ssh/bitrix_mount

# Проверьте логи SSHFS
docker logs cdn-sshfs
```

### Проблема: WebP файлы не создаются
```bash
# Проверьте права на директорию кеша
docker exec cdn-webp-converter ls -la /var/cache/webp/

# Проверьте логи конвертера
docker logs cdn-webp-converter

# Проверьте что NGINX правильно проксирует
docker logs cdn-nginx
```

### Проблема: 502 Bad Gateway
```bash
# Проверьте что все сервисы запущены
docker-compose ps

# Перезапустите сервисы
docker-compose restart

# Проверьте сеть Docker
docker network ls
```

## 📊 Мониторинг после развертывания

### Ключевые метрики для отслеживания:
1. **Cache Hit Rate** - должен быть >80% после прогрева
2. **WebP Conversion Rate** - количество конвертаций/сек
3. **SSHFS Mount Status** - должен быть всегда "mounted"
4. **Disk Usage** - следите за размером кеша WebP

### Автоматическая очистка кеша:
```bash
# Добавьте в crontab на Сервере 2
0 3 * * * /path/to/bitrix-cdn-server/docker-manage.sh clean
```

## 🎯 Финальная проверка

После развертывания убедитесь:
1. ✅ Изображения загружаются с cdn.termokit.ru
2. ✅ WebP версии отдаются для поддерживающих браузеров
3. ✅ Оригиналы остаются на Битрикс сервере
4. ✅ При загрузке новых файлов на Битрикс они автоматически доступны через CDN
5. ✅ Мониторинг работает и показывает метрики

## 🆘 Поддержка

При проблемах:
1. Проверьте логи: `docker-compose logs -f`
2. Запустите валидацию: `./validate-all.sh`
3. Проверьте документацию в `/docs/TROUBLESHOOTING.md`

---
**Важно**: Этот CDN сервер НЕ хранит оригиналы файлов! Он только читает их с Битрикс сервера через SSHFS и создает оптимизированные WebP версии в своем локальном кеше.