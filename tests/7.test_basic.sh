#!/bin/bash

echo "1. Все товары, без фильтров и сортировки"
curl "http://localhost:8000/catalog/products" | jq
echo -e "\n----------------------------\n"

echo "2. Фильтр по категории 'Одежда'"
curl "http://localhost:8000/catalog/products?category=%D0%9E%D0%B4%D0%B5%D0%B6%D0%B4%D0%B0" | jq
echo -e "\n----------------------------\n"

echo "3. Фильтр по минимальной цене (от 1000)"
curl "http://localhost:8000/catalog/products?min_price=1000" | jq
echo -e "\n----------------------------\n"

echo "4. Фильтр по максимальной цене (до 5000)"
curl "http://localhost:8000/catalog/products?max_price=5000" | jq
echo -e "\n----------------------------\n"

echo "5. Фильтр по диапазону цены (от 1000 до 5000)"
curl "http://localhost:8000/catalog/products?min_price=1000&max_price=5000" | jq
echo -e "\n----------------------------\n"

echo "6. Фильтр по наличию (только товары в наличии)"
curl "http://localhost:8000/catalog/products?in_stock=true" | jq
echo -e "\n----------------------------\n"

echo "7. Фильтр по отсутствию на складе"
curl "http://localhost:8000/catalog/products?in_stock=false" | jq
echo -e "\n----------------------------\n"

echo "8. Сортировка по цене по возрастанию"
curl "http://localhost:8000/catalog/products?sort_by=price_asc" | jq
echo -e "\n----------------------------\n"

echo "9. Сортировка по цене по убыванию"
curl "http://localhost:8000/catalog/products?sort_by=price_desc" | jq
echo -e "\n----------------------------\n"

echo "10. Сортировка по среднему рейтингу по возрастанию"
curl "http://localhost:8000/catalog/products?sort_by=rating_asc" | jq
echo -e "\n----------------------------\n"

echo "11. Сортировка по среднему рейтингу по убыванию"
curl "http://localhost:8000/catalog/products?sort_by=rating_desc" | jq
echo -e "\n----------------------------\n"

echo "12. Категория=Одежда, цена от 1000 до 5000, в наличии, сортировка по рейтингу по убыванию"
curl "http://localhost:8000/catalog/products?category=%D0%9E%D0%B4%D0%B5%D0%B6%D0%B4%D0%B0&min_price=1000&max_price=5000&in_stock=true&sort_by=rating_desc" | jq
echo -e "\n----------------------------\n"

echo "13. Категория=Электроника, нет в наличии, сортировка по цене по возрастанию"
curl "http://localhost:8000/catalog/products?category=%D0%AD%D0%BB%D0%B5%D0%BA%D1%82%D1%80%D0%BE%D0%BD%D0%B8%D0%BA%D0%B0&in_stock=false&sort_by=price_asc" | jq
echo -e "\n----------------------------\n"

echo "14. Параметры по умолчанию (без фильтров)"
curl "http://localhost:8000/catalog/products" | jq
echo -e "\n----------------------------\n"

echo "15. Все товары от продавца с seller id=3, отсортированные по убыванию рейтинга"
curl "http://localhost:8000/catalog/products?seller_id=3&in_stock=true&sort_by=rating_desc" | jq
echo -e "\n----------------------------\n"

echo "16. Проверка файла product.py"
curl http://localhost:8000/catalog/product/7 | jq
echo -e "\n----------------------------\n"

echo "17. Проверка файла comments.py"
curl -s "http://localhost:8000/catalog/products/1/comments" | jq
echo -e "\n----------------------------\n"

echo "18. Проверка файла comments.py (сортировка)"
curl -s "http://localhost:8000/catalog/products/3/comments?sort_by=rating&order=desc" | jq
echo -e "\n----------------------------\n"

echo "19. Проверка файла comments_by_user.py"
curl -s "http://localhost:8000/catalog/users/3/comments?sort_by=rating&order=asc" | jq
echo -e "\n----------------------------\n"

echo "20. Проверка вывода всех продавцов"
curl -s "http://localhost:8000/catalog/sellers/" | jq
echo -e "\n----------------------------\n"

echo "21. Проверка вывода всех категорий"
curl -s "http://localhost:8000/catalog/categories/" | jq
echo -e "\n----------------------------\n"

echo "22. Проверка в sellers_categories.py сортировки по рейтингу"
curl -s "http://localhost:8000/catalog/sellers/?sort_by=rating" | jq
echo -e "\n----------------------------\n"

echo "23. Проверка в sellers_categories.py сортировки по количеству продаж"
curl -s "http://localhost:8000/catalog/sellers/?sort_by=sales" | jq
echo -e "\n----------------------------\n"