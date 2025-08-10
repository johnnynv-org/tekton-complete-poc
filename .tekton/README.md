# Tekton Configuration Structure

This directory contains Tekton pipeline configurations organized into two layers following industry best practices.

## Directory Structure

```
.tekton/
├── infrastructure/                    # Infrastructure Layer (One-time deployment)
│   ├── namespace-security-policy.yaml # Namespace and Pod Security Policy configuration
│   ├── rbac.yaml                      # ServiceAccount, Role, RoleBinding  
│   ├── eventlistener.yaml             # EventListener service
│   ├── eventlistener-nodeport.yaml    # NodePort service (network connectivity)
│   ├── triggerbinding.yaml            # Extract parameters from webhooks
│   └── triggertemplate.yaml           # Template for creating PipelineRuns
└── pipelines/                         # Business Logic Layer (Version-controlled deployment)
    ├── task-pytest.yaml              # Task definition with security contexts
    ├── pipeline.yaml                 # Pipeline definition
    └── pipelinerun.yaml              # Example PipelineRun (for manual testing)
```

## Deployment Strategy

### Infrastructure Layer (One-time setup by Platform Team)

Deploy the infrastructure components once per cluster:

```bash
kubectl apply -f .tekton/infrastructure/rbac.yaml
kubectl apply -f .tekton/infrastructure/triggerbinding.yaml  
kubectl apply -f .tekton/infrastructure/triggertemplate.yaml
kubectl apply -f .tekton/infrastructure/eventlistener.yaml
```

### Business Logic Layer (Automated by GitHub Actions)

The pipeline definitions are automatically applied on every code push:

```bash
# Executed automatically by GitHub Actions
kubectl apply -f .tekton/pipelines/task-pytest.yaml
kubectl apply -f .tekton/pipelines/pipeline.yaml
```

## Benefits

- **Separation of Concerns**: Infrastructure vs Business Logic
- **Pipeline as Code**: Business logic evolves with application code
- **Role Separation**: Platform team manages infrastructure, Dev team manages pipelines
- **Version Control**: Pipeline changes are tracked alongside code changes
- **Dynamic Updates**: Latest pipeline definitions are always used

## Manual Testing

For manual pipeline testing, use the example PipelineRun:

```bash
kubectl apply -f .tekton/pipelines/pipelinerun.yaml
```
