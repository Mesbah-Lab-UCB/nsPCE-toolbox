
%% Clear the workspace
clear


%% Setup the DFBA model

INFO.nmodel = 1; % Number of models

% LOAD MODELS. These should be .mat files generated by the COBRA toolbox. 
% When generating these files using the COBRA toolbox, a big number is used
% as infinity. This number should be fed to the DB vector (Default bound).
load iJR904.mat 
model{1} = iJR904; 
DB(1) = 2000;
INFO.DB = DB;

% exID ARRAY
% You can either search the reaction names by name or provide them directly
% in the exID array.
% RxnNames = {'EX_glc(e)', 'EX_ac(e)', 'biomass'};
% for i = 1:length(RxnNames)
%    [a,exID(i)] = ismember(RxnNames(i),model.rxns);
% end
%
% Lower bounds and upper bounds for these reactions should be provided in
% the RHS code. 
%
% This codes solves the LPs in standard form. Bounds on exchange fluxes in 
% the exID array can be modified directly on the first 2*n rows where n is 
% the number of exchange fluxes. Order will be lower bound, upper bound, 
% lower bound, upper bound in the same order as exID. 
%
% NOTE: All bounds on fluxes in the exID arrays are relaxed to -Inf and 
% + Inf. These bounds need to be updated if needed in the RHS file.
exID{1}=[344, 429, 392, 329];
INFO.exID = exID;

% COST VECTORS
% Usually the first cost vector will be biomass maximization, but it can
% be any other objective. The CPLEX objects will minimize by default. 
% Report only nonzero elements. 
% The structure should be:
% C{model} = struct
% Element C{k}(i) of C, is the cost structure i for model k. 
% C{k}(i).sense = +1 for minimize, or -1 for maximize.
% C{k}(i).rxns = array containing the reactions in this objective. 
% C{k}(i).wts = array containing coefficients for reactions reported in 
% rxns. Both arrays should have the same length. 
% Example, if:
% C{k}(i).rxns = [144, 832, 931];
% C{k}(i).wts = [3, 1, -1];
% Then the cost vector for this LP will be:
% Cost{k}(i) = 3*v_144 + v_832 - v_931 (fluxes for model k). 
% This cost vector will be either maximized or minimized depending on the
% value of C{k}(i).sense.
%
% In SBML files, usually production fluxes are positive and uptake fluxes
% are negative. Keep in mind that maximizing a negative flux implies 
% minimizing its absolute value.
% Different models can have different number of objectives. 
minim = 1;
maxim = -1;
% Maximize growth
C{1}(1).sense = maxim;
C{1}(1).rxns = [150];
C{1}(1).wts = [1];
% Maximize ethanol
C{1}(2).sense = maxim;
C{1}(2).rxns = [329];
C{1}(2).wts = [1];
% Maximize glucose
C{1}(3).sense = maxim;
C{1}(3).rxns = [344];
C{1}(3).wts = [1];
% Maximize xylose
C{1}(4).sense = maxim;
C{1}(4).rxns = [429];
C{1}(4).wts = [1];
% Store in INFO structure
INFO.C = C;

% INITIAL CONDITIONS
% Y1 = Volume (L)
% Y2 = Biomass EColi (gDW/L)
% Y3 = Glucose (g/L)
% Y4 = Xylose (g/L)
% Y5 = O2 (mmol/L)
% Y6 = Ethanol (g/L)
% Y7 = Penalty
Y0 = [1 0.03 15.5 8 0.24 0 0]';

% TIME OF SIMULATION
tspan = [0,10];

% CPLEX Objects construction parameters
INFO.LPsolver = 0; % CPLEX = 0, Gurobi = 1.
                   % CPLEX works equally fine with both methods.
                   % Gurobi seems to work better with Method = 1, and 
                   % Mosek with Method = 0.
INFO.tol = 1E-9; % Feasibility, optimality and convergence tolerance for Cplex (tol>=1E-9). 
                 % It is recommended it is at least 2 orders of magnitude
                 % tighter than the integrator tolerance. 
                 % If problems with infeasibility messages, tighten this
                 % tolerance.
INFO.tolPh1 = INFO.tol; % Tolerance to determine if a solution to phaseI equals zero.
                   % It is recommended to be the same as INFO.tol. 
INFO.tolevt = 2*INFO.tol; % Tolerance for event detection. Has to be greater 
                   % than INFO.tol.

% INTEGRATION TOLERANCES
% You can modify the integration tolerances here.
% If some of the flows become negative after running the simulation once
% you can add the 'Nonnegative' option.
NN = 1:length(Y0);
options = odeset('AbsTol',1E-6,'RelTol',1E-6,'Nonnegative',NN,'Events',@evts);

% PARAMETER VALUES
% INFO: You can use the INFO struct to pass parameters. Don't use any of 
% the names already declared or: INFO.t (carries time information), 
% INFO.ncost, INFO.lexID, INFO.LlexID, INFO.lbct, INFO.ubct, INFO.sense,
% INFO.b, INFO.pair. 
vgmax = 10.5; % maximum uptake rate of glucose
Kg = 0.0027; % saturation constant for glucose
vzmax = 6; % maximum uptake rate of xylose
Kz = 0.0165; % saturation constant for xylose
Kig = 0.005; % inhibition constant for glucose
vo = 15*0.24/(0.024+0.24); % uptake rate for oxygen (do not use MM because we assume extracelluar oxygen conc controlled)
INFO.param = [vgmax ; Kg ; vzmax ; Kz ; Kig ; vo]; % passed to the RHS function

% % SAVE VARIABLES FOR LATER USE
% save('EColi_dfba_parameters.mat','INFO','model','Y0','options','tspan')


%% Integrate DFBA model over time

% Setup the model 
[model,INFO] = ModelSetupM(model,Y0,INFO);

% Get Lexicographic solution to LP
if INFO.LPsolver == 0
    [INFO] = LexicographicOpt(model,INFO);
elseif INFO.LPsolver == 1
    [INFO] = LexicographicOptG(model,INFO);
else
    display('Solver not currently supported.');
end

% Execute integration
tic
tint = 0;
TF = [];
YF = [];
while tint<tspan(2)
    % Look at MATLAB documentation if you want to change solver.
    % ode15s is more or less accurate for stiff problems.
    [T,Y] = ode15s(@DRHS,tspan,Y0,options,INFO);
    TF = [TF;T];
    YF = [YF;Y];
    tint = T(end);
    tspan = [tint,tspan(2)];
    Y0 = Y(end,:);
    if tint == tspan(2)
        break;
    end
    
    %Determine model with basis change
    value = evts(tint,Y0,INFO);
    [jjj,j] = min(value);
    ct = 0;
    k = 0;
    while j>ct
        k = k + 1;
        ct = ct + size(model{k}.A,1);
    end
    INFO.flagbasis = k;
    fprintf('Basis change at time %d. \n',tint);
    
    % Update b vector
    [INFO] = bupdate(tint,Y0,INFO);
    
    % Perform lexicographic optimization
    if INFO.LPsolver == 0
        [INFO] = LexicographicOpt(model,INFO);
    elseif INFO.LPsolver == 1
        [INFO] = LexicographicOptG(model,INFO);
    else
        display('Solver not currently supported.');
    end
end
fprintf('Integration took %g seconds\n', toc)
T = TF;
Y = YF;

% Plot results
plot(T,Y(:,2),'-b',T,Y(:,3),'--r',T,Y(:,4),'-.k','linewidth',1.5)
set(gcf,'color','w')
set(gca,'FontSize',16)
xlabel('time (hours)')
ylabel('concentration (g/L)')
legend('biomass', 'glucose', 'xylose')
