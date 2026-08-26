# Immutable SPIP deployment — www.monel.co

Built in response to [`incidents/2026-08-21-spip-rce-webshell.md`](../incidents/2026-08-21-spip-rce-webshell.md).

Everything SPIP executes lives in a versioned, read-only image. Upgrading is a
rebuild; rolling back is the previous tag. The three directories SPIP genuinely
needs to write are volumes, and none of them can execute PHP.

**Status.** The image builds, and the hardening has been verified empirically: SPIP
4.4.21 and all ten pinned plugins present, non-root, nothing in the webroot writable
outside the two volumes, every nginx denial confirmed against webshell-shaped files,
and runtime settings proven to propagate through FastCGI. **Not yet tested:** anything
requiring the database — SPIP actually rendering a page, and the core upgrade migration.
Those belong to the rebuild. See [Before first deploy](#before-first-deploy).

---

## What is pinned

| | Version | Pinned in |
|---|---|---|
| SPIP core | **4.4.21** | `core.lock` |
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
├── compose.yaml            nginx + php-fpm, read-only, non-root, no capabilities
├── core.lock               SPIP core version — single source of truth
├── plugins.lock            contrib plugins: version, archive path, sha256, size
├── bin/
│   ├── fetch-plugins.sh    build-time: download, verify, unpack (fails closed)
│   └── check-updates.sh    compare locks against upstream; --rehash to bump
├── config/
│   └── mes_options.php     runtime options; secrets come from the environment
├── nginx/
│   ├── 00-log-format.conf  http-context settings
│   └── monel.conf          vhost: routing plus the PHP-execution denials
└── php/
    ├── zz-spip-hardening.ini
    ├── opcache-blacklist.txt
    └── www.conf            php-fpm pool
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
- **A dropped file cannot execute.** `^~ /IMG/` and `^~ /local/` in nginx keep the PHP
  handler out of both directories, and a nested regex 404s executable-looking names so
  a shell is not even disclosed as source.
- **No second stage.** `exec`/`system`/`proc_open`/`popen`/`putenv` are all in
  `disable_functions`, so PHP cannot spawn a downloader at all. `putenv` is there
  specifically to break the `LD_PRELOAD` bypass found in `stats-mailer.php`. The
  `wget`/`curl` binaries are also deleted, but treat that as noise reduction rather
  than a control: Alpine's `wget` is a BusyBox applet and removing the symlink does
  not remove the applet. The boundary is `disable_functions` plus egress filtering.
- **No CGI.** nginx ignores `.htaccess` entirely, so the `AddHandler cgi-script .alfa`
  trick from `/var/www/mlml.fr` has nothing to attach to. `.alfa` is 404'd anyway.

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

Ordered. Items 1–3 are blocking.

1. **Provide the secrets.** Create `deploy/secrets/` — untracked, mode 0700 — with:
   - `connect.php` — database credentials, **rotated**, not the compromised ones
   - `cles.php` — SPIP's encryption keys, carried over from the old install

   `cles.php` must be carried over rather than regenerated: SPIP uses it to decrypt
   existing stored values. Copy it from the preserved webroot, not from a running
   compromised host.

2. **Check `_BAZAAR_VIDEO_ID`.** It is 50 in the recovered prod config and 26 in
   development checkouts — SPIP article ids are per-database. 50 is the default here.
   Confirm it against the restored database and set `MONEL_BAZAAR_VIDEO_ID` if it
   differs — see [Runtime settings](#runtime-settings); no rebuild needed.

3. **Decide the `/ecrire/` restriction.** The block is written and commented out in
   `nginx/monel.conf`. Four accounts use the back office. If they can work from known
   networks, uncomment it — it removes the entire authenticated attack surface from the
   internet, and it is the single cheapest control in this directory.

4. **Check the image-processing setting.** `exec` is disabled, so SPIP must use GD
   (the default), not `convert`/netpbm. Back office → Configuration → Fonctions
   avancées → Traitement des images.

5. **Check facteur's transport.** It must be SMTP. The sendmail transport uses
   `popen()`, which is disabled — and there is no MTA in the container anyway.

6. **Freeze the composer lock.** `composer create-project` re-resolves transitive
   dependencies (the symfony polyfills and so on) on every build, so two builds of the
   same tag are not byte-identical. The runtime image deletes `composer.lock`, so pull
   it from the builder stage:
   ```sh
   docker build -f deploy/Dockerfile --target builder -t monel-builder:tmp .
   docker create --name t monel-builder:tmp
   docker cp t:/build/composer.lock deploy/composer.lock
   docker rm t
   ```
   Then add a `COPY deploy/composer.lock /build/composer.lock` + `composer install`
   step after `create-project --no-install`. Until this is done, "same tag" means
   "same SPIP version", not "same bytes" — which is enough to deploy safely but not
   enough to prove two builds are identical.

7. **Set `set_real_ip_from`** in `nginx/00-log-format.conf` to the proxy's range,
   otherwise every log line records the proxy address — which would have made the
   57-source-address analysis in the incident report impossible.

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

### Runtime settings

Settings that vary per environment are environment variables, not baked constants, so
changing one is a `docker compose up -d` rather than a rebuild.

| Variable | Default | Purpose |
|---|---|---|
| `MONEL_IMAGE` | — (required) | image tag to run |
| `MONEL_BAZAAR_VIDEO_ID` | `50` | SPIP article id of the "comment ça marche" video |
| `CYCLOS_*` | unset | unreleased `cyclos-api` branch; absent in production |

**Adding a new one means editing two files.** php-fpm clears the worker environment,
so a variable must be both read in `config/mes_options.php` *and* allowlisted as
`env[NAME] = $NAME` in `php/www.conf`. Miss the second and the setting silently falls
back to its default with no error — the failure mode is a wrong value, not a crash.

The allowlist is deliberate: `clear_env = yes` plus explicit entries means only these
variables reach PHP. Everything else in the container environment stays invisible to
`getenv()` and to `phpinfo()`. The base image ships `clear_env = no`, which would have
worked by accident and broken silently on a base-image change.

### Verifying a running container

```sh
# Should print nothing. Anything listed is an unexpected write to the webroot.
docker diff $(docker compose -f deploy/compose.yaml ps -q php) | grep -v '^C /var/spip'

# Should 404, not 200 and not the file's source.
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/IMG/test.php

# Should 400.
curl -s -o /dev/null -w '%{http_code}\n' \
     -H 'X-Spip-Filtre: html_entity_decode' http://127.0.0.1:8080/
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
