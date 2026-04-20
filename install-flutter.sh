#!/bin/bash

# 1. Клонируем Flutter (stable ветка)
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi

# 2. Добавляем Flutter в PATH
export PATH="$PATH:`pwd`/flutter/bin"

# 3. Принудительно скачиваем зависимости и собираем Web
flutter config --enable-web
flutter pub get
flutter build web --release
