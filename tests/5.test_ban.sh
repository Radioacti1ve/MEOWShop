#!/bin/bash

# Отключаем set -e, будем обрабатывать ошибки вручную
# set -e

# Включаем отладку
# set -x

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Счетчики тестов
TOTAL_TESTS=6
PASSED_TESTS=0
declare -a FAILED_TESTS=()

check_status() {
    local response="$1"
    local expected_status="${2:-200}"
    local http_code=$(echo "$response" | grep -oP 'HTTP_CODE:\K[0-9]+' || echo "unknown")
    
    if [[ "$http_code" == "$expected_status" ]]; then
        echo -e "${GREEN}✓ HTTP статус верный: $http_code${NC}"
        return 0
    else
        echo -e "${RED}✗ Неверный HTTP статус: $http_code (ожидался: $expected_status)${NC}"
        return 1
    fi
}

get_response_body() {
    local response="$1"
    echo "$response" | sed '$ d' || echo "$response"  # Возвращаем оригинальный ответ в случае ошибки
}

log_test_result() {
    local test_name="$1"
    if [[ $2 -eq 0 ]]; then
        ((PASSED_TESTS++))
    else
        FAILED_TESTS+=("$test_name")
    fi
}

# База данных
PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

# Тестовые данные
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="hashed_admin_password"
BANNED_USERNAME="ekaterina_smirnova"
BANNED_PASSWORD="hashed_password_2"

echo -e "\n🔍 Тестирование функционала бана/разбана пользователей..."

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
    -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}" \
    -w "\nHTTP_CODE:%{http_code}")

RESPONSE_BODY=$(get_response_body "$PRE_BAN_LOGIN")
echo "Ответ на вход до бана:"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

TEST_RESULT=0
if ! check_status "$PRE_BAN_LOGIN" "200"; then
    TEST_RESULT=1
fi

ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token' || echo "")
if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
    echo -e "${RED}✗ Не получен валидный токен доступа${NC}"
    TEST_RESULT=1
else
    echo -e "${GREEN}✓ Получен валидный токен доступа${NC}"
fi
log_test_result "pre-ban-login" $TEST_RESULT

# 2. Авторизуемся как админ
echo -e "\n2️⃣ Авторизуемся как админ..."
ADMIN_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" \
    -w "\nHTTP_CODE:%{http_code}")

RESPONSE_BODY=$(get_response_body "$ADMIN_LOGIN")
echo "Ответ на вход админа:"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

TEST_RESULT=0
if ! check_status "$ADMIN_LOGIN" "200"; then
    TEST_RESULT=1
fi

ADMIN_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token' || echo "")
if [[ "$ADMIN_TOKEN" == "null" || -z "$ADMIN_TOKEN" ]]; then
    echo -e "${RED}✗ Не получен валидный токен доступа для админа${NC}"
    TEST_RESULT=1
else
    echo -e "${GREEN}✓ Админ успешно авторизован${NC}"
fi
log_test_result "admin-login" $TEST_RESULT

# 3. Баним пользователя
echo -e "\n3️⃣ Баним пользователя $BANNED_USERNAME (user_id=$BANNED_USER_ID)..."
BAN_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/ban/$BANNED_USER_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -w "\nHTTP_CODE:%{http_code}")

RESPONSE_BODY=$(get_response_body "$BAN_RESPONSE")
echo "Ответ на бан:"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

TEST_RESULT=0
if ! check_status "$BAN_RESPONSE" "200"; then
    TEST_RESULT=1
fi

BAN_MESSAGE=$(echo "$RESPONSE_BODY" | jq -r '.message' || echo "")
if [[ "$BAN_MESSAGE" != *"banned successfully"* ]]; then
    echo -e "${RED}✗ Неверный ответ на бан пользователя${NC}"
    TEST_RESULT=1
else
    echo -e "${GREEN}✓ Пользователь успешно забанен${NC}"
fi
log_test_result "ban-user" $TEST_RESULT

# 4. Проверяем, что забаненный пользователь не может войти
echo -e "\n4️⃣ Проверяем, что забаненный пользователь не может войти..."
BANNED_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}" \
    -w "\nHTTP_CODE:%{http_code}")

RESPONSE_BODY=$(get_response_body "$BANNED_LOGIN")
echo "Ответ на попытку входа забаненного пользователя:"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

TEST_RESULT=0
if ! check_status "$BANNED_LOGIN" "403"; then
    TEST_RESULT=1
fi

BANNED_MESSAGE=$(echo "$RESPONSE_BODY" | jq -r '.detail' || echo "")
if [[ "$BANNED_MESSAGE" != "User is banned" ]]; then
    echo -e "${RED}✗ Неверное сообщение для забаненного пользователя${NC}"
    TEST_RESULT=1
else
    echo -e "${GREEN}✓ Забаненный пользователь не может войти${NC}"
fi
log_test_result "banned-login" $TEST_RESULT

# 5. Разбаниваем пользователя
echo -e "\n5️⃣ Разбаниваем пользователя..."
UNBAN_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/unban/$BANNED_USER_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -w "\nHTTP_CODE:%{http_code}")

RESPONSE_BODY=$(get_response_body "$UNBAN_RESPONSE")
echo "Ответ на разбан:"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

TEST_RESULT=0
if ! check_status "$UNBAN_RESPONSE" "200"; then
    TEST_RESULT=1
fi

UNBAN_MESSAGE=$(echo "$RESPONSE_BODY" | jq -r '.message' || echo "")
if [[ "$UNBAN_MESSAGE" != *"unbanned successfully"* ]]; then
    echo -e "${RED}✗ Неверный ответ на разбан пользователя${NC}"
    TEST_RESULT=1
else
    echo -e "${GREEN}✓ Пользователь успешно разбанен${NC}"
fi
log_test_result "unban-user" $TEST_RESULT

# 6. Проверяем, что разбаненный пользователь может войти
echo -e "\n6️⃣ Проверяем, что разбаненный пользователь может войти..."
POST_UNBAN_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$BANNED_USERNAME\",\"password\":\"$BANNED_PASSWORD\"}" \
    -w "\nHTTP_CODE:%{http_code}")

RESPONSE_BODY=$(get_response_body "$POST_UNBAN_LOGIN")
echo "Ответ после разбана:"
echo "$RESPONSE_BODY" | jq '.' || echo "$RESPONSE_BODY"

TEST_RESULT=0
if ! check_status "$POST_UNBAN_LOGIN" "200"; then
    TEST_RESULT=1
fi

ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token' || echo "")
if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
    echo -e "${RED}✗ Не получен валидный токен доступа после разбана${NC}"
    TEST_RESULT=1
else
    echo -e "${GREEN}✓ Пользователь успешно вошел после разбана${NC}"
fi
log_test_result "post-unban-login" $TEST_RESULT

# Выводим итоги
echo -e "\n=== Итоги тестирования ==="
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Все тесты ($PASSED_TESTS из $TOTAL_TESTS) успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}❌ Провалено ${#FAILED_TESTS[@]} из $TOTAL_TESTS тестов${NC}"
    echo -e "${RED}Проваленные тесты: ${FAILED_TESTS[*]}${NC}"
    exit 1
fi
