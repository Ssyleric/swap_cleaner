# `swap_cleaner.sh` — Purge automatique du swap avec notification Discord

🧹 **Objectif**  
Sur un hôte **Proxmox VE (PVE)**, ce script surveille l’utilisation du **swap** et, si elle reste **au-dessus d’un seuil** pendant une durée continue définie, il déclenche une purge douce du swap (`swapoff -a && swapon -a`).  
À chaque action (ou erreur), une **notification Discord** est envoyée (message + **pièce jointe** du log).

---

## 🧩 Fonctionnement (résumé)
1. À **chaque exécution** (idéalement via `cron`), le script lit le **% de swap utilisé** (`free -m`).  
2. S’il est **≥ THRESHOLD** (par défaut **90%**), un **compteur** s’incrémente dans `STATE_FILE` (`/var/tmp/swap_usage_count.txt`).  
3. Si ce compteur atteint `DURATION_MIN / CHECK_EVERY_MIN` (ex.: **120 min / 10 min = 12** exécutions consécutives), le script :  
   - journalise l’action dans `LOG` (`/var/log/swap_cleaner.log`),  
   - exécute `swapoff -a && swapon -a`,  
   - envoie une **notification Discord** avec le **log joint**,  
   - réinitialise le compteur.  
4. Si l’usage repasse **sous** le seuil, le **compteur est remis à 0**.

Le script s’exécute **en instance unique** grâce à un **lock** (`/var/tmp/.swap_cleaner.lock`) pour éviter les chevauchements via `cron`.

---

## ✅ Prérequis
- Hôte **PVE** (ou Linux avec `swapoff` / `swapon` disponibles).
- **Root** requis (ne pas utiliser `sudo` dans PVE, exécuter en root directement).
- Paquet **`jq`** (installé automatiquement si absent).
- Accès **HTTP sortant** vers l’URL **Discord Webhook**.

---

## 🔧 Variables (override possibles via l’environnement)
| Variable            | Par défaut | Description |
|---------------------|------------|-------------|
| `WEBHOOK`           | *(exemple dans le script)* | URL du **Discord Webhook** recevant la notification. |
| `THRESHOLD`         | `90`       | Seuil de **% de swap utilisé** déclenchant le comptage. |
| `CHECK_EVERY_MIN`   | `10`       | Fréquence (en minutes) d’exécution par `cron`. |
| `DURATION_MIN`      | `120`      | Durée **continue** (en minutes) au-delà du seuil avant action. |
| `STATE_FILE`        | `/var/tmp/swap_usage_count.txt` | Compteur persistant entre exécutions. |
| `LOG`               | `/var/log/swap_cleaner.log`     | Journal d’exécution (+ joint à Discord). |

**Calcul interne :** nombre d’exécutions consécutives requises = `ceil(DURATION_MIN / CHECK_EVERY_MIN)`.

---

## 📦 Installation
1. **Copier** le script dans votre répertoire de scripts (recommandé : `/home/scripts`) :  
   ```bash
   install -m 0755 swap_cleaner.sh /home/scripts/swap_cleaner.sh
   ```
2. **Vérifier** le shebang et les permissions :  
   ```bash
   head -n 1 /home/scripts/swap_cleaner.sh
   ls -l /home/scripts/swap_cleaner.sh
   ```
3. **Créer** les emplacements nécessaires (log + state seront créés au premier run) :  
   ```bash
   mkdir -p /var/tmp
   touch /var/log/swap_cleaner.log
   ```

> 💡 Conformément à votre organisation, `/home/scripts` est le dossier de référence pour vos scripts.

---

## ⏱️ Planification (cron)
Exécution **toutes les 10 minutes** (cohérente avec la valeur par défaut `CHECK_EVERY_MIN=10`).  
Ouvrir le **crontab root** :  
```bash
crontab -e
```
Ajouter la ligne suivante :  
```cron
*/10 * * * * CHECK_EVERY_MIN=10 DURATION_MIN=120 THRESHOLD=90 WEBHOOK="https://discord.com/api/webhooks/XXX/YYY" /home/scripts/swap_cleaner.sh
```
- **Adapter** `WEBHOOK`, `THRESHOLD`, `CHECK_EVERY_MIN`, `DURATION_MIN` si nécessaire.
- **Important :** le script doit être lancé **en root** (crontab root).

### Exemples d’override
- Exécuter **toutes les 5 minutes** avec seuil **80%** et durée **1h** :  
  ```cron
  */5 * * * * CHECK_EVERY_MIN=5 DURATION_MIN=60 THRESHOLD=80 WEBHOOK="https://discord.com/api/webhooks/XXX/YYY" /home/scripts/swap_cleaner.sh
  ```
- Exécuter **toutes les 15 minutes** avec durée **2h30** :  
  ```cron
  */15 * * * * CHECK_EVERY_MIN=15 DURATION_MIN=150 WEBHOOK="https://discord.com/api/webhooks/XXX/YYY" /home/scripts/swap_cleaner.sh
  ```

---

## 🧪 Tests rapides (safe)
1. **Test lecture & log** (sans forcer purge) :  
   ```bash
   THRESHOLD=0 CHECK_EVERY_MIN=10 DURATION_MIN=9999 /home/scripts/swap_cleaner.sh && tail -n 5 /var/log/swap_cleaner.log
   ```
   - Force `USAGE ≥ THRESHOLD` mais **n’atteint pas** la durée → **aucune purge**.
2. **Test action contrôlée** (⚠️ purge volontaire) :  
   ```bash
   THRESHOLD=0 CHECK_EVERY_MIN=1 DURATION_MIN=1 /home/scripts/swap_cleaner.sh
   ```
   - Déclenche `swapoff -a && swapon -a` **une fois** et envoie la **notif Discord**.

---

## 🔔 Notifications Discord
- Le message est formaté **multiligne** et limité **< 2000 caractères** (troncature gérée).  
- Le **fichier log** `/var/log/swap_cleaner.log` est **joint** systématiquement aux actions/erreurs.  
- Le message inclut **Avant/Après** (`free -h`) pour la lisibilité.

> ✅ Respecte vos exigences **Discord** : `jq -Rs` pour payload JSON et **pièce jointe** via `curl -F`.

---

## 🛡️ Sécurité & impacts
- L’action `swapoff -a && swapon -a` peut **déplacer de la mémoire** et provoquer une **latence** temporaire selon la charge.  
- Assurez-vous d’avoir **suffisamment de RAM** pour absorber le contenu du swap.  
- Évitez d’exécuter en même temps que des opérations lourdes (ex.: backup/restores massifs).  
- Le script **échoue en silence** côté cron si le réseau vers Discord est indisponible (les logs locaux restent disponibles).

---

## 🧰 Dépannage
- **Aucune notif Discord ?**  
  - Vérifiez la **valeur `WEBHOOK`** et la **connectivité** (pare-feu, DNS).  
  - Consultez `/var/log/swap_cleaner.log` et rejouez le test d’action contrôlée.
- **Pas d’action malgré un swap élevé ?**  
  - Confirmez la **fréquence cron** réelle et le **calcul `ceil(DURATION_MIN / CHECK_EVERY_MIN)`**.  
  - Examinez `STATE_FILE` (compteur) et supprimez-le si besoin : `rm -f /var/tmp/swap_usage_count.txt`.
- **Chevauchements cron** :  
  - Le lock file (`/var/tmp/.swap_cleaner.lock`) empêche les runs concurrents.  
  - Vérifiez l’absence d’exécutions trop longues (IO/charge).

---

## 🗑️ Désinstallation
```bash
crontab -e      # retirer la ligne cron
rm -f /home/scripts/swap_cleaner.sh /var/log/swap_cleaner.log /var/tmp/swap_usage_count.txt /var/tmp/.swap_cleaner.lock
```

---

## ✍️ Note
- Le script est conçu pour être **idempotent**, robuste (`set -euo pipefail`) et **VSN** (bonnes pratiques, `jq` requis, envoi Discord avec pièce jointe, limite 2000 caractères).  
- Adaptez `THRESHOLD`, `CHECK_EVERY_MIN`, `DURATION_MIN` en fonction de votre profil d’utilisation mémoire réelle.

---

## 📄 Licence
Utilisation interne. Adapter si nécessaire à votre politique de sécurité.
