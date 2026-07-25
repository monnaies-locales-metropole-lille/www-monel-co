# Cyclos M2M access-client token — reproduction runbook

How to set up a machine-to-machine (M2M) access-client token in Cyclos so a
server-side integration (e.g. the monel.co SPIP site) can authenticate to the
REST API without a username/password. Written so it can be replayed verbatim on
another instance (e.g. production).

Menu labels below are from the **classic backend** in **French**.

## Prerequisites / assumptions
- You have a **network admin** login to the classic backend (`https://<host>/classic`).
- The **`Services internet`** (`webServices`) channel is **enabled** in the configuration used by your admin group.
  - Verify: **Système → Configurations → `<your config>` → onglet Canaux →** `Services internet` = **Oui**.

## Part A — One-time system setup (do once per Cyclos instance)

### A1. Create the "Access client" identification method  ← the key unlock
1. **Système → Méthodes d'identification de l'utilisateur**.
2. **Nouveau ▾ → Accès client**.
3. Give it a name (e.g. `Accès client`) → **Enregistrer**.

> Without this, the access-client permissions stay greyed out as *"Aucune action
> disponible"*. This — not any license/PRO limit — is the real gate.

### A2. Allow that method on the web-services channel
1. **Système → Configurations → `<your config>` → onglet Canaux → `Services internet`**.
2. Add the new method to **"Méthodes d'identification de l'utilisateur"** → **Enregistrer**.

### A3. Grant the access-client permissions to the admin group
1. **Système → Groupes → `<admin group>` → onglet Autorisations → Modifier**.
2. In the **Accès aux canaux** block: **"Mes accès client"** → tick **Gérer**.
3. In the **Gestion des utilisateurs** block: **"Accès aux clients"** → tick **Vue + Gérer + Activer**.
   - *"Mes accès client"* = a user managing their own; *"Accès aux clients"* =
     admins managing others'. The **admin one** is what makes the *Clients d'accès*
     link appear on a user's profile.
4. **Enregistrer**.

## Part B — Per integration (repeat for each API client)

### B1. Create the dedicated admin user
1. **Utilisateurs → Nouveau ▾ → `<admin group>`** (e.g. *Administrateurs de réseau*).
2. Login = e.g. `api_monel_co`, name, email, and set a **login password** (needed
   for the activation call — keep it).
3. **Enregistrer**.

### B2. Give that user channel access
The channel default is *"Désactivé par défaut"*, so grant it explicitly:
1. On the user's profile → **Accès aux canaux** → enable **Services internet** → save.

### B3. Create the access client
1. On the user's profile → **Clients d'accès → Nouveau** → name it (e.g. `token1`) → save.
2. Note the **4-digit activation code** it shows (e.g. `6582`). Status = *En attente d'activation*.

### B4. Activate → obtain the token (API call)
```bash
curl -sS -X POST "https://<host>/<network>/activate-access-client" \
     -u "<login>:<password>" \
     -d "<activation-code>"
```
Example (test instance):
```bash
curl -sS -X POST "https://test-moncompte.mlml.fr/mlml/activate-access-client" \
     -u "api_monel_co:<password>" \
     -d "6582"
```
- Auth = **the owner's** login + password (Basic auth), code in the **request body** (plain text).
- Response body = the **access-client token** (64 chars). It's shown once and **does not expire**.

### B5. Verify the token
```bash
curl -sS -H "Access-Client-Token: <token>" \
     "https://<host>/api/auth"
```
Expect `200` with `"display":"<user>"` and `"systemAdministrator":true`.

### B6. Store the token
Put it in the SPIP local config (`spip/config/mes_options.php`, git-ignored):
```php
define('_CYCLOS_API_URL',      'https://<host>/api');
define('_CYCLOS_ACCESS_TOKEN', '<token>');
```

## Gotchas (so you don't re-hit them)
- **"Clients d'accès" isn't a menu label.** The permissions are **"Mes accès client"** and **"Accès aux clients"**.
- The permissions are **greyed out until A1 exists** — do A1 first.
- **Two different permissions:** granting only "Mes accès client" (personal) does
  *not* put the link on another user's profile; you also need "Accès aux clients" (admin).
- **Per-user channel access (B2)** is required because the channel is *disabled by default*.
- Activation is a **legacy endpoint** `/<network>/activate-access-client`, **not**
  `/api/...`; it uses the **owner's** credentials, not the admin's.

## Production differences to change
- **Host**: swap `test-moncompte.mlml.fr` → prod host.
- **Network path**: confirm the prod network's path segment (here `/mlml`) for the
  activation URL — verify with `curl -I -X GET https://<host>/<network>/activate-access-client`
  (expect `405`, meaning it exists).
- **Fresh token**: generate a **new** access client on prod; the test token won't work there.
- **Credentials**: a new `api_*` user + password on prod.

## Security notes
- The token grants **network-admin** (`systemAdministrator`) access — treat it as a
  secret. Keep it server-side only, never in the repo or client-side code.
- To **revoke/rotate**: block or delete the access client on the user's profile
  (**Clients d'accès**), then create a new one.
