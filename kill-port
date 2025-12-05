#!/bin/bash
# ~/bin/kill-port.sh

if [ -z "$1" ]; then
    echo "Usage: kill-port <port_number>"
    exit 1
fi
PORT=$1
echo "🔍 Looking for process on port $PORT..."
PID=$(lsof -ti tcp:$PORT)
if [ -z "$PID" ]; then
    echo "✅ No process found on port $PORT"
    exit 0
fi
echo "💀 Killing process $PID on port $PORT..."
kill -9 $PID
echo "✅ Port $PORT is now free"
