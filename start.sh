#!/usr/bin/env bash
set -euo pipefail

SRV_DIR="server"

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
        # spróbuj pobrać Oracle .deb (archive)
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
# 🔧 Ustawiam Java 22 jako domyślną
if [ -d "/usr/lib/jvm/jdk-22-oracle-x64/bin" ]; then
    echo "🔧 Ustawiam Java 22 jako domyślną..."
    sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/jdk-22-oracle-x64/bin/java 9999
    sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/jdk-22-oracle-x64/bin/javac 9999
    sudo update-alternatives --set java /usr/lib/jvm/jdk-22-oracle-x64/bin/java
    sudo update-alternatives --set javac /usr/lib/jvm/jdk-22-oracle-x64/bin/javac
fi

# sprawdź jeszcze raz
java -version


# sprawdź jeszcze raz
java -version



# ====== Upewnij się, że jq jest dostępne (potrzebne do API PaperMC) ======
if ! command -v jq >/dev/null 2>&1; then
  log "⬇️ Instaluję jq (potrzebne do pobierania PaperMC) ..."
  sudo apt update
  sudo apt install -y jq
fi

# ====== Wybór wersji Minecrafta ======
while true; do
  echo
  read -rp "🎮 Wybierz wersję Minecrafta (np. 1.21 lub 1.21.7) [dozwolone 1.21 .. 1.21.8]: " VERSION
  if [[ "$VERSION" =~ ^1\.21([.][1-8])?$ ]]; then
    break
  else
    echo "❌ Niepoprawna wersja. Podaj 1.21 lub 1.21.1..1.21.8."
  fi
done

# ====== Przygotuj katalog serwera ======
mkdir -p "$SRV_DIR"
cd "$SRV_DIR"

# ====== Pobierz server.jar tylko jeśli nie ma ======
if [ -f server.jar ]; then
  log "📦 server.jar już istnieje — pomijam pobieranie."
else
  log "📥 Pobieram PaperMC $VERSION..."
  LATEST_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$VERSION" | jq -r '.builds[-1] // empty')
  if [ -z "$LATEST_BUILD" ]; then
    echo "❌ Nie udało się znaleźć buildu PaperMC dla wersji $VERSION przez API."
    echo "   Sprawdź wersję i spróbuj ponownie."
    exit 1
  fi
  DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$VERSION/builds/$LATEST_BUILD/downloads/paper-$VERSION-$LATEST_BUILD.jar"
  log "🔗 Pobieram z: $DOWNLOAD_URL"
  if ! wget -q --show-progress "$DOWNLOAD_URL" -O server.jar; then
    echo "❌ Pobieranie server.jar nie powiodło się."
    exit 1
  fi
  log "✅ PaperMC $VERSION (build $LATEST_BUILD) pobrany jako server.jar."
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
