#!/bin/bash

# Example for the Docker Hub V2 API
# Returns all images and tags associated with a Docker Hub organization account.
# Requires 'jq': https://stedolan.github.io/jq/

# set username, password, and organization
#HUBNAME=${3}
#HUBPASS=${4}
ORG="wehaveliftoff"
METHOD=${2}
REPO=${1}
TIMESTAMP=${3:-notimestamp}

# Explanation of options:
#
# First parameter:
#  repo -> name of the repo you want to list the images/tags from
#  allrepos -> output new tags from all repos
# Second parameter:
#  all -> output all tags for reference
#  newest -> output most recently added tag(s) (excluding tags named "latest" if backend or preprocessor)
#  alldiff -> output list of tags that weren't there when we last ran
#  newestdiff -> output newest tag if it did not yet exist when we last ran  
# Third and last parameter (optional)
#  if this parameter is provided, then supply timestamp of latest image with output of script

# Explanation of logic:
#
# namedrepo newest -> will only ouput newest tag for this repo. 
#                     If repo contains the name "preprocessor" or is backend (literal!) it will filter out "latest"
#                     and will only show tags containing "master"
# allrepos newest -> will show the latest tag for each repo. Includes repo-name of course. does not filter "latest"-tags out
# namedrepo all -> will show newest ten tags forthis repo. No filters are applied 
# allrepos all -> shows newest ten tags for every repo. No filters. Includes repo-name

if [ $# -lt 2 ]
then
  echo "syntax: $0 repo|allrepos all|newest|alldiff|newestdiff <t>"
  exit 1
fi

if [ "${HUBNAME}x" == "x" ] || [ "${HUBPASS}x" == "x" ]
then
  echo "provide HUBNAME and HUBPASS env vars to login to docker hub" >&2
  exit 1
fi

# check the parameters provided
if [ "${REPO}" == "allrepos" ]
then
  ALLREPOS=yes
else
  ALLREPOS=no
fi

# -------

set -e

# get token
# echo "Retrieving token ..."
TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${HUBNAME}'", "password": "'${HUBPASS}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token)
    if [ $? -ne 0 ]
    then
      # "Apparent Docker Hub API failure. Exiting"
      exit 1
    fi

if [ "${ALLREPOS}" == "yes" ]
then
    # get list of repositories
    # "Retrieving repository list ..."
    REPO_LIST=$(curl -s -H "Authorization: JWT ${TOKEN}" https://hub.docker.com/v2/repositories/${ORG}/?page_size=100 | jq -r '.results|.[]|.name')
    if [ "${REPO_LIST}x" == "x" ]
    then
      # Apparent failure. Exit
      exit 1
    fi
else
    REPO_LIST=${REPO}
fi

# output images & tags

touch /tmp/repo_${REPO}_all_new.txt
touch /tmp/repo_${REPO}_newest_new.txt

# Make sure we dont copy an empty file over the previous status (caused by last AP{-call failing)
#
if [ `wc -l /tmp/repo_${REPO}_all_new.txt | awk '{ print $1 }'` -gt 0 ]
then
  cp /tmp/repo_${REPO}_all_new.txt /tmp/repo_${REPO}_all_old.txt
fi

if [ `wc -l /tmp/repo_${REPO}_newest_new.txt | awk '{ print $1 }'` -gt 0 ]
then
  cp /tmp/repo_${REPO}_newest_new.txt /tmp/repo_${REPO}_newest_old.txt
fi
cat /dev/null > /tmp/repo_${REPO}_all_new.txt
cat /dev/null > /tmp/repo_${REPO}_newest_new.txt

function gimmecurl() {
    curl -s -H "Authorization: JWT ${TOKEN}" "https://registry.hub.docker.com/v2/repositories/${ORG}/${1}/tags/?page_size=10"
}

for i in ${REPO_LIST}
do
#  echo "${i}:"
  cr=$'\r'
  i="${i%$cr}"
  # tags
  if [ "${METHOD}" == "all" ] || [ "${METHOD}" == "alldiff" ]
  then
    if [ "$TIMESTAMP" != "notimestamp" ]
    then
      if [ "${ALLREPOS}" == "yes" ]
      then
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | awk '{ printf "%s (%s)\n",$2,$1 }' | sed "s/^/${ORG}\/${i}:/" | sed 's/"//g' >> /tmp/repo_${REPO}_all_new.txt
      else
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | awk '{ printf "%s (%s)\n",$2,$1 }' | sed 's/"//g' >> /tmp/repo_${REPO}_all_new.txt
      fi
    else
      if [ "${ALLREPOS}" == "yes" ]
      then
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | awk '{ printf "%s\n",$2 }' |  sed "s/^/${ORG}\/${i}:/" | sed 's/"//g' >> /tmp/repo_${REPO}_all_new.txt
      else
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | awk '{ printf "%s\n",$2 }' | sed 's/"//g' >> /tmp/repo_${REPO}_all_new.txt
      fi
    fi
    if [ $? -ne 0 ]
    then
      echo "Apparent Docker Hub API failure. Exiting" >&2
      exit 1
    fi
  else
    if [ "$TIMESTAMP" != "notimestamp" ]
    then
      if [ "${ALLREPOS}" == "yes" ]
      then
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | head -1 | awk '{ printf "%s (%s)\n",$2,$1 }' |  sed "s/^/${ORG}\/${i}:/" | sed 's/"//g' >> /tmp/repo_${REPO}_newest_new.txt
      else
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | grep -v latest |sort -r | head -1 | awk '{ printf "%s (%s)\n",$2,$1 }' |  sed 's/"//g' >> /tmp/repo_${REPO}_newest_new.txt
      fi
    else
      if [ "${ALLREPOS}" == "yes" ]
      then
        gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | head -1 | awk '{ printf "%s\n",$2 }' |  sed "s/^/${ORG}\/${i}:/" | sed 's/"//g' >> /tmp/repo_${REPO}_newest_new.txt
      else
        # NOTE: we only take master-tags and exclude "latest" if this is the backend or the preprocessor!
        if [ "$i" == "backend" ] 
        then
          BACKEND=yes
        else
          BACKEND=no
        fi
        set +e
        echo $i | grep preprocessor >/dev/null 2>&1
        if [ $? -eq 0 ]
        then
          PREPROC=yes
         else
          PREPROC=no
        fi
        set -e
        if [ "${BACKEND}" == "yes" ] || [ "${PREPROC}" == "yes" ]
        then
          gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | grep -v latest | grep master | sort -r | head -1 | awk '{ printf "%s\n",$2 }' |  sed 's/"//g' >> /tmp/repo_${REPO}_newest_new.txt
        else
          gimmecurl "$i" | jq '."results"[] | "\(.last_updated) \(.name)"' | sort -r | head -1 | awk '{ printf "%s\n",$2 }' |  sed 's/"//g' >> /tmp/repo_${REPO}_newest_new.txt
        fi
      fi
    fi
    if [ $? -ne 0 ]
    then
      echo "Apparent Docker Hub API failure. Exiting" >&2
      exit 1
    fi
  fi
done

if [ "${METHOD}" == "all" ]
then
   if [ `wc -l /tmp/repo_${REPO}_all_new.txt | awk '{ print $1 }'` -lt 1 ]
  then
    echo "Too few lines in /tmp/repo_${REPO}_all_new.txt ; apparent Docker Hub API failure" >&2
    exit 1
	else
    cat /tmp/repo_${REPO}_all_new.txt
  fi
elif [ "${METHOD}" == "newest" ]
then
  if [ `wc -l /tmp/repo_${REPO}_newest_new.txt | awk '{ print $1 }'` -lt 1 ]
  then
    echo "Too few lines in /tmp/repo_${REPO}_newest_new.txt ; apparent Docker Hub API failure" >&2
    exit 1
	else
    cat /tmp/repo_${REPO}_newest_new.txt
  fi
elif [ "${METHOD}" == "alldiff" ]
then
  if [ `sum /tmp/repo_${REPO}_all_new.txt | awk '{print $1 }'` != `sum /tmp/repo_${REPO}_all_old.txt | awk '{print $1 }'` ]
  then
    if [ `wc -l /tmp/repo_${REPO}_all_new.txt | awk '{ print $1 }'` -lt 1 ]
    then
      echo "Too few lines in /tmp/repo_${REPO}_all_new.txt ; apparent Docker Hub API failure" >&2
      exit 1
		else
      diff --unchanged-line-format= --old-line-format= --new-line-format='%L' /tmp/repo_${REPO}_all_old.txt /tmp/repo_${REPO}_all_new.txt
		fi
  fi
elif [ "${METHOD}" == "newestdiff" ]
then
  if [ `sum /tmp/repo_${REPO}_newest_new.txt | awk '{print $1 }'` != `sum /tmp/repo_${REPO}_newest_old.txt | awk '{print $1 }'` ]
  then
    if [ `wc -l /tmp/repo_${REPO}_newest_new.txt | awk '{ print $1 }'` -lt 1 ]
    then
      echo "Too few lines in /tmp/repo_${REPO}_newest_new.txt ; apparent Docker Hub API failure" >&2
      exit 1
		else
      diff --unchanged-line-format= --old-line-format= --new-line-format='%L' /tmp/repo_${REPO}_newest_old.txt /tmp/repo_${REPO}_newest_new.txt
	  fi
  fi
fi
