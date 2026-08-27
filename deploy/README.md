# Immutable SPIP deployment — www.monel.co

Built in response to [`incidents/2026-08-21-spip-rce-webshell.md`](../incidents/2026-08-21-spip-rce-webshell.md).

Everything SPIP executes lives in a versioned, read-only image. Upgrading is a
rebuild; rolling back is the previous tag. The three directories SPIP genuinely
needs to write are volumes, and none of them can execute PHP.

**Status.** Verified end to end against the preserved production database: the real
site renders (homepage, articles, forms), compiled skeletons land outside the webroot,
nothing in the webroot is writable, the database is unreachable from anywhere but the
web container, and every denial holds against real webshell-shaped files. **Not yet
done:** the core upgrade migration from 4.4.16, which runs on the first visit to
`/ecrire/` and needs a real admin login. See [Before first deploy](#before-first-deploy).

---

## What is pinned

| | Version | Pinned in |
|---|---|---|
| SPIP core | **4.4.21** | `core.lock` (official zip, sha256-pinned) |
| 10 contrib plugins | see below | `plugins.lock` (sha256 per archive) |
| Site templates | this repository | build context |

4.4.21 is the floor: 4.4.20 fixes CVE-2026-77647 only, and the publisher released
4.4.21 precisely because 4.4.20 remained exploitable (report §3.1a). 4.4.21 is also
the current latest — there is no newer release to skip to.

### Plugin versions

The old install used SPIP's back-office installer, which leaves plugins in
`spip/plugins/auto/<name>/v<version>/` with no manifest anywhere. Those versions were
recovered from the directory names and re-pinned against the SVP depot. Four could
not be pinned as-installed because the depot no longer carries them — patch bumps
within the same major, all of them:

| Plugin | Was installed | Pinned | |
|---|---|---|---|
| bootstrap4 | 4.7.2 | 4.7.2 | |
| facteur | 5.4.0 | **5.4.1** | 5.4.0 withdrawn upstream |
| formidable | 7.5.3 | **7.6.1** | |
| nospam | 3.0.1 | 3.0.1 | |
| saisies | 6.3.4 | **6.3.5** | 6.3.4 withdrawn upstream |
| scssphp | 3.1.1 | **3.1.2** | |
| select2 | 2.1.0 | **2.1.2** | 2.1.0 withdrawn upstream |
| spip_bonux | 4.4.1 | 4.4.1 | |
| verifier | 3.9.2 | 3.9.2 | |
| yaml | 3.2.0 | 3.2.0 | |

Composer is not an option for these: `get.spip.net/composer` carries 83 packages and
none of the ten are among them. The SVP depot (`plugins.spip.net/depots/principal.xml`)
serves immutable per-version archives, so `plugins.lock` records a sha256 for each and
`bin/fetch-plugins.sh` fails the build on any mismatch.

This is report recommendation #2 — *pin the core and plugins to a manifest* — made
concrete. The manifest is also the answer to recommendation #3: there is now a single
file that says what this site is made of.

---

## Layout

```
.dockerignore               at the REPO ROOT — Docker reads it from the context root
.github/workflows/
├── build-push.yml          build and push to GHCR on a vX.Y tag
└── check-updates.yml       nightly lockfile watch; opens an issue when behind

deploy/
├── Dockerfile              two-stage build: assemble webroot, then harden runtime
├── compose.yaml            two services: web (Apache + mod_php) and db (MariaDB)
├── core.lock               SPIP core version — single source of truth
├── plugins.lock            contrib plugins: version, archive path, sha256, size
├── bin/
│   ├── fetch-plugins.sh    build-time: download, verify, unpack (fails closed)
│   ├── check-updates.sh    compare locks against upstream; --rehash to bump
│   └── backup-db.sh        daily dump out of the db container (install as cron)
├── config/
│   ├── mes_options.php     runtime options; relocates tmp/ outside the webroot
│   └── connect.php.example template for secrets/connect.php
├── apache/
│   ├── hardening.conf      server-wide: ServerTokens, TraceEnable, global deny
│   └── monel.conf          the vhost, and the PHP-execution denials
└── php/
    ├── zz-spip-hardening.ini
    └── opcache-blacklist.txt
```

---

## The writable set

Measured against the live install rather than assumed:

| Path | Where it lives | Web-reachable | PHP can run there |
|---|---|---|---|
| `IMG/` (58 MB) | volume, inside webroot | yes, sandboxed CSP | **no** |
| `local/` (3.4 MB) | volume, inside webroot | yes | **no** |
| `tmp/` (12 MB) | volume at `/var/spip/tmp`, **outside webroot** | **no** | yes, unavoidably |
| `config/` | read-only in the image | denied | n/a |
| secrets | `./secrets`, read-only, outside webroot | **no** | n/a |

The third row is the honest one. SPIP compiles templates into `tmp/cache/skel/` and
`include`s them; that directory must be both writable and executable-by-include. It is
where the 21 August payload actually ran, and no amount of read-only webroot changes
that. What changes is everything after: `_DIR_TMP` puts it outside the document root,
so it is not addressable by URL, and the compiled cache expires. The attacker had to
re-drop the shell four times before landing a real file in the webroot — under this
layout, that last step fails.

### What the image actually buys you

- **No persistence.** `img_cache.php` and `hasil.php` cannot be written. Neither can
  `ecrire/public/compiler.php` be modified — which is what took the site down.
- **Remediation becomes a restart.** `docker diff` on a running container is a real
  integrity check because the filesystem is immutable by construction. This is report
  recommendation #1 without needing a separate FIM product.
- **The back office stops being a write path.** `plugins/` is root-owned mode 0555 and
  `spip_loader.php` is deleted, so SVP finds nothing writable and the "install plugin"
  button is inert.
- **A dropped file cannot execute.** `php_admin_flag engine off` on `IMG/` and
  `local/` cannot be overridden by anything written into those directories — it is the
  strongest primitive available here, and it has no nginx equivalent. A `FilesMatch`
  deny means a shell is not disclosed as source either.
- **No second stage.** `exec`/`system`/`proc_open`/`popen`/`putenv` are all in
  `disable_functions`, so PHP cannot spawn a downloader at all. `putenv` is there
  specifically to break the `LD_PRELOAD` bypass found in `stats-mailer.php`. The
  `wget`/`curl` binaries are also deleted, but treat that as noise reduction rather
  than a control: Alpine's `wget` is a BusyBox applet and removing the symlink does
  not remove the applet. The boundary is `disable_functions` plus egress filtering.
- **No CGI, and no usable `.htaccess`.** `mod_cgi`/`mod_cgid` are not loaded at all, so
  the `AddHandler cgi-script .alfa` trick from `/var/www/mlml.fr` has nothing to attach
  to. `AllowOverride None` on the writable directories means a dropped `.htaccess` is
  never read; `AllowOverride All` on the webroot is safe precisely because that
  directory is read-only, and it buys us SPIP's own upstream-maintained rules.
- **No symlink escape.** `Options SymLinksIfOwnerMatch` on the writable directories
  refuses any symlink whose target has a different owner, so a link from `IMG/` to the
  mounted `connect.php` is not followed.

---

## What this does not fix

**Containerisation is not isolation, and this is the point the incident already
proved.** Cyclos was containerised and it bought nothing, because `network_mode: host`
and PostgreSQL on `0.0.0.0` removed every boundary (report §5.1). A container here
blocks §5.2 — it cannot read `/var/lib/postgresql/backups/` — but it does **not** block
§5.3: a container on a bridge network still reaches a host PostgreSQL via the gateway
address.

So the load-bearing control is still report recommendation #9: **run this on a host
that holds no Cyclos data.** If that is not done, the largest finding in the incident
report is unaddressed no matter how good the image is.

Also unaddressed by anything in this directory: rotating the credentials in report
item 11, the `preprod-mlml-01` rebuild (item 6), and the CNIL determination (item 17).

---

## Before first deploy

Ordered. Items 1–3 are blocking; the site will not start without them.

1. **Provide the secrets.** Create `deploy/secrets/` — untracked — with:
   - `connect.php` — database credentials, **rotated**, not the compromised ones.
     Start from `config/connect.php.example`; note the host is `db`, the compose
     service, not `localhost`.
   - `cles.php` — SPIP's encryption keys, carried over from the old install.

   `cles.php` must be carried over rather than regenerated: SPIP uses it to decrypt
   existing stored values, and it cannot create one because the mount is read-only.
   Without it the site returns a 200 with an empty page and logs
   `Echec ecriture du fichier cle`. Copy it from the preserved webroot, not from a
   running compromised host.

   **Own them `root:65532`, mode `0640` — not `65532:65532`.** `SymLinksIfOwnerMatch`
   is what stops an attacker symlinking from `IMG/` to `connect.php`, and it compares
   the symlink's owner against the target's. If the secrets are owned by the runtime
   user, that comparison succeeds and the file is served as a static download. Verified
   both ways: a root-owned target is refused, a same-owner target is served.

2. **Set `MONEL_DB_PASSWORD`.** It creates the database user on first start and must
   match the password in `connect.php`. Do not reuse the pre-incident value — the old
   one is in a dump the attacker could read (report §4.3).

3. **Migrate the data.** One-time, against the real database:
   ```sh
   gunzip -c /var/backups/mysql/sqldump/monel.sql.gz \
     | docker compose -f deploy/compose.yaml exec -T db mariadb -umonel -p"$MONEL_DB_PASSWORD" monel
   ```
   Then copy the verified-clean `IMG/` into the `spip_img` volume. Note the image has
   no installer (`ecrire/install` is deleted at build), so an empty database cannot
   bootstrap itself — restoring a dump is the only supported path.

4. **Check `_BAZAAR_VIDEO_ID`.** It is 50 in the recovered prod config and 26 in
   development checkouts — SPIP article ids are per-database. 50 is the default here.
   Confirm it against the restored database and set `MONEL_BAZAAR_VIDEO_ID` if it
   differs — see [Runtime settings](#runtime-settings); no rebuild needed.

5. **Decide the `/ecrire/` restriction.** The block is written and commented out in
   `apache/monel.conf`. Four accounts use the back office. If they can work from known
   networks, uncomment it — it removes the entire authenticated attack surface from the
   internet, and it is the single cheapest control in this directory.

6. **Check the image-processing setting.** `exec` is disabled, so SPIP must use GD
   (the default), not `convert`/netpbm. Back office → Configuration → Fonctions
   avancées → Traitement des images.

7. **Check facteur's transport.** It must be SMTP. The sendmail transport uses
   `popen()`, which is disabled — and there is no MTA in the container anyway.

8. **Run the core migration.** The database is at the 4.4.16 schema; the image ships
   4.4.21. SPIP applies the migration on the first visit to `/ecrire/` by a logged-in
   admin. It writes to the database, not the filesystem, so read-only is fine — but the
   deploy is not finished until someone does it.

9. **Configure `mod_remoteip`** so the container logs the real client address rather
   than the front proxy's. Without it every log line records the proxy — which would
   have made the 57-source-address analysis in the incident report impossible, and
   would also break the `/ecrire/` IP restriction above.

---

## Build and deploy

```sh
# From the repository root, not from deploy/
docker build -f deploy/Dockerfile -t monel-spip:4.4.21-1 .

export MONEL_IMAGE=monel-spip:4.4.21-1
docker compose -f deploy/compose.yaml up -d
```

Tag scheme is `<spip-version>-<build>`: bump the suffix for a template or plugin
change, the prefix for a core upgrade.

Rollback is `MONEL_IMAGE=monel-spip:4.4.21-0 docker compose up -d`. Volumes are
untouched, so content and uploads survive.

### Continuous integration

Two workflows, in `.github/workflows/`.

**`build-push.yml`** — on a `vX.Y` tag, builds and pushes to GHCR:

```
git tag v3.8 && git push origin v3.8
  -> ghcr.io/monnaies-locales-metropole-lille/monel-spip:3.8
     ghcr.io/monnaies-locales-metropole-lille/monel-spip:3.8-spip4.4.21
     ghcr.io/monnaies-locales-metropole-lille/monel-spip:latest
```

The site version drives the tag; the SPIP version rides along in a second tag and in
the `co.monel.spip.version` OCI label, so "which SPIP is running in production" is
answerable from the image alone. `co.monel.plugins.lock.sha256` records the plugin
manifest digest. SBOM and signed build provenance are attached and pushed.

GHCR is used because it authenticates with the built-in `GITHUB_TOKEN` — no long-lived
registry credential to store or rotate. The Docker Hub credentials for `mlmel` are
committed to the ansible repository and are compromised (report §5.9 item 6); nothing
here depends on them.

The build **refuses to run if `core.lock` pins SPIP below 4.4.21.** That turns the
"never lower this" comment into a gate: 4.4.20 and 4.4.16 both fail the check.

**`check-updates.yml`** — nightly at 06:00 UTC, runs `bin/check-updates.sh` and opens
(or updates) a labelled GitHub issue when core or a plugin is behind, closing it again
once the locks are current. This is report recommendation #7, and the one control that
would have prevented the incident outright.

> Scheduled workflows only run from the **default branch**. Until this lands on
> `master`, the nightly check will not fire — use *Run workflow* to test it.

### Database

MariaDB runs in the stack, not on the host. It has **no published port** and sits on an
`internal: true` network, so Docker installs no gateway for it: nothing off the host can
reach it, and it cannot reach anything itself. Verified both directions.

That does not protect the database from a compromise of the site — an attacker with PHP
execution reaches it either way, exactly as they would have over a unix socket. What it
buys is the reverse direction (nothing else on the host can reach SPIP's data) and, more
importantly, a genuinely self-contained stack: moving this site to its own VM, which is
report recommendation #9 and the largest outstanding structural fix, becomes a copy of
`compose.yaml` plus two volumes rather than a rebuild.

**Backups replace the backupninja handler.** `10-moneldb.mysql` authenticated through
`/etc/mysql/debian.cnf` against a local mysqld and cannot reach a container. Install
`bin/backup-db.sh` as a daily root cron instead. It writes to the same path the old
setup used —

```
/var/backups/mysql/sqldump/monel.sql.gz
```

— so `prod-db-backup-sync` on preprod and every restore habit keep working. Two
deliberate changes from the old config: it dumps **only the `monel` schema**, where
`databases = all` also dumped `mysql` and therefore every account's password hash into
the same directory (the same mistake as `globals.sql.gz` on the Postgres side, §5.9
item 3); and the dump directory is **0700**, where the Postgres backups were
world-readable and that is how a webshell read the entire Cyclos database without a
single credential (§5.2, report item 12).

### Runtime settings

Settings that vary per environment are environment variables, not baked constants, so
changing one is a `docker compose up -d` rather than a rebuild.

| Variable | Default | Purpose |
|---|---|---|
| `MONEL_IMAGE` | — (required) | image tag to run |
| `MONEL_PORT` | `8090` | localhost port the front proxy targets |
| `MONEL_BAZAAR_VIDEO_ID` | `50` | SPIP article id of the "comment ça marche" video |
| `CYCLOS_*` | unset | unreleased `cyclos-api` branch; absent in production |

Adding a new one means reading it in `config/mes_options.php` and passing it in
`compose.yaml` — that is all. Under mod_php the container environment *is* the Apache
process environment, so `getenv()` sees it directly.

**That cuts both ways, and it is a real regression from the php-fpm layout.** php-fpm
could allowlist exactly which variables reached PHP (`clear_env` plus explicit `env[]`
entries); mod_php has no equivalent, so `getenv()` and `phpinfo()` can read the entire
container environment. Keep the environment minimal, and put nothing in it that PHP
should not be able to read. The database credentials are not there — they are in
`connect.php`, mounted read-only from outside the webroot.

### Verifying a running container

```sh
# Should print nothing. Anything listed is an unexpected write to the webroot.
docker diff $(docker compose -f deploy/compose.yaml ps -q web) | grep -v '^C /var/spip'

# All three should be 403 — denied, and not disclosed as source either.
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/IMG/test.php
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/IMG/shell.alfa
curl -s -o /dev/null -w '%{http_code}\n' \
     -H 'X-Spip-Filtre: html_entity_decode' http://127.0.0.1:8090/

# Should be 200 — legitimate uploads must still serve.
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/IMG/some-real-image.jpg
```

Wire the first of those into monitoring. Report §7 is blunt about this: nothing
alerted on a new PHP file in the webroot, on a modified core file, or on 1,736 exploit
attempts. A `docker diff` that must stay empty is a cheap, high-signal alarm.

---

## Upgrading

This is the part the incident turned on. 4.4.20 was released 17 August, 4.4.21 on
20 August, and the site was compromised on the 21st still running 4.4.16.

```sh
./bin/check-updates.sh            # exit 1 if anything is behind
./bin/check-updates.sh --rehash   # bump plugins.lock, re-download, re-hash
```

`--rehash` moves plugins only. Core is bumped by editing `SPIP_VERSION` in
`core.lock` after reading the release note at <https://blog.spip.net/>.

Then rebuild, tag, deploy. Two notes:

- **Core upgrades run a database migration on first visit to `/ecrire/`.** The site
  is not fully upgraded until someone loads the private area. It writes to the
  database, not the filesystem, so read-only is fine — but do not consider a core
  deploy finished before that step.
- **Plugin upgrades may also carry migrations.** Same mechanism, same caveat.

Run `check-updates.sh` nightly in CI and fail the job on exit 1. That is report
recommendation #7, and it is the one that would have prevented this outright.

### Egress

The compose bridge cannot express an allowlist — it is all-or-nothing, and cutting it
entirely would break outbound mail. Do it at the host firewall against the fixed subnet
instead:

```sh
# Adjust to the real SMTP relay.
iptables -I DOCKER-USER -s 172.28.0.0/24 -d <smtp-relay> -p tcp --dport 587 -j ACCEPT
iptables -A DOCKER-USER -s 172.28.0.0/24 -j REJECT
```

SMTP is currently the only egress the site needs. When `cyclos-api` ships it will need
a second ACCEPT for the Cyclos host on 443 — add it then, not pre-emptively.

`DOCKER-USER` is used because Docker flushes its own chains on restart. This is report
recommendation #5; `wget` reached `pastebin.support.one` at 13:57:33 on 21 August.

---

## Loose ends

Things found while writing this that are not resolved here.

- **The Cyclos integration is unreleased work on the `cyclos-api` branch.** It is not
  deployed and never was: the `mes_options.php` recovered from the compromised prod
  webroot contains no Cyclos configuration, and `grep -ri cyclos` across the preserved
  configs returns nothing. The dev token pointing at `test-moncompte.mlml.fr` was
  therefore not exposed by this incident and does not belong on the report's rotation
  list. The constants are defined here only when the environment supplies them, so
  production runs without them and the branch works by setting variables rather than
  by editing the image.
- **When `cyclos-api` merges, it must use `recuperer_url()`.** `allow_url_fopen = Off`
  blocks `file_get_contents('https://…')`, so an HTTP client written the obvious way
  will fail. Worth settling on the branch rather than at merge. The fix is to use
  SPIP's own fetcher, never to re-enable the setting. Noted in the ini as well.
- **`_SPIP_CHMOD` was `0777`.** The image sets `0750` (SPIP applies it to `mkdir()`
  directly and to files as `& 0666`, so: 0750 dirs, 0640 files). The old value is how
  `/var/www/mlml.fr` ended up world-writable throughout its plugin tree.
- **The report says 4.4.17 was never released.** `get.spip.net` does list a 4.4.17.
  Immaterial to the conclusions — the unapplied releases were 4.4.18 through 4.4.21 —
  but §3.1a says the number was skipped by the publisher, and that appears to be
  wrong.
- **`config/ecran_securite.php` does not self-update** in the version installed here,
  contrary to what is sometimes assumed about it. It ships inside `spip/spip` as
  `vendor/spip/security` and is pinned with the core. It also did not prevent either
  CVE — the publisher said so explicitly, and the compromised `/var/www/mlml.fr` had it
  installed.
- **`compromised-backup/` is still untracked and unignored** (report item 19). The
  `.dockerignore` here keeps it out of image builds, but it should be gitignored
  independently.
