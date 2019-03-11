# Usage

Install the chart to namespace 'app1-t1'
with values supplied in './values-fail-none.yaml'.

> ./install-chart.sh chart=./canfail release=t1 namespace=app1-t1 pod-selector=app=canfail values=./values-fail-none.yaml timeout=120

