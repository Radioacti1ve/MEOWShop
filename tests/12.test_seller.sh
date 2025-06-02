#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base URL and test user credentials
BASE_URL=${API_URL:-http://localhost:8000}
TEST_EMAIL="seller_test@example.com"
TEST_PASSWORD="test_password"
TEST_USERNAME="seller_test"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="hashed_admin_password"

echo -e "${BLUE}Testing Seller Functionality...${NC}"

# 1. Register test seller
echo -e "\n${BLUE}1. Registering test seller...${NC}"
REGISTER_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/sellers/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\":\"$TEST_USERNAME\",
    \"email\":\"$TEST_EMAIL\",
    \"password\":\"$TEST_PASSWORD\"
  }")

PENDING_SELLER_ID=$(echo $REGISTER_RESPONSE | grep -o '"pending_seller_id":[0-9]*' | cut -d':' -f2)
if [ -z "$PENDING_SELLER_ID" ]; then
    echo -e "${RED}✗ Seller registration failed${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Seller registration successful. Pending ID: $PENDING_SELLER_ID${NC}"
fi

# 2. Admin approves seller application
echo -e "\n${BLUE}2. Admin approving seller application...${NC}"
# First get admin token
ADMIN_TOKEN=$(curl -s -X POST "${BASE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$ADMIN_TOKEN" ]; then
    echo -e "${RED}✗ Admin login failed${NC}"
    exit 1
fi

# Approve seller application
APPROVE_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/sellers/${PENDING_SELLER_ID}/approve" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "approved",
    "admin_comment": "Test seller approved"
  }')

if [[ $APPROVE_RESPONSE == *"approved"* ]]; then
    echo -e "${GREEN}✓ Seller application approved${NC}"
else
    echo -e "${RED}✗ Failed to approve seller application${NC}"
    exit 1
fi

# 3. Seller login
echo -e "\n${BLUE}3. Seller logging in...${NC}"
LOGIN_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}")

TOKEN=$(echo $LOGIN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
    echo -e "${RED}✗ Seller login failed${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Seller login successful${NC}"
fi

# 4. Create new product (status: waiting)
echo -e "\n${BLUE}4. Creating new product...${NC}"
CREATE_PRODUCT_RESPONSE=$(curl -s -X POST "${BASE_URL}/catalog/seller/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "product_name": "Test Product",
    "description": "A high-quality test product",
    "category": "Test Category",
    "price": 99.99,
    "in_stock": 100
  }')

PRODUCT_ID=$(echo $CREATE_PRODUCT_RESPONSE | grep -o '"product_id":[0-9]*' | cut -d':' -f2)
if [ -z "$PRODUCT_ID" ]; then
    echo -e "${RED}✗ Product creation failed${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Product created successfully with ID: $PRODUCT_ID${NC}"
fi

# 5. Get seller's products
echo -e "\n${BLUE}5. Getting seller's products...${NC}"
PRODUCTS_RESPONSE=$(curl -s -X GET "${BASE_URL}/catalog/seller/products" \
  -H "Authorization: Bearer ${TOKEN}")

if [[ $PRODUCTS_RESPONSE == *"Test Product"* ]] && [[ $PRODUCTS_RESPONSE == *"waiting"* ]]; then
    echo -e "${GREEN}✓ Products list retrieved successfully with correct status${NC}"
else
    echo -e "${RED}✗ Failed to retrieve products list or incorrect product status${NC}"
    exit 1
fi

# 6. Try to update product while in waiting status (should fail)
echo -e "\n${BLUE}6. Testing update restrictions for waiting products...${NC}"
UPDATE_RESPONSE=$(curl -s -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "price": 89.99
  }')

if [[ $UPDATE_RESPONSE == *"Cannot update product with 'waiting' status"* ]]; then
    echo -e "${GREEN}✓ Update restriction working correctly${NC}"
else
    echo -e "${RED}✗ Update restriction test failed${NC}"
    exit 1
fi

# 7. Admin approves product (changes status to available)
echo -e "\n${BLUE}7. Admin approving product...${NC}"
ADMIN_UPDATE_RESPONSE=$(curl -s -X PATCH "${BASE_URL}/catalog/admin/products/${PRODUCT_ID}/status" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "available"
  }')

if [[ $ADMIN_UPDATE_RESPONSE == *"available"* ]]; then
    echo -e "${GREEN}✓ Product status updated to available${NC}"
else
    echo -e "${RED}✗ Failed to update product status${NC}"
    exit 1
fi

# 8. Update product after approval
echo -e "\n${BLUE}8. Updating approved product...${NC}"
UPDATE_RESPONSE=$(curl -s -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "price": 89.99,
    "description": "Updated test product description"
  }')

if [[ $UPDATE_RESPONSE == *"89.99"* ]] && [[ $UPDATE_RESPONSE == *"Updated test product description"* ]]; then
    echo -e "${GREEN}✓ Product updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to update product${NC}"
    exit 1
fi

# 9. Change product status to out_of_stock
echo -e "\n${BLUE}9. Changing product status to out_of_stock...${NC}"
STATUS_UPDATE_RESPONSE=$(curl -s -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}/status" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "out_of_stock"
  }')

if [[ $STATUS_UPDATE_RESPONSE == *"out_of_stock"* ]]; then
    echo -e "${GREEN}✓ Product status updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to update product status${NC}"
    exit 1
fi

# 10. Delete product
echo -e "\n${BLUE}10. Deleting product...${NC}"
DELETE_RESPONSE=$(curl -s -X DELETE "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}")

if [[ $DELETE_RESPONSE == *"success"* ]]; then
    echo -e "${GREEN}✓ Product deleted successfully${NC}"
else
    echo -e "${RED}✗ Failed to delete product${NC}"
    exit 1
fi

# 11. Verify product was deleted
echo -e "\n${BLUE}11. Verifying product deletion...${NC}"
VERIFY_DELETE=$(curl -s -X GET "${BASE_URL}/catalog/seller/products" \
  -H "Authorization: Bearer ${TOKEN}")

if [[ $VERIFY_DELETE == *"$PRODUCT_ID"* ]]; then
    echo -e "${RED}✗ Product still exists after deletion${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Product deletion verified${NC}"
fi

# Clean up test data
echo -e "\n${BLUE}Cleaning up test data...${NC}"
# Delete test seller (admin only)
CLEANUP_RESPONSE=$(curl -s -X DELETE "${BASE_URL}/auth/sellers/${PENDING_SELLER_ID}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}")

echo -e "${GREEN}Test completed successfully!${NC}"

echo "6. Updating product (this should fail while status is waiting)..."
UPDATE_RESPONSE=$(curl -s -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "product_name": "Updated Test Product",
    "price": 150.00
  }')

if [[ $UPDATE_RESPONSE == *"waiting"* ]]; then
    echo -e "${GREEN}✓ Update correctly blocked for waiting product${NC}"
else
    echo -e "${RED}✗ Update protection for waiting products failed${NC}"
fi

# Попытка изменения статуса (должна быть заблокирована для waiting)
echo "7. Attempting to change product status (should fail while waiting)..."
STATUS_UPDATE_RESPONSE=$(curl -s -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}/status" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "out_of_stock"
  }')

if [[ $STATUS_UPDATE_RESPONSE == *"waiting"* ]]; then
    echo -e "${GREEN}✓ Status update correctly blocked for waiting product${NC}"
else
    echo -e "${RED}✗ Status update protection failed${NC}"
fi

# Удаление товара
echo "8. Deleting product..."
DELETE_RESPONSE=$(curl -s -X DELETE "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}")

if [[ $DELETE_RESPONSE == *"success"* ]]; then
    echo -e "${GREEN}✓ Product deleted successfully${NC}"
else
    echo -e "${RED}✗ Product deletion failed${NC}"
fi

# Очистка: удаление тестового пользователя
echo "9. Cleaning up test data..."
# Требуется авторизация админа для очистки
# (в реальном сценарии здесь должна быть авторизация админа и удаление тестового пользователя)

echo -e "${GREEN}All seller tests completed!${NC}"
