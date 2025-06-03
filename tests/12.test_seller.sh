#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables for test tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function for tracking test results
track_test() {
    local name=$1
    local result=$2
    ((TESTS_TOTAL++))
    if [ "$result" = true ]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ $name${NC}"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗ $name${NC}"
        return 1
    fi
    return 0
}

print_test_summary() {
    echo -e "\n${BLUE}Test Summary:${NC}"
    echo -e "Total tests:    $TESTS_TOTAL"
    echo -e "${GREEN}Tests passed:   $TESTS_PASSED${NC}"
    echo -e "${RED}Tests failed:   $TESTS_FAILED${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests completed successfully!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

cleanup() {
    local fail_count=0
    echo -e "\n${BLUE}Cleaning up...${NC}"
    
    # First ban the seller (while admin token is still valid)
    if [ ! -z "$ADMIN_TOKEN" ] && [ ! -z "$USER_ID" ]; then
        local ban_response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/admin/ban/${USER_ID}" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}")
        local ban_code=$(echo "$ban_response" | tail -n1)
        local ban_body=$(echo "$ban_response" | head -n1)
        if [ "$ban_code" != "200" ]; then
            echo -e "${RED}Failed to ban test seller (code: $ban_code)${NC}"
            echo -e "${RED}Response: $ban_body${NC}"
            ((fail_count++))
        fi
    fi

    # Then revoke seller token
    if [ ! -z "$TOKEN" ]; then
        local response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/auth/logout" \
            -H "Authorization: Bearer ${TOKEN}")
        local code=$(echo "$response" | tail -n1)
        [ "$code" != "200" ] && ((fail_count++))
    fi
    
    # Finally revoke admin token
    if [ ! -z "$ADMIN_TOKEN" ]; then
        local response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/auth/logout" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}")
        local code=$(echo "$response" | tail -n1)
        [ "$code" != "200" ] && ((fail_count++))
    fi
    
    if [ $fail_count -eq 0 ]; then
        echo -e "${GREEN}✓ Cleanup completed successfully${NC}"
        return 0
    else
        echo -e "${RED}Warning: Some cleanup operations failed${NC}"
        return 1
    fi
}

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
echo -e "Request data: username=$TEST_USERNAME, email=$TEST_EMAIL"

REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/auth/sellers/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\":\"$TEST_USERNAME\",
    \"email\":\"$TEST_EMAIL\",
    \"password\":\"$TEST_PASSWORD\"
  }")

HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$REGISTER_RESPONSE" | head -n1)

echo -e "Response status: $HTTP_CODE"
echo -e "Response body: $RESPONSE_BODY"

if [ "$HTTP_CODE" != "201" ]; then
    ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.detail // .message // empty')
    if [ ! -z "$ERROR_MSG" ]; then
        echo -e "${RED}Error: $ERROR_MSG${NC}"
    fi
    track_test "Seller registration" false
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    echo -e "${RED}✗ Invalid JSON response${NC}"
    exit 1
fi

PENDING_SELLER_ID=$(echo "$RESPONSE_BODY" | jq -r '.pending_seller_id')
USER_ID=$(echo "$RESPONSE_BODY" | jq -r '.user_id')

if [ "$PENDING_SELLER_ID" = "null" ] || [ -z "$PENDING_SELLER_ID" ]; then
    echo -e "${RED}✗ No pending_seller_id in response${NC}"
    exit 1
fi

track_test "Seller registration" true
echo -e "${BLUE}Pending ID: $PENDING_SELLER_ID${NC}"
echo -e "${BLUE}User ID: $USER_ID${NC}"

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
    track_test "Seller approval" true
else
    track_test "Seller approval" false
    exit 1
fi

# 3. Seller login
echo -e "\n${BLUE}3. Seller logging in...${NC}"
LOGIN_RESPONSE=$(curl -s -X POST "${BASE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}")

TOKEN=$(echo $LOGIN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
    track_test "Seller login" false
    exit 1
else
    track_test "Seller login" true
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

if ! echo "$CREATE_PRODUCT_RESPONSE" | jq . >/dev/null 2>&1; then
    track_test "Product creation" false
    echo -e "${RED}✗ Invalid JSON response for product creation${NC}"
    exit 1
fi

PRODUCT_ID=$(echo "$CREATE_PRODUCT_RESPONSE" | jq -r '.product_id')
PRODUCT_STATUS=$(echo "$CREATE_PRODUCT_RESPONSE" | jq -r '.status')

if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" = "null" ]; then
    track_test "Product creation" false
    echo -e "${RED}✗ Product creation failed - missing product_id${NC}"
    exit 1
fi

if [ "$PRODUCT_STATUS" != "waiting" ]; then
    track_test "Product creation" false
    echo -e "${RED}✗ Product has incorrect status: $PRODUCT_STATUS (expected: waiting)${NC}"
    exit 1
fi

track_test "Product creation" true
echo -e "${BLUE}Created product ID: $PRODUCT_ID${NC}"

# 5. Get seller's products
echo -e "\n${BLUE}5. Getting seller's products...${NC}"
PRODUCTS_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/catalog/seller/products" \
  -H "Authorization: Bearer ${TOKEN}")

HTTP_CODE=$(echo "$PRODUCTS_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$PRODUCTS_RESPONSE" | head -n1)

if [ "$HTTP_CODE" != "200" ]; then
    track_test "Get products" false
    echo -e "${RED}✗ Failed to get products list. Status: $HTTP_CODE${NC}"
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    track_test "Get products" false
    echo -e "${RED}✗ Invalid JSON response for products list${NC}"
    exit 1
fi

# Verify our test product is in the list with correct status
FOUND_PRODUCT=$(echo "$RESPONSE_BODY" | jq -r ".[] | select(.product_id == $PRODUCT_ID)")
if [ -z "$FOUND_PRODUCT" ]; then
    track_test "Get products" false
    echo -e "${RED}✗ Created product not found in products list${NC}"
    exit 1
fi

PRODUCT_STATUS=$(echo "$FOUND_PRODUCT" | jq -r '.status')
if [ "$PRODUCT_STATUS" != "waiting" ]; then
    track_test "Get products" false
    echo -e "${RED}✗ Product has incorrect status: $PRODUCT_STATUS (expected: waiting)${NC}"
    exit 1
fi

track_test "Get products" true
echo -e "${BLUE}Found product: $(echo "$FOUND_PRODUCT" | jq -c .)${NC}"

# 6. Try to update product while in waiting status (should fail)
echo -e "\n${BLUE}6. Testing update restrictions for waiting products...${NC}"
UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "price": 89.99
  }')

HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$UPDATE_RESPONSE" | head -n1)

if [ "$HTTP_CODE" != "400" ]; then
    track_test "Update restriction" false
    echo -e "${RED}✗ Expected error 400 for waiting product update, got $HTTP_CODE${NC}"
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    track_test "Update restriction" false
    echo -e "${RED}✗ Invalid JSON error response${NC}"
    exit 1
fi

ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.detail // .message // empty')
if [[ ! "$ERROR_MSG" =~ .*waiting.* ]]; then
    track_test "Update restriction" false
    echo -e "${RED}✗ Expected error message about waiting status${NC}"
    echo -e "Got: $ERROR_MSG"
    exit 1
fi

track_test "Update restriction" true
echo -e "${BLUE}Got expected error: $ERROR_MSG${NC}"

# 7. Admin approves product
echo -e "\n${BLUE}7. Admin approving product...${NC}"
ADMIN_UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/admin/products/waiting/approve/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}")

HTTP_CODE=$(echo "$ADMIN_UPDATE_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$ADMIN_UPDATE_RESPONSE" | head -n1)

echo -e "Response code: $HTTP_CODE"
echo -e "Response body: $RESPONSE_BODY"

if [ "$HTTP_CODE" != "200" ]; then
    track_test "Admin product approval" false
    echo -e "${RED}✗ Failed to approve product. Status: $HTTP_CODE${NC}"
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    track_test "Admin product approval" false
    echo -e "${RED}✗ Invalid JSON response for product approval${NC}"
    exit 1
fi

track_test "Admin product approval" true

# 8. Update product after approval
echo -e "\n${BLUE}8. Updating approved product...${NC}"
UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "price": 89.99,
    "description": "An updated test product"
  }')

HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$UPDATE_RESPONSE" | head -n1)

if [ "$HTTP_CODE" != "200" ]; then
    track_test "Product update" false
    echo -e "${RED}✗ Failed to update product. Status: $HTTP_CODE${NC}"
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    track_test "Product update" false
    echo -e "${RED}✗ Invalid JSON response for product update${NC}"
    exit 1
fi

# Verify update was successful
UPDATED_PRICE=$(echo "$RESPONSE_BODY" | jq -r '.price')
UPDATED_DESC=$(echo "$RESPONSE_BODY" | jq -r '.description')

if [ "$UPDATED_PRICE" != "89.99" ] || [ "$UPDATED_DESC" != "An updated test product" ]; then
    track_test "Product update" false
    echo -e "${RED}✗ Product update verification failed${NC}"
    exit 1
fi

track_test "Product update" true

# 9. Delete product
echo -e "\n${BLUE}9. Deleting product...${NC}"
DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "${BASE_URL}/catalog/seller/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}")

HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$DELETE_RESPONSE" | head -n1)

if [ "$HTTP_CODE" != "200" ]; then
    track_test "Product deletion" false
    echo -e "${RED}✗ Failed to delete product. Status: $HTTP_CODE${NC}"
    echo -e "Response body: $RESPONSE_BODY"
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    track_test "Product deletion" false
    echo -e "${RED}✗ Invalid JSON response for product deletion${NC}"
    exit 1
fi

track_test "Product deletion" true

# 10. Verify product deletion
echo -e "\n${BLUE}10. Verifying product deletion...${NC}"
VERIFY_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${BASE_URL}/catalog/seller/products" \
  -H "Authorization: Bearer ${TOKEN}")

HTTP_CODE=$(echo "$VERIFY_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$VERIFY_RESPONSE" | head -n1)

if [ "$HTTP_CODE" != "200" ]; then
    track_test "Product deletion verification" false
    echo -e "${RED}✗ Failed to get products list. Status: $HTTP_CODE${NC}"
    echo -e "Response body: $RESPONSE_BODY"
    exit 1
fi

if ! echo "$RESPONSE_BODY" | jq . >/dev/null 2>&1; then
    track_test "Product deletion verification" false
    echo -e "${RED}✗ Invalid JSON response for products list${NC}"
    exit 1
fi

# Check that the deleted product is not in the list
FOUND_PRODUCT=$(echo "$RESPONSE_BODY" | jq -r ".[] | select(.product_id == $PRODUCT_ID)")
if [ ! -z "$FOUND_PRODUCT" ]; then
    track_test "Product deletion verification" false
    echo -e "${RED}✗ Product still exists in seller's products list${NC}"
    echo -e "Found product: $FOUND_PRODUCT"
    exit 1
fi

track_test "Product deletion verification" true

# Print final test summary
print_test_summary

# Call cleanup function (registered with trap)
cleanup
exit $?