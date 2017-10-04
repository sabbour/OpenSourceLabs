#!/bin/bash

echo "Getting service external IP.."
while [ 1 ]
do
    SERVICEIP=$(kubectl get svc colorapp --namespace=staging -o=jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo "SERVICEIP: $SERVICEIP"
    if [ "$SERVICEIP"="" ]
    then
            exit
    else
            echo "Waiting for service to be ready"
    fi
    sleep 5
done

echo "Creating config map with the microservice URL"
create configmap serviceurls --from-literal COLORAPPURL=http://$SERVICEIP:3000/colors

echo "Applying config map"
kubecrt label configmap serviceurls app=colorappp