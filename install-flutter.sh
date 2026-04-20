#!/bin/bash

# 1. Безопасность Git
git config --global --add safe.directory "*"

# 2. Установка Flutter (если нет в кэше)
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

# 3. Путь к бинарнику
FLUTTER="./flutter/bin/flutter"

# 4. Диагностика и настройка
$FLUTTER config --no-analytics
$FLUTTER config --enable-web
$FLUTTER doctor

# 5. Сборка БЕЗ лишних флагов
$FLUTTER pub get
$FLUTTER build web --release
