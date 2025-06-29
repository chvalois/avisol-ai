#!/bin/bash

# Script d'injection CSV avec codes département alphanumériques (2A, 2B, etc.)

set -e

echo "🚀 Injection du CSV des élus/maires avec gestion des codes département alphanumériques..."

# Vérifier que le fichier CSV existe
if [ ! -f "data/elus-maires.csv" ]; then
    echo "❌ Fichier data/elus-maires.csv introuvable"
    exit 1
fi

echo "✅ Fichier trouvé : data/elus-maires.csv"

# Vérifier que PostgreSQL est démarré
if ! docker compose ps postgres | grep -q "Up"; then
    echo "❌ PostgreSQL n'est pas démarré. Lancez d'abord: docker compose up -d postgres"
    exit 1
fi

# Créer un fichier CSV temporaire avec les dates converties
echo "🔄 Conversion des dates françaises DD/MM/YYYY vers YYYY-MM-DD..."

# Copier le header
head -n 1 data/elus-maires.csv > data/elus-maires_converted.csv

# Convertir les dates avec sed
tail -n +2 data/elus-maires.csv | sed -E 's/([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{4})/\3-\2-\1/g' >> data/elus-maires_converted.csv

echo "✅ Dates converties dans data/elus-maires_converted.csv"

# Analyser les codes département et commune uniques
echo "🔍 Analyse des codes département et commune présents :"
echo "📍 Codes département :"
cut -d';' -f1 data/elus-maires_converted.csv | tail -n +2 | sort | uniq -c | head -5
echo "📍 Codes commune (échantillon) :"
cut -d';' -f5 data/elus-maires_converted.csv | tail -n +2 | sort | uniq | head -10
echo "   ... (affichage partiel)"

# Copier le CSV converti dans le container PostgreSQL
echo "📋 Copie du fichier CSV converti dans le container..."
docker cp data/elus-maires_converted.csv openwebui-postgres:/tmp/

# Créer la table avec code_departement en VARCHAR
echo "🗄️ Création de la table avec code_departement en VARCHAR..."
docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -c "
-- Supprimer la table si elle existe pour repartir de zéro
DROP TABLE IF EXISTS elus_maires CASCADE;

-- Table des élus/maires avec codes département et commune alphanumériques
CREATE TABLE elus_maires (
    id SERIAL PRIMARY KEY,
    code_departement VARCHAR(10),            -- NULL autorisé car parfois vide
    libelle_departement VARCHAR(255),        -- NULL autorisé car parfois vide  
    code_collectivite_statut_particulier INTEGER,
    libelle_collectivite_statut_particulier VARCHAR(255),
    code_commune VARCHAR(10) NOT NULL,      -- VARCHAR pour gérer 2A004, 2B156, etc.
    libelle_commune VARCHAR(255) NOT NULL,
    nom_elu VARCHAR(255) NOT NULL,
    prenom_elu VARCHAR(255) NOT NULL,
    code_sexe CHAR(1) NOT NULL CHECK (code_sexe IN ('M', 'F')),
    date_naissance DATE,
    code_categorie_socio_professionnelle INTEGER,
    libelle_categorie_socio_professionnelle TEXT,
    date_debut_mandat DATE,
    date_debut_fonction DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index pour améliorer les performances (avec gestion des NULL)
CREATE INDEX idx_elus_departement ON elus_maires(code_departement) WHERE code_departement IS NOT NULL;
CREATE INDEX idx_elus_collectivite ON elus_maires(code_collectivite_statut_particulier) WHERE code_collectivite_statut_particulier IS NOT NULL;
CREATE INDEX idx_elus_commune ON elus_maires(code_commune);
CREATE INDEX idx_elus_nom ON elus_maires(nom_elu, prenom_elu);
CREATE INDEX idx_elus_sexe ON elus_maires(code_sexe);

-- Index spécifique pour les recherches par département ou collectivité
CREATE INDEX idx_elus_dept_libelle ON elus_maires(libelle_departement) WHERE libelle_departement IS NOT NULL;
CREATE INDEX idx_elus_collectivite_libelle ON elus_maires(libelle_collectivite_statut_particulier) WHERE libelle_collectivite_statut_particulier IS NOT NULL;
"

# Injection via COPY avec le fichier converti
echo "💾 Injection des données..."
docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -c "
COPY elus_maires (
    code_departement,
    libelle_departement,
    code_collectivite_statut_particulier,
    libelle_collectivite_statut_particulier,
    code_commune,
    libelle_commune,
    nom_elu,
    prenom_elu,
    code_sexe,
    date_naissance,
    code_categorie_socio_professionnelle,
    libelle_categorie_socio_professionnelle,
    date_debut_mandat,
    date_debut_fonction
) FROM '/tmp/elus-maires_converted.csv' 
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ';',
    NULL '',
    ENCODING 'UTF8'
);
"

# Vérifier que l'injection a fonctionné
echo "🔍 Vérification de l'injection..."
INJECTION_COUNT=$(docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -t -c "SELECT COUNT(*) FROM elus_maires;" | tr -d ' ')
echo "📊 Nombre d'enregistrements injectés : $INJECTION_COUNT"

if [ "$INJECTION_COUNT" -gt 0 ]; then
    echo "✅ Injection réussie !"
    
    # Statistiques détaillées
    echo ""
    echo "📊 Statistiques complètes :"
    docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -c "
    SELECT 
        COUNT(*) as total_elus,
        COUNT(DISTINCT code_departement) as nb_departements_metro,
        COUNT(DISTINCT code_collectivite_statut_particulier) as nb_collectivites_outremer,
        COUNT(DISTINCT code_commune) as nb_communes,
        COUNT(CASE WHEN date_naissance IS NOT NULL THEN 1 END) as dates_naissance_valides,
        COUNT(CASE WHEN date_debut_mandat IS NOT NULL THEN 1 END) as dates_mandat_valides,
        COUNT(CASE WHEN code_departement IS NULL THEN 1 END) as elus_outremer
    FROM elus_maires;
    "
    
    echo ""
    echo "👤 Répartition par sexe :"
    docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -c "
    SELECT code_sexe, COUNT(*) as nombre 
    FROM elus_maires 
    GROUP BY code_sexe 
    ORDER BY code_sexe;
    "
    
    echo ""
    echo "🏛️ Codes département et commune présents (échantillon) :"
    docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -c "
    SELECT code_departement, code_commune, libelle_commune, COUNT(*) as nb_elus
    FROM elus_maires 
    GROUP BY code_departement, code_commune, libelle_commune
    ORDER BY 
        CASE 
            WHEN code_departement ~ '^[0-9]+
    
else
    echo "❌ L'injection a échoué"
    echo "📋 Vérifiez les logs PostgreSQL :"
    docker logs openwebui-postgres --tail=20
fi

# Nettoyer le fichier temporaire
echo ""
echo "🧹 Nettoyage des fichiers temporaires..."
rm -f data/elus-maires_converted.csv
docker exec openwebui-postgres rm -f /tmp/elus-maires_converted.csv

echo ""
echo "✅ Script terminé !"
echo "💡 La table 'elus_maires' est maintenant disponible dans PostgreSQL"
echo "🔍 Pour tester : docker exec -it openwebui-postgres psql -U openwebui_user -d openwebui_db"
echo ""
echo "📝 Requêtes de test utiles :"
echo "   SELECT COUNT(*) FROM elus_maires;"
echo "   -- Départements métropole/Corse :"
echo "   SELECT DISTINCT code_departement, libelle_departement FROM elus_maires WHERE code_departement IS NOT NULL ORDER BY code_departement;"
echo "   -- Collectivités d'outre-mer :"
echo "   SELECT DISTINCT code_collectivite_statut_particulier, libelle_collectivite_statut_particulier FROM elus_maires WHERE code_collectivite_statut_particulier IS NOT NULL;"
echo "   -- Communes de Corse :"
echo "   SELECT * FROM elus_maires WHERE code_departement IN ('2A', '2B') LIMIT 5;"
echo "   -- Communes d'outre-mer :"
echo "   SELECT * FROM elus_maires WHERE code_collectivite_statut_particulier = 972 LIMIT 5;" THEN code_departement::integer 
            ELSE 999 
        END,
        code_departement, code_commune
    LIMIT 10;
    "
    
    echo ""
    echo "🏝️ Vérification spéciale - Communes de Corse :"
    docker exec openwebui-postgres psql -U openwebui_user -d openwebui_db -c "
    SELECT code_departement, code_commune, libelle_commune, COUNT(*) as nb_elus
    FROM elus_maires 
    WHERE code_departement IN ('2A', '2B')
    GROUP BY code_departement, code_commune, libelle_commune
    ORDER BY code_departement, code_commune
    LIMIT 10;
    "
    
else
    echo "❌ L'injection a échoué"
    echo "📋 Vérifiez les logs PostgreSQL :"
    docker logs openwebui-postgres --tail=20
fi

# Nettoyer le fichier temporaire
echo ""
echo "🧹 Nettoyage des fichiers temporaires..."
rm -f data/elus-maires_converted.csv
docker exec openwebui-postgres rm -f /tmp/elus-maires_converted.csv

echo ""
echo "✅ Script terminé !"
echo "💡 La table 'elus_maires' est maintenant disponible dans PostgreSQL"
echo "🔍 Pour tester : docker exec -it openwebui-postgres psql -U openwebui_user -d openwebui_db"
echo ""
echo "📝 Requêtes de test utiles :"
echo "   SELECT COUNT(*) FROM elus_maires;"
echo "   SELECT DISTINCT code_departement, libelle_departement FROM elus_maires ORDER BY code_departement;"
echo "   SELECT * FROM elus_maires WHERE code_departement IN ('2A', '2B') LIMIT 5;"