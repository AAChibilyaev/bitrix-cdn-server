# Varnish Configuration for Bitrix CDN
# Version 4.0 syntax

vcl 4.0;

import std;

# Backend definition
backend default {
    .host = "nginx";
    .port = "80";
    .connect_timeout = 5s;
    .first_byte_timeout = 30s;
    .between_bytes_timeout = 10s;
    .max_connections = 50;
    
    # ИСПРАВЛЕНО: Health check (убраны несовместимые опции)
    .probe = {
        .url = "/health";
        .timeout = 2s;
        .interval = 5s;
        .window = 5;
        .threshold = 3;
    }
}

# ACL для очистки кеша
acl purge {
    "localhost";
    "127.0.0.1";
    "172.25.0.0/24";  # Docker network - правильный CIDR синтаксис
}

# Обработка входящих запросов
sub vcl_recv {
    # Устанавливаем backend
    set req.backend_hint = default;
    
    # Нормализация URL
    set req.url = std.querysort(req.url);
    
    # Удаляем порт из Host заголовка
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");
    
    # PURGE запросы для очистки кеша
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
            return(synth(405, "Method Not Allowed"));
        }
        return (purge);
    }
    
    # Обработка OPTIONS для CORS
    if (req.method == "OPTIONS") {
        return(synth(200, "OK"));
    }
    
    # Разрешаем только GET, HEAD, OPTIONS
    if (req.method != "GET" && req.method != "HEAD" && req.method != "OPTIONS") {
        return (pass);
    }
    
    # Пропускаем health check
    if (req.url ~ "^/health" || req.url ~ "^/nginx_status") {
        return (pass);
    }
    
    # Удаляем cookies для статических файлов
    if (req.url ~ "\.(jpg|jpeg|gif|png|ico|css|zip|tgz|gz|rar|bz2|pdf|txt|tar|wav|bmp|rtf|js|flv|swf|html|htm|webp|svg|woff|woff2|ttf|eot)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
    }
    
    # Удаляем tracking параметры
    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
        set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
        set req.url = regsub(req.url, "\?&", "?");
        set req.url = regsub(req.url, "\?$", "");
    }
    
    # Нормализация Accept-Encoding
    if (req.http.Accept-Encoding) {
        if (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            unset req.http.Accept-Encoding;
        }
    }
    
    # Кешируем по умолчанию
    return (hash);
}

# Обработка хеша
sub vcl_hash {
    hash_data(req.url);
    
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    
    # Различаем WebP и обычные версии
    if (req.http.Accept ~ "webp" && req.url ~ "\.(jpg|jpeg|png|gif)") {
        hash_data("webp");
    }
    
    return (lookup);
}

# Обработка ответа от backend
sub vcl_backend_response {
    # Включаем gzip если не включен
    if (beresp.http.content-type ~ "(text|javascript|json|xml|html)") {
        set beresp.do_gzip = true;
    }
    
    # Устанавливаем TTL для изображений
    if (bereq.url ~ "\.(jpg|jpeg|gif|png|ico|webp|svg)(\?.*)?$") {
        unset beresp.http.set-cookie;
        set beresp.ttl = 365d;
        set beresp.http.Cache-Control = "public, max-age=31536000";
    }
    
    # TTL для CSS и JS
    if (bereq.url ~ "\.(css|js)(\?.*)?$") {
        unset beresp.http.set-cookie;
        set beresp.ttl = 30d;
        set beresp.http.Cache-Control = "public, max-age=2592000";
    }
    
    # TTL для шрифтов
    if (bereq.url ~ "\.(woff|woff2|ttf|eot)(\?.*)?$") {
        unset beresp.http.set-cookie;
        set beresp.ttl = 365d;
        set beresp.http.Cache-Control = "public, max-age=31536000";
    }
    
    # Разрешаем кеширование для кодов 404 на короткое время
    if (beresp.status == 404) {
        set beresp.ttl = 1m;
    }
    
    # Добавляем grace period
    set beresp.grace = 6h;
    
    return (deliver);
}

# Обработка ответа клиенту
sub vcl_deliver {
    # Добавляем заголовок о статусе кеша
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    # Добавляем заголовок Varnish
    set resp.http.X-Varnish-Cache = "Bitrix CDN";
    
    # Удаляем некоторые заголовки для безопасности
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.Via;
    unset resp.http.X-Varnish;
    
    return (deliver);
}

# Обработка ошибок
sub vcl_synth {
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";
    
    synthetic({"
<!DOCTYPE html>
<html>
<head>
    <title>"} + resp.status + " " + resp.reason + {"</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d9534f; }
    </style>
</head>
<body>
    <h1>Error "} + resp.status + {"</h1>
    <p>"} + resp.reason + {"</p>
    <p>Bitrix CDN Server</p>
</body>
</html>
"});
    
    return (deliver);
}

# Обработка backend ошибок
sub vcl_backend_error {
    set beresp.http.Content-Type = "text/html; charset=utf-8";
    set beresp.http.Retry-After = "5";
    
    synthetic({"
<!DOCTYPE html>
<html>
<head>
    <title>503 Backend Error</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d9534f; }
    </style>
</head>
<body>
    <h1>503 Backend Error</h1>
    <p>The backend server is temporarily unavailable.</p>
    <p>Please try again later.</p>
    <p>Bitrix CDN Server</p>
</body>
</html>
"});
    
    return (deliver);
}