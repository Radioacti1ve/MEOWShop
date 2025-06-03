#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функции-помощники
check_status() {
    local response="$1"
    local expected_status="${2:-200}"
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ HTTP статус верный: $http_code${NC}"
        return 0
    else
        echo -e "${RED}✗ Неверный HTTP статус: $http_code (ожидался: $expected_status)${NC}"
        return 1
    fi
}

get_response_body() {
    echo "$1" | sed '/HTTP_CODE/d'
}

check_json_field() {
    local json="$1"
    local field="$2"
    local expected_value="$3"
    local actual_value=$(echo "$json" | jq -r ".$field")
    
    if [ "$actual_value" = "$expected_value" ]; then
        echo -e "${GREEN}✓ Поле $field имеет ожидаемое значение: $actual_value${NC}"
        return 0
    else
        echo -e "${RED}✗ Поле $field имеет неверное значение: $actual_value (ожидалось: $expected_value)${NC}"
        return 1
    fi
}

assert() {
    if [ $1 -eq $2 ]; then
        echo -e "${GREEN}✓ Тест пройден: $3${NC}"
    else
        echo -e "${RED}✗ Тест провален: $3 (ожидалось $2, получено $1)${NC}"
        exit 1
    fi
}

# Счетчик тестов
TOTAL_TESTS=9
PASSED_TESTS=0

API_URL="http://localhost:8000/auth"

echo -e "\n${BLUE}🔐 Начинаем тестирование авторизации и управления ролями...${NC}"

echo -e "\n${BLUE}1️⃣ Тестирование авторизации админа${NC}"
echo "Попытка входа с правильными данными..."
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin", "password": "hashed_admin_password"}')

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

ADMIN_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
if [[ "$ADMIN_TOKEN" == "null" || -z "$ADMIN_TOKEN" ]]; then
    echo -e "${RED}✗ Не удалось получить токен доступа${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен токен доступа администратора${NC}"

# Проверяем тип токена и срок действия
TOKEN_TYPE=$(echo "$RESPONSE_BODY" | jq -r '.token_type')
if [[ "$TOKEN_TYPE" != "bearer" ]]; then
    echo -e "${RED}✗ Неверный тип токена: $TOKEN_TYPE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Тип токена корректный: $TOKEN_TYPE${NC}"

echo -e "\n${BLUE}2️⃣ Тестирование неправильной авторизации${NC}"
echo "Попытка входа с неверным паролем..."
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin", "password": "wrong_password"}')

# Проверяем что получили ошибку авторизации
if check_status "$response" "401"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Проверяем сообщение об ошибке
ERROR_DETAIL=$(echo "$RESPONSE_BODY" | jq -r '.detail')
if [[ "$ERROR_DETAIL" != *"Incorrect"* && "$ERROR_DETAIL" != *"некорректный"* ]]; then
    echo -e "${RED}✗ Неожиданное сообщение об ошибке: $ERROR_DETAIL${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получено корректное сообщение об ошибке${NC}"

echo -e "\n${BLUE}3️⃣ Тестирование регистрации продавца${NC}"
TIMESTAMP=$(date +%s)
SELLER_USERNAME="test_shop_$TIMESTAMP"
SELLER_EMAIL="test.shop$TIMESTAMP@example.com"

echo "Регистрация продавца с данными:"
echo "Username: $SELLER_USERNAME"
echo "Email: $SELLER_EMAIL"

response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/sellers/register" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "'$SELLER_USERNAME'",
        "email": "'$SELLER_EMAIL'",
        "password": "test_password"
    }')

if check_status "$response" "201"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Проверяем наличие и валидность pending_seller_id
PENDING_SELLER_ID=$(echo "$RESPONSE_BODY" | jq -r '.pending_seller_id')
if [[ "$PENDING_SELLER_ID" == "null" || -z "$PENDING_SELLER_ID" ]]; then
    echo -e "${RED}✗ Не удалось получить ID заявки продавца${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен ID заявки продавца: $PENDING_SELLER_ID${NC}"

# Проверяем начальный статус заявки
STATUS=$(echo "$RESPONSE_BODY" | jq -r '.status')
if [[ "$STATUS" != "pending" ]]; then
    echo -e "${RED}✗ Неверный начальный статус заявки: $STATUS (ожидался: pending)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Начальный статус заявки корректный: $STATUS${NC}"

echo -e "\n${BLUE}4️⃣ Проверка списка заявок через админа${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/sellers/pending" \
    -H "Authorization: Bearer $ADMIN_TOKEN")

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Список заявок: $RESPONSE_BODY"

# Проверяем наличие нашей заявки в списке
FOUND_APPLICATION=$(echo "$RESPONSE_BODY" | jq -r ".[] | select(.pending_seller_id==$PENDING_SELLER_ID)")
if [[ -z "$FOUND_APPLICATION" ]]; then
    echo -e "${RED}✗ Заявка продавца не найдена в списке${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Заявка найдена в списке ожидающих подтверждения${NC}"

# Проверяем статус заявки в списке
APP_STATUS=$(echo "$FOUND_APPLICATION" | jq -r '.status')
if [[ "$APP_STATUS" != "pending" ]]; then
    echo -e "${RED}✗ Неверный статус заявки в списке: $APP_STATUS${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Статус заявки в списке корректный: $APP_STATUS${NC}"

echo -e "\n${BLUE}5️⃣ Одобрение заявки продавца${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/sellers/$PENDING_SELLER_ID/approve" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "status": "approved",
        "admin_comment": "Документы проверены, заявка одобрена"
    }')

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Проверяем статус заявки после одобрения
APPROVED_STATUS=$(echo "$RESPONSE_BODY" | jq -r '.status')
if [[ "$APPROVED_STATUS" != "approved" ]]; then
    echo -e "${RED}✗ Неверный статус заявки после одобрения: $APPROVED_STATUS${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Статус заявки успешно обновлен на: $APPROVED_STATUS${NC}"

# Проверяем комментарий админа
ADMIN_COMMENT=$(echo "$RESPONSE_BODY" | jq -r '.admin_comment')
if [[ "$ADMIN_COMMENT" != "Документы проверены, заявка одобрена" ]]; then
    echo -e "${YELLOW}⚠️ Комментарий админа не соответствует отправленному${NC}"
fi
echo -e "${GREEN}✓ Комментарий админа сохранен: $ADMIN_COMMENT${NC}"

echo -e "\n${BLUE}6️⃣ Проверка авторизации нового продавца${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "'$SELLER_USERNAME'",
        "password": "test_password"
    }')

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Получаем и проверяем токены
SELLER_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.refresh_token')

if [[ "$SELLER_TOKEN" == "null" || -z "$SELLER_TOKEN" ]]; then
    echo -e "${RED}✗ Не удалось получить access token продавца${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен access token продавца${NC}"

if [[ "$REFRESH_TOKEN" == "null" || -z "$REFRESH_TOKEN" ]]; then
    echo -e "${RED}✗ Не удалось получить refresh token продавца${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен refresh token продавца${NC}"

echo -e "\n${BLUE}7️⃣ Проверка роли продавца${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $SELLER_TOKEN")

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Информация о пользователе: $RESPONSE_BODY"

# Проверяем роль и другие данные пользователя
SELLER_ROLE=$(echo "$RESPONSE_BODY" | jq -r '.role')
if [[ "$SELLER_ROLE" != "seller" ]]; then
    echo -e "${RED}✗ Неверная роль пользователя: $SELLER_ROLE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Роль пользователя корректно установлена как 'seller'${NC}"

echo -e "\n${BLUE}8️⃣ Тест обновления токена${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/refresh" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

NEW_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
if [[ "$NEW_TOKEN" == "null" || -z "$NEW_TOKEN" ]]; then
    echo -e "${RED}✗ Не получен новый токен${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен новый токен доступа${NC}"

# Проверяем тип токена
TOKEN_TYPE=$(echo "$RESPONSE_BODY" | jq -r '.token_type')
if [[ "$TOKEN_TYPE" != "bearer" ]]; then
    echo -e "${RED}✗ Неверный тип токена: $TOKEN_TYPE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Тип токена корректный: $TOKEN_TYPE${NC}"

echo -e "\n${BLUE}9️⃣ Тест выхода и проверка черного списка токенов${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/logout" \
    -H "Authorization: Bearer $SELLER_TOKEN")

if check_status "$response" "200"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Проверяем что старый токен действительно в черном списке
echo "Проверка токена в черном списке..."
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $SELLER_TOKEN")

if check_status "$response" "401"; then
    echo -e "${GREEN}✓ Токен успешно добавлен в черный список${NC}"
else
    echo -e "${RED}✗ Токен все еще активен после выхода${NC}"
    exit 1
fi

# Итоговая статистика
echo -e "\n${BLUE}=== Итоги тестирования ===${NC}"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}✅ Все тесты ($PASSED_TESTS из $TOTAL_TESTS) успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}❌ Пройдено только $PASSED_TESTS из $TOTAL_TESTS тестов${NC}"
    exit 1
fi

response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $SELLER_TOKEN")

HTTP_CODE=${response##*HTTP_CODE:}
assert $HTTP_CODE 401 "Токен в черном списке"

echo -e "\n${GREEN}Все тесты успешно пройдены!${NC}"