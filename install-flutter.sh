#!/bin/bash

# 1. Доверяем директории (фикс для Git)
git config --global --add safe.directory "*"

# 2. Клонируем Flutter, если его нет
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

# 3. Определяем полный путь к исполняемому файлу
FLUTTER_BIN="$(pwd)/flutter/bin/flutter"

# 4. Настройка
$FLUTTER_BIN config --no-analytics
$FLUTTER_BIN config --enable-web

# 5. Сборка
$FLUTTER_BIN pub get
$FLUTTER_BIN build web --release --web-renderer=canvaskit
