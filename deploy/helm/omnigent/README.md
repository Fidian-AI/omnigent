# Omnigent Helm chart

Deploys the Omnigent server plus, by default, an in-cluster Postgres and the
**kubernetes managed-sandbox provider** (on-demand runner Pods in a dedicated,
least-privilege namespace). A Helm rendering of the Kustomize manifests in
[`deploy/kubernetes/`](../../kubernetes/README.md) — see that README and
[`overlays/sandbox-runners/README.md`](../../kubernetes/overlays/sandbox-runners/README.md)
for the architecture and security notes.

No secret has a working default. Supply them at install time from an
**untracked values file**, `--set`, or pre-created Secrets — never commit them.

## Quickstart

1. **Build the server image** (managed sandboxes need the `kubernetes` extra,
   which the published image omits):

   ```bash
   docker build -f deploy/docker/Dockerfile \
     --build-arg OMNIGENT_EXTRAS=kubernetes \
     -t <registry>/omnigent-server:k8s .
   docker push <registry>/omnigent-server:k8s
   ```

2. **Write an untracked values file** (e.g. `~/omnigent-values.yaml`):

   ```yaml
   image:
     repository: <registry>/omnigent-server
     tag: k8s

   postgres:
     password: "<url-safe strong password>"

   # Origin your browser uses, if not port-forward (e.g. a Cloudflare tunnel):
   # server:
   #   publicUrl: https://omnigent.example.com

   sandboxes:
     credentials:
       data:
         ANTHROPIC_API_KEY: sk-ant-...
         # CLAUDE_CODE_OAUTH_TOKEN: ...   # Claude subscription instead of API key
         # OPENAI_API_KEY: sk-...
         # GIT_TOKEN: github_pat_...      # private-repo clone/fetch/push
   ```

3. **Install:**

   ```bash
   helm install omnigent deploy/helm/omnigent \
     -n omnigent --create-namespace \
     -f ~/omnigent-values.yaml
   ```

4. **Verify:**

   ```bash
   kubectl get pods -n omnigent
   kubectl port-forward -n omnigent svc/omnigent 8000:80
   curl localhost:8000/health        # → {"status":"ok"}
   ```

Sessions created with `host_type: "managed"` (the web UI's New Sandbox option)
each get a runner Pod in the sandboxes namespace; the Pod dials back to the
server over the in-cluster Service, so nothing needs public exposure.

## Secrets without values files

Prefer Secrets managed out of band (sealed-secrets, external-secrets)? Point
the chart at them instead of passing values:

```yaml
# Server secrets: DATABASE_URL (+ POSTGRES_PASSWORD if postgres.enabled,
# + OMNIGENT_ACCOUNTS_COOKIE_SECRET for accounts auth).
existingSecret: my-omnigent-secrets

# Harness credentials for runner Pods, in the sandboxes namespace:
sandboxes:
  credentials:
    existingSecret: my-omnigent-creds
```

Runner Pods reference the credentials Secret via a non-optional `envFrom`, so
they stall in `CreateContainerConfigError` until it exists.

The in-sandbox host forwards the standard harness credential vars to its
runners; for extra variables beyond that set, add
`OMNIGENT_RUNNER_ENV_PASSTHROUGH: NAME1,NAME2` to the credentials Secret (see
the [sandbox-runners README](../../kubernetes/overlays/sandbox-runners/README.md#model-credentials-llm-keys)).

## Auth

The chart defaults to **single-user, no login** (`auth.enabled: false` +
`auth.localSingleUser: true`): every request that reaches the server acts as
the one local user. Keep the Service private — `kubectl port-forward`, or an
SSO-guarded tunnel (e.g. Cloudflare Access) — since network reachability is
the only barrier. This mode is fully compatible with managed sandboxes.

Multi-user options (see [`deploy/README.md#auth`](../../README.md#auth)):

- `auth.enabled: true` — built-in accounts (username/password, first visitor
  becomes admin). Requires `auth.accountsCookieSecret`. **Not compatible with
  managed sandboxes** (the runner dial-back is refused with 403).
- `auth.enabled: true` + `auth.provider: header` — behind a trusted SSO proxy
  that injects an identity header. Works with managed sandboxes.
- OIDC — set the `OMNIGENT_OIDC_*` vars via `server.extraEnvFrom`. Works with
  managed sandboxes.

## Values

| Key | Default | Notes |
|---|---|---|
| `image.repository` / `image.tag` | official image / `latest` | Must be a build with `OMNIGENT_EXTRAS=kubernetes` when `sandboxes.enabled` |
| `server.publicUrl` | `""` | Sets `OMNIGENT_WS_ALLOWED_ORIGINS`; needed when browsing via a non-localhost origin |
| `server.env` / `server.extraEnvFrom` | `{}` / `[]` | Extra env / env sources for the server |
| `auth.enabled` | `false` | See [Auth](#auth) |
| `auth.localSingleUser` | `true` | No-login fallback when auth is disabled |
| `postgres.enabled` | `true` | In-cluster Postgres 16 StatefulSet |
| `postgres.password` | — | **Required** when `postgres.enabled` (URL-safe) |
| `database.url` | `""` | **Required** when `postgres.enabled: false` |
| `existingSecret` | `""` | Use a pre-created server Secret instead |
| `persistence.size` / `.className` / `.existingClaim` | `10Gi` / `""` / `""` | Artifact-store PVC |
| `service.type` / `.port` | `ClusterIP` / `80` | |
| `ingress.enabled` | `false` | Optional; port-forward / tunnels don't need it. With TLS, either set the cert-manager annotation (and create that ClusterIssuer) or pre-create the `ingress.tls.secretName` Secret |
| `sandboxes.enabled` | `true` | The kubernetes managed-sandbox provider |
| `sandboxes.namespace` | `omnigent-sandboxes` | Runner-Pod namespace (separate by design) |
| `sandboxes.serverUrl` | in-cluster Service DNS | Dial-back URL for runner Pods |
| `sandboxes.credentials.data` | `{}` | LLM/git keys rendered into the creds Secret |
| `sandboxes.credentials.existingSecret` | `""` | Pre-created creds Secret instead |
| `sandboxes.image` / `.env` / `.nodeSelector` / `.resources` | provider defaults | Runner-Pod overrides |

The server Deployment is pinned to **1 replica** (in-memory runner registry —
do not scale it out).

## Recreate this deployment

Everything needed lives in this directory:

1. **Server image** — stock image + the kubernetes client:
   `docker build -f deploy/docker/Dockerfile --build-arg OMNIGENT_EXTRAS=kubernetes -t <registry>/omnigent-server:k8s .`
2. **Host image** — [`hostimage/`](hostimage/): the official host image plus the
   `opencode` CLI and a named-provider config for custom LLM endpoints
   (Fireworks today). Build per the Dockerfile header; runner Pods boot from it
   (`sandboxes.image`).
3. **Values** — copy [`examples/values-eks.yaml`](examples/values-eks.yaml)
   outside the repo, fill in, `helm upgrade --install` with the key
   `--set-string` flags shown in its header.
4. **Agents** — [`agents/`](agents/): one directory per agent
   (`config.yaml` = the spec: harness, model, provider). Publish them all to
   the running server with `agents/publish.sh <server-url>`. The anchor
   sessions it creates own the agents — deleting one cascade-deletes the
   agent and its sessions.

## Agents and harness support

The server also seeds **built-in native agents** (the "Harnesses" section of
the UI picker — Claude Code, Codex, Pi, …). Those run with zero setup beyond
the keys in the creds Secret, so custom agents are only needed where they add
something a key can't: a pinned endpoint/provider, or bundled
prompt/skills/guardrails customization.

One agent = one directory under [`agents/`](agents/). Current set:

| Agent | Harness | Why it exists |
|---|---|---|
| `claude-code` | claude-native | Same runtime as the built-in Claude Code entry; a bundle to hang org-wide skills/prompts on (`ANTHROPIC_API_KEY`) |
| `codex-openai` | codex-native | Same runtime as the built-in Codex entry; customization anchor (`OPENAI_API_KEY`) |
| `codex-glm` | codex | Fireworks endpoint via the named `fireworks` provider, GLM 5.2 default (model switchable per session within Fireworks) |
| `pi-glm` | pi | GLM 5.2 on Fireworks (Chat Completions wire) via the same provider |

Per-repo customization needs no agent at all: the native CLIs read
`CLAUDE.md` / `.claude/` (Claude Code) and `AGENTS.md` (Codex) from the
session workspace.

Custom OpenAI-compatible endpoints (like Fireworks) reach codex/pi **only
through a named provider** (`hostimage/omnigent-config.yaml`) — inline
`auth: {api_key, base_url}` on a spec is silently ignored by those
harnesses' spawn builders (only claude-sdk / openai-agents thread it).

`opencode` resolves to the opencode-native harness, and its CLI **is** in the
host image (see [`hostimage/`](hostimage/)). It runs against **first-party
providers** — it reads `ANTHROPIC_`/`OPENAI_`/`GEMINI_`/`GOOGLE_` keys straight
from the creds Secret — so those work with no extra config.

**Still not wirable to a custom endpoint in managed sandboxes:**

- `opencode` against a **custom** OpenAI-compatible endpoint (Fireworks-style,
  via the named-provider block) — its custom-endpoint routing is
  Databricks-gateway-only (`opencode_native_provider.py`) and its per-session
  `XDG_CONFIG_HOME` bypasses any image-baked opencode config, so the
  `providers:` entry never reaches it.
- `hermes` — the `hermes` CLI is not in the host image, the spawn dispatch
  wires no provider/gateway env for it, and it authenticates via its own
  interactive flow only (which a headless runner Pod cannot complete). Adding
  the binary alone does not make it usable.

Both gaps need upstream omnigent changes (generic named-provider support in the
opencode-native / hermes executors), not deployment config.

## Upgrades and teardown

```bash
helm upgrade omnigent deploy/helm/omnigent -n omnigent -f ~/omnigent-values.yaml
helm uninstall omnigent -n omnigent
```

Config/secret changes roll the server pod automatically (checksum
annotations). `helm uninstall` removes the sandboxes namespace (and any
in-flight runner Pods) but leaves the release namespace, the artifacts PVC
(kept via `helm.sh/resource-policy`), and the Postgres
`volumeClaimTemplates` PVC behind — delete those manually if you mean it.
