classdef simulinkAuditUtilitiesTest < matlab.unittest.TestCase
    %SIMULINKAUDITUTILITIESTEST Regression tests for both Skill packages.

    methods (TestClassSetup)
        function addRepositoryScripts(testCase)
            repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repositoryRoot, 'skills', ...
                'simulink-model-auditor', 'scripts')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(repositoryRoot, 'skills', ...
                'embedded-foc-simulink-codegen', 'scripts')));
        end
    end

    methods (Test)
        function validSimulationFixtureHasNoFailures(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            report = audit_embedded_foc_model(fixture.file, ...
                'Profile', 'simulation', 'Verbose', false);

            testCase.verifyEqual(report.summary.fail, 0);
            testCase.verifyEqual(report.profile, 'simulation');
            testCase.verifyTrue(report.compile.succeeded);
        end

        function badFixtureFindsStructuralFailures(testCase)
            fixture = createAuditFixture('bad');
            testCase.addTeardown(@() removeFixture(fixture));

            report = audit_embedded_foc_model(fixture.file, ...
                'Profile', 'simulation', 'Verbose', false);

            verifyCheckStatus(testCase, report, 'solver.fixed_step', 'FAIL');
            verifyCheckStatus(testCase, report, 'architecture.desktop_blocks', 'FAIL');
            verifyCheckStatus(testCase, report, 'architecture.plant_separation', 'FAIL');
        end

        function deploymentProfileTightensProductionSettings(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            simulation = audit_embedded_foc_model(fixture.file, ...
                'Profile', 'simulation', 'Verbose', false);
            deployment = audit_embedded_foc_model(fixture.file, ...
                'Profile', 'deployment', 'Verbose', false);

            testCase.verifyGreaterThan(deployment.summary.fail, simulation.summary.fail);
            verifyCheckStatus(testCase, deployment, 'codegen.ert', 'FAIL');
            verifyCheckStatus(testCase, deployment, ...
                'numeric.compiled_interface_types', 'PASS');
        end

        function invalidControllerPathErrorsCleanly(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            invalidPath = [fixture.model '/MissingController'];
            testCase.verifyError(@() audit_embedded_foc_model(fixture.file, ...
                'ControllerPath', invalidPath, 'Verbose', false), ...
                'audit_embedded_foc_model:InvalidControllerPath');
        end

        function auditDoesNotAlterSavedModel(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));
            before = readBytes(fixture.file);

            audit_embedded_foc_model(fixture.file, ...
                'Profile', 'simulation', 'Verbose', false);
            after = readBytes(fixture.file);

            testCase.verifyEqual(after, before);
        end

        function jsonReportIsWrittenAndParseable(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));
            outputFile = fullfile(fixture.folder, 'artifacts', 'audit.json');

            report = audit_embedded_foc_model(fixture.file, ...
                'Profile', 'simulation', 'Verbose', false, ...
                'OutputFile', outputFile);
            decoded = jsondecode(fileread(outputFile));

            testCase.verifyTrue(isfile(outputFile));
            testCase.verifyEqual(decoded.schemaVersion, 2);
            testCase.verifyEqual(decoded.model, fixture.model);
            testCase.verifyEqual(report.outputFile, outputFile);
        end

        function codegenRequiresExplicitAuthorization(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            testCase.verifyError(@() run_embedded_foc_codegen(fixture.file), ...
                'run_embedded_foc_codegen:BuildNotAuthorized');
        end

        function genericAuditorAcceptsArbitraryModel(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            report = audit_simulink_model(fixture.file, ...
                'Scope', [fixture.model '/FOC_Controller'], ...
                'Profile', 'simulation', 'Verbose', false);

            testCase.verifyEqual(report.summary.fail, 0);
            testCase.verifyEqual(report.modelChanged, false);
            testCase.verifyEqual(report.scope, ...
                [fixture.model '/FOC_Controller']);
        end

        function genericDeploymentProfileIsFailClosed(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            report = audit_simulink_model(fixture.file, ...
                'Scope', [fixture.model '/FOC_Controller'], ...
                'Profile', 'deployment', 'Verbose', false);

            verifyCheckStatus(testCase, report, 'codegen.ert', 'FAIL');
            verifyCheckStatus(testCase, report, ...
                'numeric.compiled_interface_types', 'PASS');
        end

        function genericAuditorFindsUnsafeFixture(testCase)
            fixture = createAuditFixture('bad');
            testCase.addTeardown(@() removeFixture(fixture));

            report = audit_simulink_model(fixture.file, ...
                'Scope', [fixture.model '/FOC_Controller'], ...
                'Profile', 'deployment', 'Verbose', false);

            verifyCheckStatus(testCase, report, 'solver.fixed_step', 'FAIL');
            verifyCheckStatus(testCase, report, ...
                'structure.unconnected_ports', 'FAIL');
        end

        function genericAuditorRejectsInvalidScope(testCase)
            fixture = createAuditFixture('valid');
            testCase.addTeardown(@() removeFixture(fixture));

            invalidScope = [fixture.model '/MissingScope'];
            testCase.verifyError(@() audit_simulink_model(fixture.file, ...
                'Scope', invalidScope, 'Verbose', false), ...
                'audit_simulink_model:InvalidScope');
        end

        function genericAuditorHasNoAnalyzerIssues(testCase)
            repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(repositoryRoot, 'skills', ...
                'simulink-model-auditor', 'scripts', 'audit_simulink_model.m');
            issues = checkcode(file, '-id');
            testCase.verifyEmpty(issues);
        end

        function focAuditorHasNoAnalyzerIssues(testCase)
            repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(repositoryRoot, 'skills', ...
                'simulink-model-auditor', 'scripts', ...
                'audit_embedded_foc_model.m');
            issues = checkcode(file, '-id');
            testCase.verifyEmpty(issues);
        end

        function buildGateHasNoAnalyzerIssues(testCase)
            repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(repositoryRoot, 'skills', ...
                'embedded-foc-simulink-codegen', 'scripts', ...
                'run_embedded_foc_codegen.m');
            issues = checkcode(file, '-id');
            testCase.verifyEmpty(issues);
        end

        function exampleGeneratorHasNoAnalyzerIssues(testCase)
            repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(repositoryRoot, 'skills', ...
                'simulink-model-auditor', 'scripts', ...
                'create_simulink_audit_example.m');
            issues = checkcode(file, '-id');
            testCase.verifyEmpty(issues);
        end
    end
end

function fixture = createAuditFixture(kind)
folder = tempname;
mkdir(folder);
[~, token] = fileparts(tempname);
modelName = matlab.lang.makeValidName(['focAudit_' token]);
if strcmp(kind, 'bad')
    variant = 'unsafe';
else
    variant = 'valid';
end
modelFile = create_simulink_audit_example(folder, ...
    'ModelName', modelName, ...
    'BoundaryName', 'FOC_Controller', ...
    'Variant', variant);
fixture = struct('folder', folder, 'model', modelName, 'file', modelFile);
end

function closeFixtureModel(modelName)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end

function removeFixture(fixture)
closeFixtureModel(fixture.model);
if isfolder(fixture.folder)
    rmdir(fixture.folder, 's');
end
end

function bytes = readBytes(file)
fileId = fopen(file, 'r');
assert(fileId ~= -1, 'Could not open fixture model.');
cleanup = onCleanup(@() fclose(fileId));
bytes = fread(fileId, inf, '*uint8');
delete(cleanup);
end

function verifyCheckStatus(testCase, report, id, expectedStatus)
index = find(strcmp({report.checks.id}, id), 1);
testCase.assertNotEmpty(index, sprintf('Missing audit check: %s', id));
testCase.verifyEqual(report.checks(index).status, expectedStatus);
end
