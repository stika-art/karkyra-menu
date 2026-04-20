# 1. Настройка Git для обхода ограничений прав доступа
git config --global --add safe.directory "*"

# 2. Клонируем Flutter (stable ветка)
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi

# 3. Добавляем Flutter в PATH
export PATH="$PATH:`pwd`/flutter/bin"

# 4. Инициализация и сборка (используем --no-analytics для стабильности в CI)
flutter config --no-analytics
flutter config --enable-web
flutter pub get
flutter build web --release --web-renderer canvaskit
