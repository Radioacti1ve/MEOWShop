#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Счетчики тестов
TOTAL_TESTS=10
PASSED_TESTS=0
declare -a FAILED_TESTS

# Функция для регистрации результата теста
log_test_result() {
    local test_name="$1"
    local result="$2"
    
    if [ "$result" = "pass" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓ Тест пройден: $test_name${NC}"
    else
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗ Тест не пройден: $test_name${NC}"
    fi
}

# Функция для проверки HTTP статуса
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

# Функция для получения тела ответа
get_response_body() {
    echo "$1" | sed '/HTTP_CODE/d'
}

# Функция для проверки поля в JSON-ответе
check_json_field() {
    local response="$1"
    local field="$2"
    local expected_value="$3"
    local error_message="$4"
    
    local actual_value=$(echo "$response" | jq -r ".$field")
    if [[ "$actual_value" == "null" && "$expected_value" != "null" ]]; then
        echo -e "${RED}✗ Ошибка: Поле $field отсутствует или равно null${NC}"
        echo "Полученный ответ:"
        echo "$response" | jq .
        return 1
    elif [[ "$expected_value" != "null" && "$actual_value" != "$expected_value" ]]; then
        echo -e "${RED}✗ Ошибка: $error_message${NC}"
        echo "Ожидалось: $expected_value"
        echo "Получено: $actual_value"
        return 1
    fi
    echo -e "${GREEN}✓ Поле $field корректно${NC}"
    return 0
}

# Функция для проверки токена
check_token() {
    local token="$1"
    local token_name="$2"
    
    if [[ "$token" == "null" || -z "$token" ]]; then
        echo -e "${RED}✗ Не получен $token_name${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Получен $token_name${NC}"
    return 0
}

# Конфигурация теста
API_URL="http://localhost:8000/auth"
TIMESTAMP=$(date +%s)
USERNAME="testuser_${TIMESTAMP}"
EMAIL="test_${TIMESTAMP}@example.com"
PASSWORD="TestPassword123!"

echo -e "${BLUE}🔐 Начинаем тестирование базовой авторизации...${NC}"
echo -e "${BLUE}📝 Тестовый пользователь:${NC}"
echo "Username: $USERNAME"
echo "Email: $EMAIL"
echo -e "Password: $PASSWORD\n"

# Функция очистки
cleanup() {
    echo -e "\n${BLUE}🧹 Очистка тестовых данных...${NC}"
    if [[ -n "$ACCESS_TOKEN" ]]; then
        echo "Выход из системы и очистка токена..."
        curl -s -X POST "$API_URL/logout" \
            -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
    fi
    
    if [[ -n "$NEW_ACCESS_TOKEN" ]]; then
        echo "Очистка обновленного токена..."
        curl -s -X POST "$API_URL/logout" \
            -H "Authorization: Bearer $NEW_ACCESS_TOKEN" > /dev/null
    fi
}

# Регистрируем cleanup для выполнения при выходе
trap cleanup EXIT

echo -e "\n${BLUE}1️⃣ Тестирование регистрации...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"$USERNAME\",
        \"email\": \"$EMAIL\",
        \"password\": \"$PASSWORD\"
    }")

# Проверка 1: Регистрация нового пользователя
if check_status "$response" "201"; then
    log_test_result "Регистрация пользователя" "pass"
else
    log_test_result "Регистрация пользователя" "fail"
fi

# Получаем и проверяем тело ответа
RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Проверка 2: Проверка user_id
USER_ID=$(echo "$RESPONSE_BODY" | jq -r '.user_id')
if [[ "$USER_ID" != "null" && -n "$USER_ID" ]]; then
    log_test_result "Получение user_id" "pass"
else
    log_test_result "Получение user_id" "fail"
fi

# Проверка 3: Сообщение о регистрации
if check_json_field "$RESPONSE_BODY" "message" "User created successfully" "Неверное сообщение о регистрации"; then
    log_test_result "Проверка сообщения о регистрации" "pass"
else
    log_test_result "Проверка сообщения о регистрации" "fail"
fi

echo -e "\n${BLUE}2️⃣ Тестирование входа в систему...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"username\": \"$USERNAME\",
        \"password\": \"$PASSWORD\"
    }")

# Проверка 4: Вход в систему
if check_status "$response"; then
    log_test_result "Вход в систему" "pass"
else
    log_test_result "Вход в систему" "fail"
    exit 1
fi

RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Получаем токены
ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.refresh_token')

# Проверка 5: Проверка токенов
test_tokens_valid=true

if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]] || \
   ! echo "$ACCESS_TOKEN" | grep -q "^ey.*\..*\..*$"; then
    echo -e "${RED}✗ Неверный формат access token${NC}"
    test_tokens_valid=false
fi

if [[ "$REFRESH_TOKEN" == "null" || -z "$REFRESH_TOKEN" ]] || \
   ! echo "$REFRESH_TOKEN" | grep -q "^ey.*\..*\..*$"; then
    echo -e "${RED}✗ Неверный формат refresh token${NC}"
    test_tokens_valid=false
fi

if [[ "$(echo "$RESPONSE_BODY" | jq -r '.token_type')" != "bearer" ]]; then
    echo -e "${RED}✗ Неверный тип токена${NC}"
    test_tokens_valid=false
fi

if [ "$test_tokens_valid" = true ]; then
    log_test_result "Проверка токенов" "pass"
else
    log_test_result "Проверка токенов" "fail"
fi

# Проверка 6: Получение информации о пользователе
echo -e "\n${BLUE}3️⃣ Тестирование получения информации о пользователе...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

if check_status "$response"; then
    log_test_result "Получение информации о пользователе" "pass"
else
    log_test_result "Получение информации о пользователе" "fail"
fi

# Проверка 7: Обновление токена
echo -e "\n${BLUE}4️⃣ Тестирование обновления токена...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/refresh" \
    -H "Content-Type: application/json" \
    -d "{
        \"refresh_token\": \"$REFRESH_TOKEN\"
    }")

if check_status "$response"; then
    log_test_result "Обновление токена" "pass"
else
    log_test_result "Обновление токена" "fail"
fi

# Проверка 8: Проверка нового токена
RESPONSE_BODY=$(get_response_body "$response")
NEW_ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')

echo -e "\n${BLUE}5️⃣ Проверка нового access_token...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $NEW_ACCESS_TOKEN")

if check_status "$response"; then
    log_test_result "Проверка нового токена" "pass"
else
    log_test_result "Проверка нового токена" "fail"
fi

# Проверка 9: Выход из системы
echo -e "\n${BLUE}6️⃣ Тестирование выхода из системы...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$API_URL/logout" \
    -H "Authorization: Bearer $NEW_ACCESS_TOKEN")

if check_status "$response"; then
    log_test_result "Выход из системы" "pass"
else
    log_test_result "Выход из системы" "fail"
fi

# Проверка 10: Проверка черного списка
echo -e "\n${BLUE}Проверка, что токен в черном списке...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $NEW_ACCESS_TOKEN")

if check_status "$response" "401"; then
    log_test_result "Проверка черного списка" "pass"
else
    log_test_result "Проверка черного списка" "fail"
fi

# Итоговая статистика
echo -e "\n${BLUE}=== Итоги тестирования ===${NC}"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}✅ Все тесты ($PASSED_TESTS из $TOTAL_TESTS) успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}❌ Пройдено только $PASSED_TESTS из $TOTAL_TESTS тестов${NC}"
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo -e "\n${RED}Не пройденные тесты:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "${RED}  - $test${NC}"
        done
    fi
    exit 1
fi
