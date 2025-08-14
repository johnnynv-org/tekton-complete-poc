#!/bin/bash

echo "🚀 Deploying updated Tekton configurations..."
echo ""

# Set namespace
NAMESPACE="tekton-pipelines"

echo "1️⃣  Applying Pipeline and Task definitions..."
kubectl apply -f .tekton/pipelines/task-pytest.yaml
kubectl apply -f .tekton/pipelines/pipeline.yaml

echo ""
echo "2️⃣  Updating TriggerBinding and TriggerTemplate..."
kubectl apply -f .tekton/infrastructure/triggerbinding.yaml
kubectl apply -f .tekton/infrastructure/triggertemplate.yaml

echo ""
echo "3️⃣  Updating EventListener..."
kubectl apply -f .tekton/infrastructure/eventlistener.yaml

echo ""
echo "4️⃣  Applying Ingress configuration..."
kubectl apply -f .tekton/infrastructure/ingress.yaml

echo ""
echo "5️⃣  Optionally applying NodePort service (if needed for backup access)..."
echo "   Note: NodePort 30081 is configured (30080 is used by gpu-artifacts-web-service)"
echo "   Uncomment the next line if you want NodePort access:"
echo "   # kubectl apply -f .tekton/infrastructure/eventlistener-nodeport.yaml"

echo ""
echo "6️⃣  Verifying deployments..."
echo ""

echo "📋 EventListener status:"
kubectl get eventlistener github-webhook-production -n $NAMESPACE

echo ""
echo "📋 TriggerBinding status:"
kubectl get triggerbinding github-webhook-triggerbinding -n $NAMESPACE

echo ""
echo "📋 TriggerTemplate status:"
kubectl get triggertemplate github-webhook-triggertemplate -n $NAMESPACE

echo ""
echo "📋 Pipeline status:"
kubectl get pipeline pytest-pipeline -n $NAMESPACE

echo ""
echo "📋 Ingress status:"
kubectl get ingress github-webhook-ingress -n $NAMESPACE

echo ""
echo "🌐 Access points:"
echo "   Webhook URL: http://webhook.10.34.2.129.nip.io"
echo "   Dashboard: http://tekton.10.34.2.129.nip.io"
echo "   Artifacts: http://artifacts.10.34.2.129.nip.io"

echo ""
echo "✅ Deployment completed!"
echo ""
echo "🧪 To test the webhook:"
echo "curl -X POST http://webhook.10.34.2.129.nip.io \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'X-GitHub-Event: push' \\"
echo "  -d '{"
echo "    \"repository\": {"
echo "      \"clone_url\": \"$(git remote get-url origin)\","
echo "      \"name\": \"$(basename \$(git remote get-url origin) .git)\""
echo "    },"
echo "    \"after\": \"$(git rev-parse HEAD)\","
echo "    \"short_sha\": \"$(git rev-parse --short HEAD)\","
echo "    \"ref\": \"refs/heads/$(git branch --show-current)\""
echo "  }'"
