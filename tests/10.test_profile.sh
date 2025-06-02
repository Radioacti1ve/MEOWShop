# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TOTAL_TESTS=0
FAILED_TESTS=0

# Функция для проверки HTTP статуса и валидации JSON
validate_response() {
    local response="$1"
    local expected_status="${2:-200}"
    local test_name="$3"
    local validation_command="$4"
    local error_message="$5"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local test_result=0
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    local body=$(echo "$response" | sed '/HTTP_CODE/d')
    
    # Проверка HTTP статуса
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ HTTP статус верный: $http_code${NC}"
    else
        echo -e "${RED}✗ Неверный HTTP статус: $http_code (ожидался: $expected_status)${NC}"
        test_result=1
    fi
    
    # Проверка JSON структуры
    if ! echo "$body" | jq '.' >/dev/null 2>&1; then
        echo -e "${RED}✗ Невалидный JSON ответ${NC}"
        test_result=1
    elif [ -n "$validation_command" ]; then
        if ! echo "$body" | eval "$validation_command" >/dev/null 2>&1; then
            echo -e "${RED}✗ $error_message${NC}"
            test_result=1
        fi
    fi
    
    [[ $test_result == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "$body" | jq '.'
    echo "Результат теста \"$test_name\": $test_result (0=успех, 1=ошибка)"
    return $test_result
}

USERNAME="user$(date +%s)"
PASSWORD="password123"
EMAIL="${USERNAME}@example.com"

echo "📌 Регистрируем пользователя: $USERNAME"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "'"$USERNAME"'",
    "email": "'"$EMAIL"'",
    "password": "'"$PASSWORD"'"
  }')
validate_response "$response" "201" "Регистрация пользователя" \
    'jq -e ".message == \"User created successfully\" and .user_id"' \
    "Неверный формат ответа при регистрации"
echo -e "\n"

echo "📌 Авторизация пользователя: $USERNAME"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}")

validate_response "$response" "200" "Авторизация пользователя" \
    'jq -e ".access_token and .refresh_token and .token_type == \"bearer\""' \
    "Неверный формат токена авторизации"
RESPONSE_BODY=$(echo "$response" | sed '/HTTP_CODE/d')
echo "Ответ сервера на логин: $RESPONSE_BODY"
TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Ошибка авторизации, токен не получен"
  exit 1
fi

echo -e "\n✅ Получен токен: $TOKEN"

NEW_USERNAME="${USERNAME}_updated"
NEW_EMAIL="${NEW_USERNAME}@example.com"

echo -e "\n📌 Обновляем профиль пользователя (username и email)"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT http://localhost:8000/users/profile/update \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "new_username": "'"$NEW_USERNAME"'",
    "new_email": "'"$NEW_EMAIL"'"
  }')
validate_response "$response" "200" "Обновление профиля" \
    'jq -e ".message == \"Profile updated successfully\""' \
    "Неверный формат ответа при обновлении профиля"
echo -e "\n"

# === Итоговая статистика ===
echo -e "\n=== Итоги тестирования ==="
echo "Всего тестов: $TOTAL_TESTS"
echo "Провалено тестов: $FAILED_TESTS"
echo "Успешных тестов: $((TOTAL_TESTS - FAILED_TESTS))"
[[ $FAILED_TESTS -gt 0 ]] && exit 1 || exit 0
