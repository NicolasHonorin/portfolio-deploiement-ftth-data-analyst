-- Portfolio : déploiement FTTH — Hérault
-- 01_controles_sources.sql — Contrôles des deux suivis importés
-- Reporting figé au vendredi 2 octobre 2026 — semaine 2026-S40.
-- Source SQL02 à SQL27 : Requetes sql deploiement ftth.pdf (26 requêtes).
-- Logique et commentaires du PDF conservés ; sauts de page retirés.
-- Prérequis : datasets créés dans BigQuery et deux CSV de suivi importés.
-- Ordre des fichiers : 01 à 05.
--
-- Prérequis : les deux tables de suivi sont importées dans le dataset raw.
-- Je lance les contrôles séparément pour lire chaque résultat.
-- Je vérifie notamment les 25 033 lignes attendues dans chacun des deux suivis.
-- Je traite les anomalies éventuelles avant de créer les vues.

-- ======================================================================
-- SQL02 — Vérifier les volumes et les clés
-- ======================================================================
-- Je commence par vérifier le nombre de lignes importées dans chaque suivi.
-- Je compare ce nombre aux identifiants distincts et je compte les identifiants NULL.

SELECT
'suivi_cables' AS source
,COUNT(*) AS nb_lignes
,COUNT(DISTINCT id_cable) AS nb_cles
,COUNTIF(id_cable IS NULL) AS cles_vides
FROM `portfolio_deploiement_ftth_raw.suivi_cables_raw`
UNION ALL
SELECT
'suivi_boites' AS source
,COUNT(*) AS nb_lignes
,COUNT(DISTINCT id_boite) AS nb_cles
,COUNTIF(id_boite IS NULL) AS cles_vides
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw`;

-- ======================================================================
-- SQL03 — Rechercher les doublons
-- ======================================================================
-- Je recherche les identifiants présents plusieurs fois dans chaque suivi.
-- Je regroupe les lignes par identifiant et je garde les groupes qui dépassent une ligne.

SELECT
'suivi_cables' AS source
,id_cable AS cle
,COUNT(*) AS nb_lignes
FROM `portfolio_deploiement_ftth_raw.suivi_cables_raw`
GROUP BY id_cable
HAVING COUNT(*) > 1
UNION ALL
SELECT
'suivi_boites' AS source
,id_boite AS cle
,COUNT(*) AS nb_lignes
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw`
GROUP BY id_boite
HAVING COUNT(*) > 1;

-- ======================================================================
-- SQL04 — Contrôler le périmètre par prestataire
-- ======================================================================
-- Je vérifie la répartition du programme entre les cinq prestataires.
-- Je compte leurs PM et leurs boîtes, puis je somme les EL prévus.

SELECT
prestataire_id
,COUNT(DISTINCT id_pm) AS nb_pm
,COUNT(*) AS nb_boites
,SUM(nbr_el) AS el_prevus
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw`
GROUP BY prestataire_id
ORDER BY prestataire_id;

-- ======================================================================
-- SQL05 — Contrôler la relation entre les deux suivis
-- ======================================================================
-- Je vérifie qu’une boîte correspond à un câble entrant, et qu’aucun câble n’est isolé.
-- Je contrôle aussi qu’un même câble n’est pas associé à plusieurs boîtes.
-- Je compare leur prestataire, PM, branche, section, commune, zone et capacité.

SELECT
'boite_sans_cable' AS controle
,COUNTIF(cables.id_cable IS NULL) AS anomalies
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw` AS boites
LEFT JOIN `portfolio_deploiement_ftth_raw.suivi_cables_raw` AS cables
ON boites.id_cable = cables.id_cable
UNION ALL
SELECT
'cable_sans_boite' AS controle
,COUNTIF(boites.id_boite IS NULL) AS anomalies
FROM `portfolio_deploiement_ftth_raw.suivi_cables_raw` AS cables
LEFT JOIN `portfolio_deploiement_ftth_raw.suivi_boites_raw` AS boites
ON cables.id_cable = boites.id_cable
UNION ALL
SELECT
'plusieurs_boites_par_cable' AS controle
,COUNT(*) - COUNT(DISTINCT id_cable) AS anomalies
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw`
UNION ALL
SELECT
'contexte_different' AS controle
,COUNTIF(
boites.prestataire_id != cables.prestataire_id
OR boites.id_pm != cables.id_pm
OR boites.branche != cables.branche
OR boites.section != cables.section
OR boites.commune != cables.commune
OR boites.type_zone != cables.type_zone
OR boites.capacite_cable_fo != cables.capacite_cable_fo
) AS anomalies
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw` AS boites
INNER JOIN `portfolio_deploiement_ftth_raw.suivi_cables_raw` AS cables
ON boites.id_cable = cables.id_cable;

-- ======================================================================
-- SQL06 — Contrôler la chronologie et les métrages
-- ======================================================================
-- Je vérifie l’ordre des travaux : tirage, pose, réflectométrie, puis recette.
-- Une étape réalisée doit avoir ses prérequis, avec des dates dans le bon ordre.
-- Je contrôle aussi les valeurs de métrage des câbles et les dates après le 02/10/2026.

SELECT
'boites' AS objet
,COUNTIF(
(boites.date_pose_boite IS NOT NULL
AND (cables.date_fin_tirage IS NULL
OR boites.date_pose_boite < cables.date_fin_tirage))
OR (boites.date_reflectometrie IS NOT NULL
AND (boites.date_pose_boite IS NULL
OR boites.date_reflectometrie < boites.date_pose_boite))
OR (boites.date_recette_optique IS NOT NULL
AND (boites.date_reflectometrie IS NULL
OR boites.date_recette_optique < boites.date_reflectometrie))
) AS ordre_invalide
,COUNTIF(
boites.date_pose_boite > DATE '2026-10-02'
OR boites.date_reflectometrie > DATE '2026-10-02'
OR boites.date_recette_optique > DATE '2026-10-02'
) AS dates_futures
FROM `portfolio_deploiement_ftth_raw.suivi_boites_raw` AS boites
LEFT JOIN `portfolio_deploiement_ftth_raw.suivi_cables_raw` AS cables
ON boites.id_cable = cables.id_cable
UNION ALL
SELECT
'cables' AS objet
,COUNTIF(
(date_fin_tirage IS NOT NULL
AND (date_debut_tirage IS NULL
OR date_fin_tirage < date_debut_tirage
OR valeur_debut IS NULL
OR valeur_fin IS NULL
OR valeur_fin <= valeur_debut))
OR (date_fin_tirage IS NULL AND valeur_fin IS NOT NULL)
) AS ordre_invalide
,COUNTIF(
date_debut_tirage > DATE '2026-10-02'
OR date_fin_tirage > DATE '2026-10-02'
) AS dates_futures
FROM `portfolio_deploiement_ftth_raw.suivi_cables_raw`;

-- ======================================================================
-- SQL07 — Vérifier la conversion des semaines ISO
-- ======================================================================
-- Je teste la conversion des semaines ISO avant de calculer les délais de planning.
-- Je compare les lundis calculés à trois dates connues, dont un changement d’année.
-- Je poursuis seulement si chaque lundi calculé correspond au lundi attendu.

SELECT
'2025-S01' AS semaine_iso
,DATE_TRUNC(PARSE_DATE('%G-S%V', '2025-S01'), ISOWEEK) AS lundi_calcule
,DATE '2024-12-30' AS lundi_attendu
UNION ALL
SELECT
'2020-S53' AS semaine_iso
,DATE_TRUNC(PARSE_DATE('%G-S%V', '2020-S53'), ISOWEEK) AS lundi_calcule
,DATE '2020-12-28' AS lundi_attendu
UNION ALL
SELECT
'2026-S40' AS semaine_iso
,DATE_TRUNC(PARSE_DATE('%G-S%V', '2026-S40'), ISOWEEK) AS lundi_calcule
,DATE '2026-09-28' AS lundi_attendu;
