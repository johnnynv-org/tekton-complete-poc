# Tekton配置同步更新

## 更改概述

本次更新将项目配置文件与当前运行的Tekton实例同步，解决了GitHub Actions无法触发Tekton Pipeline的问题。

## 主要更改

### 1. GitHub Actions工作流 (`.github/workflows/tekton-ci.yml`)
- **变更前**: 使用NodePort访问 `http://$NODE_IP:30080`
- **变更后**: 使用Ingress访问 `http://webhook.10.34.2.129.nip.io`
- **变更前**: Dashboard URL `http://tekton.10.117.3.193.nip.io`
- **变更后**: Dashboard URL `http://tekton.10.34.2.129.nip.io`

### 2. EventListener配置 (`.tekton/infrastructure/eventlistener.yaml`)
- **变更前**: 名称 `github-listener`
- **变更后**: 名称 `github-webhook-production`
- **新增**: GitHub interceptor配置，支持webhook secret验证
- **新增**: 支持push和pull_request事件类型

### 3. TriggerBinding配置 (`.tekton/infrastructure/triggerbinding.yaml`)
- **变更前**: 名称 `github-push-binding`
- **变更后**: 名称 `github-webhook-triggerbinding`
- **变更**: 参数映射适配GitHub Actions payload格式
- **新增**: `ref`参数支持

### 4. TriggerTemplate配置 (`.tekton/infrastructure/triggertemplate.yaml`)
- **变更前**: 名称 `pytest-trigger-template`
- **变更后**: 名称 `github-webhook-triggertemplate`
- **保持**: Pipeline引用 `pytest-pipeline`（保持项目逻辑）
- **新增**: `ref`参数支持

### 5. NodePort服务配置 (`.tekton/infrastructure/eventlistener-nodeport.yaml`)
- **变更前**: 服务名 `el-github-listener-nodeport`，端口30080
- **变更后**: 服务名 `el-github-webhook-production-nodeport`，端口30081
- **原因**: 30080端口已被`gpu-artifacts-web-service`使用

### 6. 新增Ingress配置 (`.tekton/infrastructure/ingress.yaml`)
- **新增**: 专用的Ingress配置文件
- **域名**: `webhook.10.34.2.129.nip.io`
- **后端**: `el-github-webhook-production:8080`

### 7. Pipeline配置更新 (`.tekton/pipelines/pipeline.yaml`)
- **变更**: 更新所有URL从 `10.117.3.193` 到 `10.34.2.129`
- **影响**: Dashboard链接、Artifacts链接

### 8. 新增Webhook Secret配置 (`.tekton/infrastructure/webhook-secret.yaml`)
- **新增**: Secret配置模板文件
- **用途**: GitHub webhook验证（可选）

## 部署步骤

### 方式1: 使用部署脚本（推荐）
```bash
cd /path/to/tekton-complete-poc
./.tekton/deploy-updated-configs.sh
```

### 方式2: 手动部署
```bash
# 1. 应用Pipeline定义
kubectl apply -f .tekton/pipelines/task-pytest.yaml
kubectl apply -f .tekton/pipelines/pipeline.yaml

# 2. 更新Triggers配置
kubectl apply -f .tekton/infrastructure/triggerbinding.yaml
kubectl apply -f .tekton/infrastructure/triggertemplate.yaml
kubectl apply -f .tekton/infrastructure/eventlistener.yaml

# 3. 应用Ingress
kubectl apply -f .tekton/infrastructure/ingress.yaml

# 4. (可选) NodePort服务
kubectl apply -f .tekton/infrastructure/eventlistener-nodeport.yaml
```

## 验证步骤

### 1. 检查服务状态
```bash
kubectl get eventlistener,triggerbinding,triggertemplate -n tekton-pipelines
kubectl get ingress github-webhook-ingress -n tekton-pipelines
```

### 2. 测试Webhook端点
```bash
curl -X POST http://webhook.10.34.2.129.nip.io \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "repository": {
      "clone_url": "https://github.com/johnnynv/tekton-poc.git",
      "name": "tekton-poc"
    },
    "after": "main",
    "short_sha": "12345678",
    "ref": "refs/heads/main"
  }'
```

### 3. 验证GitHub Actions
推送代码到main分支，检查GitHub Actions是否能成功触发Tekton Pipeline。

## 访问地址

- **Webhook端点**: http://webhook.10.34.2.129.nip.io
- **Tekton Dashboard**: http://tekton.10.34.2.129.nip.io
- **测试报告**: http://artifacts.10.34.2.129.nip.io

## 故障排除

### GitHub Actions失败
1. 检查runner网络连接
2. 验证Ingress是否工作
3. 查看EventListener日志

### Pipeline未创建
1. 检查TriggerBinding参数映射
2. 验证TriggerTemplate配置
3. 查看Tekton Dashboard

### 访问问题
1. 确认DNS解析 (`nslookup webhook.10.34.2.129.nip.io`)
2. 检查Ingress Controller状态
3. 验证Service endpoints
