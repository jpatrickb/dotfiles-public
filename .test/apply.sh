#!/bin/bash
# Runs inside the container: apply the mounted source to a fresh home.
export PATH="$HOME/.local/bin:$PATH"
echo "=== chezmoi apply (source: /src) ==="
# AWS_CLI / GCP_CLI = false test the "skipped" paths. init answers the prompts, then applies.
time chezmoi --source /src init --apply \
  --promptBool "Install the AWS CLI=${AWS_CLI:-true}" \
  --promptBool "Install the GCP CLI=${GCP_CLI:-true}"
