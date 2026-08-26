# Notification CNIL — document préparatoire

**Incident** INC-2026-08-21-001
**Établi le** 26 août 2026
**Sources** `2026-08-21-spip-rce-webshell.md` (analyse technique),
`2026-08-21-cyclos-data-risk-assessment.md` (analyse des données)

> Établi d'après la *Trame des notifications de violations de données* (CNIL, juillet 2023).
> La notification doit impérativement être déposée via le **téléservice** de la CNIL : les
> notifications adressées par un autre canal sont refusées.
>
> **Légende** — ✅ élément disponible · ⚠️ arbitrage requis · ❌ **à fournir par
> l'association**

---

## ⏰ Échéance

**Date de prise de connaissance : 26 août 2026.** L'article 33 du RGPD impose une
notification dans un délai de **72 heures, soit au plus tard le 29 août 2026**.

Tous les éléments marqués ❌ ci-dessous sont d'ordre administratif et non technique. Si
l'un d'eux ne peut être réuni à temps, **déposer une *notification initiale*** — la trame le
prévoit expressément — puis la compléter par une *notification complémentaire*. Un numéro
SIREN manquant ne doit pas retarder le dépôt.

---

## 1. Type de notification

⚠️ **Recommandation : *notification initiale***, sauf si l'ensemble des ❌ est réuni avant
le dépôt. Les mesures correctives étant en cours (reconstruction de la préproduction,
base de données de `mlml.fr` non identifiée), une notification complémentaire sera de toute
façon nécessaire.

## 2. Identification de l'organisme

| Champ | État |
|---|---|
| Numéro SIREN | ❌ |
| Dénomination | ❌ (dénomination légale de l'association) |
| Numéro de TVA intracommunautaire | ❌ le cas échéant |
| Secteur d'activité | ❌ — proposition : *économie sociale et solidaire / monnaie locale complémentaire* |
| Effectif | ❌ |
| Adresse postale, code postal, ville | ❌ |
| Pays | ✅ France |

## 3. Coordonnées du responsable légal

❌ Civilité · Nom · Prénom · Adresse électronique — représentant légal de l'association.

## 4. Personne à contacter

❌ Civilité · Nom · Prénom · Fonction · Adresse électronique · Téléphone.
Vraisemblablement la personne ayant conduit l'investigation.

## 5. Autres organismes impliqués

⚠️ **Arbitrage requis.** Les serveurs `162.19.68.97` et `51.91.148.73` appartiennent à des
plages OVH. La qualification d'OVH comme *sous-traitant* au sens de l'article 28 dépend du
contrat : dans le cas d'une infrastructure administrée par vos soins, avec accès root
propre, OVH n'est en général **pas** sous-traitant pour ces données. Décrire la relation
d'hébergement de façon factuelle et laisser la CNIL apprécier. Déclarer également tout
tiers assurant l'administration de l'instance Cyclos pour votre compte.

---

## 6. Nature de la violation — dates

| Champ | Valeur |
|---|---|
| Période déterminée | ✅ Oui |
| **Début** | ✅ **21 août 2026, 08 h 14 min 22 s (CEST)** — première exploitation réussie, `prod-mlml-01` |
| **Fin** | ✅ **26 août 2026, vers 12 h 00 (CEST)** — arrêt d'Apache sur les deux serveurs |
| Toujours en cours | ✅ Non — violation confinée |
| **Prise de connaissance** | ✅ **26 août 2026** |

**Commentaires sur les dates** ✅ — trois intrusions distinctes :

- 21 août 08 h 14 — `prod-mlml-01` (`www.monel.co`), SPIP 4.4.16
- 23 août 05 h 59 — `preprod-mlml-01` (`www-monel-co.mlml.fr`), second acteur
- 24 au 26 août — `/var/www/mlml.fr` sur la préproduction, plusieurs acteurs ; dernière
  écriture malveillante le 26 août à 09 h 24, cinq heures avant le confinement

**Circonstances de la découverte** ✅ — Le premier attaquant a lui-même corrigé la
vulnérabilité pour en exclure ses concurrents. Ce correctif étant défectueux, il a rendu le
site public inopérant à compter du 24 août à 23 h 50. L'investigation menée le 26 août sur
cette panne a révélé la présence des programmes malveillants. **La découverte est
incidente** : aucun dispositif de supervision n'a signalé l'apparition de nouveaux fichiers,
la modification d'un fichier du cœur applicatif, ni les 1 736 tentatives d'exploitation.

**Motifs de retard** ✅ — Néant. La notification intervient dans les 72 heures suivant la
prise de connaissance.

## 7. À propos de la violation

**Nature de la violation** ✅
- ☑ **Perte de la confidentialité** — présumée (voir § 11)
- ☐ Perte de l'intégrité — **écartée par la preuve** : comparaison des 417 tables de la base
  Cyclos sur toute la période d'intrusion, aucune modification
- ☑ **Perte de la disponibilité** — site public défaillant du 24 août 23 h 50 au 26 août,
  puis arrêté volontairement

**Origine de l'incident** ✅ — ☑ *Piratage, logiciel malveillant*

**Cause de l'incident** ✅ — ☑ *Acte externe malveillant*

**Descriptif détaillé** ✅ — texte à reporter dans le téléservice :

---

### Descriptif détaillé de la violation

**1. Nature et origine de l'incident**

La violation résulte de l'exploitation malveillante d'une vulnérabilité affectant le
système de gestion de contenu SPIP, utilisé pour le site institutionnel de l'association.

L'attaque a exploité deux vulnérabilités critiques, toutes deux publiquement documentées et
corrigées par l'éditeur avant la survenance de l'incident :

- **CVE-2026-77647** (CVSS 3.1 : 9.8) — exécution de code arbitraire à distance sans
  authentification. Le compilateur de squelettes de SPIP insérait dans les gabarits
  compilés, au moyen de la fonction `var_export()` et sans échappement, les paramètres
  transmis dans la requête HTTP. Une balise PHP placée dans un paramètre d'URL était ainsi
  écrite telle quelle dans le fichier compilé, puis exécutée par le serveur.
  **Corrigée par la version 4.4.20, publiée le 17 août 2026.**
- **CVE-2026-77806** (CVSS 3.1 : 9.8) — injection de code au moyen de l'en-tête HTTP
  `X-Spip-Filtre`, mal traité par la fonction `analyse_resultat_skel`. Cet en-tête a permis
  de contourner l'encodage qui aurait neutralisé les balises injectées.
  **Corrigée par la version 4.4.21, publiée le 20 août 2026.**

Ces deux failles ont été signalées anonymement à l'éditeur par l'intermédiaire de l'ANSSI.
L'éditeur a explicitement indiqué, lors de la publication du correctif, que des tentatives
d'exploitation étaient déjà observées et que l'« écran de sécurité » de SPIP ne protégeait
pas contre cette vulnérabilité.

**Au moment des faits, le serveur de production exécutait la version 4.4.16, installée le
6 juillet 2026, jour même de sa publication.** Les versions correctives 4.4.20 et 4.4.21
étaient donc disponibles respectivement depuis quatre jours et depuis un jour lorsque
l'intrusion est survenue, et n'avaient pas été appliquées.

L'éditeur a publié quatre versions de sécurité dans les onze jours ayant précédé
l'intrusion : 4.4.18 le 10 août (dont une injection SQL non authentifiée), 4.4.19 le
12 août, 4.4.20 le 17 août et 4.4.21 le 20 août. Aucune n'a été installée.

L'association ne disposait pas de procédure de veille sur les annonces de sécurité de
l'éditeur ni de processus formalisé d'application des correctifs. Ce manquement est la
cause directe de la violation et fait l'objet de mesures correctives détaillées ci-après.
Il est précisé, sans que cela l'atténue, que la mise à jour précédente avait été appliquée
le jour de sa publication : le défaut porte sur une série resserrée de publications
survenues en août, non sur un défaut d'entretien prolongé de l'installation.

Un second site hébergé sur le serveur de préproduction exécutait la version 4.3.9,
également vulnérable et davantage encore en retard de mises à jour.

L'attaque n'était pas ciblée. Elle s'inscrit dans une campagne d'exploitation massive et
indiscriminée survenue immédiatement après la publication des correctifs : les journaux
enregistrent 1 736 tentatives d'exploitation provenant de 57 adresses IP distinctes sur le
serveur de production, et 1 782 tentatives sur le serveur de préproduction, entre le
21 et le 26 août 2026.

**2. Déroulé**

*Serveur de production*

Le 21 août 2026 à 08 h 14 min 22 s (CEST), une unique requête HTTP GET non authentifiée a
permis le dépôt d'un premier programme malveillant (interpréteur de commandes web, dit
« webshell ») dans la racine du site, conférant à son auteur l'exécution de commandes
arbitraires avec les droits du compte du serveur web.

À 13 h 57, l'attaquant a téléchargé depuis un hébergeur externe un second programme, offrant
des fonctions de gestion de fichiers et d'envoi de courriels, qu'il a utilisé de manière
interactive pendant environ deux heures.

À 15 h 30, l'attaquant a lui-même corrigé la vulnérabilité qu'il venait d'exploiter, afin
d'en empêcher l'exploitation par des tiers concurrents. Ce correctif étant défectueux, il a
provoqué l'indisponibilité progressive du site public à compter du 24 août à 23 h 50.

*Serveur de préproduction*

Le 23 août à 05 h 59, un second acteur — précédemment tenu en échec sur le serveur de
production par le correctif décrit ci-dessus — a compromis par le même procédé l'instance
SPIP de préproduction.

Du 24 au 26 août, une seconde instance SPIP hébergée sur ce même serveur (version 4.3.9),
installée manuellement et non couverte par les outils de gestion de configuration de
l'association, a été compromise par plusieurs acteurs distincts. Douze programmes
malveillants y ont été retrouvés, dont un client d'administration de bases de données
(Adminer) et un interpréteur de commandes disposant de six mécanismes d'exécution
indépendants. La dernière écriture malveillante date du 26 août à 09 h 24, soit environ
cinq heures avant la mise hors service des serveurs.

**3. Données susceptibles d'avoir été consultées**

Le compte du serveur web compromis disposait :

- d'un accès en lecture aux sauvegardes quotidiennes de la base de données de la plateforme
  d'échange Cyclos, celles-ci étant accessibles à tout utilisateur local du serveur
  (permissions 0644 dans un répertoire 0755) ;
- d'un accès direct, en lecture et en écriture, à la base de données Cyclos en production,
  au moyen d'un mot de passe stocké en clair dans un dépôt de code et aisément devinable.

Ces sauvegardes contiennent environ 4 000 enregistrements concernant environ 150 personnes :
154 comptes utilisateurs, 131 adresses électroniques, 194 empreintes de mots de passe
(hachées au moyen de l'algorithme bcrypt, facteur de coût 10), les coordonnées
professionnelles des contacts désignés d'environ 122 organisations adhérentes (nom, prénom,
courriel et téléphone directs), 116 adresses postales et 1 042 enregistrements de connexion
comportant une adresse IP.

Elles contiennent en outre 658 relevés de compte mensuels concernant 18 adhérents, couvrant
la période de décembre 2022 à juillet 2026. Chaque relevé mentionne la raison sociale, le
numéro SIRET, le solde du compte, la limite de solde autorisée, ainsi que le détail des
transactions (date, contrepartie nommée, montant).

Il a été vérifié qu'aucune donnée bancaire (IBAN, BIC), aucun numéro de carte de paiement,
aucun numéro d'inscription au répertoire (NIR) et aucune donnée sensible au sens de
l'article 9 du RGPD ne figurent dans la base concernée. Aucun mot de passe n'était stocké en
clair.

**4. Conséquences**

*Perte de confidentialité — présumée.* La journalisation des connexions à la base de données
PostgreSQL était désactivée. Il n'est donc pas possible d'établir si la base a effectivement
été consultée, et cette information est définitivement irrécupérable. Compte tenu de la
présence, pendant trois jours, d'un programme malveillant interactif sur un serveur
hébergeant une copie librement lisible de ces sauvegardes, l'association retient l'hypothèse
de la divulgation et en tire les conséquences.

*Perte d'intégrité — écartée.* La comparaison des sauvegardes de la base Cyclos antérieures
et postérieures à l'intrusion (20, 22 et 26 août 2026) établit qu'aucune donnée n'a été
modifiée : les 417 tables sont identiques, à l'exception de trois tables techniques
(horodatages de tâches planifiées et compteurs internes). Aucun compte, aucun mot de passe,
aucun solde et aucune transaction n'ont été altérés.

*Perte de disponibilité — avérée.* Le site public a été indisponible par intermittence à
compter du 24 août à 23 h 50, du fait du correctif défectueux appliqué par l'attaquant, puis
volontairement arrêté le 26 août à des fins de confinement.

**5. Circonstances de la découverte**

L'incident a été découvert de manière incidente. Le correctif défectueux appliqué par
l'attaquant ayant rendu le site public inopérant, l'investigation menée le 26 août 2026 sur
cette panne a mis au jour la présence des programmes malveillants.

Aucun dispositif de supervision n'a signalé l'apparition de nouveaux fichiers dans la racine
web, la modification d'un fichier du cœur applicatif, ni les milliers de tentatives
d'exploitation enregistrées. L'association relève que, si le correctif appliqué par
l'attaquant avait été fonctionnel, la compromission serait vraisemblablement restée
indétectée.

**6. Mesures immédiates**

Les serveurs web ont été arrêtés le 26 août 2026 à 12 h 00. L'ensemble des éléments de preuve
(racines web, journaux, sauvegardes de bases de données) a été conservé. Une analyse
technique complète de l'intrusion et des programmes malveillants a été conduite, ainsi
qu'une vérification de l'intégrité des données. Les mesures correctives sont détaillées dans
la rubrique « Mesures techniques et organisationnelles appliquées au traitement suite à la
violation ».

---

## 7 bis. Applicabilité du RGPD — données d'entreprises

⚠️ Question soulevée : les données concernant des entreprises adhérentes relèvent-elles du
RGPD ? **Oui — l'obligation de notification est établie.** Analyse :

### Ce que le RGPD exclut effectivement

Le **considérant 14** du RGPD énonce que le règlement « ne couvre pas le traitement des
données à caractère personnel qui concernent les personnes morales, notamment les
entreprises dotées de la personnalité juridique, y compris le nom, la forme juridique et
les coordonnées de la personne morale ».

La CNIL confirme que « des coordonnées d'entreprises (par exemple, l'entreprise
« Compagnie A » avec son adresse postale, le numéro de téléphone de son standard et un
courriel de contact générique) ne sont pas, en principe, des données personnelles ».

**Sont donc hors champ, pour les adhérents constitués en société :** raison sociale, SIRET,
SIREN, RCS, TVA intracommunautaire, forme juridique, code NAF, effectif, date de création,
adresse du siège, courriel générique.

### Ce qui relève du RGPD dans le jeu de données concerné

L'exclusion vise la personne morale elle-même, **non les personnes physiques qui la
représentent**. Sont des données à caractère personnel :

| Donnée | Volume | Fondement |
|---|---|---|
| Nom et prénom des contacts désignés | ~122 | Personne physique identifiée (art. 4.1) |
| Courriels nominatifs | 131 | Identifiant une personne physique |
| Téléphones directs attribués à une personne | — | Identification indirecte |
| Comptes utilisateurs (nom, identifiant) | 154 | Personnes physiques identifiées |
| Empreintes de mots de passe | 194 | Données d'authentification rattachées à une personne |
| Adresses IP de connexion | 1 042 | Donnée personnelle (CJUE, *Breyer*, C-582/14) |

La qualification ne change pas du fait que ces données sont **professionnelles** ni du fait
qu'elles soient **déjà publiques** : la CNIL retient de longue date que les informations
relatives aux dirigeants et représentants d'entreprises constituent des données
personnelles, quelle que soit la forme de l'entreprise.

### Le point déterminant pour les 658 relevés de compte

La qualification des relevés dépend de la **forme juridique** de chacun des 18 adhérents
titulaires d'un compte :

- **Société (SARL, SAS, SCOP, association…)** → solde, limite et transactions sont des
  informations d'affaires confidentielles, **hors champ du RGPD** (protégeables par
  ailleurs au titre du secret des affaires).
- **Entreprise individuelle, micro-entrepreneur, profession libérale** → il n'existe pas de
  séparation entre la personne et l'entreprise : **ces données sont des données
  personnelles**, y compris le SIRET, les soldes et l'historique de transactions.

C'est l'objet de l'action 17d du rapport d'incident. Le champ `forme_juridique` figure dans
la base et permet de trancher immédiatement.

### Conséquence

**Le RGPD s'applique et la notification reste obligatoire**, non en raison des données
d'entreprises, mais des ~150 personnes physiques identifiées (contacts désignés, titulaires
de comptes, adresses IP).

Ce qui change : la rubrique « nature des données » doit distinguer ce qui relève du RGPD de
ce qui n'en relève pas, et le décompte des données financières dépend du résultat de
l'action 17d. Cela peut **réduire l'assiette** de la violation, non la supprimer.

> Cette analyse est documentaire et ne constitue pas un avis juridique. La qualification
> définitive relève du responsable de traitement, le cas échéant avec un conseil.

---

## 8. Nature des données concernées

| Catégorie | Cocher | Justification |
|---|---|---|
| État civil | ☑ ✅ | Nom et prénom d'environ 122 contacts désignés |
| NIR | ☐ ✅ | **Absence vérifiée** — aucune occurrence dans l'ensemble de la base |
| Coordonnées | ☑ ✅ | 131 adresses électroniques, téléphones directs, 116 adresses postales |
| Données d'identification ou d'accès | ☑ ✅ | 154 identifiants, 194 empreintes de mots de passe (bcrypt) |
| Données financières / économiques | ☑ ⚠️ | **658 relevés de compte mensuels**, 18 adhérents, décembre 2022 → juillet 2026 : soldes, limites, transactions avec contreparties nommées. **Qualification subordonnée à la forme juridique des 18 titulaires** — voir § 7 bis et action 17d. Données personnelles pour les entreprises individuelles ; informations d'affaires hors champ pour les sociétés. |
| Documents officiels | ⚠️ | 6 extraits *Kbis* — documents d'immatriculation, publics en France. Il **ne s'agit pas** de pièces d'identité. Recommandation : ne pas cocher et le préciser en texte libre. |
| Données de localisation | ⚠️ | 1 042 enregistrements de connexion comportant une adresse IP. Il ne s'agit pas de géolocalisation au sens usuel ; le mentionner en texte libre plutôt que cocher. |
| Infractions / condamnations | ☐ ✅ | Néant |

**Données sensibles** ✅ — **aucune**. Ni origine raciale ou ethnique, ni opinions
politiques, philosophiques ou religieuses, ni appartenance syndicale, ni orientation
sexuelle, ni données de santé, biométriques ou génétiques. Vérifié sur le schéma de la base.

**Nombre approximatif d'enregistrements concernés** ✅ ≈ **4 000** :

| Catégorie | Nombre |
|---|---|
| Comptes utilisateurs | 154 |
| Valeurs de profil d'organisation | 2 067 |
| Relevés de compte mensuels | 658 |
| Enregistrements de connexion (IP) | 1 042 |
| Adresses postales | 116 |
| Empreintes de mots de passe | 194 |

**Catégories de personnes concernées** ✅ — ☑ *Adhérents* · ☑ *Utilisateurs*
(⚠️ ajouter *Employés* si l'un des 4 comptes opérateurs correspond à un salarié)

**Nombre approximatif de personnes concernées** ✅ ≈ **150** — environ 122 contacts désignés
d'organisations adhérentes, auxquels s'ajoutent les titulaires de comptes (recouvrement
partiel). **18 d'entre eux sont sensiblement plus exposés**, étant les titulaires dont les
relevés figuraient dans la base.

⚠️ Aucun mineur. Personnes vulnérables : sans objet.

---

## 9. Mesures de sécurité préalables à la violation

✅ Élément disponible — exposer les deux volets avec franchise ; la CNIL apprécie
favorablement la transparence.

**Mesures en place :**
- Mots de passe hachés au moyen de **bcrypt** (facteur de coût 10) — jamais stockés en clair
- Pare-feu applicatif hôte (UFW), politique de refus par défaut en entrée
- Accès SSH restreint à l'authentification par clé depuis un unique poste d'administration ;
  **aucune** tentative d'authentification en échec enregistrée
- HTTPS imposé, avec HSTS et en-têtes de sécurité standards
- Sauvegardes quotidiennes des bases de données, avec rotation
- Infrastructure gérée sous forme de code (Ansible) — pour les serveurs gérés

**Manquements identifiés par l'investigation :**
- **Absence de procédure de veille de sécurité et de processus formalisé d'application des
  correctifs.** La production exécutait SPIP 4.4.16, installée le 6 juillet 2026 le jour de
  sa publication ; quatre versions de sécurité ont suivi dans les onze jours précédant la
  violation (4.4.18, 4.4.19, 4.4.20, 4.4.21) et aucune n'a été appliquée. **Cause directe de
  la violation.**
- Une **seconde instance SPIP (4.3.9) hors gestion de configuration**, plus en retard encore
  et absente de tout inventaire
- Sauvegardes de base de données **accessibles en lecture à tout utilisateur local**
  (0644 dans un répertoire 0755) — donc au compte du serveur web
- Mot de passe de base de données **stocké en clair dans un dépôt versionné**, et aisément
  devinable
- Cyclos non isolé du serveur web : conteneur en mode réseau hôte, PostgreSQL à l'écoute sur
  toutes les interfaces
- Journalisation des connexions PostgreSQL **désactivée** — empêchant toute détermination
  d'un accès effectif à la base
- Aucun contrôle d'intégrité des fichiers ni alerte sur les racines web

> ⚠️ Le module `ecran_securite.php` de SPIP était installé, mais l'éditeur a explicitement
> indiqué qu'il **ne protège pas** contre ces vulnérabilités. Ne pas le présenter comme une
> mesure d'atténuation.

---

## 10. Conséquences potentielles

**En cas de perte de confidentialité** ✅
- ☑ Les données ont été diffusées plus que nécessaire et ont échappé à la maîtrise des
  personnes concernées
- ☑ Les données peuvent être corrélées avec d'autres informations relatives aux personnes
- ☑ Les données peuvent être exploitées à d'autres fins que celles prévues et/ou de manière
  non loyale

**En cas de perte d'intégrité** — ☐ néant. Vérifié : 417 tables inchangées.

**En cas de perte de disponibilité** ✅ — ☑ *Dysfonctionnement et difficultés à fournir un
service critique* (site public indisponible du 24 au 26 août ; plateforme Cyclos arrêtée
volontairement à des fins de confinement)

## 11. Préjudices potentiels pour les personnes concernées

✅ — ☑ Perte de contrôle sur leurs données personnelles · ☑ Vol d'identité (usurpation dans
le cadre d'hameçonnage ciblé) · ☑ Fraude (fraude au président / au faux fournisseur) ·
☑ Pertes financières (par voie de conséquence) · ☑ Atteinte à la réputation · ☑ Perte de la
confidentialité de données protégées par un secret (confidentialité commerciale des
18 titulaires de comptes)

Texte libre :

> Le risque principal est celui de l'ingénierie sociale ciblée, et non celui de la fraude
> financière directe. Le système concerné ne contenait aucune coordonnée bancaire, aucun
> numéro de carte de paiement ni aucun identifiant national : aucun paiement ne peut être
> initié à partir des données divulguées.
>
> En revanche, ces données permettent une usurpation particulièrement crédible : pour chacune
> des quelque 122 organisations adhérentes, elles comportent l'identité de l'organisation, le
> nom, le prénom, le courriel et le téléphone directs de son contact désigné, ainsi que la
> confirmation de son adhésion au réseau. Pour 18 organisations, elles comportent en outre
> quatre années de relevés de compte mensuels — soldes, limites et contreparties nommées —
> permettant une approche mentionnant des transactions et des relations commerciales réelles.

**Estimation du niveau de gravité** ⚠️ — **recommandation : *Important***.

Arguments pour un niveau inférieur (*Limité*) : absence de données sensibles, bancaires ou
d'identifiants nationaux ; mots de passe fortement hachés ; intégrité vérifiée intacte ;
environ 150 personnes concernées. Arguments contraires : quatre années de relevés financiers
concernant 18 organisations identifiées, et un vecteur d'hameçonnage d'une crédibilité
démontrée. Le niveau *Maximal* n'est pas soutenable. **L'arbitrage final vous appartient.**

---

## 12. Mesures techniques et organisationnelles appliquées suite à la violation

✅ Élément disponible.

**Réalisées :** conservation des éléments de preuve (racines web, journaux, sauvegardes de
bases) ; arrêt d'Apache sur les deux serveurs le 26 août ; analyse forensique complète de
l'intrusion et de l'ensemble des programmes malveillants recueillis ; vérification de
l'intégrité de la base Cyclos sur 417 tables ; confirmation du périmètre — aucune
application non gérée sur le serveur de production.

**En cours ou planifiées :** reconstruction complète du serveur de préproduction à partir de
sources saines, en version SPIP 4.4.21 ou ultérieure ; réinitialisation forcée des mots de
passe des 128 comptes Cyclos actifs et invalidation des sessions ; rotation de l'ensemble
des secrets de bases de données, de services et d'infrastructure ; correction des permissions
des sauvegardes ; suppression des identifiants en clair du dépôt de code ; activation de la
journalisation des connexions PostgreSQL ; règles de filtrage applicatif bloquant la
signature de l'exploit ; contrôle d'intégrité des fichiers ; **mise en place d'une procédure
de veille de sécurité et d'application des correctifs** ; séparation du site public et de la
plateforme Cyclos ; mise sous gestion de configuration de l'ensemble des applications
exposées sur Internet.

## 13. Communication aux personnes concernées

⚠️ **Recommandation : *Non, mais elles le seront*** — avec indication d'une date prévue.

❌ Date prévue · moyen utilisé (courriel aux adhérents ; envisager un courrier recommandé ou
un appel téléphonique pour les 18 titulaires de comptes).

Recommandations détaillées au § 8 de l'analyse de risque. Deux points méritent d'être
rappelés : procéder à la réinitialisation des mots de passe **avant** la communication, de
sorte que tout message invitant à « cliquer ici pour réinitialiser » soit manifestement
frauduleux ; et avertir explicitement que la notification de violation constitue elle-même
un prétexte idéal pour une campagne d'hameçonnage fondée sur les données divulguées.

## 14. Notifications transfrontalières et autres notifications

✅ — ☐ Non (aux trois questions), sous réserve que les adhérents soient exclusivement
français. ⚠️ Confirmer qu'aucune organisation adhérente n'est établie dans un autre État
membre.

---

## Récapitulatif des éléments manquants

**L'ensemble des éléments d'investigation est complet.** Les points en suspens sont
exclusivement administratifs :

| # | Élément | Source |
|---|---|---|
| 1 | SIREN, dénomination, TVA, secteur, effectif, adresse | ❌ registres de l'association |
| 2 | Responsable légal — identité et adresse électronique | ❌ |
| 3 | Personne à contacter — identité, fonction, courriel, téléphone | ❌ |
| 4 | Qualification de la relation d'hébergement (OVH, tiers administrateur éventuel) | ⚠️ |
| 5 | Date et canal prévus pour la communication aux adhérents | ❌ |
| 6 | Niveau de gravité retenu | ⚠️ recommandation : *Important* |
| 7 | Confirmation qu'aucun adhérent n'est établi hors de France | ⚠️ |
| 8 | Forme juridique des 18 titulaires de comptes (§ 7 bis, action 17d) | ⚠️ requête immédiate |

Une question technique demeure ouverte et peut affecter le périmètre : la base de données
utilisée par `/var/www/mlml.fr` n'a pas été identifiée, alors qu'un client d'administration
de bases de données (Adminer) fonctionnel y avait été déposé
(`2026-08-21-spip-rce-webshell.md`, § 8, action 6d). Si elle contient des données
personnelles, les nombres d'enregistrements et de personnes ci-dessus augmentent. Cet
élément relève de la *notification complémentaire*.
