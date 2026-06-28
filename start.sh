#!/bin/bash -e

cd /app/RoonServer
echo Starting version:
cat ./VERSION

echo
./check.sh

echo
ROON_DATAROOT=/data ./start.sh
