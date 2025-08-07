# 06 - Tekton Pipeline配置

本文档详细说明Tekton Pipeline和Task的配置，专注于业务逻辑的执行，与Triggers组件协同工作。

## Tekton组件架构

```
EventListener → TriggerTemplate → PipelineRun Creation
                                        ↓
                                Tekton Pipeline
                                        ↓
                 ┌─────────────────────────────────────┐
                 │           pytest-task                │
                 │  ┌─────────┬─────────┬─────────┬─── │
                 │  │git-clone│install  │run-tests│run │
                 │  │         │deps     │         │main│
                 │  └─────────┴─────────┴─────────┴────┘
                 └─────────────────────────────────────┘
```

**触发流程：**
1. EventListener接收HTTP请求
2. TriggerTemplate自动创建PipelineRun
3. Pipeline执行预定义的Task序列
4. 每个Task独立完成特定功能

## Task配置详解

### 文件位置
`.tekton/task-pytest.yaml`

### 1. Task基本信息

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: pytest-task
  namespace: default
spec:
  description: Run pytest tests for the project
```

### 2. 参数配置

```yaml
params:
  - name: git-url
    type: string
    description: Git repository URL
  - name: git-revision
    type: string
    description: Git revision to checkout
    default: main
```

**参数说明：**
- `git-url`: Git仓库的完整URL
- `git-revision`: 要检出的Git版本（commit SHA或分支名）

### 3. 工作空间配置

```yaml
workspaces:
  - name: source
    description: The workspace containing the source code
```

**工作空间用途：**
- 在Task的不同step之间共享文件
- 存储git clone的代码
- 作为pytest执行的工作目录

### 4. Step详解

#### Step 1: Git Clone

```yaml
- name: git-clone
  image: alpine/git:latest
  workingDir: $(workspaces.source.path)
  script: |
    #!/bin/sh
    set -e
    echo "Cloning repository $(params.git-url) at revision $(params.git-revision)"
    git clone $(params.git-url) .
    git checkout $(params.git-revision)
    echo "Repository cloned successfully"
    ls -la
```

**功能：**
- 使用alpine/git镜像克隆代码
- 检出指定的revision
- 列出文件确认克隆成功

#### Step 2: 安装依赖

```yaml
- name: install-dependencies
  image: python:3.9-slim
  workingDir: $(workspaces.source.path)
  script: |
    #!/bin/bash
    set -e
    echo "Installing Python dependencies..."
    pip install -r requirements.txt
    echo "Dependencies installed successfully"
```

**功能：**
- 使用Python 3.9环境
- 安装requirements.txt中的依赖
- 为后续步骤准备Python环境

#### Step 3: 运行测试

```yaml
- name: run-tests
  image: python:3.9-slim
  workingDir: $(workspaces.source.path)
  script: |
    #!/bin/bash
    set -e
    echo "Running pytest tests..."
    pip install -r requirements.txt
    python -m pytest tests/ -v --tb=short
    echo "Tests completed successfully"
```

**功能：**
- 重新安装依赖（确保环境一致）
- 运行pytest测试，使用详细输出模式
- 失败时显示简短的traceback

#### Step 4: 运行主程序

```yaml
- name: run-main-program
  image: python:3.9-slim
  workingDir: $(workspaces.source.path)
  script: |
    #!/bin/bash
    set -e
    echo "Running main program..."
    python main.py
    echo "Main program executed successfully"
```

**功能：**
- 演示应用程序的实际运行
- 验证代码不仅测试通过，也能正常执行

## Pipeline配置详解

### 文件位置
`.tekton/pipeline.yaml`

### 1. Pipeline基本信息

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: pytest-pipeline
  namespace: default
spec:
  description: CI/CD Pipeline for Python pytest POC
```

### 2. Pipeline参数

```yaml
params:
  - name: git-url
    type: string
    description: Git repository URL
    default: "https://github.com/your-username/tekton-poc.git"
  - name: git-revision
    type: string
    description: Git revision to checkout
    default: main
```

**注意：** `git-url`的默认值需要根据实际仓库地址修改。

### 3. Pipeline工作空间

```yaml
workspaces:
  - name: shared-data
    description: Shared workspace for pipeline tasks
```

### 4. Task引用

```yaml
tasks:
  - name: run-pytest-tests
    taskRef:
      name: pytest-task
    params:
      - name: git-url
        value: $(params.git-url)
      - name: git-revision
        value: $(params.git-revision)
    workspaces:
      - name: source
        workspace: shared-data
```

**说明：**
- 引用前面定义的`pytest-task`
- 传递Pipeline参数到Task
- 将Pipeline的工作空间映射到Task

## PipelineRun配置

### 文件位置
`.tekton/pipelinerun.yaml`（模板文件）

### 配置示例

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: pytest-pipeline-run
  namespace: default
spec:
  pipelineRef:
    name: pytest-pipeline
  params:
    - name: git-url
      value: "https://github.com/your-username/tekton-poc.git"
    - name: git-revision
      value: main
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

**存储配置：**
- 使用动态PVC（volumeClaimTemplate）
- ReadWriteOnce访问模式
- 1Gi存储空间

## 执行流程

### 1. 应用配置

```bash
# 应用Task
kubectl apply -f .tekton/task-pytest.yaml

# 应用Pipeline
kubectl apply -f .tekton/pipeline.yaml
```

### 2. 创建PipelineRun

```bash
# 方式1：使用模板文件
kubectl apply -f .tekton/pipelinerun.yaml

# 方式2：命令行创建（推荐用于自动化）
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: pytest-pipeline-run-$(date +%Y%m%d-%H%M%S)
  namespace: default
spec:
  pipelineRef:
    name: pytest-pipeline
  params:
    - name: git-url
      value: "https://github.com/your-username/tekton-poc.git"
    - name: git-revision
      value: main
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
EOF
```

### 3. 监控执行

```bash
# 查看PipelineRun状态
kubectl get pipelinerun

# 查看TaskRun状态
kubectl get taskrun

# 实时查看日志
kubectl logs -f taskrun/pytest-task-run-xyz
```

## Tekton Dashboard查看

访问Tekton Dashboard可以可视化查看Pipeline执行：

- **URL**: http://tekton.10.117.3.193.nip.io
- **用户名**: admin
- **密码**: admin123

**Dashboard功能：**
- 查看Pipeline和Task定义
- 监控PipelineRun和TaskRun状态
- 查看执行日志
- 重新运行Pipeline

## 常见问题和解决方案

### 1. Git Clone失败

**问题：** 无法访问Git仓库

**解决方案：**
```bash
# 检查网络连接
kubectl run test-pod --image=alpine/git --rm -it -- sh
# 在pod中测试: git clone <your-repo-url>
```

### 2. Python依赖安装失败

**问题：** pip install失败

**解决方案：**
```yaml
# 在task中添加更多debug信息
script: |
  #!/bin/bash
  set -e
  echo "Python version: $(python --version)"
  echo "Pip version: $(pip --version)"
  cat requirements.txt
  pip install -r requirements.txt
```

### 3. 测试失败

**问题：** pytest执行报错

**解决方案：**
```bash
# 查看详细的TaskRun日志
kubectl logs taskrun/your-taskrun-name --all-containers

# 查看PipelineRun状态
kubectl describe pipelinerun your-pipelinerun-name
```

### 4. 存储空间不足

**问题：** PVC创建失败

**解决方案：**
```bash
# 检查存储类
kubectl get storageclass

# 增加存储空间
spec:
  resources:
    requests:
      storage: 2Gi  # 增加到2Gi
```

## 性能优化建议

### 1. 镜像优化
- 使用更小的基础镜像
- 考虑使用多阶段构建
- 预构建包含依赖的自定义镜像

### 2. 缓存策略
- 使用持久化workspace
- 缓存Python包安装
- 重用Git仓库

### 3. 并行执行
- 将独立的测试步骤并行化
- 使用Pipeline的并行任务功能

## 下一步

Tekton Pipeline配置完成后，请继续阅读：
- [06 - 端到端测试](./06-端到端测试.md)
