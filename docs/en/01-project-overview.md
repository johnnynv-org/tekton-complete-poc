# 01 - Project Overview

## Project Introduction

This project is a GitHub Actions + Tekton POC (Proof of Concept) that demonstrates a complete CI/CD pipeline from GitHub code commits to Tekton pytest execution.

## Architecture Design

### Approach 1: Direct kubectl Mode (Deprecated)
```
GitHub Push → Runner → kubectl apply → Tekton Pipeline
```
**Issues:** Runner handles too many responsibilities, violates production best practices

### Approach 2: Tekton Triggers Mode (Current)
```
┌─────────────────┐    ┌───────────────────┐    ┌─────────────────────────┐
│                 │    │                   │    │   Kubernetes Cluster   │
│  GitHub Repo    │───▶│  Self-hosted      │───▶│  ┌─────────────────────┐│
│  (tekton-poc)   │    │  GitHub Runner    │    │  │ Tekton EventListener││
│                 │    │ swqa-gh-runner-poc│    │  │  (Internal Service) ││
└─────────────────┘    └───────────────────┘    │  └─────────────────────┘│
         │                       │              │           │             │
         │                       │              │           ▼             │
    Code Push Trigger        HTTP POST          │  ┌─────────────────────┐│
                           to Internal Service   │  │   Tekton Pipeline   ││
                                                 │  │   (Execute pytest)  ││
                                                 │  └─────────────────────┘│
                                                 └─────────────────────────┘
```

**Advantages:**
- **Separation of Concerns**: Runner only handles triggering, not business logic
- **Security Isolation**: Tekton completely internal, no external exposure
- **Production Grade**: Complies with enterprise-level CI/CD best practices

## Core Components

### 1. GitHub Repository
- Contains Python code and pytest tests
- GitHub Actions workflow configuration
- Tekton resource configuration files (Pipeline, Task, EventListener, etc.)

### 2. Self-hosted GitHub Runner
- **Name**: `swqa-gh-runner-poc`
- **Location**: Machine that can access Kubernetes cluster internal network
- **Responsibility**: Receive GitHub webhooks, forward HTTP requests to Tekton EventListener
- **Permissions**: Minimal permissions, only needs network access to internal services

### 3. Kubernetes Cluster + Tekton
- **Tekton Pipelines**: Core pipeline engine
- **Tekton Triggers**: Event-driven components
  - **EventListener**: Internal service that listens for HTTP requests
  - **TriggerBinding**: Parse GitHub payload parameters
  - **TriggerTemplate**: Define PipelineRun creation template
- **Tekton Dashboard**: Web UI interface
  - Access URL: http://tekton.10.117.3.193.nip.io
  - Username: admin
  - Password: admin123

## Workflow (Tekton Triggers Mode)

1. **Code Commit**: Developer pushes code to GitHub main branch
2. **Trigger Actions**: GitHub Actions detects push event
3. **Runner Processing**: Execute simplified workflow on `swqa-gh-runner-poc`
4. **HTTP Trigger**: Runner sends HTTP POST to internal EventListener service
5. **Event Processing**: EventListener parses request, creates PipelineRun via TriggerTemplate
6. **Execute Tests**: Tekton Pipeline automatically runs pytest tests
7. **View Results**: Check execution results in Tekton Dashboard

## Project Structure

```
tekton-poc/
├── .github/
│   └── workflows/           # GitHub Actions config (simplified Runner logic)
├── .tekton/                 # Tekton resource configuration
│   ├── task-pytest.yaml           # Tekton Task definition
│   ├── pipeline.yaml              # Tekton Pipeline definition
│   ├── eventlistener.yaml         # EventListener configuration
│   ├── triggerbinding.yaml        # TriggerBinding configuration
│   └── triggertemplate.yaml       # TriggerTemplate configuration
├── src/                     # Source code
├── tests/                   # pytest test files
├── docs/
│   ├── zh/                 # Chinese documentation
│   └── en/                 # English documentation
├── main.py                 # Main program file
├── pytest.ini             # pytest configuration (including marker definitions)
└── requirements.txt        # Python dependencies
```

## Next Steps

Please read the documentation in the following order:

- [02 - Tekton Environment Setup](./02-tekton-environment-setup.md)
- [03 - Project Code Structure](./03-project-code-structure.md)
- [04 - Tekton Triggers Configuration](./04-tekton-triggers-configuration.md)
- [05 - GitHub Actions Configuration](./05-github-actions-configuration.md)
- [06 - End-to-End Testing](./06-end-to-end-testing.md)
- [07 - Troubleshooting](./07-troubleshooting.md)
