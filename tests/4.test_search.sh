#!/bin/bash
set -e

BASE_URL="http://localhost:8000"

echo "1. Тестирование базового поиска..."
echo "Поиск товаров Xiaomi:"
curl -s -X GET -G "$BASE_URL/catalog/search/search" -d "q=xiaomi" | jq '.'
echo -e "\n----------------------------\n"

echo "2. Тестирование поиска с пагинацией..."
echo "Поиск устройств (должно вернуть смартфон и наушники):"
curl -s -X GET -G "$BASE_URL/catalog/search/search" --data-urlencode "q=смартфон наушники" -d "page=1" -d "page_size=2" | jq '.'
echo -e "\n----------------------------\n"

echo "3. Тестирование поиска по категории..."
echo "Поиск по категории 'Бытовая техника':"
curl -s -X GET -G "$BASE_URL/catalog/search/search" --data-urlencode "q=кофемашина пылесос" --data-urlencode "category_id=Бытовая техника" | jq '.'
echo -e "\n----------------------------\n"

echo "4. Тестирование автодополнения..."
echo "Получение подсказок для 'сма' (должен быть 'смартфон'):"
curl -s -X GET -G "$BASE_URL/catalog/search/suggest" --data-urlencode "q=сма" -d "limit=5" | jq '.'
echo -e "\n----------------------------\n"

echo "5. Тестирование похожих товаров..."
echo "Поиск похожих товаров для Xiaomi Redmi Note 11 (ID=1):"
curl -s -X GET "$BASE_URL/catalog/search/similar/1?limit=5" | jq '.'
echo -e "\n----------------------------\n"

echo "6. Тестирование поиска с несуществующим текстом..."
echo "Поиск несуществующего товара:"
curl -s -X GET -G "$BASE_URL/catalog/search/search" -d "q=abcdefghijklmnopqrstuvwxyz123456789" | jq '.'
echo -e "\n----------------------------\n"

echo "7. Тестирование автодополнения с коротким запросом..."
echo "Получение подсказок для 'пы':"
curl -s -X GET -G "$BASE_URL/catalog/search/suggest" --data-urlencode "q=пы" -d "limit=10" | jq '.'
echo -e "\n----------------------------\n"

echo "8. Тестирование поиска с спец. символами..."
echo "Поиск с специальными символами:"
curl -s -X GET -G "$BASE_URL/catalog/search/search" --data-urlencode "q=!@#$%^&*" | jq '.'
echo -e "\n----------------------------\n"

echo "9. Тестирование похожих товаров с несуществующим ID..."
echo "Поиск похожих товаров для несуществующего ID:"
curl -s -X GET "$BASE_URL/catalog/search/similar/999999?limit=5" | jq '.'
echo -e "\n----------------------------\n"

echo "10. Тестирование поиска в описании..."
echo "Поиск по слову 'мощный' (должен найти пылесос):"
curl -s -X GET -G "$BASE_URL/catalog/search/search" --data-urlencode "q=мощность" -d "page=1" -d "page_size=10" | jq '.'
echo -e "\n----------------------------\n"

# Добавим тесты на проверку ошибок
echo "11. Тестирование некорректных параметров пагинации..."
echo "Попытка использовать отрицательную страницу:"
curl -s -X GET -G "$BASE_URL/catalog/search/search" --data-urlencode "q=смартфон" -d "page=-1" | jq '.'
echo -e "\n----------------------------\n"

echo "12. Тестирование слишком большого размера страницы..."
echo "Попытка запросить слишком много результатов:"
curl -s -X GET -G "$BASE_URL/catalog/search/search" --data-urlencode "q=смартфон" -d "page_size=1000" | jq '.'
echo -e "\n----------------------------\n"

echo "13. Тестирование поиска без параметра q..."
echo "Попытка поиска без поискового запроса:"
curl -s -X GET "$BASE_URL/catalog/search/search" | jq '.'
echo -e "\n----------------------------\n"

echo "Тестирование поиска завершено."
