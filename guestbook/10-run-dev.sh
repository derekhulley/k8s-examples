kubectl apply -f 00-redis-config.yaml -n demo
kubectl apply -f 01-redis-master-deployment.yaml -n demo
kubectl apply -f 02-redis-master-service.yaml -n demo
kubectl apply -f 08-redis-slave-deployment-dev.yaml -n demo
kubectl apply -f 04-redis-slave-service.yaml -n demo
kubectl apply -f 07-frontend-deployment-dev.yaml -n demo
kubectl apply -f 06-frontend-service.yaml -n demo
