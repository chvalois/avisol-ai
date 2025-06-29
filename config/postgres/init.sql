-- Initialisation de la base de données Open WebUI avec table des élus

-- Créer des extensions utiles
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Table des élus/maires
CREATE TABLE IF NOT EXISTS elus_maires (
    id SERIAL PRIMARY KEY,
    code_departement INTEGER NOT NULL,
    libelle_departement VARCHAR(255) NOT NULL,
    code_collectivite_statut_particulier INTEGER,
    libelle_collectivite_statut_particulier VARCHAR(255),
    code_commune INTEGER NOT NULL,
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

-- Index pour améliorer les performances
CREATE INDEX IF NOT EXISTS idx_elus_departement ON elus_maires(code_departement);
CREATE INDEX IF NOT EXISTS idx_elus_commune ON elus_maires(code_commune);
CREATE INDEX IF NOT EXISTS idx_elus_nom ON elus_maires(nom_elu, prenom_elu);
CREATE INDEX IF NOT EXISTS idx_elus_sexe ON elus_maires(code_sexe);

-- Trigger pour mettre à jour automatiquement updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_elus_maires_updated_at 
    BEFORE UPDATE ON elus_maires 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Log de l'initialisation
DO $$
BEGIN
    RAISE NOTICE 'Table elus_maires créée avec succès';
END $$;