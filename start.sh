#!/usr/bin/env bash
set -euo pipefail

SRV_DIR="server"
CONF_FILE="$SRV_DIR/.mcserver.conf"
USER_AGENT="mc-server-setup/1.0 (https://example.invalid)"

log() { echo -e "$@"; }

# ====== Instalacja Javy 22 (z fallbackiem na Oracle .deb) ======
echo "🔍 Sprawdzanie Javy..."
if java -version 2>&1 | grep -q "22"; then
    echo "✅ Java 22 już jest zainstalowana."
else
    echo "⬇️ Instalacja Java 22 przez apt (openjdk-22-jdk)..."
    sudo apt update || true
    if sudo apt install -y openjdk-22-jdk >/dev/null 2>&1; then
        echo "✅ openjdk-22-jdk zainstalowane przez apt."
    else
        echo "⚠️ openjdk-22-jdk nie jest dostępne w apt. Spróbuję zainstalować Oracle JDK 22 (.deb)..."
        TMP_DEB="jdk22.deb"
        if wget -q --show-progress "https://download.oracle.com/java/22/archive/jdk-22_linux-x64_bin.deb" -O "$TMP_DEB"; then
            echo "⬇️ Pobrano jdk22.deb — instaluję..."
            sudo apt install -y ./"$TMP_DEB"
            rm -f "$TMP_DEB"
            if java -version 2>&1 | grep -q "22"; then
                echo "✅ Java 22 zainstalowana z paczki Oracle."
            else
                echo "❌ Po instalacji .deb Java 22 nadal nie wykryta."
            fi
        else
            echo "❌ Nie udało się pobrać Oracle JDK22 .deb automatycznie."
            echo "   Możesz zainstalować JDK22 ręcznie (Adoptium/Oracle) lub kontynuować z aktualną Javą."
            read -rp "Kontynuować mimo braku Java22 (użyć dostępnej Javy)? (y/n): " yn
            if [[ ! "$yn" =~ ^[Yy]$ ]]; then
                echo "Przerwanie. Zainstaluj Java22 ręcznie i uruchom ponownie."
                exit 1
            fi
        fi
    fi
fi

# 🔧 Ustawiam Java 22 jako domyślną jeśli istnieje katalog Oracle
if [ -d "/usr/lib/jvm/jdk-22-oracle-x64/bin" ]; then
    echo "🔧 Ustawiam Java 22 jako domyślną..."
    sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/jdk-22-oracle-x64/bin/java 9999
    sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/jdk-22-oracle-x64/bin/javac 9999
    sudo update-alternatives --set java /usr/lib/jvm/jdk-22-oracle-x64/bin/java
    sudo update-alternatives --set javac /usr/lib/jvm/jdk-22-oracle-x64/bin/javac
fi

# sprawdź jeszcze raz
java -version

# ====== Upewnij się, że jq jest dostępne (potrzebne do API) ======
if ! command -v jq >/dev/null 2>&1; then
  log "⬇️ Instaluję jq (potrzebne do pobierania wersji i serwera) ..."
  sudo apt update
  sudo apt install -y jq
fi

# ====== Przygotuj katalog serwera i plik konfiguracyjny (do pierwszego uruchomienia) ======
mkdir -p "$SRV_DIR"
cd "$SRV_DIR"

# funkcje porównania wersji (sort -V)
version_ge() {
  # zwraca 0 jeśli $1 >= $2
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$1" ]
}
version_le() {
  # zwraca 0 jeśli $1 <= $2
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

# ====== Pobierz najnowszą stabilną wersję Minecraft (Mojang manifest) ======
# (skrypt korzysta z launchermeta.mojang.com version_manifest.json)
LATEST_MC="$(curl -s -A "$USER_AGENT" "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r '.latest.release // empty')"
if [ -z "$LATEST_MC" ]; then
  echo "⚠️ Nie udało się pobrać najnowszej wersji Minecraft z Mojang. Ustawiam LATEST_MC na 999 (brak walidacji do góry)."
  LATEST_MC="999"
fi

# ====== Jeśli brak pliku konfiguracyjnego — zapytaj użytkownika (tylko pierwszy raz) ======
if [ -f "$CONF_FILE" ]; then
  # załaduj ustawienia
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  log "ℹ️ Wczytano ustawienia z $CONF_FILE: SILNIK=$ENGINE, WERSJA=$MC_VERSION"
else
  echo
  echo "🛠️ Konfiguracja serwera (wykonywane tylko teraz; zapisywane w $CONF_FILE)"
  echo
  # Silnik serwera — wybór
  PS3="Wybierz silnik serwera (podaj numer): "
  options=("PaperMC" "PurpurMC" "Forge" "NeoForge" "Fabric")
  select opt in "${options[@]}"; do
    if [[ -n "$opt" ]]; then
      ENGINE="$opt"
      break
    else
      echo "❌ Niepoprawny wybór. Wybierz numer z listy."
    fi
  done

  # Wersja Minecraft — walidacja: >=1.17 i <= LATEST_MC
  while true; do
    echo
    read -rp "🎮 Jaka wersja Minecraft? (np. 1.21 lub 1.21.7) — dozwolone: od 1.17 do $LATEST_MC: " MC_VERSION
    # prosty regex na format num.num(.num)
    if ! [[ "$MC_VERSION" =~ ^[0-9]+\.[0-9]+([.][0-9]+)?$ ]]; then
      echo "❌ Niepoprawny format wersji. Użyj np. 1.20 lub 1.20.1."
      continue
    fi
    if ! version_ge "$MC_VERSION" "1.17"; then
      echo "❌ Wersja musi być >= 1.17."
      continue
    fi
    if [ "$LATEST_MC" != "999" ]; then
      if ! version_le "$MC_VERSION" "$LATEST_MC"; then
        echo "❌ Wersja nie może być nowsza niż najnowsza stabilna ($LATEST_MC)."
        continue
      fi
    fi
    break
  done

  # zapisz ustawienia (żeby nie pytać przy następnym uruchomieniu)
  cat > "$CONF_FILE" <<EOF
ENGINE="$ENGINE"
MC_VERSION="$MC_VERSION"
EOF
  log "✅ Ustawienia zapisane do $CONF_FILE"
fi

# ====== Pobierz server.jar tylko jeśli nie ma ======
if [ -f server.jar ]; then
  log "📦 server.jar już istnieje — pomijam pobieranie."
else
  log "📥 Przygotowuję pobranie dla silnika: $ENGINE, wersja: $MC_VERSION"

  case "$ENGINE" in
    "PaperMC")
      log "🔗 Pobieram PaperMC $MC_VERSION..."
      # pobierz najnowszy build dla danej wersji
      LATEST_BUILD="$(curl -s -A "$USER_AGENT" "https://api.papermc.io/v2/projects/paper/versions/$MC_VERSION" | jq -r '.builds[-1] // empty')"
      if [ -z "$LATEST_BUILD" ]; then
        echo "❌ Nie udało się znaleźć buildu PaperMC dla wersji $MC_VERSION przez API."
        echo "   Sprawdź wersję i spróbuj ponownie."
        exit 1
      fi
      DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$MC_VERSION/builds/$LATEST_BUILD/downloads/paper-$MC_VERSION-$LATEST_BUILD.jar"
      log "🔗 Pobieram z: $DOWNLOAD_URL"
      if ! wget -q --show-progress --user-agent="$USER_AGENT" "$DOWNLOAD_URL" -O server.jar; then
        echo "❌ Pobieranie PaperMC nie powiodło się."
        exit 1
      fi
      log "✅ PaperMC $MC_VERSION (build $LATEST_BUILD) pobrany jako server.jar."
      ;;
    "PurpurMC")
      log "🔗 Pobieram Purpur $MC_VERSION..."
      # Purpur ma prosty endpoint do pobrania latest build per version
      DOWNLOAD_URL="https://api.purpurmc.org/v2/purpur/$MC_VERSION/latest/download"
      log "🔗 Pobieram z: $DOWNLOAD_URL"
      if ! wget -q --show-progress --user-agent="$USER_AGENT" "$DOWNLOAD_URL" -O server.jar; then
        echo "❌ Pobieranie Purpur nie powiodło się."
        exit 1
      fi
      log "✅ Purpur $MC_VERSION pobrany jako server.jar."
      ;;
    "Forge"|"NeoForge"|"Fabric")
      log "⚠️ Dla $ENGINE pobiorę VANILLA server.jar (Mojang)."
      # Pobierz URL servera z manifestu Mojang
      VERSION_URL="$(curl -s -A "$USER_AGENT" "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id==$v) | .url // empty')"
      if [ -z "$VERSION_URL" ]; then
        echo "❌ Nie znaleziono danych wersji $MC_VERSION w manifest.json Mojang."
        exit 1
      fi
      SERVER_JAR_URL="$(curl -s -A "$USER_AGENT" "$VERSION_URL" | jq -r '.downloads.server.url // empty')"
      if [ -z "$SERVER_JAR_URL" ]; then
        echo "❌ Nie udało się znaleźć URL do server.jar dla wersji $MC_VERSION."
        exit 1
      fi
      log "🔗 Pobieram VANILLA server.jar z: $SERVER_JAR_URL"
      if ! wget -q --show-progress --user-agent="$USER_AGENT" "$SERVER_JAR_URL" -O server.jar; then
        echo "❌ Pobieranie vanilla server.jar nie powiodło się."
        exit 1
      fi
      log "✅ Vanilla server.jar $MC_VERSION pobrany jako server.jar."
      log "ℹ️ Uwaga: Aby zainstalować $ENGINE (Forge/NeoForge/Fabric) musisz uruchomić instalator/loader osobno — ten skrypt pobiera tylko vanilla server.jar jako punkt startowy."
      ;;
    *)
      echo "❌ Nieznany silnik: $ENGINE"
      exit 1
      ;;
  esac
fi

# ====== Akceptacja EULA ======
if [ ! -f eula.txt ]; then
  log "📜 Tworzę eula.txt (eula=true)"
  echo "eula=true" > eula.txt
else
  log "📜 eula.txt już istnieje."
fi

# ====== Pytanie o RAM (1-15 GB) ======
while true; do
  echo
  read -rp "⚙️ Ile chcesz GB RAM dla serwera (liczba całkowita 1-15)? " RAM_CHOICE
  if ! [[ "$RAM_CHOICE" =~ ^[0-9]+$ ]]; then
    echo "❌ Podaj liczbę całkowitą."
    continue
  fi
  if [ "$RAM_CHOICE" -lt 1 ] || [ "$RAM_CHOICE" -gt 15 ]; then
    echo "❌ Zakres dozwolony to 1–15 GB."
    continue
  fi
  break
done

MEM_ARG="${RAM_CHOICE}G"
log
log "🚀 Uruchamiam serwer: java -Xmx${MEM_ARG} -Xms${MEM_ARG} -jar server.jar nogui"
log "Aby zatrzymać serwer użyj w konsoli komendy 'stop' lub Ctrl+C'."

exec java -Xmx"${MEM_ARG}" -Xms"${MEM_ARG}" -jar server.jar nogui
