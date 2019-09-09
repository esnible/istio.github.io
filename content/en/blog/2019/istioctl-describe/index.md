---
title: "istioctl describe" in Istio 1.3
description: Introducing a command-line utility to find configuration affecting pod traffic.
publishdate: 2019-09-20
attribution: Ed Snible (IBM)
keywords: [traffic-management, istioctl, debugging]
---

# istioctl describe

Istio 1.3 includes an experimental command-line tool designed to help find and
understand configuration that affects traffic to a pod.

`istioctl experimental describe pod <pod>` shows the Istio configuration that affects a pod.

The team has prepared a mini-tutorial to demonstrate the features and use of the tool.

## describe tutorial using Bookinfo tutorial

First, let us [deploy Bookinfo](/docs/examples/bookinfo/).

```
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
echo Bookinfo at $GATEWAY_URL/productpage
```

Let's describe a pod:

```
export RATINGS_POD=$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}')
istioctl experimental describe pod $RATINGS_POD
```

The output tells us which containers the pod exposes, the Istio protocol for the microservice on port 9080, and the mTLS settings for the pod. 

```
Pod: ratings-v1-f745cf57b-qrxl2
   Pod Ports: 9080 (ratings), 15090 (istio-proxy)
--------------------
Service: ratings
   Port: http 9080/HTTP
Pilot reports that pod enforces HTTP/mTLS and clients speak HTTP
```

## DestinationRules

Next we apply the DestinationRules suggested by the documentation.  I used mTLS,
so I must apply _destination-rule-all-mtls.yaml_:

```
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
istioctl experimental describe pod $RATINGS_POD
```

Applying _destination-rule-all-mtls.yaml_ created four destination rules: `details`, `productpage`, `ratings`, and `reviews`.

```
istioctl experimental describe pod $RATINGS_POD
```

Now `istioctl describe` shows additional output:

```
Pod: ratings-v1-f745cf57b-qrxl2
   Pod Ports: 9080 (ratings), 15090 (istio-proxy)
--------------------
Service: ratings
   Port: http 9080/HTTP
DestinationRule: ratings for "ratings"
   Matching subsets: v1
      (Non-matching subsets v2,v2-mysql,v2-mysql-vm)
   Traffic Policy TLS Mode: ISTIO_MUTUAL
Pilot reports that pod enforces HTTP/mTLS and clients speak mTLS
```

The *DestinationRule* now appears in the output.  This tells us that the `ratings` DestinationRule is present, and that it defines the subset `v1` which matches this pod.
Clients talking to the ratings microservice will use mTLS.

## VirtualServices

Now I will follow the Bookinfo example to [Request Routing](/docs/tasks/traffic-management/request-routing/) and define some VirtualServices:

```
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
```

After applying this rule I "describe" the _reviews-v1_ pod:

```
export REVIEWS_V1_POD=$(kubectl get pod -l app=reviews,version=v1 -o jsonpath='{.items[0].metadata.name}')
istioctl experimental describe pod $REVIEWS_V1_POD
```

The output resembles what we saw before the VirtualServices were defined, but we now see that they are present:

```
VirtualService: reviews
   1 HTTP route(s)
```

After applying _virtual-service-all-v1.yaml_ the traffic all goes to version 1.  The "stars disappear".  If this was a real cluster, someone might notice the logs to v2/v3
are no longer appearing.  Users might notice features and not working.  `describe` will not
just report the VirtualServices that configure a pod.  If it seems that a VirtualService
configures a pod, but actually blocks it, the output will include a warning.

```
export REVIEWS_V2_POD=$(kubectl get pod -l app=reviews,version=v2 -o jsonpath='{.items[0].metadata.name}')
istioctl experimental describe pod $REVIEWS_V2_POD
```

The warning "No destinations match pod subsets" tells us the problem.
No traffic will arrive due to the VirtualService destinations.

```
VirtualService: reviews
   WARNING: No destinations match pod subsets (checked 1 HTTP routes)
      Route to non-matching subset v1 for (everything)
```

Oh no!  I must revert!  I'll delete the bogus Istio configuration:

```
kubectl delete -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
```

If I refresh the browser at this point the stars do not appear.  Instead I see
*Error fetching product details!* and *Error fetching product reviews!*  Instead of
panic, I `describe`:

```
istioctl experimental describe pod $REVIEWS_V2_POD

...
VirtualService: reviews
   WARNING: No destinations match pod subsets (checked 1 HTTP routes)
      Warning: Route to UNKNOWN subset v1.  No DestinationRule.
```

At this point I look back and realize I deleted the DestinationRules, not the VirtualService V1 I wished to.  To fix the problem:

```
kubectl delete -f samples/bookinfo/networking/virtual-service-all-v1.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
```

Reloading the browser shows the app has reappeared along with the stars.  `istioctl experimental describe pod $REVIEWS_V2_POD` no longer gives warnings.

# mTLS

Let's follow the [Mutual TLS Migration](/docs/tasks/security/mtls-migration/) instructions to enable strict mTLS, but targetting ratings:

```
kubectl apply -f - <<EOF
apiVersion: "authentication.istio.io/v1alpha1"
kind: "Policy"
metadata:
  name: "ratings-strict"
spec:
  targets:
  - name: ratings
  peers:
  - mtls:
      mode: STRICT
EOF
```

Now `istioctl experimental describe pod $RATINGS_POD` reports

```
Pilot reports that pod enforces mTLS and clients speak mTLS
```

That's locked down!

If things break when mTLS is made `STRICT` it often means that the DestinationRule didn't match.  For example, if I _destination-rule-all.yaml_ is used instead of _destination-rule-all-mtls.yaml_:

```
kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml # Should have been -mtls
```

At this point the browser shows *Ratings service is currently unavailable*.  Why?

```
istioctl experimental describe pod $RATINGS_POD
```

The output is the same except the final line which now reads 

```
WARNING Pilot predicts TLS Conflict on ratings-v1-f745cf57b-qrxl2 port 9080 (pod enforces mTLS, clients speak HTTP)
  Check DestinationRule ratings/default and AuthenticationPolicy ratings-strict/default
```

Restore correct behavior with `kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml`.

## Validation of Istio requirements

`istioctl describe` will also warn if the Envoy container is not present or has not
started.  It will warn if [Istio requirements](/docs/setup/kubernetes/additional-setup/requirements/) are not met.

For example, `istioctl experimental describe pod $(kubectl -n kube-system get pod -l k8s-app=kubernetes-dashboard -o jsonpath='{.items[0].metadata.name}').kube-system` reports

```
WARNING: kubernetes-dashboard-7996b848f4-nbns2.kube-system is part of mesh; no Istio sidecar
```

## Summary of traffic rules

The tool will show a bit about the rules.  For example, let's deploy the 90/10 traffic
split:

```
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-90-10.yaml
sleep 3
istioctl experimental describe pod $REVIEWS_V1_POD
```

Let's deploy header-specific routing:

```
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-jason-v2-v3.yaml
sleep 3
istioctl experimental describe pod $REVIEWS_V1_POD
```

## Conclusion and cleanup

I hope `istioctl experimental describe` helps you to understand the traffic and security rules
used in your Istio deployment.  If you have ideas for improvements please post on
[https://discuss.istio.io](https://discuss.istio.io).

To remove the bookinfo used for this tutorial, follow [these instructions](https://istio.io/docs/examples/bookinfo/#cleanup) or run

```
kubectl delete -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl delete -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl delete -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl delete -f samples/bookinfo/networking/virtual-service-all-v1.yaml
```
