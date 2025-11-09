#!/bin/bash

# Publish script for flutter_local_ai package
# This script validates and publishes the package to pub.dev

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting publish process for flutter_local_ai${NC}\n"

# Check if dart/flutter is installed
if ! command -v dart &> /dev/null && ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Error: Dart or Flutter is not installed${NC}"
    exit 1
fi

# Use flutter if available, otherwise dart
if command -v flutter &> /dev/null; then
    CMD="flutter"
    echo -e "${GREEN}✓ Using Flutter${NC}"
else
    CMD="dart"
    echo -e "${GREEN}✓ Using Dart${NC}"
fi

# Step 1: Get dependencies
echo -e "\n${YELLOW}Step 1: Getting dependencies...${NC}"
$CMD pub get
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to get dependencies${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Step 2: Run tests
echo -e "\n${YELLOW}Step 2: Running tests...${NC}"
$CMD test
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ All tests passed${NC}"

# Step 3: Analyze code
echo -e "\n${YELLOW}Step 3: Analyzing code...${NC}"
$CMD analyze
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Code analysis failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Code analysis passed${NC}"

# Step 4: Format code
echo -e "\n${YELLOW}Step 4: Formatting code...${NC}"
$CMD format --set-exit-if-changed .
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Code formatting check failed${NC}"
    echo -e "${YELLOW}Run 'dart format .' to fix formatting issues${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Code formatting check passed${NC}"

# Step 5: Dry run publish
echo -e "\n${YELLOW}Step 5: Running dry-run publish...${NC}"
$CMD pub publish --dry-run
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Dry-run publish failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dry-run publish successful${NC}"

# Step 6: Show package info
echo -e "\n${YELLOW}Package Information:${NC}"
echo -e "Name: $(grep '^name:' pubspec.yaml | sed 's/name: //')"
echo -e "Version: $(grep '^version:' pubspec.yaml | sed 's/version: //')"
echo -e "Description: $(grep '^description:' pubspec.yaml | sed 's/description: //')"

# Step 7: Confirm before publishing
echo -e "\n${YELLOW}⚠️  Ready to publish to pub.dev${NC}"
read -p "Do you want to continue with the actual publish? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Publish cancelled${NC}"
    exit 0
fi

# Step 8: Publish
echo -e "\n${YELLOW}Step 6: Publishing to pub.dev...${NC}"
$CMD pub publish
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Publish failed${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Package published successfully!${NC}"
echo -e "${GREEN}View your package at: https://pub.dev/packages/flutter_local_ai${NC}\n"
