set -e

PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

echo "📌 Регистрируем первого пользователя (будущего админа)..."
ADMIN_USERNAME="adminUser$(date +%s)"
ADMIN_PASSWORD="password123"
ADMIN_EMAIL="${ADMIN_USERNAME}@example.com"

curl -s -X POST http://localhost:8000/register -H "Content-Type: application/json" -d "{
  \"username\": \"$ADMIN_USERNAME\",
  \"email\": \"$ADMIN_EMAIL\",
  \"password\": \"$ADMIN_PASSWORD\"
}"
echo -e "\n"

echo "📌 Регистрируем второго пользователя (которого будем банить)..."
BANNED_USERNAME="bannedUser$(date +%s)"
BANNED_PASSWORD="password123"
BANNED_EMAIL="${BANNED_USERNAME}@example.com"

curl -s -X POST http://localhost:8000/register -H "Content-Type: application/json" -d "{
  \"username\": \"$BANNED_USERNAME\",
  \"email\": \"$BANNED_EMAIL\",
  \"password\": \"$BANNED_PASSWORD\"
}"
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

echo "⚙️ Обновляем роль пользователя $ADMIN_USERNAME на admin..."
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "UPDATE \"Users\" SET role = 'admin' WHERE user_id = $ADMIN_USER_ID;"

echo "🔐 Авторизуем админа $ADMIN_USERNAME..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8000/login \
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
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на бан: $BAN_RESPONSE"

echo "✔️ Скрипт выполнен успешно."
