# 06 - pytest标签使用指南

本文档说明如何使用pytest标签（markers）来选择性运行不同类型的测试。

## 标签定义

### 配置文件位置
`pytest.ini`

### 可用标签

| 标签 | 描述 | 用途 |
|------|------|------|
| `basic` | 基础功能测试 | 测试加减乘除等基本运算 |
| `advanced` | 高级功能测试 | 测试幂运算等复杂功能 |
| `smoke` | 冒烟测试 | 快速验证核心功能是否正常 |
| `integration` | 集成测试 | 测试多个组件的协同工作 |
| `edge_case` | 边界条件测试 | 测试边界值和特殊情况 |
| `error_handling` | 错误处理测试 | 测试异常情况和错误处理 |
| `slow` | 慢速测试 | 运行时间较长的测试（预留） |

## 标签使用示例

### 测试文件中的标签

```python
import pytest

class TestCalculator:
    @pytest.mark.basic
    @pytest.mark.smoke
    def test_add_positive_numbers(self):
        """基础加法测试，也是冒烟测试"""
        assert self.calc.add(2, 3) == 5

    @pytest.mark.basic
    @pytest.mark.edge_case
    def test_add_zero(self):
        """边界条件：与零相加"""
        assert self.calc.add(0, 5) == 5

    @pytest.mark.error_handling
    @pytest.mark.smoke
    def test_divide_by_zero(self):
        """错误处理：除零异常"""
        with pytest.raises(ValueError):
            self.calc.divide(10, 0)

    @pytest.mark.advanced
    def test_power(self):
        """高级功能：幂运算"""
        assert self.calc.power(2, 3) == 8

    @pytest.mark.integration
    @pytest.mark.smoke
    def test_complex_calculation(self):
        """集成测试：复合运算"""
        result = self.calc.add(5, 3)
        result = self.calc.multiply(result, 2)
        assert result == 16
```

## 本地运行示例

### 1. 运行所有测试
```bash
python -m pytest tests/ -v
```

### 2. 运行冒烟测试
```bash
python -m pytest tests/ -v -m smoke
```

### 3. 运行基础功能测试
```bash
python -m pytest tests/ -v -m basic
```

### 4. 运行多个标签（或条件）
```bash
# 运行basic或smoke标签的测试
python -m pytest tests/ -v -m "basic or smoke"

# 运行同时有basic和smoke标签的测试
python -m pytest tests/ -v -m "basic and smoke"
```

### 5. 排除特定标签
```bash
# 运行除了slow标签之外的所有测试
python -m pytest tests/ -v -m "not slow"
```

### 6. 复杂标签组合
```bash
# 运行smoke测试，但排除integration测试
python -m pytest tests/ -v -m "smoke and not integration"
```

## Tekton Pipeline中的使用

### 1. 在Pipeline参数中指定标签

#### 运行冒烟测试
```yaml
params:
  - name: test-markers
    value: "smoke"
```

#### 运行基础测试
```yaml
params:
  - name: test-markers
    value: "basic"
```

#### 运行多个标签
```yaml
params:
  - name: test-markers
    value: "basic or smoke"
```

### 2. 不同PipelineRun示例

#### 冒烟测试PipelineRun
文件：`.tekton/pipelinerun-smoke.yaml`
```yaml
spec:
  params:
    - name: test-markers
      value: "smoke"
```

#### 完整测试PipelineRun
```yaml
spec:
  params:
    - name: test-markers
      value: ""  # 空值表示运行所有测试
```

#### 快速验证PipelineRun
```yaml
spec:
  params:
    - name: test-markers
      value: "basic and not slow"
```

## GitHub Actions集成

在GitHub Actions workflow中可以通过不同的触发条件使用不同的标签：

### 1. Push到main分支 - 运行冒烟测试
```yaml
- name: Run smoke tests on main
  if: github.ref == 'refs/heads/main'
  run: |
    # 创建PipelineRun with smoke markers
    kubectl apply -f .tekton/pipelinerun-smoke.yaml
```

### 2. Pull Request - 运行完整测试
```yaml
- name: Run full tests on PR
  if: github.event_name == 'pull_request'
  run: |
    # 创建PipelineRun with all tests
    kubectl apply -f .tekton/pipelinerun.yaml
```

## 测试结果示例

### 冒烟测试输出
```
================= test session starts =================
collected 12 items / 6 selected

tests/test_calculator.py::TestCalculator::test_add_positive_numbers PASSED    [ 16%]
tests/test_calculator.py::TestCalculator::test_subtract PASSED               [ 33%]
tests/test_calculator.py::TestCalculator::test_multiply PASSED               [ 50%]
tests/test_calculator.py::TestCalculator::test_divide PASSED                 [ 66%]
tests/test_calculator.py::TestCalculator::test_divide_by_zero PASSED         [ 83%]
tests/test_calculator.py::TestCalculatorIntegration::test_complex_calculation PASSED [100%]

================= 6 passed in 0.03s =================
```

### 基础测试输出
```
================= test session starts =================
collected 12 items / 8 selected

tests/test_calculator.py::TestCalculator::test_add_positive_numbers PASSED    [ 12%]
tests/test_calculator.py::TestCalculator::test_add_negative_numbers PASSED    [ 25%]
tests/test_calculator.py::TestCalculator::test_add_zero PASSED                [ 37%]
tests/test_calculator.py::TestCalculator::test_subtract PASSED               [ 50%]
tests/test_calculator.py::TestCalculator::test_multiply PASSED               [ 62%]
tests/test_calculator.py::TestCalculator::test_divide PASSED                 [ 75%]

================= 8 passed in 0.04s =================
```

## 最佳实践

### 1. 标签分层策略
- **smoke**: 最重要的核心功能，快速验证
- **basic**: 基础功能完整测试
- **advanced**: 高级功能测试
- **integration**: 组件间集成测试

### 2. CI/CD策略
- **开发环境**: 运行smoke测试快速反馈
- **测试环境**: 运行所有basic测试
- **生产部署前**: 运行完整测试套件

### 3. 标签组合原则
- 一个测试可以有多个标签
- smoke标签应该包含最关键的测试
- 避免过度复杂的标签组合

### 4. 维护建议
- 定期review标签的使用
- 保持标签定义的一致性
- 根据项目发展调整标签策略

## 故障排除

### 1. 标签未定义警告
```bash
PytestUnknownMarkWarning: Unknown pytest.mark.xxx
```
**解决方案**: 在`pytest.ini`中添加标签定义

### 2. 没有测试被选中
```bash
collected 0 items
```
**解决方案**: 检查标签名称拼写和测试文件中的标签使用

### 3. Tekton中标签参数不生效
**解决方案**: 确保Pipeline和Task中正确传递了`test-markers`参数

## 下一步

标签配置完成后，请继续阅读：
- [07 - 端到端测试](./07-端到端测试.md)
