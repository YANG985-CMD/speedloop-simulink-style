# Simulink FOC Skills

这个仓库现在提供两个可以单独安装、也可以一起使用的 Skill：

## 1. `embedded-foc-simulink-codegen`

FOC 执行 Skill。负责 PMSM/BLDC 的 Clarke/Park、dq 电流环、速度环、SVPWM、启动切换、转子反馈、多速率时序、嵌入式接口和受控代码生成。

## 2. `simulink-model-auditor`

通用审计 Skill。可以审计任意 Simulink 模型或子系统，不限于 FOC。检查求解器、采样率、结构连接、模型引用、库链接、数据字典、编译数据类型和代码生成配置；对 FOC 模型再增加 PI、Rate Transition、控制器边界和启动相关专项检查。

两者的分工很简单：

- MathWorks 官方 Simulink Skills/MCP 负责读模型、改模型、仿真、行为测试、`model_check` 和 Model Advisor；
- 这两个 Skill 负责领域规则、审计证据、部署门禁和安全边界。

官方项目：

- [Simulink Agentic Toolkit](https://github.com/simulink/simulink-agentic-toolkit)
- [MATLAB Agentic Toolkit](https://github.com/matlab/matlab-agentic-toolkit)
- [MATLAB MCP Core Server](https://github.com/matlab/matlab-mcp-core-server)

## 安装

先克隆仓库，再把两个 Skill 目录复制到 Codex 的 skills 目录：

```powershell
git clone https://github.com/YANG985-CMD/embedded-foc-simulink-codegen.git .\simulink-skills
Copy-Item .\simulink-skills\skills\embedded-foc-simulink-codegen `
  "$HOME\.codex\skills\embedded-foc-simulink-codegen" -Recurse
Copy-Item .\simulink-skills\skills\simulink-model-auditor `
  "$HOME\.codex\skills\simulink-model-auditor" -Recurse
```

也可以只安装其中一个。要使用代码生成门禁，必须同时安装两个 Skill。

## 使用示例

审计任意模型：

```text
使用 $simulink-model-auditor 审计这个 Simulink 模型。先调用官方
model_overview、model_read、model_check，再运行 simulation profile 的本地审计。
不要修改模型，也不要生成代码。
```

执行 FOC 修改：

```text
使用 $embedded-foc-simulink-codegen 创建一个 STM32G4 PMSM FOC 控制器。
严格使用官方 Simulink MCP 修改模型；完成后调用 $simulink-model-auditor 做通用审计和 FOC 专项审计。
```

## 本地审计脚本

```matlab
addpath('skills/simulink-model-auditor/scripts');

% 任意 Simulink 模型
generic = audit_simulink_model('any_model.slx', ...
    'Profile', 'simulation', ...
    'OutputFile', 'artifacts/simulink-audit.json');

% FOC 专项审计
foc = audit_embedded_foc_model('motor_control.slx', ...
    'ControllerPath', 'motor_control/FOC_Controller', ...
    'Profile', 'deployment', ...
    'OutputFile', 'artifacts/foc-audit.json');
```

审计脚本只读模型，不会保存修改。`READY` 只表示脚本检查通过，不等于功能正确、标准合规或硬件安全；仍需官方 `model_test`、Model Advisor、SIL/PIL、目标机时序和硬件保护验证。

## 代码生成门禁

```matlab
addpath('skills/simulink-model-auditor/scripts');
addpath('skills/embedded-foc-simulink-codegen/scripts');
build = run_embedded_foc_codegen('motor_control.slx', ...
    'ControllerPath', 'motor_control/FOC_Controller', ...
    'ConfirmBuild', true);
```

没有明确的 `ConfirmBuild=true`，或通用/FOC deployment audit 存在 FAIL，脚本不会调用 `slbuild`。

## 验证

```matlab
results = runtests('tests');
assertSuccess(results);
```

GitHub Actions 使用 MathWorks 官方 `setup-matlab@v3` 和 `run-tests@v3`，以 R2024b 作为稳定测试基线；CI 不执行真实 Embedded Coder 构建。

## 目录

```text
skills/embedded-foc-simulink-codegen/  FOC 执行 Skill
skills/simulink-model-auditor/        通用 + FOC 审计 Skill
tests/                                两个 Skill 的 MATLAB utility tests
.github/workflows/matlab-tests.yml    GitHub Actions
```
