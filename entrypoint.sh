#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

if [ -n "$EVENT_PATH" ]; then
  # Allow user to specify a different path to the GitHub event file.
  # cp "$EVENT_PATH" /github/workflow/event.json
  echo "event path"
fi

FILE=/github/workflow/event.json
if test -f "$FILE"; then
    echo "$FILE exists."
else
  FILE=.github/actions/fly-pr-review/test-event-payload.json
fi

PR_NUMBER=$(jq -r .number $FILE)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

REPO_OWNER=$(jq -r .event.base.repo.owner $FILE)
REPO_NAME=$(jq -r .event.base.repo.name $FILE)
EVENT_TYPE=$(jq -r .action $FILE)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_OWNER-$REPO_NAME}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
config="$INPUT_CONFIG"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

# launch wants to copy the fly.toml file (it doens't work if we don't --copy-config, since it's interactive). so let's copy fly.branch.toml, then it can use the correct config and everyone is happy
mv fly.branch.toml fly.toml

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  flyctl launch --auto-confirm --copy-config --no-deploy --name "$app" --region "$region" --org "$org"
  if [ -n "$INPUT_SECRETS" ]; then
    echo $INPUT_SECRETS | tr " " "\n" | flyctl secrets import --app "$app"
  fi
  flyctl deploy --auto-confirm --app "$app" --region "$region" --region "$region" --strategy immediate
elif [ "$INPUT_UPDATE" != "false" ]; then
  flyctl deploy --config "$config" --app "$app" --region "$region" --region "$region" --strategy immediate
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach --postgres-app "$INPUT_POSTGRES" || true
fi

# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
