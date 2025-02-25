#!/bin/bash
terraform destroy -auto-approve
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
rm -f assume-role-output.json
