#!/usr/bin/env bash
# Triage for the manually-deployed SPIP at /var/www/mlml.fr on preprod-mlml-01
# INC-2026-08-21-001
#
# READ-ONLY. Inspects and reports; modifies nothing.
#   sudo bash triage-preprod-mlml.sh 2>&1 | tee preprod-mlml-triage.txt
#
# This instance absorbed 1,782 of the 1,796 exploit attempts seen on preprod and is
# NOT ansible-managed, so its SPIP version and file inventory are unknown.

DOCROOT="/var/www/mlml.fr"

hr() { printf '\n===== %s =====\n' "$1"; }

hr "0. Context"
hostname; date; echo "docroot: $DOCROOT"
echo -n "SPIP version: "
grep -h "spip_version_branche = " "$DOCROOT/ecrire/inc_version.php" 2>/dev/null || echo "NOT FOUND — check layout"
ls -la "$DOCROOT" | head -30

# ------------------------------------------------------------- known IOCs ----
hr "1. Shells seen returning HTTP 200 in the access logs"
for n in sitemap.php shadow.php bootstrap.php _dec_cvfmev.php Nx_.php img_cache.php hasil.php; do
  find "$DOCROOT" -name "$n" -ls 2>/dev/null
done

hr "2. Same IOC names anywhere on the filesystem (in case of other docroots)"
find / -xdev \( -name 'sitemap.php' -o -name 'shadow.php' -o -name 'bootstrap.php' \
     -o -name '_dec_cvfmev.php' -o -name 'Nx_*.php' -o -name 'img_cache.php' \
     -o -name 'hasil*.php' \) -ls 2>/dev/null

hr "3. Hashes of anything found (compare to report section 6)"
#   preprod actor 2:  img_cache.php d63abfc6…   Nx_.php aabd3a41…
#   prod actor 1:     img_cache.php ad1b350f…   hasil.php f218b883…
find "$DOCROOT" -maxdepth 3 -name '*.php' -newermt '2026-08-01' -exec sha256sum {} \; 2>/dev/null

# --------------------------------------------------------- generic sweeps ----
hr "4. Top-level PHP in docroot (a stock SPIP has only index.php + spip.php)"
ls -la "$DOCROOT"/*.php 2>/dev/null

hr "5. PHP in directories that must never contain it"
find "$DOCROOT/IMG" "$DOCROOT/local" "$DOCROOT/tmp" "$DOCROOT/squelettes" \
     -name '*.php' 2>/dev/null | head -40

hr "6. Any PHP file modified since 2026-08-01"
find "$DOCROOT" -name '*.php' -newermt '2026-08-01' -ls 2>/dev/null | head -60

hr "7. World-writable files (actor 2 dropped shells as mode 666)"
find "$DOCROOT" -type f -perm -0002 -ls 2>/dev/null | head -40

hr "8. Obfuscation / webshell signatures"
grep -rlE 'eval\(|base64_decode\(|gzinflate\(|str_rot13\(|assert\(|\$_(POST|GET|REQUEST)\[[^]]+\]\(' \
     --include='*.php' "$DOCROOT" 2>/dev/null | head -40

hr "9. Attacker patch marker (its presence would prove exploitation)"
grep -rl "safe_export_env" "$DOCROOT" 2>/dev/null | head

hr "10. Is the var_export() sink present and unpatched?"
grep -n "var_export" "$DOCROOT/ecrire/public/compiler.php" 2>/dev/null | head

# -------------------------------------------------------------------- logs ---
hr "11. Exploit attempts against this vhost"
for f in /var/log/apache2/mlml.fr_access.log; do
  [ -f "$f" ] && echo "$f: $(grep -c 'recherche=%3C%3Fphp' "$f" 2>/dev/null)"
done
for f in /var/log/apache2/mlml.fr_access.log.*.gz; do
  [ -f "$f" ] && echo "$f: $(zgrep -c 'recherche=%3C%3Fphp' "$f" 2>/dev/null)"
done

hr "12. SUCCESSFUL requests to the dropped shells (the decisive check)"
{ zcat /var/log/apache2/mlml.fr_access.log*.gz 2>/dev/null; cat /var/log/apache2/mlml.fr_access.log 2>/dev/null; } \
  | grep -aE '(sitemap|shadow|bootstrap|_dec_cvfmev|Nx_|img_cache|hasil)\.php' \
  | grep -a ' 200 ' | tail -40

hr "13. First and last exploit attempt against this vhost"
{ zcat /var/log/apache2/mlml.fr_access.log*.gz 2>/dev/null; cat /var/log/apache2/mlml.fr_access.log 2>/dev/null; } \
  | grep -a 'recherche=%3C%3Fphp' | grep -aoE '\[[^]]+\]' | sort -t: -k1 | (head -3; echo '   ...'; tail -3)

hr "14. Source IPs attacking this vhost"
{ zcat /var/log/apache2/mlml.fr_access.log*.gz 2>/dev/null; cat /var/log/apache2/mlml.fr_access.log 2>/dev/null; } \
  | grep -a 'recherche=%3C%3Fphp' | awk '{print $1}' | sort | uniq -c | sort -rn | head -15

hr "15. SPIP runtime error log"
ls -la "$DOCROOT"/tmp/log/ 2>/dev/null | head
grep -h "safe_export_env" "$DOCROOT"/tmp/log/*.log 2>/dev/null | tail -5

# ------------------------------------------------------------------- data ----
hr "16. Database credentials this instance uses (identify its DB)"
grep -hoE "\\\$(db_server|db_host|login|pass|db)\s*=\s*'[^']*'" \
     "$DOCROOT/config/connect.php" 2>/dev/null | sed "s/=.*'\(.*\)'/= <redacted len=\${#1}>/" || \
  echo "connect.php unreadable or absent"
ls -la "$DOCROOT/config/" 2>/dev/null

hr "DONE"
echo "Decisive checks: #1, #3, #9, #12."
