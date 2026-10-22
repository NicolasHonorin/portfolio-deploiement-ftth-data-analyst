-- Portfolio : déploiement FTTH — Hérault
-- 03_vues_controles_planning.sql — Vues et contrôles Planning
-- Reporting figé au vendredi 2 octobre 2026 — semaine 2026-S40.
-- Source SQL02 à SQL27 : Requetes sql deploiement ftth.pdf (26 requêtes).
-- Logique et commentaires du PDF conservés ; sauts de page retirés.
-- Prérequis : datasets créés dans BigQuery et deux CSV de suivi importés.
-- Ordre des fichiers : 01 à 05.
--
-- Prérequis : les vues du fichier 02 existent.
-- Je crée successivement les opérations brutes, leurs dates puis les indicateurs.
-- Dans SQL19, le dénominateur regroupe les opérations échues de tout l’historique.
-- Une sélection de semaines dans Power BI peut donc donner une autre fiabilité.
-- Je compare les résultats uniquement à périmètre et filtres identiques.

-- ======================================================================
-- SQL15 — Créer les opérations programmées
-- ======================================================================
-- Je rassemble tirage, pose, réflectométrie et recette dans une même vue de planning.
-- Chaque ligne représente une opération avec une clé qui précise son type.
-- Je garde le premier engagement, la dernière prévision et le nombre de replanifications.
-- Je retiens les opérations ayant un engagement initial, même si elles ne sont pas réalisées.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_operations_brutes` AS
SELECT
CONCAT('TIRAGE|', id_cable) AS id_operation
,prestataire_id
,id_pm
,id_cable AS id_element
,'TIRAGE' AS operation
,mode_pose
,type_zone
,commune
,semaine_entree_planning_tirage AS semaine_entree
,semaine_tirage_planifiee_initiale AS semaine_initiale
,semaine_tirage_planifiee AS semaine_courante
,nb_replanification_tirage AS nb_replanifications
,date_fin_tirage AS date_reelle
FROM `portfolio_deploiement_ftth.v_cables`
WHERE TRUE
AND semaine_tirage_planifiee_initiale IS NOT NULL
UNION ALL
SELECT
CONCAT('POSE|', id_boite) AS id_operation
,prestataire_id
,id_pm
,id_boite AS id_element
,'POSE' AS operation
,mode_pose
,type_zone
,commune
,semaine_entree_planning_pose AS semaine_entree
,semaine_pose_planifiee_initiale AS semaine_initiale
,semaine_pose_planifiee AS semaine_courante
,nb_replanification_pose AS nb_replanifications
,date_pose_boite AS date_reelle
FROM `portfolio_deploiement_ftth.v_boites`
WHERE TRUE
AND semaine_pose_planifiee_initiale IS NOT NULL
UNION ALL
SELECT
CONCAT('REFLECTOMETRIE|', id_boite) AS id_operation
,prestataire_id
,id_pm
,id_boite AS id_element
,'REFLECTOMETRIE' AS operation
,mode_pose
,type_zone
,commune
,semaine_entree_planning_reflectometrie AS semaine_entree
,semaine_reflectometrie_planifiee_initiale AS semaine_initiale
,semaine_reflectometrie_planifiee AS semaine_courante
,nb_replanification_reflectometrie AS nb_replanifications
,date_reflectometrie AS date_reelle
FROM `portfolio_deploiement_ftth.v_boites`
WHERE TRUE
AND semaine_reflectometrie_planifiee_initiale IS NOT NULL
UNION ALL
SELECT
CONCAT('RECETTE|', id_boite) AS id_operation
,prestataire_id
,id_pm
,id_boite AS id_element
,'RECETTE' AS operation
,mode_pose
,type_zone
,commune
,semaine_entree_planning_recette AS semaine_entree
,semaine_recette_planifiee_initiale AS semaine_initiale
,semaine_recette_planifiee AS semaine_courante
,nb_replanification_recette AS nb_replanifications
,date_recette_optique AS date_reelle
FROM `portfolio_deploiement_ftth.v_boites`
WHERE TRUE
AND semaine_recette_planifiee_initiale IS NOT NULL;

-- ======================================================================
-- SQL16 — Convertir les semaines ISO en lundis
-- ======================================================================
-- Je transforme les semaines d’entrée, initiale et courante en dates de lundi.
-- Je peux ainsi comparer les semaines et calculer leurs écarts au changement d’année.
-- Je reprends la conversion ISO testée auparavant.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_operations_dates` AS
SELECT
operations.*
,DATE_TRUNC(
PARSE_DATE('%G-S%V', semaine_entree)
,ISOWEEK
) AS date_entree
,DATE_TRUNC(
PARSE_DATE('%G-S%V', semaine_initiale)
,ISOWEEK
) AS date_initiale
,DATE_TRUNC(
PARSE_DATE('%G-S%V', semaine_courante)
,ISOWEEK
) AS date_courante
FROM `portfolio_deploiement_ftth.v_operations_brutes` AS operations;

-- ======================================================================
-- SQL17 — Calculer la fiabilité et les délais
-- ======================================================================
-- Je mesure l’horizon du premier engagement et l’écart entre semaine réelle et initiale.
-- Je considère l’engagement échu lorsque son vendredi est atteint au reporting.
-- Le planning est tenu si l’opération est réalisée dans la semaine initialement annoncée.
-- Je distingue les avances, les retards et les opérations non réalisées, et je repère les replanifications.
-- Ces indicateurs décrivent les engagements du prestataire, qui organise ses équipes.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_operations` AS
SELECT
operations.*
,DATE_DIFF(date_initiale, date_entree, ISOWEEK) AS horizon_initial
,DATE_DIFF(
DATE_TRUNC(date_reelle, ISOWEEK)
,date_initiale
,ISOWEEK
) AS ecart_semaines
,IF(
DATE_ADD(date_initiale, INTERVAL 4 DAY) <= DATE '2026-10-02'
,1
,0
) AS operation_echue
,IF(DATE_TRUNC(date_reelle, ISOWEEK) = date_initiale, 1, 0) AS planning_tenu
,IF(nb_replanifications > 0, 1, 0) AS operation_replanifiee
,CASE
WHEN date_reelle IS NULL THEN 'Non réalisée'
WHEN DATE_TRUNC(date_reelle, ISOWEEK) < date_initiale THEN 'En avance'
WHEN DATE_TRUNC(date_reelle, ISOWEEK) = date_initiale THEN 'À l’heure'
WHEN DATE_DIFF(DATE_TRUNC(date_reelle, ISOWEEK), date_initiale, ISOWEEK) = 1
THEN '1 semaine de retard'
ELSE '2 semaines ou plus'
END AS classe_delai
FROM `portfolio_deploiement_ftth.v_operations_dates` AS operations;

-- ======================================================================
-- SQL18 — Auditer les opérations de planning
-- ======================================================================
-- Je vérifie les dates obtenues, les horizons S+1 à S+3 et les compteurs de replanification.
-- Je contrôle que les entrées au planning ne dépassent pas la semaine du reporting.
-- Je vérifie aussi que les travaux restant à réaliser sont prévus entre S41 et S43.

SELECT
COUNTIF(date_entree IS NULL OR date_initiale IS NULL OR date_courante IS NULL) AS dates_manquantes
,COUNTIF(horizon_initial NOT IN (1, 2, 3)) AS horizons_invalides
,COUNTIF(date_entree > DATE '2026-09-28') AS entrees_futures
,COUNTIF(date_courante > DATE '2026-10-19') AS previsions_trop_lointaines
,COUNTIF(
nb_replanifications IS NULL
OR nb_replanifications < 0
OR (nb_replanifications = 0 AND semaine_courante != semaine_initiale)
) AS compteurs_invalides
,COUNTIF(
date_reelle IS NULL
AND semaine_courante NOT IN ('2026-S41', '2026-S42', '2026-S43')
) AS restant_hors_horizon
FROM `portfolio_deploiement_ftth.v_operations`;

-- ======================================================================
-- SQL19 — Calculer les fiabilités S+1/S+2/S+3
-- ======================================================================
-- Je compare la fiabilité selon le type d’opération et l’horizon du premier engagement.
-- Je retiens uniquement les engagements échus à la date du reporting.
-- Je divise les opérations tenues par toutes les opérations échues, même non réalisées.

SELECT
operation
,horizon_initial
,COUNT(*) AS operations_echues
,SUM(planning_tenu) AS operations_tenues
,ROUND(SAFE_DIVIDE(SUM(planning_tenu), COUNT(*)),2) AS fiabilite
FROM `portfolio_deploiement_ftth.v_operations`
WHERE TRUE
AND operation_echue = 1
GROUP BY
operation
,horizon_initial
ORDER BY
operation
,horizon_initial;
