function [vp,elbo,elbo_sd,exitflag,output,optimState,stats] = vbmc(fun,x0,LB,UB,PLB,PUB,options,varargin)
%VBMC Posterior and model inference via Variational Bayesian Monte Carlo (v0.8)
%   VBMC computes a variational approximation of the full posterior and a 
%   lower bound on the normalization constant (marginal likelhood or model
%   evidence) for a provided unnormalized log posterior.
%
%   VP = VBMC(FUN,X0,LB,UB) initializes the variational posterior in the
%   proximity of X0 (ideally, a posterior mode) and iteratively computes
%   a variational approximation for a given target log posterior FUN.
%   FUN accepts input X and returns the value of the target (unnormalized) 
%   log posterior density at X. LB and UB define a set of strict lower and 
%   upper bounds coordinate vector, X, so that the posterior has support on 
%   LB < X < UB. LB and UB can be scalars or vectors. If scalars, the bound 
%   is replicated in each dimension. Use empty matrices for LB and UB if no 
%   bounds exist. Set LB(i) = -Inf and UB(i) = Inf if the i-th coordinate
%   is unbounded (while other coordinates may be bounded). Note that if LB 
%   and UB contain unbounded variables, the respective values of PLB and PUB
%   need to be specified (see below). VBMC returns a variational posterior
%   solution VP, which can then be manipulated via other functions in the
%   VBMC toolbox (see examples below).
%
%   VP = VBMC(FUN,X0,LB,UB,PLB,PUB) specifies a set of plausible lower and
%   upper bounds such that LB < PLB < PUB < UB. Both PLB and PUB
%   need to be finite. PLB and PUB represent a "plausible" range, which
%   should denote a region of high posterior probability mass. Among other 
%   things, the plausible box is used to draw initial samples and to set 
%   priors over hyperparameters of the algorithm. When in doubt, we found 
%   that setting PLB and PUB using the topmost ~68% percentile range of the 
%   prior (e.g, mean +/- 1 SD for a Gaussian prior) works well in many 
%   cases (but note that additional information might afford a better guess).
%  
%   VP = VBMC(FUN,X0,LB,UB,PLB,PUB,OPTIONS) performs variational inference
%   with the default parameters replaced by values in the structure OPTIONS.
%   VBMC('defaults') returns the default OPTIONS struct.
%  
%   VP = VBMC(FUN,X0,LB,UB,PLB,PUB,OPTIONS,...) passes additional arguments
%   to FUN.
%  
%   VP = VBMC(FUN,VP0,...) uses variational posterior VP0 (from a previous
%   run of VBMC) to initialize the current run. You can leave PLB and PUB
%   empty, in which case they will be set using VP0 (recommended).
%
%   [VP,ELBO] = VBMC(...) returns an estimate of the ELBO, the variational
%   expected lower bound on the log marginal likelihood (log model evidence).
%   This estimate is computed via Bayesian quadrature.
%
%   [VP,ELBO,ELBO_SD] = VBMC(...) returns the standard deviation of the
%   estimate of the ELBO, as computed via Bayesian quadrature. Note that
%   this standard deviation is *not* representative of the error between the 
%   ELBO and the true log marginal likelihood.
%
%   [VP,ELBO,ELBO_SD,EXITFLAG] = VBMC(...) returns an EXITFLAG that describes
%   the exit condition. Possible values of EXITFLAG and the corresponding
%   exit conditions are
%
%    1  Change in the variational posterior, in the ELBO and its uncertainty 
%       have reached a satisfactory level of stability across recent
%       iterations, suggesting convergence of the variational solution.
%    0  Maximum number of function evaluations or iterations reached. Note
%       that the returned solution has *not* stabilized.
%
%   [VP,ELBO,ELBO_SD,EXITFLAG,OUTPUT] = VBMC(...) returns a structure OUTPUT 
%   with the following information:
%          function: <Target probability density function name>
%        iterations: <Total iterations>
%         funccount: <Total function evaluations>
%          bestiter: <Iteration of returned solution>
%      trainsetsize: <Size of training set for returned solution>
%        components: <Number of mixture components of returned solution>
%            rindex: <Reliability index (< 1 is good)>
% convergencestatus: <"probable" or "no" convergence>
%          overhead: <Fractional overhead (total runtime / total fcn time - 1)>
%          rngstate: <Status of random number generator>
%         algorithm: <Variational Bayesian Monte Carlo>
%           message: <VBMC termination message>
%              elbo: <Estimated ELBO for returned solution>
%            elbosd: <Estimated standard deviation of ELBO at returned solution>
%
%   OPTIONS = VBMC('defaults') returns a basic default OPTIONS structure.
%
%   EXITFLAG = VBMC('test') runs a battery of tests. Here EXITFLAG is 0 if
%   everything works correctly.
%
%   Examples:
%     FUN can be a function handle (using @)
%       vp = vbmc(@rosenbrock_test, ...)
%     In this case, F = rosenbrock_test(X) returns the scalar log pdf F of 
%     the target pdf evaluated at X.
%
%     An example with no hard bounds, only plausible bounds
%       plb = [-5 -5]; pub = [5 5]; options.Plot = 'on';
%       [vp,elbo,elbo_sd] = vbmc(@rosenbrock_test,[0 0],[],[],plb,pub,options);
%
%     FUN can also be an anonymous function:
%        lb = [0 0]; ub = [pi 5]; plb = [0.1 0.1]; pub = [3 4]; options.Plot = 'on';
%        vp = vbmc(@(x) 3*sin(x(1))*exp(-x(2)),[1 1],lb,ub,plb,pub,options)
%
%   See VBMC_EXAMPLES for an extended tutorial with more examples. 
%   The most recent version of the algorithm and additional documentation 
%   can be found here: https://github.com/lacerbi/vbmc
%   Also, check out the FAQ: https://github.com/lacerbi/vbmc/wiki
%
%   Reference: Acerbi, L. (2018). "Variational Bayesian Monte Carlo". 
%   To appear in Advances in Neural Information Processing Systems 31. 
%   arXiv preprint arXiv:1810.05558
%
%   See also VBMC_EXAMPLES, VBMC_KLDIV, VBMC_MODE, VBMC_MOMENTS, VBMC_PDF, 
%   VBMC_RND, @.

%--------------------------------------------------------------------------
% VBMC: Variational Bayesian Monte Carlo for posterior and model inference.
% To be used under the terms of the GNU General Public License 
% (http://www.gnu.org/copyleft/gpl.html).
%
%   Author (copyright): Luigi Acerbi, 2018
%   e-mail: luigi.acerbi@{gmail.com,nyu.edu,unige.ch}
%   URL: http://luigiacerbi.com
%   Version: 0.9 (beta)
%   Release date: Oct 9, 2018
%   Code repository: https://github.com/lacerbi/vbmc
%--------------------------------------------------------------------------

% The VBMC interface (such as details of input and output arguments) may 
% undergo minor changes before reaching the stable release (1.0).


%% Start timer

t0 = tic;

%% Basic default options
defopts.Display                 = 'iter         % Level of display ("iter", "notify", "final", or "off")';
defopts.Plot                    = 'off          % Plot marginals of variational posterior at each iteration';
defopts.MaxIter                 = '50*nvars     % Max number of iterations';
defopts.MaxFunEvals             = '100*nvars    % Max number of target fcn evaluations';
defopts.TolStableIters          = '8            % Required stable iterations for termination';

%% If called with no arguments or with 'defaults', return default options
if nargout <= 1 && (nargin == 0 || (nargin == 1 && ischar(fun) && strcmpi(fun,'defaults')))
    if nargin < 1
        fprintf('Basic default options returned (type "help vbmc" for help).\n');
    end
    vp = defopts;
    return;
end

%% If called with one argument which is 'test', run test
if nargout <= 1 && nargin == 1 && ischar(fun) && strcmpi(fun,'test')
    vp = runtest();
    return;
end

%% Advanced options (do not modify unless you *know* what you are doing)

defopts.SkipActiveSamplingAfterWarmup   = 'yes  % Skip active sampling the first iteration after warmup';
defopts.TolStableEntropyIters   = '6            % Required stable iterations to switch entropy approximation';
defopts.UncertaintyHandling     = 'no           % Explicit noise handling (only partially supported)';
defopts.NoiseSize               = '[]           % Base observation noise magnitude';
defopts.VariableWeights         = 'yes          % Use variable mixture weight for variational posterior';
defopts.WeightPenalty           = '0.1          % Penalty multiplier for small mixture weights';
defopts.Diagnostics             = 'off          % Run in diagnostics mode, get additional info';
defopts.OutputFcn               = '[]           % Output function';
defopts.TolStableExceptions     = '1            % Allowed exceptions when computing iteration stability';
defopts.Fvals                   = '[]           % Evaluated fcn values at X0';
defopts.OptimToolbox            = '[]           % Use Optimization Toolbox (if empty, determine at runtime)';
defopts.ProposalFcn             = '[]           % Weighted proposal fcn for uncertainty search';
defopts.UncertaintyHandling     = '[]           % Explicit noise handling (if empty, determine at runtime)';
defopts.NoiseSize               = '[]           % Base observation noise magnitude';
defopts.NonlinearScaling   = 'on                % Automatic nonlinear rescaling of variables';
defopts.FunEvalStart       = 'max(D,10)         % Number of initial target fcn evals';
defopts.FunEvalsPerIter    = '5                 % Number of target fcn evals per iteration';
defopts.SearchAcqFcn       = '@vbmc_acqfreg     % Fast search acquisition fcn(s)';
defopts.NSsearch           = '2^13              % Samples for fast acquisition fcn eval per new point';
defopts.NSent              = '@(K) 100*K        % Total samples for Monte Carlo approx. of the entropy';
defopts.NSentFast          = '@(K) 100*K        % Total samples for preliminary Monte Carlo approx. of the entropy';
defopts.NSentFine          = '@(K) 2^15*K       % Total samples for refined Monte Carlo approx. of the entropy';
defopts.NSelbo             = '50                % Samples per component for fast approx. of ELBO';
defopts.NSelboIncr         = '0.1               % Multiplier to samples for fast approx. of ELBO for incremental iterations';
defopts.ElboStarts         = '2                 % Starting points to refine optimization of the ELBO';
defopts.NSgpMax            = '80                % Max GP hyperparameter samples (decreases with training points)';
defopts.StableGPSampling   = '200 + 10*nvars    % Force stable GP hyperparameter sampling (reduce samples or start optimizing)';
defopts.StableGPSamples    = '0                 % Number of GP samples when GP is stable (0 = optimize)';
defopts.GPSampleThin       = '5                 % Thinning for GP hyperparameter sampling';
defopts.TolGPVar           = '1e-4              % Threshold on GP variance, used to stabilize sampling and by some acquisition fcns';
defopts.gpMeanFun          = 'negquad           % GP mean function';
defopts.KfunMax            = '@(N) N.^(2/3)     % Max variational components as a function of training points';
defopts.Kwarmup            = '2                 % Variational components during warmup';
defopts.AdaptiveK          = '2                 % Added variational components for stable solution';
defopts.HPDFrac            = '0.8               % High Posterior Density region (fraction of training inputs)';
defopts.ELCBOImproWeight   = '3                 % Uncertainty weight on ELCBO for computing lower bound improvement';
defopts.TolLength          = '1e-6              % Minimum fractional length scale';
defopts.NoiseObj           = 'off               % Objective fcn returns noise estimate as 2nd argument (unsupported)';
defopts.CacheSize          = '1e4               % Size of cache for storing fcn evaluations';
defopts.CacheFrac          = '0.5               % Fraction of search points from starting cache (if nonempty)';
defopts.StochasticOptimizer = 'adam             % Stochastic optimizer for varational parameters';
defopts.TolFunStochastic   = '1e-3              % Stopping threshold for stochastic optimization';
defopts.TolSD              = '0.1               % Tolerance on ELBO uncertainty for stopping (iff variational posterior is stable)';
defopts.TolsKL             = '0.01*sqrt(nvars)  % Stopping threshold on change of variational posterior per training point';
defopts.TolStableWarmup    = '3                 % Number of stable iterations for stopping warmup';
defopts.TolImprovement     = '0.01              % Required ELCBO improvement per fcn eval before termination';
defopts.KLgauss            = 'yes               % Use Gaussian approximation for symmetrized KL-divergence b\w iters';
defopts.TrueMean           = '[]                % True mean of the target density (for debugging)';
defopts.TrueCov            = '[]                % True covariance of the target density (for debugging)';
defopts.MinFunEvals        = '5*nvars           % Min number of fcn evals';
defopts.MinIter            = 'nvars             % Min number of iterations';
defopts.HeavyTailSearchFrac = '0.25               % Fraction of search points from heavy-tailed variational posterior';
defopts.MVNSearchFrac      = '0.25              % Fraction of search points from multivariate normal';
defopts.AlwaysRefitVarPost = 'no                % Always fully refit variational posterior';
defopts.Warmup             = 'on                % Perform warm-up stage';
defopts.StopWarmupThresh   = '1                 % Stop warm-up when increase in ELBO is confidently below threshold';
defopts.WarmupKeepThreshold = '10*nvars         % Max log-likelihood difference for points kept after warmup';
defopts.SearchCMAES        = 'on                % Use CMA-ES for search';
defopts.MomentsRunWeight   = '0.9               % Weight of previous trials (per trial) for running avg of variational posterior moments';
defopts.GPRetrainThreshold = '1                 % Upper threshold on reliability index for full retraining of GP hyperparameters';
defopts.ELCBOmidpoint      = 'on                % Compute full ELCBO also at best midpoint';
defopts.GPSampleWidths     = '5                 % Multiplier to widths from previous posterior for GP sampling (Inf = do not use previous widths)';
defopts.HypRunWeight       = '0.9               % Weight of previous trials (per trial) for running avg of GP hyperparameter covariance';
defopts.WeightedHypCov     = 'on                % Use weighted hyperparameter posterior covariance';
defopts.TolCovWeight       = '0                 % Minimum weight for weighted hyperparameter posterior covariance';
defopts.GPHypSampler       = 'slicesample       % MCMC sampler for GP hyperparameters';
defopts.CovSampleThresh    = '10                % Switch to covariance sampling below this threshold of stability index';
defopts.DetEntTolOpt       = '1e-3              % Optimality tolerance for optimization of deterministic entropy';
defopts.EntropySwitch      = 'off               % Switch from deterministic entropy to stochastic entropy when reaching stability';
defopts.EntropyForceSwitch = '0.8               % Force switch to stochastic entropy at this fraction of total fcn evals';
defopts.DetEntropyMinD     = '5                 % Start with deterministic entropy only with this number of vars or more';
defopts.TolConLoss         = '0.01              % Fractional tolerance for constraint violation of variational parameters';
defopts.BestSafeSD         = '5                 % SD multiplier of ELCBO for computing best variational solution';
defopts.BestFracBack       = '0.25              % When computing best solution, lacking stability go back up to this fraction of iterations';
defopts.TolWeight          = '1e-2              % Threshold mixture component weight for pruning';
defopts.AnnealedGPMean     = '@(N,NMAX) 0       % Annealing for hyperprior width of GP negative quadratic mean';
defopts.InitDesign         = 'plausible         % Initial samples ("plausible" is uniform in the plausible box)';

% Portfolio allocation parameters (experimental feature)
defopts.Portfolio          = 'off               % Portfolio allocation for acquisition function';
defopts.HedgeGamma         = '0';
defopts.HedgeBeta          = '0.1';
defopts.HedgeDecay         = '0.5';
defopts.HedgeMax           = 'log(10)';

%% Advanced options for unsupported/untested features (do *not* modify)
defopts.AcqFcn             = '@vbmc_acqskl       % Expensive acquisition fcn';
defopts.Nacq               = '1                 % Expensive acquisition fcn evals per new point';
defopts.WarpRotoScaling    = 'off               % Rotate and scale input';
%defopts.WarpCovReg         = '@(N) 25/N         % Regularization weight towards diagonal covariance matrix for N training inputs';
defopts.WarpCovReg         = '0                 % Regularization weight towards diagonal covariance matrix for N training inputs';
defopts.WarpNonlinear      = 'off               % Nonlinear input warping';
defopts.WarpEpoch          = '100               % Recalculate warpings after this number of fcn evals';
defopts.WarpMinFun         = '10 + 2*D          % Minimum training points before starting warping';
defopts.WarpNonlinearEpoch = '100               % Recalculate nonlinear warpings after this number of fcn evals';
defopts.WarpNonlinearMinFun = '20 + 5*D         % Minimum training points before starting nonlinear warping';
defopts.ELCBOWeight        = '0                 % Uncertainty weight during ELCBO optimization';
defopts.SearchSampleGP     = 'false             % Generate search candidates sampling from GP surrogate';
defopts.VarParamsBack      = '0                 % Check variational posteriors back to these previous iterations';
defopts.AltMCEntropy       = 'no                % Use alternative Monte Carlo computation for the entropy';


%% If called with 'all', return all default options
if strcmpi(fun,'all')
    vp = defopts;
    return;
end

%% Check that all VBMC subfolders are on the MATLAB path
add2path();

%% Input arguments

if nargin < 3 || isempty(LB); LB = -Inf; end
if nargin < 4 || isempty(UB); UB = Inf; end
if nargin < 5; PLB = []; end
if nargin < 6; PUB = []; end
if nargin < 7; options = []; end

%% Initialize display printing options

if ~isfield(options,'Display') || isempty(options.Display)
    options.Display = defopts.Display;
end

switch lower(options.Display(1:min(end,3)))
    case {'not'}                        % notify
        prnt = 1;
    case {'no','non','off'}             % none
        prnt = 0;
    case {'ite','all','on','yes'}       % iter
        prnt = 3;
    case {'fin','end'}                  % final
        prnt = 2;
    otherwise
        prnt = 3;
end

%% Initialize variables and algorithm structures

if isempty(x0)
    if prnt > 2
        fprintf('X0 not specified. Taking the number of dimensions from PLB and PUB...');
    end
    if isempty(PLB) || isempty(PUB)
        error('vbmc:UnknownDims', ...
            'If no starting point is provided, PLB and PUB need to be specified.');
    end    
    x0 = NaN(size(PLB));
    if prnt > 2
        fprintf(' D = %d.\n', numel(x0));
    end
end

% Initialize from variational posterior
if vbmc_isavp(x0)
    vp0 = x0;
    if prnt > 2
        fprintf('Initializing VBMC from variational posterior (D = %d).\n', vp0.D);
        if ~isempty(PLB) && ~isempty(PUB)
            fprintf('Using provided plausible bounds. Note that it might be better to leave them empty,\nand allow VBMC to set them using the provided variational posterior.\n');
        end
    end
    x0 = vbmc_mode(vp0);
    if isempty(PLB) && isempty(PUB)
        Xrnd = vbmc_rnd(vp0,1e6);
        PLB = quantile(Xrnd,0.1);
        PUB = quantile(Xrnd,0.9);
    end
    if isempty(LB); LB = vp0.trinfo.lb_orig; end
    if isempty(UB); UB = vp0.trinfo.ub_orig; end
    
    clear vp0 xrnd;
end
    
D = size(x0,2);     % Number of variables
optimState = [];

% Check/fix boundaries and starting points
[LB,UB,PLB,PUB] = boundscheck(x0,LB,UB,PLB,PUB,prnt);

% Convert from char to function handles
if ischar(fun); fun = str2func(fun); end

% Setup algorithm options
[options,cmaes_opts] = setupoptions(D,defopts,options);

% Setup and transform variables
K = options.Kwarmup;
[vp,optimState] = ...
    setupvars(x0,LB,UB,PLB,PUB,K,optimState,options,prnt);

% Store target density function
optimState.fun = fun;
if isempty(varargin)
    funwrapper = fun;   % No additional function arguments passed
else
    funwrapper = @(u_) fun(u_,varargin{:});
end

% Initialize function logger
[~,optimState] = vbmc_funlogger([],x0(1,:),optimState,'init',options.CacheSize,options.NoiseObj);

% GP struct and GP hyperparameters
gp = [];    hyp = [];   hyp_warp = [];
optimState.gpMeanfun = options.gpMeanFun;
switch optimState.gpMeanfun
    case {'zero','const','negquad','se'}
    otherwise
        error('vbmc:UnknownGPmean', ...
            'Unknown/unsupported GP mean function. Supported mean functions are ''zero'', ''const'', ''negquad'', and ''se''.');
end

if optimState.Cache.active
    displayFormat = ' %5.0f     %5.0f  /%5.0f   %12.2f  %12.2f  %12.2f     %4.0f %10.3g       %s\n';
else
    displayFormat = ' %5.0f       %5.0f    %12.2f  %12.2f  %12.2f     %4.0f %10.3g     %s\n';
end
if prnt > 2
    if optimState.Cache.active
        fprintf(' Iteration f-count/f-cache    Mean[ELBO]     Std[ELBO]     sKL-iter[q]   K[q]  Convergence    Action\n');
        % fprintf(displayFormat,0,0,0,NaN,NaN,NaN,NaN,Inf,'');        
    else
        fprintf(' Iteration   f-count     Mean[ELBO]     Std[ELBO]     sKL-iter[q]   K[q]  Convergence  Action\n');
        % fprintf(displayFormat,0,0,NaN,NaN,NaN,NaN,Inf,'');        
    end
end

%% Variational optimization loop
iter = 0;
isFinished_flag = false;
exitflag = 0;   output = [];    stats = [];     sKL = Inf;

while ~isFinished_flag    
    iter = iter + 1;
    optimState.iter = iter;
    vp_old = vp;
    action = '';
    optimState.redoRotoscaling = false;    
    
    if iter == 1 && optimState.Warmup; action = 'start warm-up'; end
    
    % Switch to stochastic entropy towards the end if still on deterministic
    if optimState.EntropySwitch && ...
            optimState.funccount >= options.EntropyForceSwitch*options.MaxFunEvals
        optimState.EntropySwitch = false;
        if isempty(action); action = 'entropy switch'; else; action = [action ', entropy switch']; end        
    end
    
    %% Actively sample new points into the training set
    t = tic;
    optimState.trinfo = vp.trinfo;
    if iter == 1; new_funevals = options.FunEvalStart; else; new_funevals = options.FunEvalsPerIter; end
    if optimState.Xmax > 0
        optimState.ymax = max(optimState.y(optimState.X_flag));
    end
    if optimState.SkipActiveSampling
        optimState.SkipActiveSampling = false;
    else
        [optimState,t_active(iter),t_func(iter)] = ...
            vbmc_activesample(optimState,new_funevals,funwrapper,vp,vp_old,gp,options,cmaes_opts);
    end
    optimState.N = optimState.Xmax;  % Number of training inputs
    optimState.Neff = sum(optimState.X_flag(1:optimState.Xmax));
    timer.activeSampling = toc(t);
    
    %% Input warping / reparameterization (unsupported!)
    if options.WarpNonlinear || options.WarpRotoScaling
        t = tic;
        [optimState,vp,hyp,hyp_warp,action] = ...
            vbmc_warp(optimState,vp,gp,hyp,hyp_warp,action,options,cmaes_opts);
        timer.warping = toc(t);        
    end
        
    %% Train GP
    t = tic;
        
    % Get priors, starting hyperparameters, and number of samples
    [hypprior,X_hpd,y_hpd,~,hyp0,optimState.gpMeanfun,Ns_gp] = ...
        vbmc_gphyp(optimState,optimState.gpMeanfun,0,options);
    if isempty(hyp); hyp = hyp0; end % Initial GP hyperparameters
    if Ns_gp == options.StableGPSamples && optimState.StopSampling == 0
        optimState.StopSampling = optimState.N; % Reached stable sampling
    end
    
    % Get GP training options
    gptrain_options = get_GPTrainOptions(Ns_gp,optimState,stats,options);    
    
    % Get training dataset
    [X_train,y_train] = get_traindata(optimState,options);
    
    % Fit GP to training set
    [gp,hyp,gpoutput] = gplite_train(hyp,Ns_gp,X_train,y_train, ...
        optimState.gpMeanfun,hypprior,[],gptrain_options);
    hyp_full = gpoutput.hyp_prethin; % Pre-thinning GP hyperparameters
    
    % Update running average of GP hyperparameter covariance (coarse)
    if size(hyp_full,2) > 1
        hypcov = cov(hyp_full');
        if isempty(optimState.RunHypCov) || options.HypRunWeight == 0
            optimState.RunHypCov = hypcov;
        else
            weight = options.HypRunWeight^options.FunEvalsPerIter;
            optimState.RunHypCov = (1-weight)*hypcov + ...
                weight*optimState.RunHypCov;
        end
        % optimState.RunHypCov
    else
        optimState.RunHypCov = [];
    end
    
    % Sample from GP (for debug)
    if ~isempty(gp) && 0
        Xgp = vbmc_gpsample(gp,1e3,optimState,1);
        cornerplot(Xgp);
    end
    
    timer.gpTrain = toc(t);
        
    %% Optimize variational parameters
    t = tic;
    
    % Update number of variational mixture components
    Knew = updateK(optimState,stats,options);

    % Decide number of fast/slow optimizations
    if optimState.RecomputeVarPost || options.AlwaysRefitVarPost
        Nfastopts = options.NSelbo * vp.K;
        Nslowopts = options.ElboStarts; % Full optimizations
        optimState.RecomputeVarPost = false;
    else
        % Only incremental change from previous iteration
        Nfastopts = ceil(options.NSelbo * vp.K * options.NSelboIncr);
        Nslowopts = 1;
    end
    
    % Run optimization of variational parameters
    [vp,elbo,elbo_sd,H,varss,pruned] = ...
        vpoptimize(Nfastopts,Nslowopts,vp,gp,Knew,X_hpd,y_hpd,optimState,stats,options,cmaes_opts,prnt);
    optimState.vpK = vp.K;
    optimState.H = H;   % Save current entropy
    
    timer.variationalFit = toc(t);
    
    %% Recompute warpings at end iteration (unsupported)
    if options.WarpNonlinear || options.WarpRotoScaling    
        [optimState,vp,hyp] = ...
            vbmc_rewarp(optimState,vp,gp,hyp,options,cmaes_opts);
    end
    
    %% Plot current iteration (to be improved)
    if options.Plot
        
        if D == 1
            hold off;
            gplite_plot(gp);
            hold on;
            xlims = xlim;
            xx = linspace(xlims(1),xlims(2),1e3)';
            yy = vbmc_pdf(vp,xx,false,true);
            hold on;
            plot(xx,yy+elbo,':');
            drawnow;
            
        else
            Xrnd = vbmc_rnd(vp,1e5,1,1);
            X_train = gp.X;
            if ~isempty(vp.trinfo); X_train = warpvars(X_train,'inv',vp.trinfo); end
            try
                for i = 1:D; names{i} = ['x_{' num2str(i) '}']; end
                [~,ax] = cornerplot(Xrnd,names);
                for i = 1:D-1
                    for j = i+1:D
                        axes(ax(j,i));  hold on;
                        scatter(X_train(:,i),X_train(:,j),'ok');
                    end
                end
                drawnow;
            catch
                % pause
            end            
        end
    end    
    
    %mubar
    %Sigma
    
    %----------------------------------------------------------------------
    %% Finalize iteration
    t = tic;
    
    % Compute symmetrized KL-divergence between old and new posteriors
    Nkl = 1e5;
    sKL = max(0,0.5*sum(vbmc_kldiv(vp,vp_old,Nkl,options.KLgauss)));
    
    % Compare variational posterior's moments with ground truth
    if ~isempty(options.TrueMean) && ~isempty(options.TrueCov) ...
        && all(isfinite(options.TrueMean(:))) ...
        && all(isfinite(options.TrueCov(:)))
    
        [mubar_orig,Sigma_orig] = vbmc_moments(vp,1,1e6);
        [kl(1),kl(2)] = mvnkl(mubar_orig,Sigma_orig,options.TrueMean,options.TrueCov);
        sKL_true = 0.5*sum(kl)
    else
        sKL_true = [];
    end
    
    % Record moments in transformed space
    [mubar,Sigma] = vbmc_moments(vp,0);
    if isempty(optimState.RunMean) || isempty(optimState.RunCov)
        optimState.RunMean = mubar(:);
        optimState.RunCov = Sigma;        
        optimState.LastRunAvg = optimState.N;
        % optimState.RunCorrection = 1;
    else
        Nnew = optimState.N - optimState.LastRunAvg;
        wRun = options.MomentsRunWeight^Nnew;
        optimState.RunMean = wRun*optimState.RunMean + (1-wRun)*mubar(:);
        optimState.RunCov = wRun*optimState.RunCov + (1-wRun)*Sigma;
        optimState.LastRunAvg = optimState.N;
        % optimState.RunT = optimState.RunT + 1;
    end
        
    % Check if we are still warming-up
    if optimState.Warmup && iter > 1    
        [optimState,action] = vbmc_warmup(optimState,stats,action,elbo,elbo_sd,options);
        if ~optimState.Warmup
            vp.optimize_weights = logical(options.VariableWeights);
        end        
    end
    
    % Update portfolio values
    if options.Portfolio && iter > 2
        hedge = optimState.hedge;
        er = zeros(1,hedge.n);
        hedge.count = hedge.count + 1;
        
        RecentIters = ceil(options.TolStableIters/2);
        hedge_beta = max(options.TolImprovement,mean(stats.elboSD(max(1,end-RecentIters+1):end)));

        elcbo_old = stats.elbo(end) - options.ELCBOImproWeight*stats.elboSD(end);
        elcbo = elbo - options.ELCBOImproWeight*elbo_sd;
                
        er(hedge.chosen) = min(hedge.max,max(0,(elcbo - elcbo_old)/hedge_beta)/hedge.p(hedge.chosen));        
        hedge.g = hedge.decay*hedge.g + er;
        
        [hedge.chosen,hedge.g]
        
        optimState.hedge = hedge;
    end

    % t_fits(iter) = toc(timer_fits);    
    % dt = (t_active(iter)+t_fits(iter))/new_funevals;
    
    timer.finalize = toc(t);
    
    % timer
    
    % Record all useful stats
    stats = savestats(stats, ...
        optimState,vp,elbo,elbo_sd,varss,sKL,sKL_true,gp,hyp_full,Ns_gp,pruned,timer,options.Diagnostics);
    
    %----------------------------------------------------------------------
    %% Check termination conditions    

    [optimState,stats,isFinished_flag,exitflag,action,msg] = ...
        vbmc_termination(optimState,action,stats,options);
    
    %% Write iteration output
    
    % vp.w
    
    % Stopped GP sampling this iteration?
    if Ns_gp == options.StableGPSamples && ...
            stats.gpNsamples(max(1,iter-1)) > options.StableGPSamples
        if isempty(action); action = 'stable GP sampling'; else; action = [action ', stable GP sampling']; end
    end    
    
    if prnt > 2
        if optimState.Cache.active
            fprintf(displayFormat,iter,optimState.funccount,optimState.cachecount,elbo,elbo_sd,sKL,vp.K,optimState.R,action);
        else
            fprintf(displayFormat,iter,optimState.funccount,elbo,elbo_sd,sKL,vp.K,optimState.R,action);
        end
    end
    
%     if optimState.iter > 10 && stats.elboSD(optimState.iter-1) < 0.1 && stats.elboSD(optimState.iter) > 10
%         fprintf('\nmmmh\n');        
%     end
    
end

% Pick "best" variational solution to return
[vp,elbo,elbo_sd,idx_best] = ...
    vbmc_best(stats,iter,options.BestSafeSD,options.BestFracBack);

if ~stats.stable(idx_best); exitflag = 0; end

% Print final message
if prnt > 1
    fprintf('\n%s\n', msg);    
    fprintf('Estimated ELBO: %.3f +/- %.3f.\n', elbo, elbo_sd);
    if exitflag < 1
        fprintf('Caution: Returned variational solution may have not converged.\n');
    end
    fprintf('\n');
end

if nargout > 4
    output = vbmc_output(elbo,elbo_sd,optimState,msg,stats,idx_best);
    
    % Compute total running time and fractional overhead
    optimState.totaltime = toc(t0);    
    output.overhead = optimState.totaltime / optimState.totalfunevaltime - 1;    
end

if nargout > 6
    % Remove GP from stats struct unless diagnostic run
    if ~options.Diagnostics
        stats = rmfield(stats,'gp');
        stats = rmfield(stats,'gpHypFull');
    end
end


end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function stats = savestats(stats,optimState,vp,elbo,elbo_sd,varss,sKL,sKL_true,gp,hyp_full,Ns_gp,pruned,timer,debugflag)

iter = optimState.iter;
stats.iter(iter) = iter;
stats.N(iter) = optimState.N;
stats.Neff(iter) = optimState.Neff;
stats.funccount(iter) = optimState.funccount;
stats.cachecount(iter) = optimState.cachecount;
stats.vpK(iter) = vp.K;
stats.warmup(iter) = optimState.Warmup;
stats.pruned(iter) = pruned;
stats.elbo(iter) = elbo;
stats.elboSD(iter) = elbo_sd;
stats.sKL(iter) = sKL;
if ~isempty(sKL_true)
    stats.sKL_true = sKL_true;
end
stats.gpSampleVar(iter) = varss;
stats.gpNsamples(iter) = Ns_gp;
stats.gpHypFull{iter} = hyp_full;
stats.timer(iter) = timer;
stats.vp(iter) = vp;
stats.gp(iter) = gplite_clean(gp);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function add2path()
%ADD2PATH Adds VBMC subfolders to MATLAB path.

subfolders = {'acq','ent','gplite','misc','utils'};
% subfolders = {'acq','ent','gplite','misc','utils','warp'};
pathCell = regexp(path, pathsep, 'split');
baseFolder = fileparts(mfilename('fullpath'));

onPath = true;
for iFolder = 1:numel(subfolders)
    folder = [baseFolder,filesep,subfolders{iFolder}];    
    if ispc  % Windows is not case-sensitive
      onPath = onPath & any(strcmpi(folder, pathCell));
    else
      onPath = onPath & any(strcmp(folder, pathCell));
    end
end

% ADDPATH is slow, call it only if folders are not on path
if ~onPath
    addpath(genpath(fileparts(mfilename('fullpath'))));
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% TO-DO list:
% - Write a private quantile function to avoid calls to Stats Toolbox.
% - Fix call to fmincon if Optimization Toolbox is not available.
% - Check that I am not using other ToolBoxes by mistake.
