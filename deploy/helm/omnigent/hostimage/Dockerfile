# Omnigent host image + named-provider config for custom LLM endpoints.
#
# Runner Pods mount an emptyDir over /home/omnigent (the launcher-controlled
# HOME), so a config baked under HOME would be shadowed at runtime. Instead
# the file lives at a fixed path outside HOME, with OMNIGENT_CONFIG_HOME
# pointing at it — a var the host already propagates to runners via its env
# allowlist. Managed hosts never write this config (their identity comes from
# env), so the read-only path is safe.
#
# Build & push (amd64 only — the launcher pins runner Pods to amd64 nodes):
#   docker buildx build --platform linux/amd64 \
#     -t <registry>/omnigent-host:<tag> --push deploy/helm/omnigent/hostimage
# Then set sandboxes.image to that ref and `helm upgrade`.
FROM ghcr.io/omnigent-ai/omnigent-host:latest

# Add the opencode CLI so opencode-native can launch (the base image already
# carries claude/codex/pi/kiro/agy + the Node runtime, so those harnesses —
# antigravity-native included — work unchanged). Pinned to 1.17.x: opencode-ai's
# npm `latest` is a beta pre-release omnigent's version check rejects (mirrors
# the pin in omnigent/onboarding/harness_install.py).
RUN npm install -g --no-audit --no-fund opencode-ai@~1.17.7 \
 && npm cache clean --force

COPY omnigent-config.yaml /etc/omnigent-defaults/config.yaml
ENV OMNIGENT_CONFIG_HOME=/etc/omnigent-defaults
