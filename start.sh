#!/bin/bash
set -e

if [ -z "$AZP_URL" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

if [ -z "$AZP_TOKEN_FILE" ]; then
  if [ -z "$AZP_TOKEN" ]; then
    echo 1>&2 "error: missing AZP_TOKEN environment variable"
    exit 1
  fi

  AZP_TOKEN_FILE=/azp/.token
  echo -n $AZP_TOKEN > "$AZP_TOKEN_FILE"
fi

unset AZP_TOKEN

if [ -n "$AZP_WORK" ]; then
  mkdir -p "$AZP_WORK"
fi

rm -rf /azp/agent
mkdir /azp/agent
cd /azp/agent

export AGENT_ALLOW_RUNASROOT="1"

cleanup() {
  if [ -e config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."

    ./config.sh remove --unattended \
      --auth PAT \
      --token $(cat "$AZP_TOKEN_FILE")
  fi
}

print_header() {
  lightcyan='\033[1;36m'
  nocolor='\033[0m'
  echo -e "${lightcyan}$1${nocolor}"
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE=AZP_TOKEN,AZP_TOKEN_FILE

print_header "0. Determining OS version"
AZP_OS=$(uname -i)
if [ "$AZP_OS" = "aarch64" ]
then
  AZP_OS_TYPE='arm64'
else
  AZP_OS_TYPE='arm'
fi

echo "OS TYPE: $AZP_OS_TYPE"

print_header "1. Download and installing .NET CORE"

if [ -d "/usr/share/dotnet/" ]; then
  ### Take action if $DIR exists ###
  echo ".NET CORE already installed. Skipping..."
else
  ###  Control will jump here if $DIR does NOT exists ###
  if [ "$AZP_OS_TYPE" = "arm64" ]
  then
    DOTNETCORE_URL='https://download.visualstudio.microsoft.com/download/pr/fe5c0663-3ed1-4a93-95e1-fd068b89215b/14d1caad8fd2859d5f3514745a9bf6b3/dotnet-sdk-3.1.301-linux-arm64.tar.gz'
  else
    DOTNETCORE_URL='https://download.visualstudio.microsoft.com/download/pr/ccbcbf70-9911-40b1-a8cf-e018a13e720e/03c0621c6510f9c6f4cca6951f2cc1a4/dotnet-sdk-3.1.201-linux-arm.tar.gz'
  fi

  mkdir -p /usr/share/dotnet/

  echo "Start download $DOTNETCORE_URL"
  curl -LsS $DOTNETCORE_URL | tar -xz -C /usr/share/dotnet/ & wait $!
  echo "Finish download"

  ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet
  echo "Created "
fi

print_header "2. Determining matching Azure Pipelines agent..."

AZP_AGENT_RESPONSE=$(curl -LsS \
  -u user:$(cat "$AZP_TOKEN_FILE") \
  -H 'Accept:application/json;api-version=3.0-preview' \
  "$AZP_URL/_apis/distributedtask/packages/agent?platform=linux-$AZP_OS_TYPE")

if echo "$AZP_AGENT_RESPONSE" | jq . >/dev/null 2>&1; then
  AZP_AGENTPACKAGE_URL=$(echo "$AZP_AGENT_RESPONSE" \
    | jq -r '.value | map([.version.major,.version.minor,.version.patch,.downloadUrl]) | sort | .[length-1] | .[3]')
fi

if [ -z "$AZP_AGENTPACKAGE_URL" -o "$AZP_AGENTPACKAGE_URL" == "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure Pipelines agent - check that account '$AZP_URL' is correct and the token is valid for that account"
  exit 1
fi

print_header "3. Downloading and installing Azure Pipelines agent..."

echo $AZP_AGENTPACKAGE_URL
AZP_AGENTPACKAGE_URL="https://vstsagentpackage.azureedge.net/agent/2.174.3/vsts-agent-linux-arm64-2.174.3.tar.gz"
echo $AZP_AGENTPACKAGE_URL

curl -LsS $AZP_AGENTPACKAGE_URL | tar -xz & wait $!

source ./env.sh

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

print_header "4. Configuring Azure Pipelines agent..."

##fix for microsoft build arm64
#echo "chmod 1"
#ls ./bin/Agent.Listener -l
#chmod +x ./bin/Agent.Listener
#ls ./bin/Agent.Listener -l
#echo "chmod 2"

#chmod +x a+rX *
#chmod -R 755 ./bin/
#chmod -R 755 ./

./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "$AZP_URL" \
  --auth PAT \
  --token $(cat "$AZP_TOKEN_FILE") \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

# remove the administrative token before accepting work
rm $AZP_TOKEN_FILE

print_header "4. Running Azure Pipelines agent..."

# `exec` the node runtime so it's aware of TERM and INT signals
# AgentService.js understands how to handle agent self-update and restart
exec ./externals/node/bin/node ./bin/AgentService.js interactive
