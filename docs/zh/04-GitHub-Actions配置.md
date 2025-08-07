# 04 - GitHub Actions配置

本文档详细说明GitHub Actions workflow的配置和自宿主runner的使用。

## 自宿主Runner信息

- **Runner名称**: `swqa-gh-runner-poc`
- **运行环境**: 能够访问Kubernetes集群的机器
- **用途**: 接收GitHub webhook并触发Tekton Pipeline

## Workflow配置文件

### 文件位置
`.github/workflows/tekton-ci.yml`

### 触发条件

```yaml
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
```

**说明：**
- 当代码推送到main分支时触发
- 当创建针对main分支的Pull Request时触发

### 运行环境

```yaml
jobs:
  trigger-tekton:
    runs-on: swqa-gh-runner-poc
```

**重要：** 使用自宿主runner `swqa-gh-runner-poc`，该runner必须：
- 已在GitHub仓库中注册
- 能够访问Kubernetes集群
- 安装了kubectl命令行工具

## Workflow步骤详解

### 1. 代码检出

```yaml
- name: Checkout code
  uses: actions/checkout@v4
```

使用GitHub官方action检出代码到runner环境。

### 2. 验证kubectl访问

```yaml
- name: Verify kubectl access
  run: |
    echo "Checking kubectl access..."
    kubectl version --client
    kubectl config current-context
    kubectl get nodes
```

**目的：**
- 确认kubectl工具可用
- 验证与Kubernetes集群的连接
- 检查当前的kubectl context

### 3. 应用Tekton配置

```yaml
- name: Apply Tekton Task
  run: |
    echo "Applying Tekton Task..."
    kubectl apply -f .tekton/task-pytest.yaml
    
- name: Apply Tekton Pipeline
  run: |
    echo "Applying Tekton Pipeline..."
    kubectl apply -f .tekton/pipeline.yaml
```

将项目中的Tekton Task和Pipeline定义应用到Kubernetes集群。

### 4. 生成唯一的PipelineRun名称

```yaml
- name: Generate unique PipelineRun name
  id: generate-name
  run: |
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    PIPELINE_RUN_NAME="pytest-pipeline-run-${TIMESTAMP}"
    echo "pipeline_run_name=${PIPELINE_RUN_NAME}" >> $GITHUB_OUTPUT
```

**重要性：**
- 避免PipelineRun名称冲突
- 便于追踪每次运行的结果
- 支持并发执行

### 5. 创建并执行PipelineRun

```yaml
- name: Create and execute PipelineRun
  run: |
    cat << EOF > pipelinerun-temp.yaml
    apiVersion: tekton.dev/v1beta1
    kind: PipelineRun
    metadata:
      name: ${{ steps.generate-name.outputs.pipeline_run_name }}
      namespace: ${TEKTON_NAMESPACE}
    spec:
      pipelineRef:
        name: pytest-pipeline
      params:
        - name: git-url
          value: "${{ github.server_url }}/${{ github.repository }}.git"
        - name: git-revision
          value: "${{ github.sha }}"
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
    kubectl apply -f pipelinerun-temp.yaml
```

**动态参数：**
- `git-url`: 使用GitHub提供的仓库URL
- `git-revision`: 使用当前commit的SHA
- 动态生成临时的PipelineRun YAML文件

### 6. 等待PipelineRun完成

```yaml
- name: Wait for PipelineRun completion
  run: |
    timeout 600 bash -c "
      while true; do
        STATUS=\$(kubectl get pipelinerun \${PIPELINE_RUN_NAME} -n \${TEKTON_NAMESPACE} -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo 'Unknown')
        REASON=\$(kubectl get pipelinerun \${PIPELINE_RUN_NAME} -n \${TEKTON_NAMESPACE} -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo 'Unknown')
        
        if [[ \"\$STATUS\" == \"True\" ]]; then
          echo \"PipelineRun completed successfully!\"
          break
        elif [[ \"\$STATUS\" == \"False\" ]]; then
          echo \"PipelineRun failed!\"
          exit 1
        fi
        
        sleep 10
      done
    "
```

**监控机制：**
- 每10秒检查一次状态
- 超时时间：10分钟
- 成功时返回0，失败时返回1

### 7. 获取执行结果

```yaml
- name: Get PipelineRun results
  if: always()
  run: |
    kubectl get pipelinerun ${PIPELINE_RUN_NAME} -n ${TEKTON_NAMESPACE} -o yaml
    kubectl get taskruns -n ${TEKTON_NAMESPACE} -l tekton.dev/pipelineRun=${PIPELINE_RUN_NAME}
    
    for taskrun in $(kubectl get taskruns -n ${TEKTON_NAMESPACE} -l tekton.dev/pipelineRun=${PIPELINE_RUN_NAME} -o name); do
      kubectl logs ${taskrun} -n ${TEKTON_NAMESPACE} --all-containers || true
    done
```

**输出信息：**
- PipelineRun的完整状态
- 所有相关TaskRun的列表
- 每个TaskRun的完整日志

### 8. 清理资源

```yaml
- name: Cleanup
  if: always()
  run: |
    rm -f pipelinerun-temp.yaml
    kubectl get pipelinerun -n ${TEKTON_NAMESPACE} --sort-by=.metadata.creationTimestamp -o name | head -n -5 | xargs -r kubectl delete -n ${TEKTON_NAMESPACE} || true
```

**清理策略：**
- 删除临时文件
- 保留最近5个PipelineRun
- 清理旧的PipelineRun以节省资源

## 环境变量

```yaml
env:
  TEKTON_NAMESPACE: default
```

可以通过修改此变量来使用不同的Kubernetes namespace。

## 安全考虑

### GitHub Secrets
如果需要额外的安全信息（如私有仓库访问token），可以使用GitHub Secrets：

```yaml
- name: Access private resources
  run: |
    echo ${{ secrets.KUBE_CONFIG }} | base64 -d > ~/.kube/config
```

### Runner权限
自宿主runner需要适当的权限：
- 对Kubernetes集群的读写访问
- 能够创建和删除Tekton资源
- 网络访问GitHub.com

## 故障排除

### 常见问题

1. **kubectl访问失败**
   ```bash
   # 检查kubeconfig
   kubectl config view
   kubectl config current-context
   ```

2. **PipelineRun创建失败**
   ```bash
   # 检查RBAC权限
   kubectl auth can-i create pipelineruns
   ```

3. **Tekton组件未找到**
   ```bash
   # 检查Tekton安装
   kubectl get pods -n tekton-pipelines
   ```

### 调试命令

```bash
# 查看workflow运行日志（在GitHub Actions页面）
# 检查runner状态
systemctl status actions.runner.your-runner-name

# 查看PipelineRun状态
kubectl get pipelinerun -n default

# 查看TaskRun日志
kubectl logs -f taskrun/your-taskrun-name -n default
```

## 最佳实践

### 1. 资源管理
- 定期清理旧的PipelineRun
- 监控存储使用情况
- 设置合适的资源限制

### 2. 安全性
- 使用最小权限原则
- 定期更新runner环境
- 避免在日志中暴露敏感信息

### 3. 可维护性
- 使用清晰的命名约定
- 添加适当的错误处理
- 保持workflow简洁明了

## 下一步

GitHub Actions配置完成后，请继续阅读：
- [05 - Tekton Pipeline配置](./05-Tekton-Pipeline配置.md)
