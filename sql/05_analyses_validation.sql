-- Portfolio : déploiement FTTH — Hérault
-- 05_analyses_validation.sql — Analyses de validation et exploration
-- Reporting figé au vendredi 2 octobre 2026 — semaine 2026-S40.
-- Source SQL02 à SQL27 : Requetes sql deploiement ftth.pdf (26 requêtes).
-- Logique et commentaires du PDF conservés ; sauts de page retirés.
-- Prérequis : datasets créés dans BigQuery et deux CSV de suivi importés.
-- Ordre des fichiers : 01 à 05.
--
-- Prérequis : les vues des fichiers 02 à 04 existent.
-- Je lance les requêtes séparément pour consulter les différents résultats.
-- Je conserve les arrondis du PDF ; les ratios sont arrondis à deux décimales.
-- Un ratio arrondi à deux décimales donne un pourcentage au point entier près.
-- SQL27 est une exploration complémentaire des longueurs de câbles tirés.

-- ======================================================================
-- SQL22 — Valider les KPI par prestataire
-- ======================================================================
-- Je restitue l’avancement du programme pour chaque prestataire à partir des PM.
-- Je somme les EL prévus et recettés, puis je calcule leur taux d’avancement.
-- Je compte les PM terminés et les PM démarrés qui restent à terminer.

SELECT
prestataire_id
,SUM(el_prevus) AS el_prevus
,SUM(el_recettes) AS el_recettes
,ROUND(SAFE_DIVIDE(SUM(el_recettes), SUM(el_prevus)),2) AS taux_avancement
,SUM(pm_termine) AS pm_termines
,COUNTIF(pm_demarre = 1 AND pm_termine = 0) AS pm_en_cours
FROM `portfolio_deploiement_ftth.v_pm`
GROUP BY prestataire_id
ORDER BY prestataire_id;

-- ======================================================================
-- SQL23 — Valider septembre et octobre
-- ======================================================================
-- Je vérifie les derniers mois du reporting : septembre et octobre 2026.
-- Je lis la production, le cumul et l’atteinte de l’objectif pour chaque prestataire.

SELECT
prestataire_id
,mois_label
,mois_complet
,el_recettes_mois
,objectif_mois_complet
,atteinte_mensuelle
,el_recettes_cumules
FROM `portfolio_deploiement_ftth.v_production_mensuelle`
WHERE TRUE
AND mois IN (DATE '2026-09-01', DATE '2026-10-01')
ORDER BY
prestataire_id
,mois;

-- ======================================================================
-- SQL24 — Valider le taux des blocages
-- ======================================================================
-- Je compare les blocages des câbles et des boîtes en gardant leurs périmètres distincts.
-- Je rapporte les éléments bloqués aux éléments actifs non terminés, commencés ou programmés.
-- Je calcule aussi l’ancienneté moyenne des seuls incidents encore actifs.

SELECT
type_element
,SUM(element_actif) AS elements_actifs
,SUM(blocage_actif) AS elements_bloques
,ROUND(SAFE_DIVIDE(SUM(blocage_actif), SUM(element_actif)),2) AS taux_blocage
,ROUND(AVG(age_blocage_jours),2) AS age_moyen_jours
FROM `portfolio_deploiement_ftth.v_elements`
GROUP BY type_element
ORDER BY type_element;

-- ======================================================================
-- SQL25 — Analyser les causes des blocages
-- ======================================================================
-- Je détaille les blocages actifs par prestataire, élément, mode de pose, zone, origine et cause.
-- Je compte les éléments concernés et je calcule l’ancienneté moyenne de leurs blocages.
-- Je trie les groupes les plus nombreux en premier pour préparer la revue des incidents.

SELECT
prestataire_id
,type_element
,mode_pose
,type_zone
,origine_blocage
,cause_blocage
,COUNT(*) AS nb_elements_bloques
,ROUND(AVG(age_blocage_jours),2) AS age_moyen_jours
FROM `portfolio_deploiement_ftth.v_elements`
WHERE TRUE
AND blocage_actif = 1
GROUP BY
prestataire_id
,type_element
,mode_pose
,type_zone
,origine_blocage
,cause_blocage
ORDER BY nb_elements_bloques DESC;

-- ======================================================================
-- SQL26 — Lire les trois prochaines semaines
-- ======================================================================
-- Je liste les opérations non réalisées prévues dans les trois semaines suivant le reporting.
-- Je compare leur premier engagement à leur semaine courante et au nombre de replanifications.

SELECT
prestataire_id
,id_pm
,id_element
,operation
,semaine_initiale
,semaine_courante
,horizon_initial
,nb_replanifications
FROM `portfolio_deploiement_ftth.v_operations`
WHERE TRUE
AND date_reelle IS NULL
AND semaine_courante IN ('2026-S41', '2026-S42', '2026-S43')
ORDER BY
semaine_courante
,prestataire_id
,id_pm
,operation;

-- ======================================================================
-- SQL27 — Comparer les longueurs tirées
-- ======================================================================
-- Je compare les longueurs cartographiques et réelles sur les mêmes câbles déjà tirés.

SELECT
mode_pose
,COUNT(*) AS cables_tires
,ROUND(SUM(longueur_cartographique_m) / 1000, 2) AS km_cartographiques
,ROUND(SUM(longueur_reelle_m) / 1000, 2) AS km_reels
,ROUND(
SAFE_DIVIDE(
SUM(longueur_reelle_m) - SUM(longueur_cartographique_m)
,SUM(longueur_cartographique_m)
)
,4
) AS ecart_longueur
FROM `portfolio_deploiement_ftth.v_cables`
WHERE TRUE
AND etat_cable = 'Tiré'
GROUP BY mode_pose
ORDER BY km_reels DESC;
