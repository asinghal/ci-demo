#!/usr/bin/env bash

set -e
set -u
set -o pipefail

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"
FAMILY=$1
TASK_NAME=$1
APP_NAME=$2
ECS_CLUSTER=$3
REPO_NAME=$4
ENVIRONMENT_NAME=$5
BUILD_TAG=`date +%Y%m%d%H%M`"-`git rev-parse --short $CIRCLE_SHA1`"
REGION="us-east-1"
AWS_REGION="us-east-1"

configure_aws_cli() {
	aws --version
	aws configure set default.output json
}

make_task_def(){
	task_template='[
		{
			"name": "%s",
			"image": "%s.dkr.ecr.%s.amazonaws.com/%s:%s",
			"essential": true,
			"memory": 500,
			"cpu": 200,
			"portMappings": [
				{
					"containerPort": 3000,
					"hostPort": 80
				}
			],
			"environment": [
        {
          "name": "NODE_ENV",
          "value": "%s"
        }
			],
			"logConfiguration": {
				"logDriver": "syslog",
				"options": {
						"tag": "%s",
						"syslog-address": "%s"
				}
      }
		}
	]'

	task_def=$(printf "$task_template" "$TASK_NAME" $AWS_ACCOUNT_ID "$REGION" "$REPO_NAME" $BUILD_TAG $ENVIRONMENT_NAME "$ECS_CLUSTER" "tcp://tedd-berlin-logstash-elb-205018813.eu-central-1.elb.amazonaws.com:80")
}

register_definition() {
  if revision=$(aws ecs register-task-definition --container-definitions "$task_def" --family "$FAMILY" | $JQ '.taskDefinition.taskDefinitionArn'); then
    echo "Revision: $revision"
  else
    echo "Failed to register task definition"
    return 1
  fi
}

push_ecr_image() {
	eval $(aws ecr get-login --region $REGION)
  docker tag $APP_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$BUILD_TAG
  docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$BUILD_TAG
}

deploy_cluster() {
  make_task_def
  register_definition
  if [[ $(aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_CLUSTER" --task-definition $revision | \
                 $JQ '.service.taskDefinition') != $revision ]]; then
      echo "Error updating service."
      return 1
  fi

  echo "Deployed!"
  return 0
}

configure_aws_cli
push_ecr_image
deploy_cluster
