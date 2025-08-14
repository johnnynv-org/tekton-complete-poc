#!/bin/bash

echo "🚀 Deploying Tekton CI/CD Pipeline..."
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
echo "5️⃣  Verifying deployments..."

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
echo "🧪 To test the pipeline:"
echo "   ./.tekton/test-webhook.sh"
echo ""
echo "📚 Or push code to trigger GitHub Actions"