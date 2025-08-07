# 04 - Tekton Triggers配置

本文档详细说明如何配置Tekton Triggers组件，实现通过HTTP请求触发Tekton Pipeline的生产级架构。

## 架构概述

```
GitHub Runner → HTTP POST → EventListener → TriggerBinding → TriggerTemplate → PipelineRun
```

**职责分离：**
- **EventListener**: 接收HTTP请求，验证和路由
- **TriggerBinding**: 从请求payload中提取参数
- **TriggerTemplate**: 定义如何创建PipelineRun
- **Pipeline**: 执行具体的业务逻辑

## EventListener配置

### 文件位置
`.tekton/eventlistener.yaml`

### 配置内容

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

**关键配置说明：**
- `serviceAccountName`: 指定运行权限
- `triggers`: 定义触发器列表
- `bindings`: 参数绑定引用
- `template`: PipelineRun模板引用
- `interceptors`: 请求验证和过滤

### Service配置

```yaml
apiVersion: v1
kind: Service
metadata:
  name: el-github-listener
  namespace: default
spec:
  selector:
    eventlistener: github-listener
  ports:
    - port: 8080
      targetPort: 8080
  type: ClusterIP
```

## TriggerBinding配置

### 文件位置
`.tekton/triggerbinding.yaml`

### 配置内容

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

**参数提取：**
- `git-url`: 从GitHub payload提取仓库clone URL
- `git-revision`: 提取commit SHA
- `git-repo-name`: 提取仓库名称
- `git-repo-url`: 提取仓库页面URL

## TriggerTemplate配置

### 文件位置
`.tekton/triggertemplate.yaml`

### 配置内容

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

**模板功能：**
- 动态生成PipelineRun名称
- 传递GitHub参数到Pipeline
- 自动创建工作空间

## RBAC配置

### ServiceAccount配置

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-triggers-sa
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-triggers-role
rules:
  - apiGroups: ["triggers.tekton.dev"]
    resources: ["eventlisteners", "triggerbindings", "triggertemplates"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["tekton.dev"]
    resources: ["pipelineruns", "taskruns"]
    verbs: ["create", "get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-binding
subjects:
  - kind: ServiceAccount
    name: tekton-triggers-sa
    namespace: default
roleRef:
  kind: ClusterRole
  name: tekton-triggers-role
  apiGroup: rbac.authorization.k8s.io
```

## GitHub Secret配置（可选）

### 创建Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-secret
  namespace: default
type: Opaque
stringData:
  secretToken: "your-github-webhook-secret"
```

### 使用方式

```bash
# 创建secret
kubectl create secret generic github-secret \
  --from-literal=secretToken="your-secret-here" \
  -n default
```

## 部署步骤

### 1. 应用RBAC配置

```bash
kubectl apply -f .tekton/rbac.yaml
```

### 2. 应用Triggers配置

```bash
kubectl apply -f .tekton/triggerbinding.yaml
kubectl apply -f .tekton/triggertemplate.yaml
kubectl apply -f .tekton/eventlistener.yaml
```

### 3. 验证部署

```bash
# 检查EventListener状态
kubectl get eventlistener -n default

# 检查Service
kubectl get svc -l eventlistener=github-listener -n default

# 检查Pod
kubectl get pods -l eventlistener=github-listener -n default
```

## 测试EventListener

### 内网测试

```bash
# 获取Service ClusterIP
SERVICE_IP=$(kubectl get svc el-github-listener -n default -o jsonpath='{.spec.clusterIP}')

# 发送测试请求
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

### 验证PipelineRun创建

```bash
# 检查是否创建了新的PipelineRun
kubectl get pipelinerun -n default

# 查看最新的PipelineRun
kubectl get pipelinerun -n default --sort-by=.metadata.creationTimestamp
```

## 网络配置

### 内网访问地址

EventListener的内网访问地址：
```
http://el-github-listener.default.svc.cluster.local:8080
```

或使用ClusterIP：
```bash
kubectl get svc el-github-listener -n default
```

## 安全最佳实践

### 1. 网络隔离
- EventListener只监听内网，不对外暴露
- 使用ClusterIP Service，避免NodePort或LoadBalancer

### 2. 权限最小化
- ServiceAccount只有必要的Tekton资源权限
- 不授予cluster-admin权限

### 3. 请求验证
- 配置GitHub webhook secret验证
- 使用interceptors过滤无效请求

### 4. 监控和日志
- 配置EventListener日志级别
- 监控触发频率和成功率

## 故障排除

### 常见问题

1. **EventListener Pod无法启动**
   ```bash
   kubectl describe pod -l eventlistener=github-listener -n default
   kubectl logs -l eventlistener=github-listener -n default
   ```

2. **HTTP请求无响应**
   ```bash
   # 检查Service配置
   kubectl describe svc el-github-listener -n default
   
   # 检查端口转发
   kubectl port-forward svc/el-github-listener 8080:8080 -n default
   ```

3. **PipelineRun未创建**
   ```bash
   # 检查EventListener日志
   kubectl logs -l eventlistener=github-listener -n default
   
   # 验证TriggerBinding和TriggerTemplate
   kubectl describe triggerbinding github-push-binding -n default
   kubectl describe triggertemplate pytest-trigger-template -n default
   ```

### 调试命令

```bash
# 查看所有Triggers资源
kubectl get eventlisteners,triggerbindings,triggertemplates -n default

# 查看EventListener详细状态
kubectl describe eventlistener github-listener -n default

# 实时查看日志
kubectl logs -f -l eventlistener=github-listener -n default
```

## 下一步

Tekton Triggers配置完成后，请继续阅读：
- [05 - GitHub Actions配置](./05-GitHub-Actions配置.md)
