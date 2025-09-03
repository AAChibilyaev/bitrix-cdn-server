# 🔄 Поток обработки данных в CDN

## 📋 Содержание

1. [Основной поток запроса](#основной-поток-запроса)
2. [Детальные сценарии](#детальные-сценарии)
3. [Кеширование](#кеширование)
4. [Обработка ошибок](#обработка-ошибок)
5. [Оптимизации](#оптимизации)

## 🎯 Основной поток запроса

```mermaid
sequenceDiagram
    participant U as Браузер
    participant N as NGINX
    participant V as Varnish
    participant C as Cache Disk
    participant W as WebP Converter
    participant S as SSHFS Mount
    participant B as Битрикс Server
    participant R as Redis

    U->>N: GET /upload/image.jpg
    N->>N: Check Accept: image/webp
    
    alt WebP поддерживается
        N->>V: Check Varnish cache
        alt Cache HIT in Varnish
            V->>U: Return cached WebP
        else Cache MISS in Varnish
            N->>C: Check disk cache
            alt Cache HIT on disk
                C->>N: Read image.jpg.webp
                N->>V: Store in Varnish
                N->>U: Return WebP
            else Cache MISS on disk
                N->>W: Request conversion
                W->>S: Read original via SSHFS
                S->>B: SSH connection
                B->>S: Return image data
                W->>W: Convert to WebP
                W->>C: Save to cache
                W->>R: Store metadata
                W->>N: Return WebP
                N->>V: Store in Varnish
                N->>U: Return WebP
            end
        end
    else WebP не поддерживается
        N->>S: Read original
        S->>B: Get file
        N->>U: Return JPEG/PNG
    end
```

## 🔍 Детальные сценарии

### Сценарий 1: Cache HIT (90% запросов)

**Время выполнения: ~5-10ms**

```
1. Запрос приходит на NGINX
2. NGINX проверяет Varnish (RAM cache)
3. Varnish отдает файл из памяти
4. Клиент получает ответ
```

### Сценарий 2: Первый запрос изображения

**Время выполнения: ~200-500ms**

```
1. Запрос приходит на NGINX
2. Проверка всех уровней кеша - MISS
3. WebP Converter получает задачу
4. Чтение оригинала через SSHFS
5. Конвертация в WebP (cwebp)
6. Сохранение в кеш
7. Запись метаданных в Redis
8. Отдача клиенту
9. Фоновое сохранение в Varnish
```

### Сценарий 3: Обновление изображения

**Автоматическая инвалидация кеша**

```python
# File watcher в WebP Converter
def on_modified(self, event):
    if event.src_path.endswith(('.jpg', '.png')):
        # Удаляем старую WebP версию
        cache_path = get_cache_path(event.src_path)
        if cache_path.exists():
            cache_path.unlink()
        
        # Удаляем из Redis
        redis_client.delete(f"webp:{event.src_path}")
        
        # Инвалидируем Varnish
        purge_varnish_cache(event.src_path)
```

## 🗄️ Уровни кеширования

### Level 1: Browser Cache
```http
Cache-Control: public, max-age=31536000, immutable
Expires: Wed, 01 Jan 2025 00:00:00 GMT
ETag: "686897696a7c876b7e"
```

### Level 2: Varnish (RAM)
```vcl
sub vcl_backend_response {
    if (bereq.url ~ "\.(jpg|jpeg|png|gif|webp)$") {
        set beresp.ttl = 365d;
        set beresp.grace = 6h;
    }
}
```

### Level 3: NGINX (Disk)
```nginx
location ~* \.(webp)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    open_file_cache max=1000 inactive=20s;
}
```

### Level 4: Redis (Metadata)
```python
# Структура данных в Redis
{
    "webp:/upload/image.jpg": {
        "original_size": 524288,
        "webp_size": 262144,
        "quality": 85,
        "converted_at": "2024-01-15T10:30:00Z",
        "hits": 1523,
        "last_access": "2024-01-15T14:20:00Z"
    }
}
```

## 🚨 Обработка ошибок

### Fallback стратегия

```mermaid
graph TD
    A[Запрос изображения] --> B{CDN доступен?}
    B -->|Да| C{WebP конвертация OK?}
    B -->|Нет| D[302 Redirect на Битрикс]
    
    C -->|Да| E[Отдать WebP]
    C -->|Нет| F{Оригинал доступен?}
    
    F -->|Да| G[Отдать оригинал]
    F -->|Нет| H[404 Error]
    
    D --> I[Битрикс отдает напрямую]
```

### Обработка типичных ошибок

| Ошибка | Действие | Recovery |
|--------|----------|----------|
| SSHFS отвалился | Попытка remount | Auto-restart контейнера |
| WebP конвертация failed | Отдача оригинала | Логирование, retry через 1 час |
| Redis недоступен | Работа без метаданных | Продолжение работы |
| Disk full | Очистка старого кеша | Emergency cleanup |
| High load | Rate limiting | Queue обработки |

## ⚡ Оптимизации производительности

### 1. Smart Preloading
```javascript
// Предзагрузка следующих изображений
const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            const img = entry.target;
            const webpUrl = img.src.replace(/\.(jpg|png)$/, '.webp');
            fetch(webpUrl, { mode: 'no-cors' }); // Прогрев кеша
        }
    });
});
```

### 2. Batch Processing
```python
# Группировка запросов на конвертацию
class BatchConverter:
    def __init__(self):
        self.queue = []
        self.timer = None
    
    def add_to_queue(self, image_path):
        self.queue.append(image_path)
        if len(self.queue) >= 10 or not self.timer:
            self.process_batch()
    
    def process_batch(self):
        # Параллельная обработка
        with ThreadPoolExecutor(max_workers=4) as executor:
            executor.map(convert_to_webp, self.queue)
        self.queue.clear()
```

### 3. Adaptive Quality
```python
def determine_quality(image_path, file_size):
    """Адаптивное качество в зависимости от размера"""
    if file_size < 100_000:  # < 100KB
        return 90  # Высокое качество для маленьких
    elif file_size < 500_000:  # < 500KB
        return 85  # Стандартное качество
    else:  # > 500KB
        return 80  # Агрессивное сжатие для больших
```

### 4. Progressive WebP
```bash
# Прогрессивная загрузка для больших изображений
cwebp -q 85 \
      -m 6 \
      -mt \
      -af \
      -progression \
      input.jpg \
      -o output.webp
```

## 📊 Метрики производительности

### Ключевые показатели

| Метрика | Цель | Текущее | Статус |
|---------|------|---------|--------|
| Cache Hit Ratio | > 90% | 94.2% | ✅ |
| Avg Response Time | < 50ms | 42ms | ✅ |
| P99 Response Time | < 200ms | 185ms | ✅ |
| Conversion Time | < 500ms | 320ms | ✅ |
| Error Rate | < 0.1% | 0.03% | ✅ |

### Формулы расчета

```python
# Cache Hit Ratio
hit_ratio = (cache_hits / total_requests) * 100

# Экономия трафика
savings = sum(original_sizes - webp_sizes) / sum(original_sizes) * 100

# Среднее время ответа
avg_response = sum(response_times) / len(response_times)
```

## 🔄 Жизненный цикл изображения

```mermaid
stateDiagram-v2
    [*] --> Uploaded: Загрузка в Битрикс
    Uploaded --> Detected: File watcher
    Detected --> Converting: Запрос на WebP
    Converting --> Cached: Успешная конвертация
    Converting --> Failed: Ошибка
    Failed --> Retrying: Повторная попытка
    Retrying --> Converting
    Cached --> Serving: Отдача клиентам
    Serving --> Expired: TTL истек
    Expired --> Purged: Очистка
    Purged --> [*]
    
    Cached --> Updated: Файл изменен
    Updated --> Converting: Реконвертация
```

## 🛠️ Настройка потока

### Конфигурация NGINX
```nginx
# Тюнинг для оптимального потока
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
    
    # Буферы для изображений
    client_body_buffer_size 128k;
    client_max_body_size 100m;
    
    # Кеш открытых файлов
    open_file_cache max=10000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
}
```

### Конфигурация WebP Converter
```python
# config.py
CONVERTER_CONFIG = {
    'quality': 85,
    'max_width': 2048,
    'max_height': 2048,
    'compression_level': 6,
    'thread_count': 4,
    'batch_size': 10,
    'queue_timeout': 100,  # ms
    'retry_attempts': 3,
    'retry_delay': 60,  # seconds
}
```