#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2154

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e  # Exit on failure
set -u  # Unset is an error
# There is no need to echo, output appears in TestDocs/ops/configuration/mesh/config-resource-ready/test.sh/test.sh/_test_context/test.sh_debug.txt
set -o pipefail

# This script doesn't need a control plane initially and will install Istio when needed
# @setup profile=none

echo '*** config-resource-ready step 1 ***'
snip_install_with_enable_status

echo '*** istioctl-analyze step 2 ***'
_verify_contains snip_apply_and_wait_for_httpbin_vs "$snip_apply_and_wait_for_httpbin_vs_out"


# @cleanup
kubectl apply -f samples/httpbin/httpbin.yaml
kubectl apply -f samples/httpbin/httpbin-gateway.yaml
# Delete the Istio this test installed
kubectl delete ValidatingWebhookConfiguration istiod-istio-system
kubectl get mutatingwebhookconfigurations -o custom-columns=NAME:.metadata.name --no-headers | xargs kubectl delete mutatingwebhookconfigurations
kubectl delete ns istio-system
