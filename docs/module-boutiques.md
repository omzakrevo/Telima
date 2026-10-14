# Module Boutiques — vêtements, chaussures, accessoires : lien partageable et commande directe

Même principe que le module Restaurants, adapté aux boutiques : un commerçant crée sa boutique, saisit son catalogue
(articles avec **tailles, couleurs et stock**) et reçoit un lien public `https://telimatchi.com/b/<lien>` à envoyer à ses clients
(WhatsApp, Facebook, TikTok…). Le catalogue est visible **sans compte** ; commander demande de se connecter.

## Parcours
| Qui | Où | Actions |
|---|---|---|
| Commerçant | Accueil → *Ma boutique* (`/shop`) | Créer (jusqu'à 5), modifier, logo/couverture, rayon de livraison, minimum, délai |
| Commerçant | `/shop/<id>` | Onglet Commandes (accepter, refuser, en préparation, prête, remise), onglet Catalogue (catégories, articles, photo, tailles, couleurs, stock), onglet Mon lien, interrupteur Ouvert/Fermé |
| Client | `/client/shops` | Boutiques autour de moi, recherche nom/article/quartier |
| Tout le monde | `/b/<lien>` | Page de la boutique, catalogue ; choix de la taille et de la couleur avant l'ajout au panier |
| Client connecté | `/b/<lien>/order` | Retrait ou livraison, adresse, frais calculés, message, confirmation |
| Client | `/client/shops/orders` | Suivi, annulation tant que non acceptée |
| Administrateur | `/admin/shops` | Suspendre / rétablir (le lien cesse de fonctionner) |

## Articles : tailles, couleurs, stock
* **Tailles** et **couleurs** : listes séparées par des virgules (« S, M, L » ; « Rouge, Bleu »). Vide = pas de choix.
  Si l'article en propose, le client **doit** en choisir une ; le serveur le vérifie.
* **Stock** : nombre entier, ou vide = quantité non suivie. Il diminue à chaque commande et **revient** si la commande est
  refusée, annulée par le client ou si la livraison est annulée. À zéro, l'article s'affiche « Épuisé ».
* Une même robe en taille M puis en taille L fait deux lignes dans le panier ; la limite de stock s'applique à l'article entier.

## Base de données (migrations `telima_15_boutiques` et `telima_16_telephone_facultatif`)
Tables : `shops`, `shop_categories`, `shop_products`, `shop_orders`, `shop_order_items`. Compartiment de photos : `telima-boutiques`.
Fonctions : `register_shop`, `shop_by_slug` (public), `find_shops` (public), `shop_delivery_fee`, `create_shop_order`,
`shop_order_action`, `cancel_shop_order`, `shop_dashboard`, `admin_set_shop_status`, `_shop_restock` (interne).

* Les prix sont relus côté serveur ; le client ne peut pas les modifier.
* Le commerçant ne peut pas se valider, changer de propriétaire ni modifier son lien (déclencheur `tg_shops_guard`).
* Commande « prête » en livraison : création automatique d'une livraison Telima (moto) ; le statut suit celui de la livraison.
* Paiement : espèces uniquement (le livreur encaisse les articles pour la boutique).
* La suppression complète d'un utilisateur (Admin → Utilisateurs) supprime aussi ses boutiques et leurs commandes.

## Mise en ligne
1. Base de données : migrations déjà appliquées en production.
2. Application : le lien `/b/…` ouvre l'application Android grâce à un nouveau filtre dans `AndroidManifest.xml` : c'est un changement
   natif, donc il faut une **nouvelle version complète** (1.8.0), pas seulement un patch Shorebird.
3. Site web : `.htaccess` (voir `scripts/deploy_lws.py --htaccess`) pour que `/b/<lien>` ouvre l'application.

## QR code du lien
* **Commerçant** : onglet *Mon lien* → bouton *QR code à télécharger* (affichage + image PNG 1024 px, fond blanc, prête à imprimer pour la vitrine, le menu, les flyers).
* **Client** : sur la page publique, icône QR code dans la barre du haut → même feuille, pour garder ou envoyer le code.
* Web : le PNG est téléchargé directement ; mobile : la feuille de partage du téléphone s'ouvre (enregistrer, WhatsApp…).
* Le code ne contient que le lien public ; il suit donc le commerce (aucun stockage, aucune migration).

## Pistes suivantes
Plusieurs photos par article, paiement Mobile Money, guide des tailles, promotions et codes de réduction.
