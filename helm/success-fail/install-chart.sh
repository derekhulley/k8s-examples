#!/bin/bash

# Extract arguments (https://unix.stackexchange.com/users/188975/jrichardsz)
for ARGUMENT in "$@"
do

    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            namespace)              NAMESPACE=${VALUE} ;;
            chart)                  CHART=${VALUE} ;;
            release)                RELEASE=${VALUE} ;;
            pod-selector)           POD_SELECTOR=${VALUE} ;;
            values)                 VALUES=${VALUE} ;;
            timeout)                TIMEOUT=${VALUE} ;;
            *)
    esac
done

# Mandatory arguments
if [[ -z "$NAMESPACE" ]] || [[ -z "$CHART" ]] || [[ -z "$RELEASE" ]] || [[ -z "$POD_SELECTOR" ]]; then
    echo "usage: $0 namespace=<namespace> chart=<chart-location> release=<release-name> pod-selector=<pod-selector> [values=<values-file>] [--timeout=<timeout|60s>]"
    echo "      namespace:      Kubernetes namespace to use"
    echo "      chart:          location of the Helm chart"
    echo "      release:        release name"
    echo "      pod-selector:   pod selector (label query) for monitoring and reporting; see 'kubectl get pods -l ...'"
    echo "      values:         yaml file containing values to supply for Helm installation"
    echo "      timeout:        number of seconds for Helm to wait for a successful install or upgrade"
    exit 1
fi
# Optional arguments
if [[ -z "$TIMEOUT" ]]; then
    TIMEOUT=60
fi
if [[ -z "$VALUES" ]]; then
    VALUES=/tmp/.install-chart-values.yaml
    touch $VALUES
fi


# Keep command history
DATETIME=`(date '+%Y-%m-%d_%H-%M-%S')`
HISTORY_FILE=history-"$RELEASE"-"$DATETIME".log
HISTFILE=$HISTORY_FILE
set -o history

# Create results file
RESULT_FILE=deploy-"$RELEASE"-"$DATETIME".log

# Record the history on termination
function recordHistory()
{
    echo "---------- COMMAND HISTORY ----------------" >> $RESULT_FILE
    history >> $RESULT_FILE
}
function logExit()
{
    EXIT_CODE=$?
    recordHistory
    if [[ $EXIT_CODE == 0 ]]; then
        echo "Install success: See $RESULT_FILE for full details."
    else
        echo "Install failure: See $RESULT_FILE for full details."
    fi
}
trap logExit 0 1 2 3 6 15

echo "---------- SCRIPT PARAMETERS --------------" >> $RESULT_FILE
echo "User $USER ran $0 with parameters:" >> $RESULT_FILE
echo "  namespace:          $NAMESPACE" >> $RESULT_FILE
echo "  chart:              $CHART" >> $RESULT_FILE
echo "  release:            $RELEASE" >> $RESULT_FILE
echo "  pod-selector:       $POD_SELECTOR" >> $RESULT_FILE
echo "  values:             $VALUES" >> $RESULT_FILE
echo "  timeout:            $TIMEOUT" >> $RESULT_FILE

echo "---------- VALUES -------------------------" >> $RESULT_FILE
cat "$VALUES" >> "$RESULT_FILE"
if [[ $? == 1 ]]; then
    echo "Values file not found: $VALUES"
    exit 1
fi

# Check that Helm is working
echo "---------- BASIC CHECKS -------------------" >> $RESULT_FILE
echo "helm:" >> $RESULT_FILE
echo "HELM_HOME: $HELM_HOME" >> $RESULT_FILE
helm version >> $RESULT_FILE
echo "" >> $RESULT_FILE
echo "kubectl:" >> $RESULT_FILE
echo "KUBECONFIG: $KUBECONFIG" >> $RESULT_FILE
kubectl config get-contexts >> $RESULT_FILE
kubectl version >> $RESULT_FILE
echo "" >> $RESULT_FILE
echo "kubectl config:" >> $RESULT_FILE

# Check the chart
echo "---------- CHART CHECKS -------------------" >> $RESULT_FILE
helm lint --values $VALUES $CHART >> $RESULT_FILE
if [[ $? = 1 ]]; then
    echo "Check Helm chart: $CHART"
    exit 1
fi

# Check if chart exists or not
EXISTING=$(helm list -q $RELEASE --namespace $NAMESPACE)
if [[ $EXISTING ]]; then
    echo "---------- HELM HISTORY -------------------" >> $RESULT_FILE
    helm history $RELEASE >> $RESULT_FILE
fi

function k8sFailure()
{
    echo "---------- FAILURE --------------------" >> $RESULT_FILE
    helm history $RELEASE >> $RESULT_FILE
    helm status $RELEASE >> $RESULT_FILE
    echo "" >> $RESULT_FILE
    kubectl get all -n $NAMESPACE -l $POD_SELECTOR >> $RESULT_FILE
    exit 1
}

echo "---------- HELM EXECUTION -----------------" >> $RESULT_FILE
HELM_COMMAND="helm upgrade $RELEASE $CHART --install --force --values $VALUES --namespace $NAMESPACE --wait --timeout $TIMEOUT"
eval $HELM_COMMAND >> $RESULT_FILE
HELM_COMMAND_CODE=$?

if [[ "$HELM_COMMAND_CODE" = "1" ]]; then
    k8sFailure
fi

echo "---------- K8S GENERAL CHECK --------------" >> $RESULT_FILE
sleep $TIMEOUT
K8S_ERROR_COUNT=$(kubectl get all -n $NAMESPACE -o yaml -l $POD_SELECTOR | grep -c -G Error)
K8S_FAILED_COUNT=$(kubectl get all -n $NAMESPACE -o yaml -l $POD_SELECTOR | grep -c -G 'failed:')

if [[ $K8S_ERROR_COUNT > 0 ]] || [[ $K8S_FAILED_COUNT > 0 ]]; then
    k8sFailure
fi

echo "---------- K8S JOB CHECK ------------------" >> $RESULT_FILE
K8S_JOB_COUNT=$(kubectl get jobs -n $NAMESPACE -o yaml -l $POD_SELECTOR | grep -c -G 'kind: Job')
K8S_JOB_SUCCESS_COUNT=$(kubectl get jobs -n $NAMESPACE -o yaml -l $POD_SELECTOR | grep -c -G 'succeeded:')
K8S_JOB_FAILURE_COUNT=$(kubectl get jobs -n $NAMESPACE -o yaml -l $POD_SELECTOR | grep -c -G 'failed:')
echo "$K8S_JOB_COUNT jobs found; $K8S_JOB_SUCCESS_COUNT succeeded; $K8S_JOB_FAILURE_COUNT failed" >> $RESULT_FILE
if [[ "$K8S_JOB_FAILURE_COUNT" = "0" ]]; then
    echo "As there are no failures after $TIMEOUT seconds, the deployment will be considered successful" >> $RESULT_FILE
else
    k8sFailure
fi

# Success
exit 0