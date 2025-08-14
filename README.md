# Tekton Complete POC

A comprehensive Proof of Concept demonstrating end-to-end CI/CD pipeline using Tekton and GitHub Actions.

## Overview

This project showcases a production-ready CI/CD architecture where:
- **GitHub Actions** triggers pipeline execution via webhooks
- **Tekton** handles the actual CI/CD business logic 
- **Pipeline as Code** ensures pipeline definitions evolve with application code

## Architecture

```
GitHub Push → GitHub Actions → Webhook → EventListener → TriggerBinding → TriggerTemplate → PipelineRun
```

## Quick Start

### Prerequisites
- Kubernetes cluster with Tekton installed
- Self-hosted GitHub runner with cluster access
- Ingress controller configured

### 1. Deploy Infrastructure (One-time setup)
```bash
# Deploy Tekton infrastructure components
./.tekton/deploy.sh
```

### 2. Configure GitHub Actions
The GitHub Actions workflow (`.github/workflows/tekton-ci.yml`) automatically:
- Applies latest pipeline definitions
- Triggers pipeline execution via webhook
- Provides execution status and links

### 3. Test the Pipeline
```bash
# Manual webhook test
./.tekton/test-webhook.sh

# Or simply push code to trigger GitHub Actions
git add .
git commit -m "trigger pipeline"
git push origin main
```

## Project Structure

```
├── .github/workflows/          # GitHub Actions workflow
├── .tekton/
│   ├── infrastructure/         # Tekton infrastructure (EventListener, Triggers)
│   ├── pipelines/             # Pipeline definitions (Tasks, Pipelines)
│   ├── deploy.sh              # Deployment script
│   └── test-webhook.sh        # Manual testing script
├── src/                       # Application source code
├── tests/                     # Test files
└── docs/                      # Documentation
```

## Key Features

- **Dynamic Configuration**: No hardcoded URLs or repository names
- **Separation of Concerns**: Infrastructure vs Business Logic layers
- **Security**: Proper RBAC and webhook validation
- **Monitoring**: Integration with Tekton Dashboard
- **Artifacts**: Test reports and coverage analysis

## Access Points

- **Tekton Dashboard**: http://tekton.10.34.2.129.nip.io
- **Webhook Endpoint**: http://webhook.10.34.2.129.nip.io  
- **Test Reports**: http://artifacts.10.34.2.129.nip.io

## Development

### Testing Locally
```bash
# Run pytest locally
python -m pytest tests/ -v

# Test webhook endpoint
./.tekton/test-webhook.sh
```

### Adding New Pipeline Steps
1. Edit `.tekton/pipelines/task-pytest.yaml` or `.tekton/pipelines/pipeline.yaml`
2. Commit and push changes
3. GitHub Actions will automatically apply the new definitions

## Documentation

- [English Documentation](./docs/en/) - Complete setup and configuration guide
- [中文文档](./docs/zh/) - 完整的设置和配置指南

## Troubleshooting

See [Troubleshooting Guide](./docs/en/06-troubleshooting-guide.md) for common issues and solutions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Push and create a Pull Request

Changes to pipeline definitions will be automatically tested via the CI/CD pipeline.