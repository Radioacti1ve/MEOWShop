set -e

PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

# Используем данные из существующей базы
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="hashed_admin_password"
BANNED_USERNAME="ekaterina_smirnova"  # Выбираем обычного пользователя для бана
BANNED_PASSWORD="hashed_password_2"

echo -e "\n🔍 Получаем user_id пользователя для бана..."
BANNED_USER_ID=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT user_id FROM \"Users\" WHERE username = '$BANNED_USERNAME';" | tr -d '[:space:]')

if [[ -z "$BANNED_USER_ID" ]]; then
    echo "❌ Не удалось получить user_id пользователя для бана"
    exit 1
fi
echo "Пользователь для бана user_id = $BANNED_USER_ID"

# 1. Тестируем вход пользователя до бана
echo -e "\n1️⃣ Проверяем, что пользователь может войти до бана..."
PRE_BAN_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}")

if [[ "$(echo "$PRE_BAN_LOGIN" | jq -r '.access_token')" == "null" ]]; then
    echo "❌ Ошибка: пользователь не смог войти до бана"
    exit 1
fi
echo "✅ Пользователь успешно вошел до бана"

# 2. Авторизуемся как админ
echo -e "\n2️⃣ Авторизуемся как админ..."
ADMIN_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}")

ADMIN_TOKEN=$(echo "$ADMIN_LOGIN" | jq -r '.access_token')

if [[ "$ADMIN_TOKEN" == "null" || -z "$ADMIN_TOKEN" ]]; then
    echo "❌ Ошибка авторизации админа"
    exit 1
fi
echo "✅ Админ успешно авторизован"

# 3. Баним пользователя
echo -e "\n3️⃣ Баним пользователя $BANNED_USERNAME (user_id=$BANNED_USER_ID)..."
BAN_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/ban/$BANNED_USER_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json")

echo "Ответ на бан: $BAN_RESPONSE"
if [[ "$(echo "$BAN_RESPONSE" | jq -r '.message')" != *"banned successfully"* ]]; then
    echo "❌ Ошибка при бане пользователя"
    exit 1
fi
echo "✅ Пользователь успешно забанен"

# 4. Проверяем, что забаненный пользователь не может войти
echo -e "\n4️⃣ Проверяем, что забаненный пользователь не может войти..."
BANNED_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}")

echo "Ответ на попытку входа забаненного пользователя:"
echo "$BANNED_LOGIN" | jq '.'

# 5. Разбаниваем пользователя
echo -e "\n5️⃣ Разбаниваем пользователя..."
UNBAN_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/unban/$BANNED_USER_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json")

echo "Ответ на разбан: $UNBAN_RESPONSE"
if [[ "$(echo "$UNBAN_RESPONSE" | jq -r '.message')" != *"unbanned successfully"* ]]; then
    echo "❌ Ошибка при разбане пользователя"
    exit 1
fi
echo "✅ Пользователь успешно разбанен"

# 6. Проверяем, что разбаненный пользователь может войти
echo -e "\n6️⃣ Проверяем, что разбаненный пользователь может войти..."
POST_UNBAN_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}")

if [[ "$(echo "$POST_UNBAN_LOGIN" | jq -r '.access_token')" == "null" ]]; then
    echo "❌ Ошибка: пользователь не смог войти после разбана"
    exit 1
fi
echo "✅ Пользователь успешно вошел после разбана"

echo -e "\n✨ Тесты бана/разбана завершены успешно!"
