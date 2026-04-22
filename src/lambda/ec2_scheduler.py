"""
ec2_scheduler.py — Lambda function to start/stop non-production EC2 instances
on a schedule to reduce costs.

EventBridge triggers:
  Stop:  cron(0 0 ? * MON-FRI *)  — 7pm EST weekdays
  Start: cron(0 13 ? * MON-FRI *) — 8am EST weekdays

Environment variables:
  TARGET_ENVIRONMENTS — comma-separated list e.g. "staging,dev"
  DRY_RUN             — set to "true" to log actions without executing
"""

import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')


def handler(event, context):
    action = event.get('action', 'stop').lower()
    dry_run = os.environ.get('DRY_RUN', 'false').lower() == 'true'
    target_envs = os.environ.get('TARGET_ENVIRONMENTS', 'staging,dev').split(',')

    logger.info(f"Action: {action} | Environments: {target_envs} | DryRun: {dry_run}")

    current_state = 'running' if action == 'stop' else 'stopped'

    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Environment', 'Values': target_envs},
            {'Name': 'instance-state-name', 'Values': [current_state]}
        ]
    )

    instance_ids = [
        instance['InstanceId']
        for reservation in response['Reservations']
        for instance in reservation['Instances']
    ]

    if not instance_ids:
        logger.info(f"No {current_state} instances found in environments: {target_envs}")
        return {'statusCode': 200, 'body': 'No instances to process'}

    logger.info(f"Found {len(instance_ids)} instances to {action}: {instance_ids}")

    if not dry_run:
        if action == 'stop':
            ec2.stop_instances(InstanceIds=instance_ids)
            logger.info(f"Stopped {len(instance_ids)} instances")
        elif action == 'start':
            ec2.start_instances(InstanceIds=instance_ids)
            logger.info(f"Started {len(instance_ids)} instances")
    else:
        logger.info(f"DRY RUN: Would {action} instances: {instance_ids}")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'action': action,
            'instances': instance_ids,
            'dry_run': dry_run
        })
    }
