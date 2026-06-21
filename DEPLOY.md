# Deploying OpenXPKI as a CA (Docker)

A step-by-step runbook to stand up OpenXPKI as a working Certification Authority
using this compose setup. Every step here has been run and verified.

The stack is four containers: **database** (MariaDB), **server** (the CA engine),
**client** (the API/clientd backend), and **web** (the WebUI + RPC/SCEP/EST
frontend, Apache by default or nginx).

> [!NOTE]
> This setup targets demo/test and internal use. For a production CA, follow the
> hardening notes at the end and use your own keys, secrets and certificates.

---

## 1. Prerequisites

- Docker with the `compose` plugin (`docker compose version`)
- `git` and `openssl`

## 2. Get the code and configuration

```bash
git clone https://github.com/allamiro/openxpki-docker.git
cd openxpki-docker

# Configuration (community branch of the fork, carries our fixes)
git clone https://github.com/allamiro/openxpki-config.git --single-branch --branch=community
```

`make init` does the config clone for you.

## 3. Mandatory setup (before the first start)

### 3a. CLI authentication key

The command line tools authenticate with a key pair.

```bash
mkdir -p config
openssl ecparam -name prime256v1 -genkey -noout -out config/client.key
chmod 644 config/client.key
openssl pkey -in config/client.key -pubout
```

Put the printed public key into `openxpki-config/config.d/system/cli.yaml`:

```yaml
auth:
    admin:
        key: |
         -----BEGIN PUBLIC KEY-----
         ...your public key...
         -----END PUBLIC KEY-----
        role: RA Operator
```

### 3b. Datavault secret

This key encrypts confidential data in the database. **Keep a copy in a safe
place — losing it means losing access to all encrypted data.**

```bash
openssl rand -hex 32
```

Put the 64-character value into `openxpki-config/config.d/system/crypto.yaml`
under the `svault` group:

```yaml
    svault:
        label: Secret group for datavault encryption
        method: literal
        value: <your 64-character hex value>
```

## 4. (Recommended) Web server certificate

The web container maps `openxpki-config/tls/` to `/etc/openxpki/tls/`. Place your
certificate and key here:

```
openxpki-config/tls/endentity/openxpki.crt
openxpki-config/tls/private/openxpki.pem
openxpki-config/tls/chain/        (CA chain, must contain at least one file)
```

If you provide nothing, a self-signed certificate is generated on first start
(your browser will warn — that is expected). TLS client-certificate auth does
**not** work with the dummy cert.

## 5. Bring it up

```bash
docker compose up -d web          # Apache frontend (default)
# or
docker compose up -d web-nginx    # nginx frontend (run only one)
```

`make compose` does the same. Starting `web` pulls up `db`, `server` and
`client` automatically.

## 6. Access and log in

Open: **https://localhost:8443/webui/index/**

Accept the self-signed certificate warning. At the login screen pick the
**Test Accounts** stack. On the unmodified config the password is `openxpki`:

| Username | Password | Role |
|----------|----------|------|
| `raop`, `rose`, `rob` | `openxpki` | RA Operator |
| `caop` | `openxpki` | CA Operator |
| `alice`, `bob` | `openxpki` | User |

Use `raop` / `openxpki` for administration.

## 7. Set up the Issuing CA

### Option A — Testdrive (auto-generated 2-tier PKI)

Generates a Root + Issuing CA and makes the system ready to issue certificates:

```bash
docker compose exec -u pkiadm server /bin/bash /etc/openxpki/contrib/sampleconfig.sh
```

`make sample-config` does the same. After it finishes, log in and you can issue
certificates immediately.

### Option B — Production (import your own Root / Issuing CA)

Use this when the CA keys are your own (e.g. an offline Standalone Root with a
subordinate Issuing CA). Build your hierarchy offline first — the `clca` tool
(https://github.com/openxpki/clca) is recommended for a two-tier setup — then
import the **Issuing CA** (signer) and **datavault** into the realm:

```bash
# shell as the PKI admin
make pkiadm        # or: docker compose exec -u pkiadm server /bin/bash

# import the issuing CA certificate + key, then set its alias as the signer token
openxpkiadm certificate import --file ca-signer.crt --realm democa --token certsign
openxpkiadm alias --realm democa --token certsign --identifier <identifier-from-import>

# import the datavault certificate/key (referenced by the svault secret)
openxpkiadm certificate import --file vault.crt
openxpkiadm alias --realm democa --token datasafe --identifier <vault-identifier>
```

Keep the Root CA **offline**; OpenXPKI only needs the **Issuing CA** signer and
the Root certificate (for the chain). See the QUICKSTART in the configuration
repo for the full ceremony and key-import details.

## 8. Verify

```bash
docker compose ps                                   # all containers healthy
curl -k https://localhost:8443/healthcheck/ping     # -> {"ping":1}
```

In the WebUI, issue a test certificate from a profile (e.g. TLS Server) to
confirm end-to-end issuance.

## 9. Day-to-day operations

```bash
make pkiadm                       # shell as the pkiadm user
docker compose restart server     # restart the CA engine
docker compose restart client     # restart the API/clientd backend
docker compose logs -f server client   # follow logs
docker compose down               # stop (keeps volumes/data)
```

## Troubleshooting

- **500 error / no WebUI** — usually the client session storage or log
  permissions. Check `docker compose logs client`.
- **Server marked unhealthy on first boot** — the CA engine is slow to start;
  the healthchecks include a `start_period` so give it up to ~90s.
- **Port already in use** — `8443`/`8080` are mapped by the `web` service; change
  the port mapping in `docker-compose.yml` if they clash.
- **Windows hosts** — the config uses symlinks for the realm; a Windows checkout
  can break them. Clone on Linux/macOS or enable git symlink support.

## Production hardening checklist

- [ ] Remove the `Testing` login stack from `auth/stack.yaml` and review
      `auth/handler.yaml` (it ships hardcoded demo passwords).
- [ ] Replace the `svault` secret and store a backup copy securely.
- [ ] Change the database passwords in `docker-compose.yml` **and**
      `config.d/system/database.yaml`.
- [ ] Install a real web server certificate (section 4); the dummy cert is not
      suitable and breaks TLS client authentication.
- [ ] Use your own Root/Issuing CA (Option B), not the testdrive PKI.
