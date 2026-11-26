# IPTV-СИЛА — Android и Android TV

Нативное приложение на Kotlin + Android SDK + AndroidX Media3 (ExoPlayer). Python runtime, WebView и JavaScript-обёртки не используются.

## Сборки

GitHub Actions создаёт два отдельных APK:

- **IPTV-SILA-Android-debug** — телефоны и планшеты.
- **IPTV-SILA-Android-TV-debug** — Android TV и Google TV.

Для Android TV предусмотрены отдельный launcher entry LEANBACK_LAUNCHER, TV banner, альбомная ориентация и отсутствие обязательного сенсорного экрана. Интерфейс использует стандартные Android-кнопки и элементы ввода, доступные для навигации D-pad/пультом; ExoPlayer предоставляет экранные кнопки управления воспроизведением.

## Возможности

- Открытие локальных M3U/M3U8 через системный выбор файла.
- Загрузка украинских IPTV-подборок.
- Проверка доступности плейлистов и подсчёт записей EXTINF.
- Поиск каналов и воспроизведение через Media3.
- Поддержка относительных URL в M3U.

Проверка M3U не гарантирует, что каждый отдельный видеопоток доступен.

## Сборка локально

- Телефон/планшет: gradle assembleStandardDebug
- Android TV: gradle assembleTvDebug

APK для ручного тестирования публикуются во вкладке Actions → последний запуск → Artifacts.
