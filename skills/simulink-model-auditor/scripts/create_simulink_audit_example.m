function modelFile = create_simulink_audit_example(outputFolder, varargin)
%CREATE_SIMULINK_AUDIT_EXAMPLE Create a disposable audit demonstration model.
%
% file = create_simulink_audit_example("demo", "Variant", "valid")
% file = create_simulink_audit_example("demo", "Variant", "unsafe")
%
% This deterministic generator exists for auditor demonstrations and unit
% tests. The generated model is not a controller design or production
% template. Agent-driven edits to user models must still use official
% model_edit routing.

parser = inputParser;
parser.FunctionName = mfilename;
addRequired(parser, 'outputFolder', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser, 'ModelName', 'simulink_audit_example', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser, 'BoundaryName', 'Controller', ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser, 'Variant', 'valid', ...
    @(x) any(strcmpi(string(x), ["valid", "unsafe"])));
addParameter(parser, 'Overwrite', false, ...
    @(x) islogical(x) && isscalar(x));
parse(parser, outputFolder, varargin{:});
opts = parser.Results;

outputFolder = char(outputFolder);
modelName = char(opts.ModelName);
boundaryName = char(opts.BoundaryName);
variant = lower(char(opts.Variant));
if ~isvarname(modelName)
    error('create_simulink_audit_example:InvalidModelName', ...
        'ModelName must be a valid MATLAB identifier.');
end
if ~isvarname(boundaryName)
    error('create_simulink_audit_example:InvalidBoundaryName', ...
        'BoundaryName must be code-generation-safe.');
end
if ~isfolder(outputFolder)
    [made, message] = mkdir(outputFolder);
    if ~made
        error('create_simulink_audit_example:OutputFolder', ...
            'Could not create output folder "%s": %s', outputFolder, message);
    end
end

modelFile = fullfile(outputFolder, [modelName '.slx']);
if isfile(modelFile) && ~opts.Overwrite
    error('create_simulink_audit_example:FileExists', ...
        'Model file already exists: %s', modelFile);
end
if bdIsLoaded(modelName)
    error('create_simulink_audit_example:ModelLoaded', ...
        'A model named "%s" is already loaded.', modelName);
end

new_system(modelName);
modelCleanup = onCleanup(@() closeGeneratedModel(modelName));
set_param(modelName, ...
    'SolverType', 'Fixed-step', ...
    'Solver', 'FixedStepDiscrete', ...
    'FixedStep', '0.001');

source = [modelName '/Input'];
boundary = [modelName '/' boundaryName];
sink = [modelName '/Output'];
add_block('simulink/Sources/Constant', source, ...
    'Value', 'single(0)', 'OutDataTypeStr', 'single', ...
    'SampleTime', '0.001', 'Position', [30 40 90 70]);
add_block('simulink/Ports & Subsystems/Subsystem', boundary, ...
    'TreatAsAtomicUnit', 'on', 'Position', [140 25 280 85]);
add_block('simulink/Sinks/Terminator', sink, ...
    'Position', [340 45 360 65]);

Simulink.SubSystem.deleteContents(boundary);
inport = [boundary '/Input'];
gain = [boundary '/Gain'];
outport = [boundary '/Output'];
add_block('simulink/Sources/In1', inport, ...
    'OutDataTypeStr', 'single', 'Position', [25 40 55 54]);
add_block('simulink/Math Operations/Gain', gain, ...
    'Gain', 'single(1)', 'Position', [95 30 145 65]);
add_block('simulink/Sinks/Out1', outport, ...
    'Position', [190 40 220 54]);
add_line(boundary, 'Input/1', 'Gain/1');
add_line(boundary, 'Gain/1', 'Output/1');
add_line(modelName, 'Input/1', [boundaryName '/1']);
add_line(modelName, [boundaryName '/1'], 'Output/1');

if strcmpi(variant, 'unsafe') %#ok<STLOW>
    set_param(modelName, 'SolverType', 'Variable-step', 'Solver', 'ode45');
    add_block('simulink/Sinks/Scope', [boundary '/DebugScope'], ...
        'Position', [95 100 125 130]);
    add_block('simulink/Ports & Subsystems/Subsystem', ...
        [boundary '/MotorPlant'], 'Position', [170 100 240 135]);
end

save_system(modelName, modelFile);
delete(modelCleanup);
end

function closeGeneratedModel(modelName)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end
