#!/usr/bin/env python3
"""
Script d'injection du fichier CSV des élus/maires dans PostgreSQL
Version mise à jour avec gestion des codes alphanumériques et valeurs NULL
"""

import csv
import psycopg2
from datetime import datetime
import sys
import os
from pathlib import Path
import re

# Configuration de la base de données
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'openwebui_db',
    'user': 'openwebui_user',
    'password': 'SecurePass123!'
}

def parse_date(date_str):
    """Parse une date au format DD/MM/YYYY vers YYYY-MM-DD"""
    if not date_str or date_str.strip() == '':
        return None
    try:
        # Format français DD/MM/YYYY
        day, month, year = date_str.split('/')
        return f"{year}-{month.zfill(2)}-{day.zfill(2)}"
    except:
        return None

def clean_text(text):
    """Nettoie et valide le texte"""
    if text is None or text == '' or str(text).strip() == '':
        return None
    return str(text).strip()

def clean_code(code_str):
    """Nettoie et valide un code (département ou commune) - garde les alphanumériques"""
    if code_str is None or str(code_str).strip() == '':
        return None
    return str(code_str).strip()

def clean_integer(int_str):
    """Nettoie et valide un entier"""
    if int_str is None or str(int_str).strip() == '':
        return None
    try:
        return int(str(int_str).strip())
    except ValueError:
        return None

def create_table(cursor):
    """Crée la table elus_maires avec la bonne structure"""
    print("🗄️ Création de la table elus_maires...")
    
    create_table_sql = """
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
    """
    
    cursor.execute(create_table_sql)

def inject_csv_data():
    """Injecte les données du CSV dans PostgreSQL"""
    
    # Chercher le fichier CSV dans différents emplacements
    possible_files = [
        Path('data/elus-maires.csv'),
        Path('elusmairesmai.csv'),
        Path('data/elusmairesmai.csv')
    ]
    
    csv_file = None
    for file_path in possible_files:
        if file_path.exists():
            csv_file = file_path
            break
    
    if csv_file is None:
        print("❌ Fichier CSV introuvable. Essayé :")
        for fp in possible_files:
            print(f"   - {fp}")
        return False
    
    print(f"✅ Fichier trouvé : {csv_file}")
    
    try:
        # Connexion à PostgreSQL
        print("🔌 Connexion à PostgreSQL...")
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        # Créer la table
        create_table(cursor)
        conn.commit()
        
        # Lire et injecter le CSV
        print(f"📖 Lecture du fichier {csv_file}...")
        
        insert_query = """
            INSERT INTO elus_maires (
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
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
        """
        
        inserted_count = 0
        error_count = 0
        
        with open(csv_file, 'r', encoding='utf-8') as file:
            # Détecter le délimiteur
            csv_reader = csv.DictReader(file, delimiter=';')
            
            print("💾 Injection des données...")
            
            for row_num, row in enumerate(csv_reader, 1):
                try:
                    # Préparer les données avec gestion des types alphanumériques
                    data = (
                        clean_code(row['Code du département']),
                        clean_text(row['Libellé du département']),
                        clean_integer(row['Code de la collectivité à statut particulier']),
                        clean_text(row['Libellé de la collectivité à statut particulier']),
                        clean_code(row['Code de la commune']),
                        clean_text(row['Libellé de la commune']),
                        clean_text(row['Nom de l\'élu']),
                        clean_text(row['Prénom de l\'élu']),
                        clean_text(row['Code sexe']),
                        parse_date(row['Date de naissance']),
                        clean_integer(row['Code de la catégorie socio-professionnelle']),
                        clean_text(row['Libellé de la catégorie socio-professionnelle']),
                        parse_date(row['Date de début du mandat']),
                        parse_date(row['Date de début de la fonction'])
                    )
                    
                    cursor.execute(insert_query, data)
                    inserted_count += 1
                    
                    # Commit toutes les 1000 lignes
                    if inserted_count % 1000 == 0:
                        conn.commit()
                        print(f"   ✅ {inserted_count} lignes injectées...")
                        
                except Exception as e:
                    error_count += 1
                    print(f"   ❌ Erreur ligne {row_num}: {e}")
                    if error_count > 100:  # Arrêter si trop d'erreurs
                        print("❌ Trop d'erreurs, arrêt de l'injection")
                        break
        
        # Commit final
        conn.commit()
        
        # Statistiques finales
        cursor.execute("SELECT COUNT(*) FROM elus_maires")
        total_count = cursor.fetchone()[0]
        
        print(f"\n🎉 Injection terminée !")
        print(f"   ✅ Lignes injectées: {inserted_count}")
        print(f"   ❌ Erreurs: {error_count}")
        print(f"   📊 Total en base: {total_count}")
        
        # Statistiques détaillées
        print(f"\n📈 Statistiques détaillées:")
        
        # Départements métropole + Corse
        cursor.execute("SELECT COUNT(DISTINCT code_departement) FROM elus_maires WHERE code_departement IS NOT NULL")
        dept_metro_count = cursor.fetchone()[0]
        print(f"   🏛️  Départements métropole/Corse: {dept_metro_count}")
        
        # Collectivités d'outre-mer
        cursor.execute("SELECT COUNT(DISTINCT code_collectivite_statut_particulier) FROM elus_maires WHERE code_collectivite_statut_particulier IS NOT NULL")
        collectivites_count = cursor.fetchone()[0]
        print(f"   🏝️  Collectivités d'outre-mer: {collectivites_count}")
        
        # Communes
        cursor.execute("SELECT COUNT(DISTINCT code_commune) FROM elus_maires")
        commune_count = cursor.fetchone()[0]
        print(f"   🏘️  Communes: {commune_count}")
        
        # Répartition par sexe
        cursor.execute("SELECT code_sexe, COUNT(*) FROM elus_maires GROUP BY code_sexe ORDER BY code_sexe")
        sexe_stats = cursor.fetchall()
        for sexe, count in sexe_stats:
            print(f"   👤 {sexe}: {count} élus")
        
        # Élus d'outre-mer
        cursor.execute("SELECT COUNT(*) FROM elus_maires WHERE code_departement IS NULL")
        outremer_count = cursor.fetchone()[0]
        print(f"   🌴 Élus d'outre-mer: {outremer_count}")
        
        # Collectivités d'outre-mer détail
        print(f"\n🏝️ Détail des collectivités d'outre-mer:")
        cursor.execute("""
            SELECT code_collectivite_statut_particulier, libelle_collectivite_statut_particulier, COUNT(*) as nb_elus
            FROM elus_maires 
            WHERE code_collectivite_statut_particulier IS NOT NULL
            GROUP BY code_collectivite_statut_particulier, libelle_collectivite_statut_particulier
            ORDER BY code_collectivite_statut_particulier
        """)
        collectivites_detail = cursor.fetchall()
        for code, libelle, count in collectivites_detail:
            print(f"   {code} - {libelle}: {count} élus")
        
        # Quelques exemples de Corse
        print(f"\n🏔️ Exemples de Corse:")
        cursor.execute("""
            SELECT code_departement, code_commune, libelle_commune, COUNT(*) as nb_elus
            FROM elus_maires 
            WHERE code_departement IN ('2A', '2B')
            GROUP BY code_departement, code_commune, libelle_commune
            ORDER BY code_departement, code_commune
            LIMIT 5
        """)
        corse_examples = cursor.fetchall()
        for dept, commune, libelle, count in corse_examples:
            print(f"   {dept}-{commune} - {libelle}: {count} élus")
        
        return True
        
    except psycopg2.Error as e:
        print(f"❌ Erreur PostgreSQL: {e}")
        return False
    except Exception as e:
        print(f"❌ Erreur: {e}")
        return False
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    print("🚀 Script d'injection CSV vers PostgreSQL")
    print("🔄 Version mise à jour avec codes alphanumériques")
    print("=" * 60)
    
    success = inject_csv_data()
    
    if success:
        print("\n✅ Injection réussie !")
        print("💡 Vous pouvez maintenant interroger la table 'elus_maires' dans PostgreSQL")
        print("\n📝 Exemples de requêtes :")
        print("   SELECT COUNT(*) FROM elus_maires;")
        print("   SELECT * FROM elus_maires WHERE code_departement = '2A' LIMIT 5;")
        print("   SELECT * FROM elus_maires WHERE code_collectivite_statut_particulier = 972 LIMIT 5;")
    else:
        print("\n❌ Échec de l'injection")
        sys.exit(1)