#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== PotatoHost: setup-and-start.sh ==="

# upewnij się, że start.sh jest wykonywalny
if [ -f "./start.sh" ]; then
  chmod +x ./start.sh
else
  echo "❌ start.sh nie znaleziony w repo. Upewnij się, że jest w katalogu głównym repo."
  exit 1
fi

# (opcjonalnie) zainstaluj podstawowe narzędzia, jeśli nie ma
if ! command -v jq >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y jq wget curl
fi

# --- Możesz ustawić wartości domyślne jako ENV (przekazywane przez secrety lub devcontainer settings)
RAM=${MINE_RAM:-2}      # domyślnie 2 GB (możesz nadpisać poprzez environment variable)
MINE_VERSION=${MINE_VERSION:-1.21.8}

echo "Ustawienia: VERSION=$MINE_VERSION RAM=${RAM}G"

# przygotuj `server` i uruchom start.sh w trybie nieinteraktywnym
# zakładamy że start.sh potrafi przyjąć flagi --version i --ram (jeśli nie - trzeba go dopracować)
# Jeśli Twój start.sh nie ma takich opcji, zmodyfikuj go lub zastąp poniższe polecenia odpowiednimi.
./start.sh <<EOF &
$MINE_VERSION
$RAM
EOF

# Alternatywa (jeśli start.sh nie obsługuje inputów): uruchom go w tle z 'nohup' i przekieruj logi
# nohup bash -c "./start.sh $MINE_VERSION $RAM" > mc-start.log 2>&1 &

echo "Server start triggered in background. Log: ./server/mc.log (jeśli start.sh zapisuje logi)"
exit 0
