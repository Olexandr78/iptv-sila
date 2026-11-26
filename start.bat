@echo off
chcp 65001 >nul
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
  echo Python 3 не найден. Установи Python 3 и включи Add Python to PATH.
  pause
  exit /b 1
)
if not exist config.json copy config.example.json config.json >nul
python server.py
pause
