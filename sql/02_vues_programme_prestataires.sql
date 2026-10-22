-- Portfolio : déploiement FTTH — Hérault
-- 02_vues_programme_prestataires.sql — Vues Programme et Prestataires
-- Reporting figé au vendredi 2 octobre 2026 — semaine 2026-S40.
-- Source SQL02 à SQL27 : Requetes sql deploiement ftth.pdf (26 requêtes).
-- Logique et commentaires du PDF conservés ; sauts de page retirés.
-- Prérequis : datasets créés dans BigQuery et deux CSV de suivi importés.
-- Ordre des fichiers : 01 à 05.
--
-- Prérequis : les contrôles du fichier 01 ont été examinés.
-- Je respecte l’ordre des requêtes : certaines vues dépendent des précédentes.
-- CREATE OR REPLACE VIEW remplace la définition d’une vue portant le même nom.
-- Les deux CTE du parcours se trouvent dans SQL12 et SQL13.
-- Le mois d’octobre est partiel : je ne lui applique pas l’objectif d’un mois complet.

-- ======================================================================
-- SQL08 — Créer la vue câbles depuis le suivi
-- ======================================================================
-- Je prépare une vue câbles à partir du suivi, sans modifier la table source.
-- Je calcule la longueur réelle des tirages achevés avec valeur_fin moins valeur_debut.
-- Je détermine l’état du câble à partir des dates et du planning.
-- Je repère les blocages encore actifs à la date du reporting.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_cables` AS
SELECT
cables.*
,IF(
date_fin_tirage IS NOT NULL
,valeur_fin - valeur_debut
,NULL
) AS longueur_reelle_m
,CASE
WHEN date_fin_tirage IS NOT NULL THEN 'Tiré'
WHEN date_debut_tirage IS NOT NULL THEN 'En cours'
WHEN semaine_tirage_planifiee IS NOT NULL THEN 'Programmé'
ELSE 'Non programmé'
END AS etat_cable
,IF(
date_detection_blocage <= DATE '2026-10-02'
AND (date_cloture_blocage IS NULL
OR date_cloture_blocage > DATE '2026-10-02')
,1
,0
) AS blocage_actif
FROM `portfolio_deploiement_ftth_raw.suivi_cables_raw` AS cables;

-- ======================================================================
-- SQL09 — Créer la vue boîtes depuis le suivi
-- ======================================================================
-- Je prépare une vue boîtes et je récupère le mode de pose depuis le câble associé.
-- Je compte les EL d’une boîte quand sa recette optique est réalisée.
-- Je détermine son état selon l’étape atteinte et son blocage actif au reporting.
-- La relation contrôlée auparavant permet de conserver une seule ligne par boîte.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_boites` AS
SELECT
boites.*
,cables.mode_pose
,IF(date_recette_optique IS NOT NULL, nbr_el, 0) AS el_recettes
,CASE
WHEN date_recette_optique IS NOT NULL THEN 'Recettée'
WHEN date_reflectometrie IS NOT NULL THEN 'Réflectométrie réalisée'
WHEN date_pose_boite IS NOT NULL THEN 'Posée'
WHEN semaine_pose_planifiee IS NOT NULL THEN 'Programmée'
ELSE 'Non programmée'
END AS etat_boite
,IF(
boites.date_detection_blocage <= DATE '2026-10-02'
AND (boites.date_cloture_blocage IS NULL
OR boites.date_cloture_blocage > DATE '2026-10-02')
,1
,0
) AS blocage_actif
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw` AS boites
LEFT JOIN `portfolio_deploiement_ftth_raw.suivi_cables_raw` AS cables
ON boites.id_cable = cables.id_cable;

-- ======================================================================
-- SQL10 — Vérifier les vues avant les KPI
-- ======================================================================
-- Je vérifie que la création des vues n’a pas ajouté ou supprimé de lignes.
-- Je compare les volumes et les identifiants distincts des câbles et des boîtes.
-- Je contrôle également les totaux d’EL prévus et recettés avant les indicateurs.

SELECT
'v_cables' AS objet
,COUNT(*) AS nb_lignes
,COUNT(DISTINCT id_cable) AS cles_distinctes
,CAST(NULL AS INT64) AS el_prevus
,CAST(NULL AS INT64) AS el_recettes
FROM `portfolio_deploiement_ftth.v_cables`
UNION ALL
SELECT
'v_boites' AS objet
,COUNT(*) AS nb_lignes
,COUNT(DISTINCT id_boite) AS cles_distinctes
,SUM(nbr_el) AS el_prevus
,SUM(el_recettes) AS el_recettes
FROM `portfolio_deploiement_ftth.v_boites`;

-- ======================================================================
-- SQL11 — Créer la dimension prestataires
-- ======================================================================
-- Je crée une liste unique des prestataires pour filtrer les analyses dans Power BI.
-- Je rassemble leurs EL prévus, leurs PM et l’objectif nominal de 850 EL par mois.
-- Cet objectif servira à comparer la production sur les mois complets.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.dim_prestataire` AS
SELECT
prestataire_id
,SUM(nbr_el) AS el_prevus
,COUNT(DISTINCT id_pm) AS pm_prevus
,850 AS objectif_mensuel_nominal
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw`
GROUP BY prestataire_id;

-- ======================================================================
-- SQL12 — CTE 1 — Identifier les PM terminés
-- ======================================================================
-- Je compte d’abord les câbles et leur avancement par prestataire et par PM dans une CTE.
-- Je joins ce résultat aux boîtes du même PM pour éviter de multiplier les lignes.
-- Un PM est terminé si tous ses câbles sont tirés et toutes ses boîtes sont recettées.
-- Je conserve les EL et l’indicateur de démarrage pour suivre aussi les PM en cours.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_pm` AS
WITH cables_pm AS
(
SELECT
prestataire_id
,id_pm
,COUNT(*) AS nb_cables
,COUNTIF(date_fin_tirage IS NOT NULL) AS nb_cables_tires
,COUNTIF(date_debut_tirage IS NOT NULL) AS nb_cables_commences
FROM `portfolio_deploiement_ftth.v_cables`
GROUP BY
prestataire_id
,id_pm
)
SELECT
boites.prestataire_id
,boites.id_pm
,boites.commune
,boites.type_zone
,SUM(boites.nbr_el) AS el_prevus
,SUM(boites.el_recettes) AS el_recettes
,COUNT(*) AS nb_boites
,COUNTIF(boites.date_recette_optique IS NOT NULL) AS nb_boites_recettees
,cables_pm.nb_cables
,cables_pm.nb_cables_tires
,IF(
cables_pm.nb_cables = cables_pm.nb_cables_tires
AND COUNTIF(boites.date_recette_optique IS NULL) = 0
,1
,0
) AS pm_termine
,IF(
cables_pm.nb_cables_commences > 0
OR COUNTIF(boites.date_pose_boite IS NOT NULL) > 0
,1
,0
) AS pm_demarre
FROM `portfolio_deploiement_ftth.v_boites` AS boites
INNER JOIN cables_pm
ON boites.id_pm = cables_pm.id_pm
AND boites.prestataire_id = cables_pm.prestataire_id
GROUP BY
boites.prestataire_id
,boites.id_pm
,boites.commune
,boites.type_zone
,cables_pm.nb_cables
,cables_pm.nb_cables_tires
,cables_pm.nb_cables_commences;

-- ======================================================================
-- SQL13 — CTE 2 — Production mensuelle et cumul
-- ======================================================================
-- Je regroupe d’abord les EL recettés par mois et par prestataire dans une CTE.
-- Je calcule ensuite leur cumul dans l’ordre des mois, séparément pour chaque prestataire.
-- Je compare les mois complets à l’objectif de 850 EL. Octobre reste un mois partiel.
-- Je garde les mois présents dans les recettes ; je ne génère pas de calendrier.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_production_mensuelle` AS
WITH recettes_mois AS
(
SELECT
prestataire_id
,DATE_TRUNC(date_recette_optique, MONTH) AS mois
,SUM(nbr_el) AS el_recettes_mois
FROM `portfolio_deploiement_ftth.v_boites`
WHERE TRUE
AND date_recette_optique IS NOT NULL
AND date_recette_optique <= DATE '2026-10-02'
GROUP BY
prestataire_id
,mois
)
SELECT
prestataire_id
,mois
,FORMAT_DATE('%Y-%m', mois) AS mois_label
,el_recettes_mois
,SUM(el_recettes_mois) OVER(
PARTITION BY prestataire_id
ORDER BY mois
) AS el_recettes_cumules
,IF(mois < DATE '2026-10-01', 1, 0) AS mois_complet
,IF(mois < DATE '2026-10-01', 850, NULL) AS objectif_mois_complet
,ROUND(SAFE_DIVIDE(
el_recettes_mois
,IF(mois < DATE '2026-10-01', 850, NULL)
),2) AS atteinte_mensuelle
FROM recettes_mois;

-- ======================================================================
-- SQL14 — Créer les mois présents dans les recettes
-- ======================================================================
-- Je crée la liste des mois réellement présents dans la production mensuelle.
-- Je retire les doublons pour obtenir une ligne par mois dans la dimension.
-- Cette liste servira aux axes et au filtre de mois dans Power BI.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.dim_mois` AS
SELECT DISTINCT
mois
,mois_label
,mois_complet
FROM `portfolio_deploiement_ftth.v_production_mensuelle`;
