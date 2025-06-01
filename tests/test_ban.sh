set -e

PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

# Используем существующего админа из базы данных
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="hashed_admin_password"

# Используем существующего пользователя для бана
BANNED_USERNAME="ivan_petrov"
BANNED_PASSWORD="hashed_password_1"
echo -e "\n"

echo "🔍 Получаем user_id админа из базы..."
ADMIN_USER_ID=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT user_id FROM \"Users\" WHERE username = '$ADMIN_USERNAME';" | tr -d '[:space:]')

if [[ -z "$ADMIN_USER_ID" ]]; then
  echo "❌ Не удалось получить user_id админа"
  exit 1
fi
echo "Админ user_id = $ADMIN_USER_ID"

echo "🔍 Получаем user_id пользователя для бана..."
BANNED_USER_ID=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT user_id FROM \"Users\" WHERE username = '$BANNED_USERNAME';" | tr -d '[:space:]')

if [[ -z "$BANNED_USER_ID" ]]; then
  echo "❌ Не удалось получить user_id пользователя для бана"
  exit 1
fi
echo "Пользователь для бана user_id = $BANNED_USER_ID"

echo "🔐 Авторизуем админа $ADMIN_USERNAME..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Ошибка авторизации админа. Токен не получен."
  exit 1
fi

echo "✅ Получен токен админа: $TOKEN"

echo "⛔ Баним пользователя $BANNED_USERNAME (user_id=$BANNED_USER_ID)..."
BAN_RESPONSE=$(curl -s -X PUT http://localhost:8000/admin/ban/$BANNED_USER_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")

echo "Ответ на бан: $BAN_RESPONSE"

echo "🔒 Проверяем, что забаненный пользователь не может войти..."
BANNED_LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}")

echo "Ответ на попытку входа забаненного пользователя:"
echo "$BANNED_LOGIN_RESPONSE" | jq .

echo "✔️ Скрипт выполнен успешно."
