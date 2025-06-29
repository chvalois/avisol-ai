#!/bin/bash
set -e

echo "🚀 Démarrage d'Open WebUI avec PostgreSQL..."

# Utiliser la nouvelle syntaxe
DOCKER_COMPOSE="docker compose"

# Créer les dossiers
mkdir -p volumes/{postgres,ollama,openwebui}

# Démarrer les services
$DOCKER_COMPOSE up -d

echo "✅ Services démarrés!"
echo "🌐 Open WebUI : http://localhost:3000"
echo "🦙 Ollama : http://localhost:11434"
echo "🗄️ PostgreSQL : localhost:5432"