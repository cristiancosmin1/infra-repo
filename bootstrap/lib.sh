#!/usr/bin/env bash

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

pass() {
    printf "${GREEN}✔ %s${NC}\n" "$1"
}

fail() {
    printf "${RED}✘ %s${NC}\n" "$1"
}

warn() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
}
