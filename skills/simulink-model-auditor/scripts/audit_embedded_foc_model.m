function report = audit_embedded_foc_model(model, varargin)
%AUDIT_EMBEDDED_FOC_MODEL Read-only audit of a Simulink FOC model.
%
% report = audit_embedded_foc_model("motor_control.slx")
% report = audit_embedded_foc_model("motor_control.slx", ...
%     "ControllerPath", "motor_control/FOC_Controller", ...
%     "Profile", "deployment", "OutputFile", "foc-audit.json")
%
% Profiles:
%   simulation - structural and simulation readiness; production omissions warn.
%   deployment - production omissions, unsafe rates, and unexpected double
%                controller interfaces fail closed.
%
% The function may compile the model but never saves it. It is not a
% replacement for behavior tests, Model Advisor, SIL/PIL, target timing, or
% hardware commissioning evidence.

parser = inputParser;
parser.FunctionName = mfilename;
addRequired(parser, 'model', @(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser, 'ControllerPath', '', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser, 'Profile', 'simulation', ...
    @(x) any(strcmpi(string(x), ["simulation", "deployment"])));
addParameter(parser, 'Compile', true, ...
    @(x) islogical(x) && isscalar(x));
addParameter(parser, 'Verbose', true, ...
    @(x) islogical(x) && isscalar(x));
addParameter(parser, 'OutputFile', '', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
parse(parser, model, varargin{:});
opts = parser.Results;
profile = lower(char(opts.Profile));

[modelName, modelFile, modelDir] = resolveModel(char(model));
oldDir = pwd;
dirCleanup = onCleanup(@() cd(oldDir));
if ~isempty(modelDir)
    cd(modelDir);
end

wasLoaded = bdIsLoaded(modelName);
if ~wasLoaded
    load_system(modelFile);
end
modelCleanup = onCleanup(@() closeIfOpened(modelName, wasLoaded));

controllerPath = char(opts.ControllerPath);
if isempty(controllerPath)
    controllerPath = findControllerBoundary(modelName);
else
    validateControllerPath(modelName, controllerPath);
end

checks = struct('id', {}, 'status', {}, 'message', {}, 'evidence', {});
settings = readSettings(modelName);

checks(end+1) = makeCheck('solver.fixed_step', ...
    passFail(strcmpi(settings.SolverType, 'Fixed-step')), ...
    'Controller uses a fixed-step solver.', ...
    sprintf('SolverType=%s, Solver=%s', settings.SolverType, settings.Solver));

explicitStep = isExplicitPositiveStep(settings.FixedStep);
checks(end+1) = makeCheck('solver.explicit_base_step', ...
    productionStatus(explicitStep, profile), ...
    'Deployment base step must be an explicit PWM/ADC-derived period.', ...
    sprintf('FixedStep=%s', settings.FixedStep));

checks(end+1) = makeCheck('codegen.ert', ...
    productionStatus(strcmpi(settings.SystemTargetFile, 'ert.tlc'), profile), ...
    'ERT is expected for the production embedded controller.', ...
    sprintf('SystemTargetFile=%s', settings.SystemTargetFile));

checks(end+1) = makeCheck('codegen.c99', ...
    productionStatus(contains(lower(settings.TargetLangStandard), 'c99'), profile), ...
    'Select the production C language standard deliberately.', ...
    sprintf('TargetLangStandard=%s', settings.TargetLangStandard));

isArmTarget = any(contains(lower(settings.ProdHWDeviceType), {'arm', 'cortex'}));
checks(end+1) = makeCheck('hardware.production_target', ...
    productionStatus(isArmTarget, profile), ...
    'Production hardware must match the MCU word and integer assumptions.', ...
    sprintf('ProdHWDeviceType=%s', settings.ProdHWDeviceType));

checks(end+1) = makeCheck('codegen.report', ...
    productionStatus(strcmpi(settings.GenerateReport, 'on'), profile), ...
    'Generate a code report for interface and traceability review.', ...
    sprintf('GenerateReport=%s', settings.GenerateReport));

checks(end+1) = makeCheck('numeric.nonfinite', ...
    productionStatus(strcmpi(settings.SupportNonFinite, 'off'), profile), ...
    'Disable non-finite support only after invalid numeric paths are handled.', ...
    sprintf('SupportNonFinite=%s', settings.SupportNonFinite));

[dictionary, dictionaryCheck] = inspectDictionary(modelName, profile);
checks(end+1) = dictionaryCheck;

if isempty(controllerPath)
    checks(end+1) = makeCheck('architecture.controller_boundary', ...
        productionStatus(false, profile), ...
        'No generated-controller boundary was identified.', ...
        'Provide ControllerPath or use FOC_Controller/FOC_Model.');
    controller = emptyController();
else
    controller = inspectController(controllerPath);
    checks(end+1) = makeCheck('architecture.controller_boundary', 'PASS', ...
        'A generated-controller boundary was identified.', controllerPath);
    checks(end+1) = makeCheck('architecture.atomic_boundary', ...
        productionStatus(strcmpi(controller.atomic, 'on'), profile), ...
        'Use an atomic or referenced boundary for a stable generated function.', ...
        sprintf('TreatAsAtomicUnit=%s', controller.atomic));

    [rateStatus, rateEvidence] = compareControllerRate( ...
        settings.FixedStep, controller.sampleTime);
    checks(end+1) = makeCheck('timing.controller_period', rateStatus, ...
        'Controller period must inherit or be an integer multiple of the base step.', ...
        rateEvidence);

    [desktopCount, desktopNames] = countDesktopBlocks(controllerPath);
    checks(end+1) = makeCheck('architecture.desktop_blocks', ...
        passFail(desktopCount == 0), ...
        'Keep scopes, file/workspace I/O, and desktop stimuli outside control.', ...
        joinEvidence(desktopNames));

    [plantCount, plantNames] = countPlantBlocks(controllerPath);
    checks(end+1) = makeCheck('architecture.plant_separation', ...
        passFail(plantCount == 0), ...
        'Keep inverter and motor plant blocks outside generated control.', ...
        joinEvidence(plantNames));
end

rateTransitions = inspectRateTransitions(modelName);
functionCalls = inspectFunctionCallGenerators(modelName);
pids = inspectPidBlocks(modelName);
features = inspectFeatures(modelName);

checks(end+1) = assessRateContract(rateTransitions, functionCalls);
checks(end+1) = assessRateTransitions(rateTransitions, profile);
[piSafetyCheck, piResetCheck] = assessPidControllers(pids, profile);
checks(end+1) = piSafetyCheck;
checks(end+1) = piResetCheck;

[compile, compileChecks] = inspectCompiledModel( ...
    modelName, controllerPath, settings.FixedStep, opts.Compile, profile);
checks(end+1:end+numel(compileChecks)) = compileChecks;

statuses = {checks.status};
summary = struct( ...
    'pass', sum(strcmp(statuses, 'PASS')), ...
    'warn', sum(strcmp(statuses, 'WARN')), ...
    'fail', sum(strcmp(statuses, 'FAIL')));
readiness = readinessFromSummary(summary);

report = struct( ...
    'schemaVersion', 2, ...
    'tool', mfilename, ...
    'profile', profile, ...
    'readiness', readiness, ...
    'model', modelName, ...
    'file', modelFile, ...
    'controller', controller, ...
    'settings', settings, ...
    'dictionary', dictionary, ...
    'features', features, ...
    'rateTransitions', rateTransitions, ...
    'functionCallGenerators', functionCalls, ...
    'pidControllers', pids, ...
    'compile', compile, ...
    'checks', checks, ...
    'summary', summary);

outputFile = char(opts.OutputFile);
if ~isempty(outputFile)
    report.outputFile = writeJsonReport(report, outputFile);
else
    report.outputFile = '';
end

if opts.Verbose
    printReport(report);
end

delete(modelCleanup);
delete(dirCleanup);
end

function [modelName, modelFile, modelDir] = resolveModel(modelArg)
if isfile(modelArg)
    [~, attributes] = fileattrib(modelArg);
    modelFile = attributes.Name;
    [modelDir, modelName] = fileparts(modelFile);
    return;
end

[~, candidateName, extension] = fileparts(modelArg);
if isempty(candidateName)
    candidateName = modelArg;
end
if bdIsLoaded(candidateName)
    modelName = candidateName;
    modelFile = get_param(modelName, 'FileName');
    modelDir = fileparts(modelFile);
    return;
end

if isempty(extension)
    located = which([modelArg '.slx']);
    if isempty(located)
        located = which([modelArg '.mdl']);
    end
else
    located = which(modelArg);
end
if isempty(located)
    error('audit_embedded_foc_model:ModelNotFound', ...
        'Could not locate model "%s".', modelArg);
end
modelFile = located;
[modelDir, modelName] = fileparts(modelFile);
end

function closeIfOpened(modelName, wasLoaded)
if ~wasLoaded && bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end

function validateControllerPath(modelName, controllerPath)
prefix = [modelName '/'];
isInModel = strncmp(controllerPath, prefix, numel(prefix));
handle = getSimulinkBlockHandle(controllerPath);
isSubsystem = handle ~= -1 && strcmpi(safeGetParam(controllerPath, 'BlockType'), 'SubSystem');
if ~isInModel || ~isSubsystem
    error('audit_embedded_foc_model:InvalidControllerPath', ...
        'ControllerPath "%s" is not a subsystem in model "%s".', ...
        controllerPath, modelName);
end
end

function settings = readSettings(modelName)
names = {'SolverType', 'Solver', 'FixedStep', 'SystemTargetFile', ...
    'TargetLangStandard', 'ProdHWDeviceType', 'GenCodeOnly', ...
    'GenerateReport', 'SupportNonFinite', 'DefaultParameterBehavior', ...
    'DataDictionary'};
settings = struct();
for index = 1:numel(names)
    settings.(names{index}) = safeGetParam(modelName, names{index});
end
end

function [dictionary, check] = inspectDictionary(modelName, profile)
dictionary = struct('name', safeGetParam(modelName, 'DataDictionary'), ...
    'resolvedPath', '', 'exactCase', false);
if isempty(dictionary.name)
    check = makeCheck('data.dictionary', productionStatus(false, profile), ...
        'No model data dictionary is attached.', ...
        'Use a version-controlled definition for calibrations and interfaces.');
    return;
end

modelDir = fileparts(get_param(modelName, 'FileName'));
if java.io.File(dictionary.name).isAbsolute()
    candidate = dictionary.name;
else
    candidate = fullfile(modelDir, dictionary.name);
end
if ~isfile(candidate)
    check = makeCheck('data.dictionary', 'FAIL', ...
        'The attached data dictionary does not resolve.', dictionary.name);
    return;
end

dictionary.resolvedPath = candidate;
[folder, base, extension] = fileparts(dictionary.resolvedPath);
entries = dir(folder);
dictionary.exactCase = any(strcmp({entries.name}, [base extension]));
if dictionary.exactCase
    status = 'PASS';
    message = 'The model data dictionary resolves with exact filename case.';
else
    status = productionStatus(false, profile);
    message = 'Dictionary filename case differs from the file on disk.';
end
check = makeCheck('data.dictionary', status, message, dictionary.resolvedPath);
end

function controllerPath = findControllerBoundary(modelName)
controllerPath = '';
subsystems = find_system(modelName, 'SearchDepth', 2, ...
    'FollowLinks', 'off', 'LookUnderMasks', 'none', 'BlockType', 'SubSystem');
preferred = {'FOC_Controller', 'FOC_Model'};
for p = 1:numel(preferred)
    for index = 1:numel(subsystems)
        if strcmpi(get_param(subsystems{index}, 'Name'), preferred{p})
            controllerPath = subsystems{index};
            return;
        end
    end
end
end

function controller = inspectController(controllerPath)
controller = struct( ...
    'path', controllerPath, ...
    'atomic', safeGetParam(controllerPath, 'TreatAsAtomicUnit'), ...
    'sampleTime', safeGetParam(controllerPath, 'SystemSampleTime'), ...
    'inputs', {orderedPorts(controllerPath, 'Inport')}, ...
    'outputs', {orderedPorts(controllerPath, 'Outport')});
end

function controller = emptyController()
controller = struct('path', '', 'atomic', '', 'sampleTime', '', ...
    'inputs', {{}}, 'outputs', {{}});
end

function [status, evidence] = compareControllerRate(baseStepText, controllerStepText)
evidence = sprintf('FixedStep=%s, ControllerSampleTime=%s', ...
    baseStepText, controllerStepText);
if any(strcmp(strtrim(controllerStepText), {'', '-1'}))
    status = 'PASS';
    evidence = [evidence ' (controller inherits its rate)'];
    return;
end
baseStep = str2double(baseStepText);
controllerStep = str2double(controllerStepText);
if ~isfinite(baseStep) || ~isfinite(controllerStep) || ...
        baseStep <= 0 || controllerStep <= 0
    status = 'WARN';
    return;
end
ratio = controllerStep / baseStep;
if isIntegerRatio(ratio)
    status = 'PASS';
else
    status = 'FAIL';
end
end

function names = orderedPorts(systemPath, blockType)
blocks = find_system(systemPath, 'SearchDepth', 1, 'BlockType', blockType);
if isempty(blocks)
    names = {};
    return;
end
ports = zeros(size(blocks));
for index = 1:numel(blocks)
    ports(index) = str2double(safeGetParam(blocks{index}, 'Port'));
end
[~, order] = sort(ports);
names = cellfun(@(x) get_param(x, 'Name'), blocks(order), 'UniformOutput', false);
end

function [count, names] = countDesktopBlocks(controllerPath)
types = {'Scope', 'Display', 'ToWorkspace', 'FromWorkspace', 'ToFile', ...
    'FromFile', 'SignalGenerator', 'SignalBuilder', 'XYScope'};
names = {};
for index = 1:numel(types)
    blocks = find_system(controllerPath, 'SearchDepth', 8, ...
        'LookUnderMasks', 'none', 'FollowLinks', 'off', ...
        'BlockType', types{index});
    names = [names; blocks(:)]; %#ok<AGROW>
end
names = unique(names, 'stable');
count = numel(names);
end

function [count, names] = countPlantBlocks(controllerPath)
blocks = find_system(controllerPath, 'SearchDepth', 8, ...
    'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'Block');
names = {};
referencePattern = ['(ee_lib|sps_lib|powerlib|mcb)/.*' ...
    '(machine|motor|pmsm|inverter|converter|bridge)'];
namePattern = '(^|[/ _-])(motor|pmsm|bldc|inverter)[ _-]?plant($|[/ _-])';
for index = 1:numel(blocks)
    reference = lower(strjoin({safeGetParam(blocks{index}, 'ReferenceBlock'), ...
        safeGetParam(blocks{index}, 'MaskType')}, ' '));
    blockName = lower(safeGetParam(blocks{index}, 'Name'));
    if ~isempty(regexpi(reference, referencePattern, 'once')) || ...
            ~isempty(regexpi(blockName, namePattern, 'once'))
        names{end+1, 1} = blocks{index}; %#ok<AGROW>
    end
end
names = unique(names, 'stable');
count = numel(names);
end

function transitions = inspectRateTransitions(modelName)
blocks = find_system(modelName, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'BlockType', 'RateTransition');
template = struct('path', '', 'outputSampleTime', '', ...
    'integrity', '', 'deterministic', '');
transitions = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    transitions(index) = struct( ...
        'path', blocks{index}, ...
        'outputSampleTime', safeGetParam(blocks{index}, 'OutPortSampleTime'), ...
        'integrity', safeGetParam(blocks{index}, 'Integrity'), ...
        'deterministic', safeGetParam(blocks{index}, 'Deterministic'));
end
end

function check = assessRateContract(transitions, generators)
if isempty(transitions) && isempty(generators)
    check = makeCheck('timing.rate_contract', 'WARN', ...
        'No explicit multirate crossing or function-call scheduler was found.', ...
        'A single-rate controller may be valid; document that decision.');
else
    check = makeCheck('timing.rate_contract', 'PASS', ...
        'Explicit rate-transition or function-call scheduling blocks were found.', ...
        sprintf('RateTransition=%d, FunctionCallGenerator=%d', ...
        numel(transitions), numel(generators)));
end
end

function check = assessRateTransitions(transitions, profile)
if isempty(transitions)
    check = makeCheck('timing.rate_transition_settings', 'PASS', ...
        'No Rate Transition blocks require inspection.', 'none found');
    return;
end

unsafe = {};
unknown = {};
for index = 1:numel(transitions)
    transition = transitions(index);
    values = {transition.integrity, transition.deterministic};
    if any(strcmpi(values, 'off'))
        unsafe{end+1} = transition.path; %#ok<AGROW>
    elseif any(cellfun(@isempty, values))
        unknown{end+1} = transition.path; %#ok<AGROW>
    end
end

if ~isempty(unsafe)
    status = productionStatus(false, profile);
    message = 'Rate Transition integrity or deterministic transfer is disabled.';
    evidence = joinEvidence(unsafe);
elseif ~isempty(unknown)
    status = 'WARN';
    message = 'Some Rate Transition settings could not be read.';
    evidence = joinEvidence(unknown);
else
    status = 'PASS';
    message = 'Rate Transition blocks preserve integrity and deterministic transfer.';
    evidence = sprintf('%d block(s)', numel(transitions));
end
check = makeCheck('timing.rate_transition_settings', status, message, evidence);
end

function generators = inspectFunctionCallGenerators(modelName)
blocks = find_system(modelName, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'MaskType', 'Function-Call Generator');
template = struct('path', '', 'sampleTime', '');
generators = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    sampleTime = firstAvailableParam(blocks{index}, ...
        {'sample_time', 'SampleTime', 'sampleTime'});
    generators(index) = struct( ...
        'path', blocks{index}, 'sampleTime', sampleTime);
end
end

function pids = inspectPidBlocks(modelName)
allBlocks = find_system(modelName, 'SearchDepth', 8, ...
    'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'Block');
isPid = false(size(allBlocks));
for index = 1:numel(allBlocks)
    signature = lower(strjoin({safeGetParam(allBlocks{index}, 'MaskType'), ...
        safeGetParam(allBlocks{index}, 'ReferenceBlock')}, ' '));
    isPid(index) = contains(signature, 'pid');
end
blocks = allBlocks(isPid);
template = struct('path', '', 'controller', '', 'P', '', 'I', '', ...
    'integratorMethod', '', 'limitOutput', '', 'antiWindup', '', ...
    'upperLimit', '', 'lowerLimit', '', 'externalReset', '', ...
    'timeDomain', '', 'sampleTime', '');
pids = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    pids(index) = struct( ...
        'path', blocks{index}, ...
        'controller', safeGetParam(blocks{index}, 'Controller'), ...
        'P', safeGetParam(blocks{index}, 'P'), ...
        'I', safeGetParam(blocks{index}, 'I'), ...
        'integratorMethod', safeGetParam(blocks{index}, 'IntegratorMethod'), ...
        'limitOutput', safeGetParam(blocks{index}, 'LimitOutput'), ...
        'antiWindup', safeGetParam(blocks{index}, 'AntiWindupMode'), ...
        'upperLimit', safeGetParam(blocks{index}, 'UpperSaturationLimit'), ...
        'lowerLimit', safeGetParam(blocks{index}, 'LowerSaturationLimit'), ...
        'externalReset', safeGetParam(blocks{index}, 'ExternalReset'), ...
        'timeDomain', safeGetParam(blocks{index}, 'TimeDomain'), ...
        'sampleTime', safeGetParam(blocks{index}, 'SampleTime'));
end
end

function [safetyCheck, resetCheck] = assessPidControllers(pids, profile)
if isempty(pids)
    safetyCheck = makeCheck('control.pi_safety', 'WARN', ...
        'No built-in PID/PI blocks were recognized.', ...
        'Custom PI implementations require behavior tests and manual review.');
    resetCheck = makeCheck('control.pi_reset', 'WARN', ...
        'PI reset behavior could not be inferred.', ...
        'Verify disable, startup, handoff, and fault reset behavior.');
    return;
end

unsafe = {};
continuous = {};
unbounded = {};
unknown = {};
noReset = {};
for index = 1:numel(pids)
    pid = pids(index);
    isPi = contains(upper(pid.controller), 'PI') || ~isempty(pid.I);
    if ~isPi
        continue;
    end
    if strcmpi(pid.timeDomain, 'Continuous-time') || strcmp(strtrim(pid.sampleTime), '0')
        continuous{end+1} = pid.path; %#ok<AGROW>
    end
    if strcmpi(pid.limitOutput, 'on')
        if any(strcmpi(strtrim(pid.antiWindup), {'none', 'off'}))
            unsafe{end+1} = pid.path; %#ok<AGROW>
        elseif isempty(pid.antiWindup)
            unknown{end+1} = pid.path; %#ok<AGROW>
        end
        if isempty(pid.upperLimit) || isempty(pid.lowerLimit)
            unknown{end+1} = pid.path; %#ok<AGROW>
        end
    else
        unbounded{end+1} = pid.path; %#ok<AGROW>
    end
    if isempty(pid.externalReset) || any(strcmpi(pid.externalReset, {'none', 'off'}))
        noReset{end+1} = pid.path; %#ok<AGROW>
    end
end

if ~isempty(continuous)
    safetyStatus = 'FAIL';
    safetyMessage = 'A recognized PI/PID uses a continuous-time configuration.';
    safetyEvidence = joinEvidence(continuous);
elseif ~isempty(unsafe)
    safetyStatus = 'FAIL';
    safetyMessage = 'Output limiting is enabled without anti-windup.';
    safetyEvidence = joinEvidence(unsafe);
elseif ~isempty(unbounded)
    safetyStatus = productionStatus(false, profile);
    safetyMessage = 'A recognized PI/PID has no internal output limit.';
    safetyEvidence = [joinEvidence(unbounded) ...
        ' (an external saturation/anti-windup path may be valid; verify it)'];
elseif ~isempty(unknown)
    safetyStatus = 'WARN';
    safetyMessage = 'Some PI limit or anti-windup settings could not be resolved.';
    safetyEvidence = joinEvidence(unique(unknown, 'stable'));
else
    safetyStatus = 'PASS';
    safetyMessage = 'Recognized PI/PID blocks use limits and anti-windup.';
    safetyEvidence = sprintf('%d block(s) inspected', numel(pids));
end
safetyCheck = makeCheck('control.pi_safety', safetyStatus, ...
    safetyMessage, safetyEvidence);

if isempty(noReset)
    resetStatus = 'PASS';
    resetMessage = 'Recognized PI/PID blocks expose reset behavior.';
    resetEvidence = sprintf('%d block(s) inspected', numel(pids));
else
    resetStatus = 'WARN';
    resetMessage = 'Some PI/PID blocks have no visible external reset.';
    resetEvidence = [joinEvidence(noReset) ...
        ' (wrapper-level reset may be valid; verify behavior)'];
end
resetCheck = makeCheck('control.pi_reset', resetStatus, resetMessage, resetEvidence);
end

function [compile, checks] = inspectCompiledModel( ...
        modelName, controllerPath, baseStepText, shouldCompile, profile)
checks = struct('id', {}, 'status', {}, 'message', {}, 'evidence', {});
compile = struct( ...
    'attempted', shouldCompile, ...
    'succeeded', false, ...
    'message', 'NOT RUN', ...
    'samplePeriods', [], ...
    'hasContinuousRate', false, ...
    'interfaceDataTypes', struct('path', {}, 'dataType', {}), ...
    'unexpectedDouble', {{}});

if ~shouldCompile
    checks(end+1) = makeCheck('model.compiled_evidence', ...
        productionStatus(false, profile), ...
        'Compiled sample-time and data-type checks were not run.', ...
        'Set Compile=true for readiness evidence.');
    return;
end

try
    set_param(modelName, 'SimulationCommand', 'update');
    checks(end+1) = makeCheck('model.diagram_update', 'PASS', ...
        'Model diagram update succeeded.', 'No model was saved.');
catch exception
    compile.message = exception.message;
    checks(end+1) = makeCheck('model.diagram_update', 'FAIL', ...
        'Model diagram update failed.', compactText(exception.message));
    return;
end

compiled = false;
try
    feval(modelName, [], [], [], 'compile');
    compiled = true;
    [periods, hasContinuous] = compiledSamplePeriods(controllerPath);
    interfaceTypes = compiledInterfaceTypes(controllerPath);
    unexpectedDouble = {interfaceTypes(strcmpi({interfaceTypes.dataType}, 'double')).path};

    compile.succeeded = true;
    compile.message = 'Model compilation and compiled-property inspection succeeded.';
    compile.samplePeriods = periods;
    compile.hasContinuousRate = hasContinuous;
    compile.interfaceDataTypes = interfaceTypes;
    compile.unexpectedDouble = unexpectedDouble;
catch exception
    compile.message = exception.message;
end

if compiled
    try
        feval(modelName, [], [], [], 'term');
    catch
        % Model cleanup will close models opened by this function.
    end
end

if ~compile.succeeded
    checks(end+1) = makeCheck('model.compiled_evidence', 'FAIL', ...
        'Compiled-property inspection failed.', compactText(compile.message));
    return;
end

checks(end+1) = makeCheck('model.compiled_evidence', 'PASS', ...
    'Compiled sample-time and data-type properties were inspected.', ...
    sprintf('Controller=%s', fallbackText(controllerPath, '<not identified>')));

[rateStatus, rateEvidence] = assessCompiledPeriods( ...
    compile.samplePeriods, compile.hasContinuousRate, baseStepText, profile);
checks(end+1) = makeCheck('timing.compiled_rates', rateStatus, ...
    'Compiled controller rates must be discrete integer multiples of the base step.', ...
    rateEvidence);

if isempty(controllerPath)
    typeStatus = productionStatus(false, profile);
    typeEvidence = 'Controller boundary was not identified.';
elseif isempty(compile.interfaceDataTypes)
    typeStatus = 'WARN';
    typeEvidence = 'No compiled controller interface types were available.';
elseif isempty(compile.unexpectedDouble)
    typeStatus = 'PASS';
    typeEvidence = joinDataTypeEvidence(compile.interfaceDataTypes);
else
    typeStatus = productionStatus(false, profile);
    typeEvidence = joinEvidence(compile.unexpectedDouble);
end
checks(end+1) = makeCheck('numeric.compiled_interface_types', typeStatus, ...
    'Controller interfaces should use deliberate embedded data types.', typeEvidence);
end

function [periods, hasContinuous] = compiledSamplePeriods(controllerPath)
periods = [];
hasContinuous = false;
if isempty(controllerPath)
    return;
end
blocks = find_system(controllerPath, 'SearchDepth', 8, ...
    'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block');
for index = 1:numel(blocks)
    try
        value = get_param(blocks{index}, 'CompiledSampleTime');
        blockPeriods = numericPeriods(value);
        periods = [periods blockPeriods]; %#ok<AGROW>
    catch
        % Not every virtual or linked block exposes a compiled sample time.
    end
end
if isempty(periods)
    return;
end
hasContinuous = any(periods == 0);
periods = unique(periods(isfinite(periods) & periods > 0));
end

function periods = numericPeriods(value)
periods = [];
if isnumeric(value)
    if isempty(value)
        return;
    end
    if isvector(value) && numel(value) == 2
        periods = value(1);
    elseif size(value, 2) >= 1
        periods = value(:, 1).';
    end
elseif iscell(value)
    for index = 1:numel(value)
        periods = [periods numericPeriods(value{index})]; %#ok<AGROW>
    end
end
end

function entries = compiledInterfaceTypes(controllerPath)
entries = struct('path', {}, 'dataType', {});
if isempty(controllerPath)
    return;
end
ports = [find_system(controllerPath, 'SearchDepth', 1, 'BlockType', 'Inport'); ...
    find_system(controllerPath, 'SearchDepth', 1, 'BlockType', 'Outport')];
for index = 1:numel(ports)
    try
        value = get_param(ports{index}, 'CompiledPortDataTypes');
        types = flattenDataTypes(value);
        for typeIndex = 1:numel(types)
            entries(end+1) = struct( ...
                'path', ports{index}, 'dataType', types{typeIndex}); %#ok<AGROW>
        end
    catch
        % Leave unavailable compiled properties out of the evidence.
    end
end
if ~isempty(entries)
    keys = strcat({entries.path}, '|', {entries.dataType});
    [~, keep] = unique(keys, 'stable');
    entries = entries(keep);
end
end

function types = flattenDataTypes(value)
types = {};
if ischar(value)
    types = {value};
elseif isstring(value)
    types = cellstr(value(:));
elseif iscell(value)
    for index = 1:numel(value)
        types = [types flattenDataTypes(value{index})]; %#ok<AGROW>
    end
elseif isstruct(value)
    names = fieldnames(value);
    for index = 1:numel(names)
        types = [types flattenDataTypes(value.(names{index}))]; %#ok<AGROW>
    end
end
types = types(~cellfun(@isempty, types));
end

function [status, evidence] = assessCompiledPeriods( ...
        periods, hasContinuous, baseStepText, profile)
if hasContinuous
    status = 'FAIL';
    evidence = 'A continuous compiled sample time was found inside the controller.';
    return;
end
if isempty(periods)
    status = productionStatus(false, profile);
    evidence = 'No positive compiled controller sample period was available.';
    return;
end
baseStep = str2double(baseStepText);
if ~isfinite(baseStep) || baseStep <= 0
    status = productionStatus(false, profile);
    evidence = sprintf('Periods=%s, FixedStep=%s', mat2str(periods), baseStepText);
    return;
end
ratios = periods / baseStep;
valid = arrayfun(@isIntegerRatio, ratios);
if all(valid)
    status = 'PASS';
else
    status = 'FAIL';
end
evidence = sprintf('Periods=%s, Ratios=%s', mat2str(periods), mat2str(ratios));
end

function features = inspectFeatures(modelName)
allBlocks = find_system(modelName, 'SearchDepth', 8, ...
    'LookUnderMasks', 'none', 'FollowLinks', 'off');
allNames = lower(strjoin(allBlocks, ' '));
features = struct( ...
    'hasClarke', contains(allNames, 'clark'), ...
    'hasPark', contains(allNames, 'park'), ...
    'hasSvpwm', contains(allNames, 'svpwm'), ...
    'hasCurrentLoop', any(contains(allNames, {'currloop', 'curr_loop', 'currentloop'})), ...
    'hasSpeedLoop', any(contains(allNames, {'speedloop', 'speed_loop'})), ...
    'hasStateflow', hasStateflow(modelName), ...
    'hasObserver', any(contains(allNames, ...
    {'observer', 'luenberger', 'smo', 'ekf', 'flux'})));
end

function value = hasStateflow(modelName)
value = false;
try
    charts = find_system(modelName, 'SearchDepth', 8, ...
        'LookUnderMasks', 'none', 'FollowLinks', 'off', 'SFBlockType', 'Chart');
    value = ~isempty(charts);
catch
    % Stateflow may be unavailable or the release may not support SFBlockType.
end
end

function value = firstAvailableParam(block, names)
value = '';
for index = 1:numel(names)
    value = safeGetParam(block, names{index});
    if ~isempty(value)
        return;
    end
end
end

function value = safeGetParam(object, parameter)
try
    value = get_param(object, parameter);
    if isnumeric(value) || islogical(value)
        value = mat2str(value);
    elseif isstring(value)
        value = char(value);
    elseif ~ischar(value)
        value = '';
    end
catch
    value = '';
end
end

function check = makeCheck(id, status, message, evidence)
check = struct('id', id, 'status', status, ...
    'message', message, 'evidence', evidence);
end

function status = passFail(condition)
if condition
    status = 'PASS';
else
    status = 'FAIL';
end
end

function status = productionStatus(condition, profile)
if condition
    status = 'PASS';
elseif strcmp(profile, 'deployment')
    status = 'FAIL';
else
    status = 'WARN';
end
end

function value = isExplicitPositiveStep(text)
value = ~isempty(text) && ~any(strcmpi(strtrim(text), {'auto', '-1'}));
numeric = str2double(text);
if isfinite(numeric)
    value = value && numeric > 0;
end
end

function value = isIntegerRatio(ratio)
tolerance = 100 * eps(max(1, abs(ratio)));
value = isfinite(ratio) && ratio >= 1 - tolerance && ...
    abs(ratio - round(ratio)) <= tolerance;
end

function readiness = readinessFromSummary(summary)
if summary.fail > 0
    readiness = 'NOT_READY';
elseif summary.warn > 0
    readiness = 'REVIEW';
else
    readiness = 'READY';
end
end

function evidence = joinEvidence(names)
if isempty(names)
    evidence = 'none found';
elseif numel(names) <= 5
    evidence = strjoin(names, '; ');
else
    evidence = sprintf('%s; ... (%d total)', ...
        strjoin(names(1:5), '; '), numel(names));
end
end

function evidence = joinDataTypeEvidence(entries)
parts = cell(1, numel(entries));
for index = 1:numel(entries)
    parts{index} = sprintf('%s=%s', entries(index).path, entries(index).dataType);
end
evidence = joinEvidence(parts);
end

function value = fallbackText(value, fallback)
if isempty(value)
    value = fallback;
end
end

function text = compactText(text)
text = regexprep(text, '\s+', ' ');
if numel(text) > 500
    text = [text(1:497) '...'];
end
end

function outputFile = writeJsonReport(report, requestedPath)
outputFile = char(requestedPath);
if ~isAbsolutePath(outputFile)
    outputFile = fullfile(pwd, outputFile);
end
folder = fileparts(outputFile);
if ~isempty(folder) && ~isfolder(folder)
    [made, message] = mkdir(folder);
    if ~made
        error('audit_embedded_foc_model:OutputFolder', ...
            'Could not create output folder "%s": %s', folder, message);
    end
end
payload = jsonencode(report, 'PrettyPrint', true);
[fileId, message] = fopen(outputFile, 'w', 'n', 'UTF-8');
if fileId == -1
    error('audit_embedded_foc_model:OutputFile', ...
        'Could not open output file "%s": %s', outputFile, message);
end
fileCleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '%s\n', payload);
delete(fileCleanup);
end

function value = isAbsolutePath(pathText)
value = ~isempty(regexp(pathText, '^[A-Za-z]:[\\/]|^[/\\]{2}|^/', 'once'));
end

function printReport(report)
fprintf('\nEmbedded FOC Simulink Codegen Audit\n');
fprintf('Model: %s\n', report.model);
fprintf('Profile: %s\n', report.profile);
if ~isempty(report.controller.path)
    fprintf('Controller: %s\n', report.controller.path);
end
for index = 1:numel(report.checks)
    check = report.checks(index);
    fprintf('[%s] %s - %s\n', check.status, check.id, check.message);
    if ~isempty(check.evidence)
        fprintf('       %s\n', check.evidence);
    end
end
fprintf('Summary: %d PASS, %d WARN, %d FAIL (%s)\n\n', ...
    report.summary.pass, report.summary.warn, report.summary.fail, ...
    report.readiness);
end
