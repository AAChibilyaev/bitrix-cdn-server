#!/usr/bin/env python3
"""
WebP Converter Service
Monitors directories and converts images to WebP format on demand
"""

import os
import sys
import time
import hashlib
import subprocess
import logging
from pathlib import Path
from typing import Optional, Tuple
import redis
from PIL import Image
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
QUALITY = int(os.environ.get('WEBP_QUALITY', 85))
MAX_WIDTH = int(os.environ.get('MAX_WIDTH', 2048))
MAX_HEIGHT = int(os.environ.get('MAX_HEIGHT', 2048))
CACHE_DIR = Path(os.environ.get('CACHE_DIR', '/var/cache/webp'))
SOURCE_DIR = Path(os.environ.get('SOURCE_DIR', '/mnt/bitrix'))
REDIS_HOST = os.environ.get('REDIS_HOST', 'redis')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/converter/converter.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('webp-converter')

# Redis connection
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    redis_client.ping()
    logger.info("Connected to Redis")
except:
    redis_client = None
    logger.warning("Redis not available, running without cache metadata")


class WebPConverter:
    """WebP conversion handler"""
    
    def __init__(self):
        self.supported_formats = {'.jpg', '.jpeg', '.png', '.gif', '.bmp'}
        self.stats = {
            'converted': 0,
            'skipped': 0,
            'failed': 0,
            'total_saved': 0
        }
    
    def get_cache_path(self, source_path: Path) -> Path:
        """Get cache path for source file"""
        relative_path = source_path.relative_to(SOURCE_DIR)
        cache_path = CACHE_DIR / relative_path
        return cache_path.with_suffix(cache_path.suffix + '.webp')
    
    def needs_conversion(self, source_path: Path, cache_path: Path) -> bool:
        """Check if conversion is needed"""
        if not cache_path.exists():
            return True
        
        # Check if source is newer
        source_mtime = source_path.stat().st_mtime
        cache_mtime = cache_path.stat().st_mtime
        
        return source_mtime > cache_mtime
    
    def convert_image(self, source_path: Path) -> Optional[Path]:
        """Convert image to WebP format"""
        if source_path.suffix.lower() not in self.supported_formats:
            return None
        
        cache_path = self.get_cache_path(source_path)
        
        # Check if conversion needed
        if not self.needs_conversion(source_path, cache_path):
            logger.debug(f"Skipping {source_path} - already converted")
            self.stats['skipped'] += 1
            return cache_path
        
        # Create cache directory
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            # Get original size
            original_size = source_path.stat().st_size
            
            # Convert using cwebp for better quality
            cmd = [
                'cwebp',
                '-q', str(QUALITY),
                '-mt',  # Multi-threading
                '-af',  # Auto-filter
                '-m', '6',  # Compression method
                '-resize', str(MAX_WIDTH), str(MAX_HEIGHT),
                str(source_path),
                '-o', str(cache_path)
            ]
            
            # Add alpha quality for PNG
            if source_path.suffix.lower() == '.png':
                cmd.extend(['-alpha_q', '100'])
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                # Get new size
                webp_size = cache_path.stat().st_size
                saved = original_size - webp_size
                # Правильный расчёт: положительное значение = экономия, отрицательное = увеличение
                if original_size > 0:
                    saved_percent = (saved / original_size) * 100
                else:
                    saved_percent = 0
                
                self.stats['converted'] += 1
                self.stats['total_saved'] += saved
                
                # Логируем результат конвертации
                if saved > 0:
                    logger.info(f"Converted {source_path.name}: "
                              f"{original_size:,} -> {webp_size:,} bytes "
                              f"(saved {saved_percent:.1f}%)")
                else:
                    logger.warning(f"Converted {source_path.name}: "
                                 f"{original_size:,} -> {webp_size:,} bytes "
                                 f"(increased by {abs(saved_percent):.1f}%)")
                
                # Store metadata in Redis if available
                if redis_client:
                    key = f"webp:{source_path}"
                    redis_client.hset(key, mapping={
                        'original_size': original_size,
                        'webp_size': webp_size,
                        'saved': saved,
                        'quality': QUALITY,
                        'timestamp': time.time()
                    })
                    redis_client.expire(key, 86400 * 30)  # 30 days
                
                return cache_path
            else:
                logger.error(f"Failed to convert {source_path}: {result.stderr}")
                self.stats['failed'] += 1
                return None
                
        except Exception as e:
            logger.error(f"Error converting {source_path}: {e}")
            self.stats['failed'] += 1
            return None
    
    def convert_directory(self, directory: Path):
        """Convert all images in directory"""
        logger.info(f"Converting directory: {directory}")
        
        for ext in self.supported_formats:
            for image_path in directory.rglob(f"*{ext}"):
                self.convert_image(image_path)
                
                # Small delay to prevent overload
                if self.stats['converted'] % 10 == 0:
                    time.sleep(0.1)
    
    def cleanup_orphaned(self):
        """Remove WebP files for deleted originals"""
        logger.info("Cleaning orphaned WebP files...")
        removed = 0
        
        for webp_path in CACHE_DIR.rglob("*.webp"):
            # Reconstruct original path
            relative_path = webp_path.relative_to(CACHE_DIR)
            original_path = SOURCE_DIR / str(relative_path).replace('.webp', '')
            
            if not original_path.exists():
                logger.info(f"Removing orphaned: {webp_path}")
                webp_path.unlink()
                removed += 1
                
                # Remove from Redis
                if redis_client:
                    redis_client.delete(f"webp:{original_path}")
        
        logger.info(f"Removed {removed} orphaned files")
    
    def show_stats(self):
        """Display conversion statistics"""
        logger.info("=== Conversion Statistics ===")
        logger.info(f"Converted: {self.stats['converted']}")
        logger.info(f"Skipped: {self.stats['skipped']}")
        logger.info(f"Failed: {self.stats['failed']}")
        
        if self.stats['total_saved'] > 0:
            saved_mb = self.stats['total_saved'] / (1024 * 1024)
            logger.info(f"Total saved: {saved_mb:.2f} MB")


class ImageEventHandler(FileSystemEventHandler):
    """Handle file system events for image files"""
    
    def __init__(self, converter: WebPConverter):
        self.converter = converter
    
    def on_created(self, event):
        if not event.is_directory:
            path = Path(event.src_path)
            if path.suffix.lower() in self.converter.supported_formats:
                logger.info(f"New image detected: {path}")
                self.converter.convert_image(path)
    
    def on_modified(self, event):
        if not event.is_directory:
            path = Path(event.src_path)
            if path.suffix.lower() in self.converter.supported_formats:
                logger.info(f"Image modified: {path}")
                self.converter.convert_image(path)
    
    def on_deleted(self, event):
        if not event.is_directory:
            path = Path(event.src_path)
            if path.suffix.lower() in self.converter.supported_formats:
                # Remove corresponding WebP
                cache_path = self.converter.get_cache_path(path)
                if cache_path.exists():
                    logger.info(f"Removing WebP for deleted image: {path}")
                    cache_path.unlink()
                    
                    # Remove from Redis
                    if redis_client:
                        redis_client.delete(f"webp:{path}")


def main():
    """Main converter loop"""
    logger.info("Starting WebP Converter Service")
    logger.info(f"Source: {SOURCE_DIR}")
    logger.info(f"Cache: {CACHE_DIR}")
    logger.info(f"Quality: {QUALITY}")
    
    # Create converter
    converter = WebPConverter()
    
    # Initial conversion of existing files
    if SOURCE_DIR.exists():
        logger.info("Starting initial conversion...")
        converter.convert_directory(SOURCE_DIR)
        converter.show_stats()
    else:
        logger.warning(f"Source directory not found: {SOURCE_DIR}")
    
    # Setup file system observer
    event_handler = ImageEventHandler(converter)
    observer = Observer()
    
    if SOURCE_DIR.exists():
        observer.schedule(event_handler, str(SOURCE_DIR), recursive=True)
        observer.start()
        logger.info("File system observer started")
    
    try:
        # Main loop
        while True:
            time.sleep(60)
            
            # Periodic cleanup
            if converter.stats['converted'] % 100 == 0:
                converter.cleanup_orphaned()
            
            # Show stats every hour
            if int(time.time()) % 3600 == 0:
                converter.show_stats()
                
    except KeyboardInterrupt:
        observer.stop()
        logger.info("Shutting down...")
    
    observer.join()
    converter.show_stats()


if __name__ == '__main__':
    main()
