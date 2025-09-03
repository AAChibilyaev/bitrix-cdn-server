# 🔧 Интеграция CDN с Битрикс

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## 📋 Содержание

1. [Быстрая настройка](#быстрая-настройка)
2. [Детальная конфигурация](#детальная-конфигурация)
3. [Настройка компонентов](#настройка-компонентов)
4. [Оптимизация](#оптимизация)
5. [Проверка работы](#проверка-работы)

## ⚡ Быстрая настройка

### Шаг 1: Базовая интеграция

Добавьте в файл `/bitrix/php_interface/init.php`:

```php
<?php
// CDN конфигурация
define("BX_IMG_SERVER", "https://cdn.termokit.ru");

// Автоматическая замена URL для изображений
AddEventHandler("main", "OnEndBufferContent", "ReplaceCDNImages");

function ReplaceCDNImages(&$content) {
    // Заменяем пути к изображениям на CDN
    $content = str_replace(
        'src="/upload/',
        'src="https://cdn.termokit.ru/upload/',
        $content
    );
    
    // Заменяем background-image в CSS
    $content = preg_replace(
        '/url\(["\']?\/upload\//i',
        'url("https://cdn.termokit.ru/upload/',
        $content
    );
}
```

### Шаг 2: SSH ключи

```bash
# На CDN сервере
cat /docker/ssh/bitrix_mount.pub

# На Битрикс сервере
echo "SSH_PUBLIC_KEY_HERE" >> /home/www-data/.ssh/authorized_keys
chmod 600 /home/www-data/.ssh/authorized_keys
```

## 📦 Детальная конфигурация

### Настройка через .settings.php

```php
<?php
// /bitrix/.settings.php

return [
    // ... другие настройки
    
    'cdn' => [
        'value' => [
            'enabled' => true,
            'domain' => 'cdn.termokit.ru',
            'protocol' => 'https',
            'sites' => [
                's1' => [
                    'domain' => 'cdn.termokit.ru',
                    'protocol' => 'https',
                    'locations' => [
                        'upload' => true,
                        'resize_cache' => true,
                        'iblock' => true,
                    ]
                ]
            ],
            'debug' => false,
        ],
        'readonly' => false,
    ],
    
    'cache' => [
        'value' => [
            'type' => 'files',
            'use_lock' => true,
            'sid' => $_SERVER["DOCUMENT_ROOT"]."#01",
            'ttl' => 3600,
            'cdn_cache' => [
                'enabled' => true,
                'ttl' => 86400,
            ]
        ],
    ],
];
```

### Класс-хелпер для CDN

```php
<?php
// /local/php_interface/classes/CDNHelper.php

class CDNHelper {
    private static $instance = null;
    private $cdnDomain = 'https://cdn.termokit.ru';
    private $enabled = true;
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    /**
     * Получить CDN URL для файла
     */
    public function getImageUrl($path) {
        if (!$this->enabled || !$this->shouldUseCDN($path)) {
            return $path;
        }
        
        // Убираем домен если есть
        $path = parse_url($path, PHP_URL_PATH);
        
        // Проверяем WebP поддержку
        if ($this->browserSupportsWebP() && $this->isConvertibleImage($path)) {
            $webpPath = $this->getWebPPath($path);
            if ($this->fileExistsOnCDN($webpPath)) {
                return $this->cdnDomain . $webpPath;
            }
        }
        
        return $this->cdnDomain . $path;
    }
    
    /**
     * Проверка поддержки WebP браузером
     */
    private function browserSupportsWebP() {
        return isset($_SERVER['HTTP_ACCEPT']) && 
               strpos($_SERVER['HTTP_ACCEPT'], 'image/webp') !== false;
    }
    
    /**
     * Проверка возможности конвертации
     */
    private function isConvertibleImage($path) {
        $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        return in_array($ext, ['jpg', 'jpeg', 'png', 'gif']);
    }
    
    /**
     * Получить путь к WebP версии
     */
    private function getWebPPath($path) {
        return $path . '.webp';
    }
    
    /**
     * Проверка существования файла на CDN
     */
    private function fileExistsOnCDN($path) {
        // Кешируем результат проверки
        $cacheKey = 'cdn_file_' . md5($path);
        $cache = \Bitrix\Main\Data\Cache::createInstance();
        
        if ($cache->initCache(3600, $cacheKey)) {
            return $cache->getVars();
        }
        
        $cache->startDataCache();
        
        // Быстрая проверка через HEAD запрос
        $ch = curl_init($this->cdnDomain . $path);
        curl_setopt($ch, CURLOPT_NOBODY, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 1);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        $exists = ($httpCode == 200);
        $cache->endDataCache($exists);
        
        return $exists;
    }
    
    /**
     * Проверка необходимости использования CDN
     */
    private function shouldUseCDN($path) {
        // Только для upload директории
        if (strpos($path, '/upload/') === false) {
            return false;
        }
        
        // Не для админки
        if (defined('ADMIN_SECTION') && ADMIN_SECTION === true) {
            return false;
        }
        
        // Не для локальной разработки
        if (isset($_SERVER['HTTP_HOST']) && 
            in_array($_SERVER['HTTP_HOST'], ['localhost', '127.0.0.1'])) {
            return false;
        }
        
        return true;
    }
}

// Использование
$cdnUrl = CDNHelper::getInstance()->getImageUrl('/upload/iblock/123/image.jpg');
```

## 🎨 Настройка компонентов

### Модификация компонента catalog.element

```php
<?php
// /local/templates/.default/components/bitrix/catalog.element/.default/result_modifier.php

if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

$cdn = CDNHelper::getInstance();

// Обработка основного изображения
if (!empty($arResult['DETAIL_PICTURE']['SRC'])) {
    $arResult['DETAIL_PICTURE']['CDN_SRC'] = $cdn->getImageUrl(
        $arResult['DETAIL_PICTURE']['SRC']
    );
}

// Обработка дополнительных изображений
if (!empty($arResult['MORE_PHOTO'])) {
    foreach ($arResult['MORE_PHOTO'] as &$photo) {
        $photo['CDN_SRC'] = $cdn->getImageUrl($photo['SRC']);
    }
    unset($photo);
}
```

### Компонент для responsive images

```php
<?php
// /local/components/custom/image.responsive/class.php

use Bitrix\Main\Engine\Contract\Controllerable;

class ResponsiveImageComponent extends CBitrixComponent implements Controllerable {
    
    public function executeComponent() {
        $this->arResult = $this->prepareResult();
        $this->includeComponentTemplate();
    }
    
    private function prepareResult() {
        $cdn = CDNHelper::getInstance();
        $imagePath = $this->arParams['IMAGE_PATH'];
        
        return [
            'ORIGINAL' => $imagePath,
            'CDN_URL' => $cdn->getImageUrl($imagePath),
            'WEBP_URL' => $cdn->getImageUrl($imagePath . '.webp'),
            'SIZES' => $this->generateSizes($imagePath),
        ];
    }
    
    private function generateSizes($path) {
        $sizes = [320, 640, 768, 1024, 1440, 1920];
        $result = [];
        
        foreach ($sizes as $size) {
            $resizedPath = $this->getResizedPath($path, $size);
            $result[$size] = [
                'jpg' => CDNHelper::getInstance()->getImageUrl($resizedPath),
                'webp' => CDNHelper::getInstance()->getImageUrl($resizedPath . '.webp'),
            ];
        }
        
        return $result;
    }
    
    public function configureActions() {
        return [];
    }
}
```

### Шаблон компонента

```php
<?php
// /local/components/custom/image.responsive/templates/.default/template.php

if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();

?>
<picture>
    <!-- WebP версии для разных размеров -->
    <?php foreach ($arResult['SIZES'] as $width => $urls): ?>
        <source 
            media="(min-width: <?=$width?>px)"
            srcset="<?=$urls['webp']?>"
            type="image/webp">
    <?php endforeach; ?>
    
    <!-- JPEG версии для разных размеров -->
    <?php foreach ($arResult['SIZES'] as $width => $urls): ?>
        <source 
            media="(min-width: <?=$width?>px)"
            srcset="<?=$urls['jpg']?>"
            type="image/jpeg">
    <?php endforeach; ?>
    
    <!-- Fallback -->
    <img 
        src="<?=$arResult['CDN_URL']?>" 
        alt="<?=$arParams['ALT']?>"
        loading="lazy"
        decoding="async">
</picture>
```

## ⚡ Оптимизация

### Предзагрузка критических изображений

```php
// В header.php шаблона
$criticalImages = [
    '/upload/main-banner.jpg',
    '/upload/logo.png',
];

foreach ($criticalImages as $image):
    $cdnUrl = CDNHelper::getInstance()->getImageUrl($image);
    $webpUrl = CDNHelper::getInstance()->getImageUrl($image . '.webp');
?>
    <link rel="preload" as="image" href="<?=$webpUrl?>" type="image/webp">
    <link rel="preload" as="image" href="<?=$cdnUrl?>" type="image/jpeg">
<?php endforeach; ?>
```

### Lazy Loading для каталога

```javascript
// /local/templates/.default/js/lazy-cdn.js

document.addEventListener('DOMContentLoaded', function() {
    const images = document.querySelectorAll('img[data-src]');
    
    const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const img = entry.target;
                
                // Проверяем поддержку WebP
                if (supportsWebP()) {
                    img.src = img.dataset.src.replace(/\.(jpg|png)$/i, '.webp');
                } else {
                    img.src = img.dataset.src;
                }
                
                img.removeAttribute('data-src');
                observer.unobserve(img);
            }
        });
    });
    
    images.forEach(img => imageObserver.observe(img));
});

function supportsWebP() {
    const canvas = document.createElement('canvas');
    canvas.width = 1;
    canvas.height = 1;
    return canvas.toDataURL('image/webp').indexOf('image/webp') === 0;
}
```

### Service Worker для оффлайн кеша

```javascript
// /service-worker.js

const CACHE_NAME = 'cdn-images-v1';
const CDN_DOMAIN = 'https://cdn.termokit.ru';

self.addEventListener('fetch', event => {
    if (event.request.url.includes('/upload/')) {
        event.respondWith(
            caches.match(event.request)
                .then(response => {
                    if (response) {
                        return response;
                    }
                    
                    // Заменяем домен на CDN
                    const cdnUrl = event.request.url.replace(
                        location.origin,
                        CDN_DOMAIN
                    );
                    
                    return fetch(cdnUrl)
                        .then(response => {
                            // Кешируем ответ
                            if (response.ok) {
                                const responseClone = response.clone();
                                caches.open(CACHE_NAME)
                                    .then(cache => {
                                        cache.put(event.request, responseClone);
                                    });
                            }
                            return response;
                        });
                })
        );
    }
});
```

## ✅ Проверка работы

### Тестовый скрипт

```php
<?php
// /test-cdn.php
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/header.php");

$testImages = [
    '/upload/iblock/123/test.jpg',
    '/upload/resize_cache/iblock/456/100_100_1/test.png',
];

echo "<h2>CDN Integration Test</h2>";

foreach ($testImages as $image) {
    $cdnUrl = CDNHelper::getInstance()->getImageUrl($image);
    
    echo "<div>";
    echo "<h3>Original: $image</h3>";
    echo "<p>CDN URL: $cdnUrl</p>";
    
    // Проверка доступности
    $headers = @get_headers($cdnUrl);
    $status = $headers ? substr($headers[0], 9, 3) : 'Error';
    
    echo "<p>Status: $status</p>";
    
    if ($status == '200') {
        echo '<img src="'.$cdnUrl.'" width="200" alt="Test">';
    }
    
    echo "</div><hr>";
}

require($_SERVER["DOCUMENT_ROOT"]."/bitrix/footer.php");
```

### Проверка через консоль браузера

```javascript
// Проверка загрузки с CDN
Array.from(document.images).forEach(img => {
    if (img.src.includes('cdn.termokit.ru')) {
        console.log('✅ CDN:', img.src);
    } else if (img.src.includes('/upload/')) {
        console.warn('❌ Not CDN:', img.src);
    }
});

// Проверка WebP
const webpImages = Array.from(document.images)
    .filter(img => img.src.includes('.webp'));
console.log(`WebP images: ${webpImages.length}`);

// Проверка производительности
performance.getEntriesByType('resource')
    .filter(r => r.name.includes('cdn.termokit.ru'))
    .forEach(r => {
        console.log(`${r.name}: ${r.duration.toFixed(2)}ms`);
    });
```

### Метрики для проверки

```sql
-- Битрикс MySQL запрос для проверки нагрузки
SELECT 
    COUNT(*) as requests,
    SUM(BODY_SIZE) as total_bytes,
    AVG(EXEC_TIME) as avg_time
FROM b_perf_hit
WHERE 
    PAGE_URL LIKE '%/upload/%'
    AND DATE_HIT >= DATE_SUB(NOW(), INTERVAL 1 HOUR);
```

## 🚀 Результаты интеграции

После правильной настройки вы должны увидеть:

1. **Снижение нагрузки** на основной сервер на 70-90%
2. **Ускорение загрузки** изображений в 2-3 раза
3. **Экономия трафика** 40-55% благодаря WebP
4. **Улучшение PageSpeed** на 15-25 баллов
5. **Снижение TTFB** для изображений до 10-30ms