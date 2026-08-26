#!/usr/bin/env bash
# Triage for preprod-mlml-01 — INC-2026-08-21-001
#
# READ-ONLY. This script inspects and reports; it modifies nothing.
# Run as a user with sudo:   sudo bash triage-preprod.sh 2>&1 | tee preprod-triage.txt
#
# Mirrors the investigation performed on prod-mlml-01.

DOCROOT="/var/www/www-monel-co.mlml.fr"
PRISTINE_COMPILER_SHA="c479dc2e3f9c378dc104eacc3959450d0239bdf8ac90ab57dc9a2b26353fa49a"

hr() { printf '\n===== %s =====\n' "$1"; }

hr "0. Context"
hostname; date; echo "docroot: $DOCROOT"
grep -h "spip_version_branche = " "$DOCROOT/ecrire/inc_version.php" 2>/dev/null

# ---------------------------------------------------------------- webshells --
hr "1. Non-standard PHP in webroot (expect ONLY index.php + spip.php)"
ls -la "$DOCROOT"/*.php 2>/dev/null

hr "2. Known IOC filenames"
find "$DOCROOT" -maxdepth 2 \( -name 'hasil*.php' -o -name 'img_cache.php' \) -ls 2>/dev/null

hr "3. IOC hashes (compare against report section 6)"
#   img_cache.php  ad1b350ff89c2bed2f16ebb3fa41d7bf0d6ab588ae040aa25f44bef89da1ff30
#   hasil.php      f218b883a6e2cc76ec61fbfd541c4b2dd970a1021b0d429e505251c8fbb2c865
find "$DOCROOT" -maxdepth 2 -name '*.php' -newermt '2026-08-15' -exec sha256sum {} \; 2>/dev/null

hr "4. Any file changed during the attack window (20-27 Aug), excluding cache"
find "$DOCROOT" -newermt '2026-08-20' ! -newermt '2026-08-27' -type f \
     -not -path "*/tmp/*" -not -path "*/local/cache*" -ls 2>/dev/null | head -40

hr "5. PHP in directories that must never contain it"
find "$DOCROOT/IMG" "$DOCROOT/local" "$DOCROOT/squelettes" -name '*.php' 2>/dev/null

# ------------------------------------------------------------ core integrity --
hr "6. compiler.php integrity"
ACTUAL=$(sha256sum "$DOCROOT/ecrire/public/compiler.php" 2>/dev/null | cut -d' ' -f1)
echo "actual:   $ACTUAL"
echo "pristine: $PRISTINE_COMPILER_SHA"
[ "$ACTUAL" = "$PRISTINE_COMPILER_SHA" ] && echo "==> OK (unmodified)" || echo "==> *** MISMATCH — INVESTIGATE ***"

hr "7. Attacker patch marker in core"
grep -rl "safe_export_env" "$DOCROOT/ecrire" "$DOCROOT/tmp/cache" 2>/dev/null | head

# -------------------------------------------------------------------- logs ---
hr "8. Exploit attempts in access logs"
for f in /var/log/apache2/*access.log; do
  [ -f "$f" ] && echo "$f: $(grep -c 'recherche=%3C%3Fphp' "$f" 2>/dev/null)"
done
for f in /var/log/apache2/*access.log.*.gz; do
  [ -f "$f" ] && echo "$f: $(zgrep -c 'recherche=%3C%3Fphp' "$f" 2>/dev/null)"
done

hr "9. Did any exploit SUCCEED? (200 on a non-standard .php in webroot)"
{ zcat /var/log/apache2/*access.log*.gz 2>/dev/null; cat /var/log/apache2/*access.log* 2>/dev/null; } \
  | grep -oE '"(GET|POST) /[a-zA-Z0-9_-]+\.php[^"]*" 200' \
  | grep -vE '/(spip|index|prive|ecrire)\.php' | sed -E 's/\?.*//' | sort | uniq -c | sort -rn | head -20

hr "10. Source IPs of exploit attempts"
{ zcat /var/log/apache2/*access.log*.gz 2>/dev/null; cat /var/log/apache2/*access.log* 2>/dev/null; } \
  | grep 'recherche=%3C%3Fphp' | awk '{print $1}' | sort | uniq -c | sort -rn | head -15

hr "11. SPIP runtime errors (the attacker-patch signature)"
grep -h "safe_export_env" "$DOCROOT"/tmp/log/*.log 2>/dev/null | tail -5
echo "occurrences: $(grep -hc 'safe_export_env' "$DOCROOT"/tmp/log/*.log 2>/dev/null | paste -sd+ - | bc 2>/dev/null)"

# ------------------------------------------------- www-data reachable data ---
hr "12. CRITICAL — can www-data read the synced PROD Cyclos backups?"
sudo -u www-data ls -la /var/backups/postgresql_prod/latest-daily/ 2>&1 | head
echo "--- read test (any output below = prod Cyclos data is exposed on preprod) ---"
sudo -u www-data zcat /var/backups/postgresql_prod/latest-daily/cyclos4.sql.gz 2>&1 | head -3

hr "13. Can www-data read the preprod->prod SSH key? (MUST fail)"
sudo -u www-data cat /var/backups/.ssh/id_rsa 2>&1 | head -3
ls -la /var/backups/.ssh/ 2>/dev/null

hr "14. Can www-data reach the local (preprod) Cyclos DB?"
sudo -u www-data psql "postgresql://cyclos:cyclospwd@127.0.0.1:5432/cyclos4" -c '\dt' 2>&1 | head -8

hr "15. Docker socket access (MUST be denied)"
sudo -u www-data docker ps 2>&1 | head -3

# ------------------------------------------------------------ host integrity --
hr "16. SSH sources and failures"
grep -hoE "Accepted publickey for [a-z]+ from [0-9.]+" /var/log/auth.log* 2>/dev/null | sort | uniq -c | sort -rn | head
echo "failed/invalid attempts: $(grep -hicE 'Failed password|Invalid user|authentication failure' /var/log/auth.log* 2>/dev/null | paste -sd+ - | bc 2>/dev/null)"

hr "17. Interactive logins"
last -F | head -15

hr "18. Persistence: cron and authorized_keys"
for u in root ubuntu www-data postgres backup; do
  echo "--- crontab: $u ---"; crontab -u "$u" -l 2>/dev/null | grep -v '^#'
done
echo "--- authorized_keys ---"
find /root /home /var/backups /var/lib/postgresql -name authorized_keys -exec ls -la {} \; -exec cat {} \; 2>/dev/null

hr "DONE"
echo "Decisive checks: #1, #6, #9, #12, #13."
