-- Portfolio : déploiement FTTH — Hérault
-- 04_vues_controles_blocages.sql — Vue et contrôles Blocages
-- Reporting figé au vendredi 2 octobre 2026 — semaine 2026-S40.
-- Source SQL02 à SQL27 : Requetes sql deploiement ftth.pdf (26 requêtes).
-- Logique et commentaires du PDF conservés ; sauts de page retirés.
-- Prérequis : datasets créés dans BigQuery et deux CSV de suivi importés.
-- Ordre des fichiers : 01 à 05.
--
-- Prérequis : v_cables et v_boites ont été créées dans le fichier 02.
-- Je réunis les câbles et les boîtes en conservant leur type et leur identifiant.
-- L’ancienneté des blocages actifs est calculée au 2 octobre 2026.

-- ======================================================================
-- SQL20 — Créer les éléments et blocages
-- ======================================================================
-- Je rassemble les câbles et les boîtes dans une vue avec une clé distincte par élément.
-- Une boîte compte ici une fois, même si elle intervient dans plusieurs opérations.
-- Je repère les éléments non terminés, commencés ou programmés, pour le taux de blocage.
-- Je calcule l’ancienneté des seuls blocages actifs à la date du reporting.

CREATE OR REPLACE VIEW `portfolio_deploiement_ftth.v_elements` AS
SELECT
CONCAT('CABLE|', id_cable) AS cle_element
,'CABLE' AS type_element
,id_cable AS id_element
,prestataire_id
,id_pm
,commune
,type_zone
,mode_pose
,0 AS el_directs
,cause_blocage
,ref_blocage
,origine_blocage
,date_detection_blocage
,date_cloture_blocage
,blocage_actif
,IF(
date_fin_tirage IS NULL
AND (date_debut_tirage IS NOT NULL OR semaine_tirage_planifiee IS NOT NULL)
,1
,0
) AS element_actif
,IF(
blocage_actif = 1
,DATE_DIFF(DATE '2026-10-02', date_detection_blocage, DAY)
,NULL
) AS age_blocage_jours
FROM `portfolio_deploiement_ftth.v_cables`
UNION ALL
SELECT
CONCAT('BOITE|', id_boite) AS cle_element
,'BOITE' AS type_element
,id_boite AS id_element
,prestataire_id
,id_pm
,commune
,type_zone
,mode_pose
,nbr_el AS el_directs
,cause_blocage
,ref_blocage
,origine_blocage
,date_detection_blocage
,date_cloture_blocage
,blocage_actif
,IF(
date_recette_optique IS NULL
AND (date_pose_boite IS NOT NULL OR semaine_pose_planifiee IS NOT NULL)
,1
,0
) AS element_actif
,IF(
blocage_actif = 1
,DATE_DIFF(DATE '2026-10-02', date_detection_blocage, DAY)
,NULL
) AS age_blocage_jours
FROM `portfolio_deploiement_ftth.v_boites`;

-- ======================================================================
-- SQL21 — Contrôler les blocages
-- ======================================================================
-- Je contrôle les dates des incidents et la cohérence entre blocages et éléments actifs.
-- Je vérifie qu’un incident détecté possède une cause, une référence et une origine.
-- Ces contrôles permettent d’examiner les anomalies avant de calculer les taux de blocage.

SELECT
COUNTIF(date_cloture_blocage < date_detection_blocage) AS clotures_invalides
,COUNTIF(blocage_actif = 1 AND element_actif = 0) AS blocages_hors_perimetre
,COUNTIF(
date_detection_blocage > DATE '2026-10-02'
OR date_cloture_blocage > DATE '2026-10-02'
) AS dates_futures
,COUNTIF(
date_detection_blocage IS NOT NULL
AND (cause_blocage IS NULL OR ref_blocage IS NULL OR origine_blocage IS NULL)
) AS incidents_incomplets
FROM `portfolio_deploiement_ftth.v_elements`;
