function report = audit_simulink_model(model, varargin)
%AUDIT_SIMULINK_MODEL Read-only audit for any Simulink model or subsystem.
%
% report = audit_simulink_model("system.slx")
% report = audit_simulink_model("system.slx", ...
%     "Scope", "system/Controller", ...
%     "Profile", "deployment", ...
%     "OutputFile", "simulink-audit.json")
%
% Profiles:
%   simulation - production-only omissions warn.
%   deployment - production omissions and unsafe compiled evidence fail.
%
% This function may compile the model but never saves it. Use official
% model_check and Model Advisor separately for authoritative structural and
% standards evidence.

parser = inputParser;
parser.FunctionName = mfilename;
addRequired(parser, 'model', @(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser, 'Scope', '', ...
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

scope = char(opts.Scope);
if isempty(scope)
    scope = modelName;
end
validateScope(modelName, scope);

settings = readSettings(modelName);
inventory = inspectInventory(scope);
modelReferences = inspectModelReferences(scope, modelDir);
libraryLinks = inspectLibraryLinks(scope);
unconnectedPorts = inspectUnconnectedPorts(scope);
desktopBlocks = inspectDesktopBlocks(scope);

checks = struct('id', {}, 'status', {}, 'message', {}, 'evidence', {});
checks(end+1) = makeCheck('scope.resolved', 'PASS', ...
    'The requested model scope resolved.', scope);

fixedStep = strcmpi(settings.SolverType, 'Fixed-step');
checks(end+1) = makeCheck('solver.fixed_step', ...
    productionStatus(fixedStep, profile), ...
    'Deployment models should use fixed-step execution.', ...
    sprintf('SolverType=%s, Solver=%s', settings.SolverType, settings.Solver));

explicitStep = isExplicitPositiveStep(settings.FixedStep);
checks(end+1) = makeCheck('solver.explicit_base_step', ...
    productionStatus(explicitStep, profile), ...
    'Deployment base step should be explicit.', ...
    sprintf('FixedStep=%s', settings.FixedStep));

checks(end+1) = assessDiagnostics(settings);

checks(end+1) = makeCheck('codegen.ert', ...
    productionStatus(strcmpi(settings.SystemTargetFile, 'ert.tlc'), profile), ...
    'ERT is expected for a production embedded target.', ...
    sprintf('SystemTargetFile=%s', settings.SystemTargetFile));

checks(end+1) = makeCheck('codegen.c99', ...
    productionStatus(contains(lower(settings.TargetLangStandard), 'c99'), profile), ...
    'Select the production C language standard deliberately.', ...
    sprintf('TargetLangStandard=%s', settings.TargetLangStandard));

checks(end+1) = makeCheck('codegen.report', ...
    productionStatus(strcmpi(settings.GenerateReport, 'on'), profile), ...
    'Generate a code report for interface and traceability review.', ...
    sprintf('GenerateReport=%s', settings.GenerateReport));

checks(end+1) = makeCheck('numeric.nonfinite', ...
    productionStatus(strcmpi(settings.SupportNonFinite, 'off'), profile), ...
    'Select non-finite support deliberately for production.', ...
    sprintf('SupportNonFinite=%s', settings.SupportNonFinite));

[dictionary, dictionaryCheck] = inspectDictionary(modelName, modelDir, profile);
checks(end+1) = dictionaryCheck;
checks(end+1) = assessModelReferences(modelReferences, profile);
checks(end+1) = assessLibraryLinks(libraryLinks, profile);
checks(end+1) = assessUnconnectedPorts(unconnectedPorts, profile);

if isempty(desktopBlocks)
    desktopStatus = 'PASS';
else
    desktopStatus = 'WARN';
end
checks(end+1) = makeCheck('architecture.desktop_blocks', desktopStatus, ...
    'Desktop-only blocks need an explicit simulation/code-generation boundary.', ...
    joinEvidence(desktopBlocks));

[compile, compileChecks] = inspectCompiledModel( ...
    modelName, scope, settings.FixedStep, opts.Compile, profile);
checks(end+1:end+numel(compileChecks)) = compileChecks;

statuses = {checks.status};
summary = struct( ...
    'pass', sum(strcmp(statuses, 'PASS')), ...
    'warn', sum(strcmp(statuses, 'WARN')), ...
    'fail', sum(strcmp(statuses, 'FAIL')));

report = struct( ...
    'schemaVersion', 1, ...
    'tool', mfilename, ...
    'profile', profile, ...
    'readiness', readinessFromSummary(summary), ...
    'matlabRelease', version('-release'), ...
    'matlabVersion', version, ...
    'model', modelName, ...
    'file', modelFile, ...
    'scope', scope, ...
    'modelChanged', false, ...
    'settings', settings, ...
    'dictionary', dictionary, ...
    'inventory', inventory, ...
    'modelReferences', modelReferences, ...
    'libraryLinks', libraryLinks, ...
    'unconnectedPorts', unconnectedPorts, ...
    'desktopBlocks', {desktopBlocks}, ...
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
    error('audit_simulink_model:ModelNotFound', ...
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

function validateScope(modelName, scope)
if strcmp(scope, modelName)
    return;
end
prefix = [modelName '/'];
isInModel = strncmp(scope, prefix, numel(prefix));
handle = getSimulinkBlockHandle(scope);
if ~isInModel || handle == -1
    error('audit_simulink_model:InvalidScope', ...
        'Scope "%s" does not resolve inside model "%s".', scope, modelName);
end
end

function settings = readSettings(modelName)
names = {'SolverType', 'Solver', 'FixedStep', 'SystemTargetFile', ...
    'TargetLangStandard', 'ProdHWDeviceType', 'GenerateReport', ...
    'SupportNonFinite', 'DataDictionary', 'AlgebraicLoopMsg', ...
    'InfNanMode', 'UnconnectedInputMsg', 'UnconnectedOutputMsg'};
settings = struct();
for index = 1:numel(names)
    settings.(names{index}) = safeGetParam(modelName, names{index});
end
end

function check = assessDiagnostics(settings)
names = {'AlgebraicLoopMsg', 'UnconnectedInputMsg', 'UnconnectedOutputMsg'};
disabled = {};
unknown = {};
for index = 1:numel(names)
    value = settings.(names{index});
    if strcmpi(value, 'none')
        disabled{end+1} = names{index}; %#ok<AGROW>
    elseif isempty(value)
        unknown{end+1} = names{index}; %#ok<AGROW>
    end
end
if ~isempty(disabled)
    status = 'WARN';
    message = 'Some structural diagnostics are disabled.';
    evidence = strjoin(disabled, ', ');
elseif ~isempty(unknown)
    status = 'WARN';
    message = 'Some diagnostic settings could not be read.';
    evidence = strjoin(unknown, ', ');
else
    status = 'PASS';
    message = 'Key structural diagnostics are enabled.';
    evidence = sprintf('AlgebraicLoop=%s, UnconnectedInput=%s, UnconnectedOutput=%s', ...
        settings.AlgebraicLoopMsg, settings.UnconnectedInputMsg, ...
        settings.UnconnectedOutputMsg);
end
check = makeCheck('diagnostics.structural', status, message, evidence);
end

function inventory = inspectInventory(scope)
blocks = find_system(scope, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'Type', 'Block');
subsystems = find_system(scope, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'BlockType', 'SubSystem');
inventory = struct( ...
    'blockCount', numel(blocks), ...
    'subsystemCount', numel(subsystems));
end

function references = inspectModelReferences(scope, modelDir)
blocks = find_system(scope, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'BlockType', 'ModelReference');
template = struct('path', '', 'modelName', '', 'resolvedPath', '', 'resolved', false);
references = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    referenceName = firstAvailableParam(blocks{index}, {'ModelName', 'ModelFile'});
    [resolvedPath, resolved] = resolveReferencedModel(referenceName, modelDir);
    references(index) = struct( ...
        'path', blocks{index}, ...
        'modelName', referenceName, ...
        'resolvedPath', resolvedPath, ...
        'resolved', resolved);
end
end

function [resolvedPath, resolved] = resolveReferencedModel(referenceName, modelDir)
resolvedPath = '';
resolved = false;
if isempty(referenceName)
    return;
end
candidates = {referenceName};
[~, ~, extension] = fileparts(referenceName);
if isempty(extension)
    candidates = {[referenceName '.slx'], [referenceName '.mdl'], [referenceName '.slxp']};
end
for index = 1:numel(candidates)
    candidate = candidates{index};
    localPath = fullfile(modelDir, candidate);
    if isfile(localPath)
        [~, attributes] = fileattrib(localPath);
        resolvedPath = attributes.Name;
        resolved = true;
        return;
    end
    located = which(candidate);
    if ~isempty(located)
        resolvedPath = located;
        resolved = true;
        return;
    end
end
end

function check = assessModelReferences(references, profile)
if isempty(references)
    check = makeCheck('dependencies.model_references', 'PASS', ...
        'No referenced models were found in the audit scope.', 'none found');
    return;
end
broken = {references(~[references.resolved]).path};
if isempty(broken)
    status = 'PASS';
    message = 'All referenced models resolve.';
    evidence = sprintf('%d reference(s)', numel(references));
else
    status = productionStatus(false, profile);
    message = 'One or more referenced models do not resolve.';
    evidence = joinEvidence(broken);
end
check = makeCheck('dependencies.model_references', status, message, evidence);
end

function links = inspectLibraryLinks(scope)
blocks = find_system(scope, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'Type', 'Block');
template = struct('path', '', 'status', '', 'referenceBlock', '');
links = repmat(template, 0, 1);
for index = 1:numel(blocks)
    status = safeGetParam(blocks{index}, 'LinkStatus');
    reference = safeGetParam(blocks{index}, 'ReferenceBlock');
    if ~isempty(status) && ~strcmpi(status, 'none')
        links(end+1, 1) = struct( ...
            'path', blocks{index}, 'status', status, ...
            'referenceBlock', reference); %#ok<AGROW>
    end
end
end

function check = assessLibraryLinks(links, profile)
if isempty(links)
    check = makeCheck('dependencies.library_links', 'PASS', ...
        'No library links were found in the audit scope.', 'none found');
    return;
end
statuses = lower({links.status});
brokenMask = contains(statuses, 'unresolved') | contains(statuses, 'broken');
broken = {links(brokenMask).path};
if isempty(broken)
    status = 'PASS';
    message = 'All detected library links are resolved or intentionally inactive.';
    evidence = sprintf('%d link(s)', numel(links));
else
    status = productionStatus(false, profile);
    message = 'One or more library links are unresolved.';
    evidence = joinEvidence(broken);
end
check = makeCheck('dependencies.library_links', status, message, evidence);
end

function issues = inspectUnconnectedPorts(scope)
blocks = find_system(scope, 'SearchDepth', 8, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'Type', 'Block');
template = struct('path', '', 'direction', '', 'port', 0);
issues = repmat(template, 0, 1);
for index = 1:numel(blocks)
    try
        handles = get_param(blocks{index}, 'PortHandles');
    catch
        continue;
    end
    issues = appendUnconnected(issues, blocks{index}, handles, 'Inport', 'input');
    issues = appendUnconnected(issues, blocks{index}, handles, 'Outport', 'output');
    issues = appendUnconnected(issues, blocks{index}, handles, 'Enable', 'enable');
    issues = appendUnconnected(issues, blocks{index}, handles, 'Trigger', 'trigger');
    issues = appendUnconnected(issues, blocks{index}, handles, 'Reset', 'reset');
end
end

function issues = appendUnconnected(issues, block, handles, field, direction)
if ~isfield(handles, field)
    return;
end
ports = handles.(field);
for index = 1:numel(ports)
    if ports(index) ~= -1 && get_param(ports(index), 'Line') == -1
        issues(end+1, 1) = struct( ...
            'path', block, 'direction', direction, 'port', index); %#ok<AGROW>
    end
end
end

function check = assessUnconnectedPorts(issues, profile)
if isempty(issues)
    status = 'PASS';
    message = 'No unconnected ports were found by the local heuristic.';
    evidence = 'Run official model_check for authoritative connectivity evidence.';
else
    status = productionStatus(false, profile);
    message = 'Unconnected ports were found by the local heuristic.';
    evidence = joinPortEvidence(issues);
end
check = makeCheck('structure.unconnected_ports', status, message, evidence);
end

function blocks = inspectDesktopBlocks(scope)
types = {'Scope', 'Display', 'ToWorkspace', 'FromWorkspace', 'ToFile', ...
    'FromFile', 'SignalGenerator', 'SignalBuilder', 'XYScope'};
blocks = {};
for index = 1:numel(types)
    found = find_system(scope, 'SearchDepth', 8, ...
        'LookUnderMasks', 'none', 'FollowLinks', 'off', ...
        'BlockType', types{index});
    blocks = [blocks; found(:)]; %#ok<AGROW>
end
blocks = unique(blocks, 'stable');
end

function [dictionary, check] = inspectDictionary(modelName, modelDir, profile)
dictionary = struct('name', safeGetParam(modelName, 'DataDictionary'), ...
    'resolvedPath', '', 'exactCase', false);
if isempty(dictionary.name)
    check = makeCheck('data.dictionary', productionStatus(false, profile), ...
        'No model data dictionary is attached.', ...
        'A script/model workspace may be valid; verify data ownership.');
    return;
end

if isAbsolutePath(dictionary.name)
    candidate = dictionary.name;
else
    candidate = fullfile(modelDir, dictionary.name);
end
if ~isfile(candidate)
    located = which(dictionary.name);
    if ~isempty(located)
        candidate = located;
    end
end
if ~isfile(candidate)
    check = makeCheck('data.dictionary', 'FAIL', ...
        'The attached data dictionary does not resolve.', dictionary.name);
    return;
end

[~, attributes] = fileattrib(candidate);
dictionary.resolvedPath = attributes.Name;
[folder, base, extension] = fileparts(dictionary.resolvedPath);
entries = dir(folder);
dictionary.exactCase = any(strcmp({entries.name}, [base extension]));
if dictionary.exactCase
    status = 'PASS';
    message = 'The data dictionary resolves with exact filename case.';
else
    status = productionStatus(false, profile);
    message = 'Dictionary filename case differs from the file on disk.';
end
check = makeCheck('data.dictionary', status, message, dictionary.resolvedPath);
end

function [compile, checks] = inspectCompiledModel( ...
        modelName, scope, baseStepText, shouldCompile, profile)
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
    [periods, hasContinuous] = compiledSamplePeriods(scope);
    interfaceTypes = compiledInterfaceTypes(scope);
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
        % Model cleanup closes models opened by this function.
    end
end

if ~compile.succeeded
    checks(end+1) = makeCheck('model.compiled_evidence', 'FAIL', ...
        'Compiled-property inspection failed.', compactText(compile.message));
    return;
end

checks(end+1) = makeCheck('model.compiled_evidence', 'PASS', ...
    'Compiled sample-time and data-type properties were inspected.', ...
    sprintf('Scope=%s', scope));

[rateStatus, rateEvidence] = assessCompiledPeriods( ...
    compile.samplePeriods, compile.hasContinuousRate, baseStepText, profile);
checks(end+1) = makeCheck('timing.compiled_rates', rateStatus, ...
    'Deployment rates must be discrete integer multiples of the base step.', ...
    rateEvidence);

if isempty(compile.interfaceDataTypes)
    typeStatus = 'WARN';
    typeEvidence = 'No compiled interface types were available for this scope.';
elseif isempty(compile.unexpectedDouble)
    typeStatus = 'PASS';
    typeEvidence = joinDataTypeEvidence(compile.interfaceDataTypes);
else
    typeStatus = productionStatus(false, profile);
    typeEvidence = joinEvidence(unique(compile.unexpectedDouble, 'stable'));
end
checks(end+1) = makeCheck('numeric.compiled_interface_types', typeStatus, ...
    'Deployment interfaces should use deliberate target data types.', typeEvidence);
end

function [periods, hasContinuous] = compiledSamplePeriods(scope)
periods = [];
hasContinuous = false;
blocks = find_system(scope, 'SearchDepth', 8, ...
    'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block');
for index = 1:numel(blocks)
    try
        value = get_param(blocks{index}, 'CompiledSampleTime');
        periods = [periods numericPeriods(value)]; %#ok<AGROW>
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

function entries = compiledInterfaceTypes(scope)
entries = struct('path', {}, 'dataType', {});
ports = [find_system(scope, 'SearchDepth', 1, 'BlockType', 'Inport'); ...
    find_system(scope, 'SearchDepth', 1, 'BlockType', 'Outport')];
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
    status = productionStatus(false, profile);
    evidence = 'A continuous compiled sample time was found in the audit scope.';
    return;
end
if isempty(periods)
    status = 'WARN';
    evidence = 'No positive compiled sample period was available.';
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

function evidence = joinPortEvidence(issues)
parts = cell(1, min(numel(issues), 5));
for index = 1:numel(parts)
    parts{index} = sprintf('%s (%s %d)', ...
        issues(index).path, issues(index).direction, issues(index).port);
end
evidence = strjoin(parts, '; ');
if numel(issues) > 5
    evidence = sprintf('%s; ... (%d total)', evidence, numel(issues));
end
end

function evidence = joinDataTypeEvidence(entries)
parts = cell(1, numel(entries));
for index = 1:numel(entries)
    parts{index} = sprintf('%s=%s', entries(index).path, entries(index).dataType);
end
evidence = joinEvidence(parts);
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
        error('audit_simulink_model:OutputFolder', ...
            'Could not create output folder "%s": %s', folder, message);
    end
end
payload = jsonencode(report, 'PrettyPrint', true);
[fileId, message] = fopen(outputFile, 'w', 'n', 'UTF-8');
if fileId == -1
    error('audit_simulink_model:OutputFile', ...
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
fprintf('\nSimulink Model Audit\n');
fprintf('Model: %s\n', report.model);
fprintf('Scope: %s\n', report.scope);
fprintf('Profile: %s\n', report.profile);
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
