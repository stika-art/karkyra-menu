#!/bin/bash

# 1. Установка переменных окружения
export PATH="$PATH:`pwd`/flutter/bin"

# 2. Безопасность Git (критично для Vercel)
git config --global --add safe.directory "*"

# 3. Клонирование Flutter (если его нет)
if [ ! -d "flutter" ]; then
  echo "Installing Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
else
  echo "Flutter SDK found in cache."
fi

# 4. Настройка
flutter config --no-analytics
flutter config --enable-web

# 5. Сборка
echo "Running pub get..."
flutter pub get

echo "Building Flutter Web..."
flutter build web --release --base-href /

echo "Build finished successfully!"
