# 05 - GitHub Actions Configuration

This document details the simplified GitHub Actions workflow configuration, focusing on triggering Tekton rather than executing specific business logic.

## Design Philosophy

### Separation of Concerns
- **GitHub Actions**: Handles webhook reception and simple parameter processing
- **Runner**: Only responsible for HTTP request forwarding, no business logic execution
- **Tekton**: Handles all CI/CD business logic execution

### Self-hosted Runner Information
- **Runner Name**: `swqa-gh-runner-poc`
- **Environment**: Machine that can access Kubernetes cluster internal network
- **Permissions**: Minimal permissions, only needs network access to EventListener service

## Workflow Configuration File

### File Location
`.github/workflows/tekton-ci.yml`

### Trigger Conditions

```yaml
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
```

**Description:**
- Triggered when code is pushed to main branch
- Triggered when Pull Request is created for main branch

### Execution Environment

```yaml
jobs:
  trigger-tekton:
    runs-on: swqa-gh-runner-poc
```

**Important:** Uses self-hosted runner `swqa-gh-runner-poc`, which must:
- Be registered in the GitHub repository
- Have access to Kubernetes cluster
- Have kubectl command-line tool installed

## Workflow Steps (Simplified Version)

### 1. Code Checkout

```yaml
- name: Checkout code
  uses: actions/checkout@v4
```

Checkout code, mainly used to get repository information and construct HTTP requests.

### 2. Trigger Tekton EventListener

```yaml
- name: Trigger Tekton Pipeline
  run: |
    # Get EventListener internal address
    EVENTLISTENER_URL="http://el-github-listener.default.svc.cluster.local:8080"
    
    # Construct GitHub-style payload
    PAYLOAD=$(cat <<EOF
    {
      "repository": {
        "clone_url": "${{ github.server_url }}/${{ github.repository }}.git",
        "name": "${{ github.event.repository.name }}",
        "html_url": "${{ github.server_url }}/${{ github.repository }}"
      },
      "after": "${{ github.sha }}",
      "ref": "${{ github.ref }}",
      "head_commit": {
        "id": "${{ github.sha }}",
        "message": "${{ github.event.head_commit.message }}"
      }
    }
    EOF
    )
    
    # Send HTTP POST request to EventListener
    echo "Triggering Tekton Pipeline..."
    curl -X POST \$EVENTLISTENER_URL \
      -H "Content-Type: application/json" \
      -H "X-GitHub-Event: push" \
      -d "\$PAYLOAD"
    
    echo "Tekton Pipeline triggered successfully!"
```

**Core Logic:**
- Construct GitHub-format JSON payload
- Send HTTP POST to internal EventListener
- EventListener automatically creates PipelineRun

### 3. Optional: Check Trigger Status

```yaml
- name: Verify Trigger (Optional)
  run: |
    echo "Pipeline triggered. Check Tekton Dashboard for execution status:"
    echo "Dashboard URL: http://tekton.10.117.3.193.nip.io"
    echo "Commit SHA: ${{ github.sha }}"
```

**Description:**
- Runner's work ends here
- Specific Pipeline execution happens in Tekton
- Result viewing requires Tekton Dashboard

## Security Considerations

### Runner Permission Minimization
Self-hosted runner only needs:
- Network access to Kubernetes cluster internal network
- No kubectl permissions required
- No direct access to Tekton resources required

### Network Security
- EventListener only listens on internal network, no external exposure
- Use ClusterIP Service for security isolation
- Optional: Configure GitHub webhook secret verification

## Troubleshooting

### Common Issues

1. **HTTP request failure**
   ```bash
   # Test network connectivity on runner machine
   curl -v http://el-github-listener.default.svc.cluster.local:8080
   ```

2. **EventListener no response**
   ```bash
   # Check EventListener status
   kubectl get eventlistener -n default
   kubectl logs -l eventlistener=github-listener -n default
   ```

3. **PipelineRun not created**
   ```bash
   # Check Triggers configuration
   kubectl get triggerbindings,triggertemplates -n default
   ```

### Debugging Steps

1. **View GitHub Actions logs** - Confirm HTTP request was sent successfully
2. **Check EventListener logs** - Confirm request was received and processed
3. **View Tekton Dashboard** - Confirm PipelineRun was created

## Advantages Summary

### Advantages over Traditional kubectl Approach

1. **Clear Responsibilities**: Runner only handles triggering, not business logic
2. **High Security**: No need to configure kubectl permissions on Runner
3. **Scalable**: Supports multiple trigger sources, easy to extend
4. **Production Grade**: Complies with enterprise-level CI/CD architecture best practices
5. **Easy Maintenance**: Simple configuration, fewer failure points

## Next Steps

After GitHub Actions configuration is complete, please continue reading:
- [06 - End-to-End Testing](./06-end-to-end-testing.md)
