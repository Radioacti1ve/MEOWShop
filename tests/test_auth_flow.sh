#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BLUE='\033[0;34m'

# Функция для проверки условия
assert() {
    if [ $1 -eq $2 ]; then
        echo -e "${GREEN}✓ Тест пройден: $3${NC}"
    else
        echo -e "${RED}✗ Тест провален: $3 (ожидалось $2, получено $1)${NC}"
        exit 1
    fi
}

API_URL="http://localhost:8000/auth"

echo -e "\n${BLUE}1. Тестирование авторизации админа${NC}"
echo "Попытка входа с правильными данными..."
ADMIN_LOGIN_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin", "password": "hashed_admin_password"}')

HTTP_CODE=${ADMIN_LOGIN_RESPONSE: -3}
RESPONSE_BODY=${ADMIN_LOGIN_RESPONSE:0:${#ADMIN_LOGIN_RESPONSE}-3}

assert $HTTP_CODE 200 "Авторизация админа"

# Сохраняем токены
ADMIN_TOKEN=$(echo $RESPONSE_BODY | jq -r '.access_token')
echo "Получен токен админа"

echo -e "\n${BLUE}2. Тестирование неправильной авторизации${NC}"
INVALID_LOGIN_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin", "password": "wrong_password"}')

HTTP_CODE=${INVALID_LOGIN_RESPONSE: -3}
assert $HTTP_CODE 401 "Неправильный пароль"

echo -e "\n${BLUE}3. Тестирование регистрации продавца${NC}"
SELLER_REGISTER_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/sellers/register" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "test_shop_1",
        "email": "test.shop1@example.com",
        "password": "test_password",
        "company_name": "Test Shop One LLC",
        "contact_phone": "+7 999 111 22 33",
        "tax_number": "1234567891",
        "documents_url": "https://example.com/docs/test_shop_1"
    }')

HTTP_CODE=${SELLER_REGISTER_RESPONSE: -3}
RESPONSE_BODY=${SELLER_REGISTER_RESPONSE:0:${#SELLER_REGISTER_RESPONSE}-3}

assert $HTTP_CODE 201 "Регистрация продавца"

# Сохраняем ID заявки
PENDING_SELLER_ID=$(echo $RESPONSE_BODY | jq -r '.pending_seller_id')
echo "ID заявки продавца: $PENDING_SELLER_ID"

echo -e "\n${BLUE}4. Проверка списка заявок через админа${NC}"
PENDING_LIST_RESPONSE=$(curl -s -w "%{http_code}" -X GET "$API_URL/sellers/pending" \
    -H "Authorization: Bearer $ADMIN_TOKEN")

HTTP_CODE=${PENDING_LIST_RESPONSE: -3}
assert $HTTP_CODE 200 "Получение списка заявок"

echo -e "\n${BLUE}5. Одобрение заявки продавца${NC}"
APPROVE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/sellers/$PENDING_SELLER_ID/approve" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "status": "approved",
        "admin_comment": "Документы проверены"
    }')

HTTP_CODE=${APPROVE_RESPONSE: -3}
RESPONSE_BODY=${APPROVE_RESPONSE:0:${#APPROVE_RESPONSE}-3}

assert $HTTP_CODE 200 "Одобрение заявки"
APPROVED_STATUS=$(echo $RESPONSE_BODY | jq -r '.status')
[ "$APPROVED_STATUS" == "approved" ] && \
    echo -e "${GREEN}✓ Статус заявки корректно обновлен на 'approved'${NC}" || \
    (echo -e "${RED}✗ Неправильный статус заявки: $APPROVED_STATUS${NC}" && exit 1)

echo -e "\n${BLUE}6. Проверка авторизации нового продавца${NC}"
SELLER_LOGIN_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/login" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "test_shop_1",
        "password": "test_password"
    }')

HTTP_CODE=${SELLER_LOGIN_RESPONSE: -3}
RESPONSE_BODY=${SELLER_LOGIN_RESPONSE:0:${#SELLER_LOGIN_RESPONSE}-3}

assert $HTTP_CODE 200 "Авторизация продавца"
SELLER_TOKEN=$(echo $RESPONSE_BODY | jq -r '.access_token')

echo -e "\n${BLUE}7. Проверка роли продавца${NC}"
SELLER_INFO_RESPONSE=$(curl -s -w "%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $SELLER_TOKEN")

HTTP_CODE=${SELLER_INFO_RESPONSE: -3}
RESPONSE_BODY=${SELLER_INFO_RESPONSE:0:${#SELLER_INFO_RESPONSE}-3}

assert $HTTP_CODE 200 "Получение информации о продавце"
SELLER_ROLE=$(echo $RESPONSE_BODY | jq -r '.role')
[ "$SELLER_ROLE" == "seller" ] && \
    echo -e "${GREEN}✓ Роль пользователя корректно установлена как 'seller'${NC}" || \
    (echo -e "${RED}✗ Неправильная роль пользователя: $SELLER_ROLE${NC}" && exit 1)

echo -e "\n${BLUE}8. Тест обновления токена${NC}"
REFRESH_TOKEN=$(echo $SELLER_LOGIN_RESPONSE | jq -r '.refresh_token')
REFRESH_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/refresh" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")

HTTP_CODE=${REFRESH_RESPONSE: -3}
assert $HTTP_CODE 200 "Обновление токена"

echo -e "\n${BLUE}9. Тест выхода и черного списка токенов${NC}"
LOGOUT_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API_URL/logout" \
    -H "Authorization: Bearer $SELLER_TOKEN")

HTTP_CODE=${LOGOUT_RESPONSE: -3}
assert $HTTP_CODE 200 "Выход из системы"

# Пробуем использовать токен после выхода
BLACKLIST_TEST_RESPONSE=$(curl -s -w "%{http_code}" -X GET "$API_URL/me" \
    -H "Authorization: Bearer $SELLER_TOKEN")

HTTP_CODE=${BLACKLIST_TEST_RESPONSE: -3}
assert $HTTP_CODE 401 "Токен в черном списке"

echo -e "\n${GREEN}Все тесты успешно пройдены!${NC}" 