#!/usr/bin/env bash
# this creates a github webhook that gets all events to a REPOSITORY, useful with Jenkins Blue Ocean

AUTH_TOKEN=""
SERVICE_URL=""
ORGANISATION=""
REPOSITORY=""

for i in "$@"
do
case ${i} in
    -AUTH_TOKEN=*|--AUTH_TOKEN=*)
    AUTH_TOKEN="${i#*=}"
    ;;
    -ORGANISATION=*|--ORGANISATION=*)
    ORGANISATION="${i#*=}"
    ;;
    -SERVICE_URL=*|--SERVICE_URL=*)
    SERVICE_URL="${i#*=}"
    ;;
    -REPOSITORY=*|--REPOSITORY=*)
    REPOSITORY="${i#*=}"
    ;;
esac
done

echo $ORGANISATION
GIT_URL="https://api.github.com/repos/${ORGANISATION}/${REPOSITORY}/hooks"
echo $GIT_URL

generate_post_data()
{
  cat <<EOF
{
  "name": "web",
  "active": true,
  "events": ["*"],
  "config": {
    "url": "https://${SERVICE_URL}/github-webhook/",
    "content_type": "application/x-www-form-urlencoded"
  }
}
EOF
}

curl -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Authorization: token ${AUTH_TOKEN}" \
    --data "$(generate_post_data)" \
    ${GIT_URL}