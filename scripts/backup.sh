#!/bin/bash

# Script de sauvegarde pour Open WebUI

BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "📦 Création d'une sauvegarde..."

# Créer le dossier de backup
mkdir -p $BACKUP_DIR

# Sauvegarder PostgreSQL
echo "💾 Sauvegarde de la base de données..."
docker exec openwebui-postgres pg_dump -U $(grep POSTGRES_USER .env | cut -d'=' -f2) $(grep POSTGRES_DB .env | cut -d'=' -f2) > $BACKUP_DIR/postgres_backup_$TIMESTAMP.sql

# Sauvegarder les volumes
echo "📁 Sauvegarde des volumes..."
tar -czf $BACKUP_DIR/volumes_backup_$TIMESTAMP.tar.gz volumes/

echo "✅ Sauvegarde terminée dans $BACKUP_DIR/"