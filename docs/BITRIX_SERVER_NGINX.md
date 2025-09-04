# 🔧 Конфигурация NGINX для Первого Сервера (Bitrix)

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## 🎯 Цель

Настройка NGINX на первом сервере (с Bitrix) для правильного роутинга изображений на CDN сервер **ТОЛЬКО для обычных пользователей**.

## 📋 Основная конфигурация

Добавьте в основной конфиг сайта на Bitrix сервере (`/etc/nginx/sites-available/termokit.ru`):

```nginx
# Bitrix Server NGINX Configuration для интеграции с CDN
# Сервер 1: termokit.ru (основной Bitrix)
# Сервер 2: cdn.termokit.ru (CDN кеш)

server {
    listen 80;
    listen 443 ssl http2;
    server_name termokit.ru www.termokit.ru;
    
    root /var/www/bitrix;
    index index.php index.html;
    
    # SSL конфигурация (ваши существующие настройки)
    # ssl_certificate /path/to/cert;
    # ssl_certificate_key /path/to/key;
    
    # КРИТИЧНО: Определяем тип пользователя
    set $is_admin 0;
    
    # Проверяем админские пути
    if ($request_uri ~ "^/bitrix/admin/") {
        set $is_admin 1;
    }
    if ($request_uri ~ "^/local/admin/") {
        set $is_admin 1;
    }
    if ($request_uri ~ "^/bitrix/tools/") {
        set $is_admin 1;
    }
    
    # КЛЮЧЕВАЯ ЛОГИКА: Роутинг изображений для обычных пользователей
    location ~* ^/upload/.*\.(jpg|jpeg|png|gif|bmp)$ {
        # Для админов - отдаём локально
        if ($is_admin = 1) {
            try_files $uri =404;
            break;
        }
        
        # Для обычных пользователей - редирект на CDN
        return 301 https://cdn.termokit.ru$request_uri;
    }
    
    # Обычные файлы upload (не изображения) остаются локально
    location ~* ^/upload/ {
        try_files $uri =404;
        
        # Кеш только для не-админов
        if ($is_admin = 0) {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Bitrix стандартная обработка PHP
    location / {
        try_files $uri $uri/ @bitrix;
    }
    
    location @bitrix {
        fastcgi_pass php-fpm;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root/index.php;
    }
    
    # PHP обработка
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass php-fpm;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
    
    # Безопасность Bitrix
    location ~ /\.ht {
        deny all;
    }
    
    location ~* ^/bitrix/(modules|local_cache|stack_cache|managed_cache|html_pages)/ {
        deny all;
    }
}
```

## 🔧 Альтернативный вариант (с map)

Более производительный способ через map в `nginx.conf`:

```nginx
# В блоке http {} добавить:
map $request_uri $is_admin_uri {
    default 0;
    "~^/bitrix/admin/" 1;
    "~^/local/admin/" 1; 
    "~^/bitrix/tools/" 1;
}

# В server {} блоке:
server {
    # ... остальная конфигурация
    
    # Роутинг изображений с проверкой типа пользователя
    location ~* ^/upload/.*\.(jpg|jpeg|png|gif|bmp)$ {
        # Для админов - локальная отдача
        if ($is_admin_uri = 1) {
            try_files $uri =404;
            break;
        }
        
        # Для обычных пользователей - CDN
        return 301 https://cdn.termokit.ru$request_uri;
    }
}
```

## 🚀 Что происходит:

1. **Обычный пользователь** заходит на `termokit.ru/upload/image.jpg`
   - NGINX первого сервера делает 301 редирект на `cdn.termokit.ru/upload/image.jpg`
   - Браузер запрашивает CDN сервер
   - CDN сервер отдаёт WebP (если поддерживается) или оригинал

2. **Администратор** заходит на `termokit.ru/bitrix/admin/...` и видит изображение
   - NGINX определяет админский путь  
   - Изображение отдаётся локально с первого сервера
   - Никакого редиректа на CDN

## ⚠️ ВАЖНО ДОБАВИТЬ В ПРОЕКТ:

Нужно создать файл с этой конфигурацией для первого сервера!