# 04 - Tekton Triggers Configuration

This document details how to configure Tekton Triggers components to implement a production-grade architecture that triggers Tekton Pipelines via HTTP requests.

## Architecture Overview

```
GitHub Runner → HTTP POST → EventListener → TriggerBinding → TriggerTemplate → PipelineRun
```

**Separation of Concerns:**
- **EventListener**: Receives HTTP requests, validates and routes
- **TriggerBinding**: Extracts parameters from request payload
- **TriggerTemplate**: Defines how to create PipelineRun
- **Pipeline**: Executes specific business logic

## EventListener Configuration

### File Location
`.tekton/eventlistener.yaml`

### Configuration Content

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-listener
  namespace: default
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: github-push-trigger
      bindings:
        - ref: github-push-binding
      template:
        ref: pytest-trigger-template
      interceptors:
        - name: "verify-github-payload"
          ref:
            name: "github"
          params:
            - name: "secretRef"
              value:
                secretName: github-secret
                secretKey: secretToken
            - name: "eventTypes"
              value: ["push"]
```

**Key Configuration:**
- `serviceAccountName`: Specifies execution permissions
- `triggers`: Defines list of triggers
- `bindings`: Parameter binding reference
- `template`: PipelineRun template reference
- `interceptors`: Request validation and filtering

## TriggerBinding Configuration

### File Location
`.tekton/triggerbinding.yaml`

### Configuration Content

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-push-binding
  namespace: default
spec:
  params:
    - name: git-url
      value: $(body.repository.clone_url)
    - name: git-revision
      value: $(body.after)
    - name: git-repo-name
      value: $(body.repository.name)
    - name: git-repo-url
      value: $(body.repository.html_url)
```

**Parameter Extraction:**
- `git-url`: Extract repository clone URL from GitHub payload
- `git-revision`: Extract commit SHA
- `git-repo-name`: Extract repository name
- `git-repo-url`: Extract repository page URL

## TriggerTemplate Configuration

### File Location
`.tekton/triggertemplate.yaml`

### Configuration Content

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: pytest-trigger-template
  namespace: default
spec:
  params:
    - name: git-url
      description: Git repository URL
    - name: git-revision
      description: Git revision to checkout
    - name: git-repo-name
      description: Repository name
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        name: pytest-run-$(tt.params.git-revision)
        namespace: default
      spec:
        pipelineRef:
          name: pytest-pipeline
        params:
          - name: git-url
            value: $(tt.params.git-url)
          - name: git-revision
            value: $(tt.params.git-revision)
        workspaces:
          - name: shared-data
            volumeClaimTemplate:
              spec:
                accessModes:
                  - ReadWriteOnce
                resources:
                  requests:
                    storage: 1Gi
```

## Deployment Steps

### 1. Apply RBAC Configuration

```bash
kubectl apply -f .tekton/rbac.yaml
```

### 2. Apply Triggers Configuration

```bash
kubectl apply -f .tekton/triggerbinding.yaml
kubectl apply -f .tekton/triggertemplate.yaml
kubectl apply -f .tekton/eventlistener.yaml
```

### 3. Verify Deployment

```bash
# Check EventListener status
kubectl get eventlistener -n default

# Check Service
kubectl get svc -l eventlistener=github-listener -n default

# Check Pod
kubectl get pods -l eventlistener=github-listener -n default
```

## Testing EventListener

### Internal Network Test

```bash
# Get Service ClusterIP
SERVICE_IP=$(kubectl get svc el-github-listener -n default -o jsonpath='{.spec.clusterIP}')

# Send test request
curl -X POST http://${SERVICE_IP}:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/johnnynv/tekton-poc.git",
      "name": "tekton-poc",
      "html_url": "https://github.com/johnnynv/tekton-poc"
    },
    "after": "main"
  }'
```

## Security Best Practices

### 1. Network Isolation
- EventListener only listens on internal network, no external exposure
- Use ClusterIP Service, avoid NodePort or LoadBalancer

### 2. Minimal Permissions
- ServiceAccount only has necessary Tekton resource permissions
- Do not grant cluster-admin privileges

### 3. Request Validation
- Configure GitHub webhook secret verification
- Use interceptors to filter invalid requests

## Troubleshooting

### Common Issues

1. **EventListener Pod fails to start**
   ```bash
   kubectl describe pod -l eventlistener=github-listener -n default
   kubectl logs -l eventlistener=github-listener -n default
   ```

2. **HTTP request no response**
   ```bash
   # Check Service configuration
   kubectl describe svc el-github-listener -n default
   
   # Check port forwarding
   kubectl port-forward svc/el-github-listener 8080:8080 -n default
   ```

## Next Steps

After Tekton Triggers configuration is complete, please continue reading:
- [05 - GitHub Actions Configuration](./05-github-actions-configuration.md)
