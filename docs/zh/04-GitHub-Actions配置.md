# 05 - GitHub Actions配置

本文档详细说明GitHub Actions workflow的简化配置，专注于触发Tekton而非执行具体业务逻辑。

## 设计理念

### 职责分离
- **GitHub Actions**: 负责接收webhook，简单的参数处理
- **Runner**: 只负责HTTP请求转发，不执行业务逻辑
- **Tekton**: 负责所有CI/CD业务逻辑的执行

### 自宿主Runner信息
- **Runner名称**: `swqa-gh-runner-poc`
- **运行环境**: 能够访问Kubernetes集群内网的机器
- **权限**: 最小化权限，只需要网络访问EventListener服务

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

## Workflow步骤详解（简化版）

### 1. 代码检出

```yaml
- name: Checkout code
  uses: actions/checkout@v4
```

检出代码，主要用于获取仓库信息和构造HTTP请求。

### 2. 触发Tekton EventListener

```yaml
- name: Trigger Tekton Pipeline
  run: |
    # 获取EventListener内网地址
    EVENTLISTENER_URL="http://el-github-listener.default.svc.cluster.local:8080"
    
    # 构造GitHub风格的payload
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
    
    # 发送HTTP POST请求到EventListener
    echo "Triggering Tekton Pipeline..."
    curl -X POST \$EVENTLISTENER_URL \
      -H "Content-Type: application/json" \
      -H "X-GitHub-Event: push" \
      -d "\$PAYLOAD"
    
    echo "Tekton Pipeline triggered successfully!"
```

**核心逻辑：**
- 构造GitHub格式的JSON payload
- 发送HTTP POST到内网EventListener
- EventListener自动创建PipelineRun

### 3. 可选：检查触发状态

```yaml
- name: Verify Trigger (Optional)
  run: |
    echo "Pipeline triggered. Check Tekton Dashboard for execution status:"
    echo "Dashboard URL: http://tekton.10.117.3.193.nip.io"
    echo "Commit SHA: ${{ github.sha }}"
```

**说明：**
- Runner的工作到此结束
- 具体的Pipeline执行在Tekton中进行
- 结果查看需要通过Tekton Dashboard

## 安全考虑

### Runner权限最小化
自宿主runner只需要：
- 网络访问Kubernetes集群内网
- 不需要kubectl权限
- 不需要直接访问Tekton资源

### 网络安全
- EventListener只监听内网，无外部暴露
- 使用ClusterIP Service，确保安全隔离
- 可选：配置GitHub webhook secret验证

## 故障排除

### 常见问题

1. **HTTP请求失败**
   ```bash
   # 在runner机器上测试网络连通性
   curl -v http://el-github-listener.default.svc.cluster.local:8080
   ```

2. **EventListener无响应**
   ```bash
   # 检查EventListener状态
   kubectl get eventlistener -n default
   kubectl logs -l eventlistener=github-listener -n default
   ```

3. **PipelineRun未创建**
   ```bash
   # 检查Triggers配置
   kubectl get triggerbindings,triggertemplates -n default
   ```

### 调试步骤

1. **查看GitHub Actions日志** - 确认HTTP请求是否发送成功
2. **检查EventListener日志** - 确认请求是否被接收和处理
3. **查看Tekton Dashboard** - 确认PipelineRun是否被创建

## 优势总结

### 相比传统kubectl方式的优势

1. **职责清晰**: Runner只负责触发，不执行业务逻辑
2. **安全性高**: 无需在Runner上配置kubectl权限
3. **可扩展**: 支持多种触发源，易于扩展
4. **生产级**: 符合企业级CI/CD架构最佳实践
5. **易维护**: 配置简单，故障点少

## 下一步

GitHub Actions配置完成后，请继续阅读：
- [05 - Tekton Pipeline配置](./05-Tekton-Pipeline配置.md)
