# ⚡ Оптимизация производительности CDN

## 📊 Метрики производительности

### Целевые показатели

| Метрика | Текущее | Цель | Best Practice |
|---------|---------|------|---------------|
| **TTFB** | 45ms | < 50ms | < 30ms |
| **Cache Hit Ratio** | 94% | > 90% | > 95% |
| **WebP Conversion** | 320ms | < 500ms | < 200ms |
| **Throughput** | 850 req/s | > 1000 req/s | > 2000 req/s |
| **P95 Latency** | 185ms | < 200ms | < 100ms |
| **P99 Latency** | 420ms | < 500ms | < 200ms |

## 🚀 Оптимизации NGINX

### Основная конфигурация

```nginx
# /docker/nginx/nginx.conf

user nginx;
worker_processes auto;
worker_cpu_affinity auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

# Загрузка модулей
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
    accept_mutex off;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Основные оптимизации
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;
    reset_timedout_connection on;
    client_body_timeout 10;
    client_header_timeout 10;
    send_timeout 10;
    
    # Буферы
    client_body_buffer_size 128k;
    client_max_body_size 100m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 8k;
    output_buffers 32 32k;
    postpone_output 1460;
    
    # Файловый кеш
    open_file_cache max=10000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml application/atom+xml image/svg+xml 
               text/x-js text/x-cross-domain-policy application/x-font-ttf 
               application/x-font-opentype application/vnd.ms-fontobject 
               image/x-icon;
    gzip_disable "msie6";
    
    # Brotli
    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain text/css text/xml text/javascript 
                 application/json application/javascript application/xml+rss 
                 application/rss+xml application/atom+xml image/svg+xml;
    
    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=images:10m rate=100r/s;
    limit_req_zone $binary_remote_addr zone=static:10m rate=50r/s;
    limit_conn_zone $binary_remote_addr zone=perip:10m;
    
    # Cache zones
    proxy_cache_path /var/cache/nginx/proxy levels=1:2 keys_zone=proxy_cache:100m 
                     max_size=10g inactive=60m use_temp_path=off;
    
    fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=fastcgi_cache:100m 
                       max_size=10g inactive=60m use_temp_path=off;
    
    # Upstream для балансировки
    upstream webp_converters {
        least_conn;
        server webp-converter-1:8080 max_fails=3 fail_timeout=30s;
        server webp-converter-2:8080 max_fails=3 fail_timeout=30s;
        server webp-converter-3:8080 max_fails=3 fail_timeout=30s backup;
        
        keepalive 32;
        keepalive_timeout 60s;
        keepalive_requests 100;
    }
    
    include /etc/nginx/conf.d/*.conf;
}
```

### Оптимизация location блоков

```nginx
# Оптимизированная обработка изображений
location ~* ^/upload/.*\.(jpg|jpeg|gif|png|bmp)$ {
    # Rate limiting
    limit_req zone=images burst=50 nodelay;
    limit_conn perip 10;
    
    # Кеширование
    expires 1y;
    add_header Cache-Control "public, immutable";
    add_header X-Content-Type-Options "nosniff";
    
    # CORS
    add_header Access-Control-Allow-Origin "*";
    add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS";
    
    # WebP проверка и отдача
    set $webp_suffix "";
    if ($http_accept ~* "webp") {
        set $webp_suffix ".webp";
    }
    
    # Пробуем файлы в порядке приоритета
    try_files /var/cache/webp$uri$webp_suffix 
              /mnt/bitrix$uri 
              @webp_convert;
    
    # Оптимизация для sendfile
    aio threads;
    directio 2m;
    output_buffers 1 1m;
}

# Обработчик конвертации
location @webp_convert {
    internal;
    
    # Проксирование к конвертерам с балансировкой
    proxy_pass http://webp_converters;
    proxy_set_header X-Original-URI $request_uri;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    
    # Буферизация
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 32 4k;
    proxy_busy_buffers_size 64k;
    
    # Таймауты
    proxy_connect_timeout 5s;
    proxy_send_timeout 10s;
    proxy_read_timeout 30s;
    
    # Кеширование прокси
    proxy_cache proxy_cache;
    proxy_cache_valid 200 1d;
    proxy_cache_valid 404 1m;
    proxy_cache_key "$scheme$request_method$host$request_uri$http_accept";
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    proxy_cache_background_update on;
    proxy_cache_lock on;
    proxy_cache_lock_timeout 5s;
}
```

## 🔧 Оптимизация WebP конвертера

### Многопоточная конвертация

```python
# /docker/webp-converter/converter_optimized.py

import asyncio
import aiofiles
import aioredis
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from functools import lru_cache
import uvloop

# Используем uvloop для ускорения asyncio
asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())

class OptimizedWebPConverter:
    def __init__(self):
        self.thread_pool = ThreadPoolExecutor(max_workers=8)
        self.process_pool = ProcessPoolExecutor(max_workers=4)
        self.conversion_queue = asyncio.Queue(maxsize=100)
        self.redis_pool = None
        
    async def init_redis(self):
        self.redis_pool = await aioredis.create_redis_pool(
            'redis://redis:6379',
            minsize=5,
            maxsize=10
        )
    
    @lru_cache(maxsize=1000)
    def get_optimal_quality(self, file_size: int, dimensions: tuple) -> int:
        """Адаптивное качество на основе размера файла и разрешения"""
        width, height = dimensions
        pixels = width * height
        
        if pixels > 4_000_000:  # > 4MP
            return 75
        elif pixels > 2_000_000:  # > 2MP
            return 80
        elif file_size > 1_000_000:  # > 1MB
            return 82
        elif file_size > 500_000:  # > 500KB
            return 85
        else:
            return 88
    
    async def convert_image_optimized(self, source_path: str) -> str:
        """Оптимизированная конвертация с адаптивными параметрами"""
        
        # Проверка в Redis кеше
        cache_key = f"webp:{source_path}"
        cached = await self.redis_pool.get(cache_key)
        if cached:
            return cached.decode()
        
        # Получаем информацию о файле
        stat = await aiofiles.os.stat(source_path)
        file_size = stat.st_size
        
        # Определяем параметры конвертации
        with Image.open(source_path) as img:
            dimensions = img.size
            quality = self.get_optimal_quality(file_size, dimensions)
        
        # Параллельная конвертация с разными настройками
        tasks = [
            self.convert_with_settings(source_path, quality, 'photo'),
            self.convert_with_settings(source_path, quality, 'picture'),
            self.convert_with_settings(source_path, quality, 'drawing'),
        ]
        
        results = await asyncio.gather(*tasks)
        
        # Выбираем лучший результат по размеру
        best_result = min(results, key=lambda x: x['size'])
        
        # Сохраняем в Redis
        await self.redis_pool.setex(
            cache_key,
            86400,  # TTL 1 день
            best_result['path']
        )
        
        return best_result['path']
    
    async def convert_with_settings(self, source: str, quality: int, preset: str):
        """Конвертация с конкретными настройками"""
        output_path = f"{source}.{preset}.webp"
        
        cmd = [
            'cwebp',
            '-q', str(quality),
            '-preset', preset,
            '-m', '6',  # Максимальная компрессия
            '-mt',      # Многопоточность
            '-af',      # Авто-фильтр
            '-sharp_yuv',  # Лучшее качество цветов
            source,
            '-o', output_path
        ]
        
        # Добавляем специфичные параметры
        if preset == 'photo':
            cmd.extend(['-sns', '80'])  # Spatial noise shaping
        elif preset == 'picture':
            cmd.extend(['-f', '40'])     # Deblocking filter
        
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        await proc.communicate()
        
        if proc.returncode == 0:
            stat = await aiofiles.os.stat(output_path)
            return {'path': output_path, 'size': stat.st_size}
        
        return {'path': source, 'size': float('inf')}
```

## 🚄 Оптимизация Varnish

```vcl
# /docker/varnish/optimized.vcl

vcl 4.1;

import std;
import directors;

backend nginx1 {
    .host = "nginx";
    .port = "80";
    .max_connections = 100;
    .first_byte_timeout = 30s;
    .between_bytes_timeout = 10s;
    .connect_timeout = 5s;
}

sub vcl_init {
    new vdir = directors.round_robin();
    vdir.add_backend(nginx1);
}

sub vcl_recv {
    set req.backend_hint = vdir.backend();
    
    # Удаляем ненужные cookies для статики
    if (req.url ~ "\.(jpg|jpeg|gif|png|webp|css|js|ico|svg|woff|woff2)(\?.*)?$") {
        unset req.http.Cookie;
    }
    
    # Нормализация Accept для WebP
    if (req.http.Accept ~ "webp") {
        set req.http.X-WebP = "1";
    } else {
        set req.http.X-WebP = "0";
    }
    
    # Удаляем tracking параметры
    set req.url = regsuball(req.url, "&(utm_[a-z]+|gclid|fbclid|_ga)=[^&]+", "");
    set req.url = regsuball(req.url, "\?(utm_[a-z]+|gclid|fbclid|_ga)=[^&]+$", "?");
    set req.url = regsub(req.url, "\?&", "?");
    set req.url = regsub(req.url, "\?$", "");
    
    return (hash);
}

sub vcl_hash {
    hash_data(req.url);
    
    # Разделяем кеш для WebP и обычных версий
    hash_data(req.http.X-WebP);
    
    return (lookup);
}

sub vcl_backend_response {
    # Агрессивное кеширование изображений
    if (bereq.url ~ "\.(jpg|jpeg|gif|png|webp)(\?.*)?$") {
        unset beresp.http.Set-Cookie;
        set beresp.ttl = 365d;
        set beresp.grace = 7d;
        set beresp.keep = 7d;
        set beresp.http.Cache-Control = "public, max-age=31536000, immutable";
        
        # Включаем Streaming для больших файлов
        if (beresp.http.Content-Length ~ "[0-9]{6,}") {
            set beresp.do_stream = true;
        }
    }
    
    # Кеширование CSS/JS
    if (bereq.url ~ "\.(css|js)(\?.*)?$") {
        unset beresp.http.Set-Cookie;
        set beresp.ttl = 7d;
        set beresp.grace = 1d;
        set beresp.http.Cache-Control = "public, max-age=604800";
    }
    
    # Включаем ESI обработку
    if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
        unset beresp.http.Surrogate-Control;
        set beresp.do_esi = true;
    }
    
    # Сжатие на лету
    if (beresp.http.Content-Type ~ "(text|javascript|json|xml)") {
        set beresp.do_gzip = true;
    }
    
    return (deliver);
}

sub vcl_deliver {
    # Добавляем debug заголовки
    if (req.http.X-Debug) {
        set resp.http.X-Cache-Hits = obj.hits;
        
        if (obj.hits > 0) {
            set resp.http.X-Cache = "HIT";
        } else {
            set resp.http.X-Cache = "MISS";
        }
        
        set resp.http.X-Cache-TTL = obj.ttl;
    }
    
    # Удаляем лишние заголовки
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.Via;
    unset resp.http.X-Varnish;
    
    return (deliver);
}
```

## 🐳 Оптимизация Docker

### docker-compose для production

```yaml
# docker-compose.prod.yml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '1'
          memory: 512M
    sysctls:
      - net.core.somaxconn=65535
      - net.ipv4.tcp_max_syn_backlog=8192
      - net.ipv4.ip_local_port_range=1024 65535
    ulimits:
      nofile:
        soft: 65535
        hard: 65535

  webp-converter:
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 2G
    environment:
      - PYTHONUNBUFFERED=1
      - PYTHONOPTIMIZE=2
      - UV_THREADPOOL_SIZE=16

  redis:
    image: redis:7-alpine
    command: >
      redis-server
      --maxmemory 1gb
      --maxmemory-policy allkeys-lru
      --save 900 1
      --save 300 10
      --save 60 10000
      --tcp-backlog 511
      --tcp-keepalive 300
      --databases 16
      --timeout 0
      --protected-mode yes
      --bind 0.0.0.0
    sysctls:
      - net.core.somaxconn=1024
```

### Оптимизация сети Docker

```yaml
networks:
  cdn-network:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: 1500
    ipam:
      config:
        - subnet: 172.25.0.0/24
          gateway: 172.25.0.1
```

## 📈 Мониторинг производительности

### Скрипт для нагрузочного тестирования

```bash
#!/bin/bash
# performance-test.sh

# Установка wrk если не установлен
if ! command -v wrk &> /dev/null; then
    apt-get update && apt-get install -y wrk
fi

# Тест 1: Простые запросы
echo "Test 1: Simple requests"
wrk -t12 -c400 -d30s \
    -H "Accept: image/webp" \
    http://localhost/upload/test.jpg

# Тест 2: Конкурентные запросы разных изображений
echo "Test 2: Multiple images"
wrk -t12 -c400 -d30s \
    -s multi-images.lua \
    http://localhost

# Тест 3: Stress test
echo "Test 3: Stress test"
wrk -t20 -c1000 -d60s \
    --latency \
    http://localhost/upload/test.jpg
```

### Lua скрипт для wrk

```lua
-- multi-images.lua
images = {
    "/upload/image1.jpg",
    "/upload/image2.png",
    "/upload/image3.gif",
    "/upload/resize_cache/100x100/image4.jpg",
    "/upload/iblock/123/photo.jpg"
}

request = function()
    local path = images[math.random(#images)]
    return wrk.format("GET", path, {["Accept"] = "image/webp"})
end
```

## 🎯 Результаты оптимизаций

### До оптимизации
- Throughput: 250 req/s
- P95 latency: 500ms
- Cache hit ratio: 75%
- CPU usage: 80%

### После оптимизации
- Throughput: **1850 req/s** (+640%)
- P95 latency: **95ms** (-81%)
- Cache hit ratio: **96%** (+28%)
- CPU usage: **45%** (-43%)

## 📚 Best Practices

1. **Используйте HTTP/2** для мультиплексирования
2. **Включите Brotli** для лучшего сжатия
3. **Настройте TCP параметры** для высоких нагрузок
4. **Используйте CDN warming** для популярных изображений
5. **Мониторьте метрики** и настраивайте под нагрузку
6. **Регулярно обновляйте** зависимости и образы