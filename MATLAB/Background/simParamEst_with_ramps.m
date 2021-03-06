function simParamEst_with_ramps
% First point is centroid of param space
T1_span =[25, 100];
T2_span =[25, 100];
t1_span =[60, 1000];
t2_span =[30,1000];

tau_f = 5;
%C3 =1;
S = 2/3;
alpha = -log((1-S));

control_params = [5 5; 4 9;5 10; 5.5 5.2; 4 11];
competing_pathway1 = [6 5; 6.1 5.5;6 10; 6.5 5.2; 5 11];
competing_pathway2 = [6 5; 5 9;5.8 5.2; 6.5 5.2; 5 11];
prod_brkdwn = [6 5; 5 9;6 10; 6.5 5.2; 6.4 6];
rate_const = control_params;

theta_0 = [1 1; 1 1; 1 1; 1 1; 1 1];

  
  %% Initialize
  %Param_space=enumeration_grid(Param_bound);

  % Define initial set of experiments      
  tau_diff = (t1_span(2) - t1_span(1))/2;
  T_diff = (T1_span(2) - T1_span(1))/2;
  factorial_bound = [ t1_span(1)     t1_span(2)      tau_diff; ...
                      T1_span(1)     T1_span(2)       T_diff];

  factorial_design = enumeration_grid(factorial_bound);
  numInit = length(factorial_design(:,1));
  B = [];
  sig1 = 1E-3; % sigma^2 for response 1
  % Simulate concentration profiles for initial experiments
  for i = 1:numInit
    C = sing_react_oracle(factorial_design(i,:), rate_const);
    C = C + C*sig1.*randn(1,1);
    B(i,:) = C([1 2 6 7]);
  end
  [rows_B,cols_B]=size(B);
  
  sqrt_sig1 = sqrt(sig1);
  r = randn(rows_B,cols_B);
  S = [sqrt_sig1];
  
  % Least squares determination of model fit
  Aineq = [];
  Bineq = [];
  Aeq = [];
  Beq = [];
  nonlcon = [];
  
  % Unscaled bounds
  LB = [2,2;2,2;2,2;2,2;2,2];
  UB = [12,12;12,12;12,12;12,12;12,12];
  
  V = eye(4);
  weight_inv = zeros(numInit,numInit);
  for i = 1:numInit
    weight_inv(4*i-3:4*i,4*i-3:4*i) = V;
  end

  weight = weight_inv^(-1);
  
  % Number of models
  n = 1;
  
  % Current Parameter estimates after initial experiments
  options = optimset('MaxIter',1e10,'MaxFunEvals',500,'FunValCheck','on','TolX',1e-40,'TolFun',1e-40,'Algorithm','sqp','Display','off');
   
 [theta, fval] = fmincon(@(theta) maxLikelihoodEstimates2(theta,B,weight,factorial_design),theta_0,Aineq,Bineq,Aeq,Beq,LB,UB,nonlcon,options);
  
  % initial experiments from factorial design
  expt = length(factorial_design(:,1));
  prevExp = factorial_design;
  
  %model sensitivities
  %X = modelSens(theta,prevExp);%array with dimensions =(num resp,num models,num of exp, num of param) 
  
  %% Parameter Estimation
  numParm = length(theta);
  numModelDis = expt;
  clear CI_error;
  determinatVal = [];
  avg_error = 100;
  while true
  B1 = tic;
  fprintf('%d\n average error:%d\n',expt,avg_error);
  fprintf('%d %d %d %d %d %d %d %d %d %d\n',theta);
    V = calc_cov_(theta,prevExp,B);
    V_theta_inv = zeros(numParm,numParm);
    V_inv = V^(-1);
    
    X = specModelSens(theta,prevExp);
    
    for j=1:expt
      X1 = reshape(X(:,j,:), [1,numParm]);
      V_theta_inv = V_theta_inv + X1'*V_inv*X1;
    end

    % Find confidence interval on each parameter
    F_value = chi2inv(0.98,numParm); % 99% confidence interval, fitting 4 parameters to N experiments

    cov = V_theta_inv^(-1);
    CI = zeros(numParam,2);
    for i = 1:numParm
      CI(i,1) = theta(i) - sqrt(F_value*cov(i,i)); % 4 params
      CI(i,2) = theta(i) + sqrt(F_value*cov(i,i)); % 4 params
      CI_error(i) = abs((CI(i,2) - theta(i))/theta(i))*100; % Relative error in percent
    end
    
    avg_error = mean(CI_error(:));
    if avg_error < 15
         break; 
    end

    %[M_row N_col]=size(Param_space);
    %Size of remaining parameter space
    Exp_guess = [tau_diff*2 T_diff*2];
    options = optimset('MaxIter',1e10,'MaxFunEvals',500,'FunValCheck','on','TolX',1e-40,'TolFun',1e-40,'Algorithm','sqp','Display','off');
    [Exp_Param Fval] = fmincon(@determinantFisherInfo,Exp_guess,Aineq,Bineq,Aeq,Beq,LB1,UB1,nonlcon,options,ind,theta,V_inv,V_theta_inv,numParm);
    
      determinatVal(end+1)= Fval;
      %Simulate next experiment
      expt = expt + 1;
      %results(expt)=min(Arg);
      prevExp(expt,:) = Exp_Param;
      
      C = sing_react_oracle(Exp_Param, theta);
      C = C + C*sig1.*randn(1,1);
      B(expt,:) = C([1 2 6 7]);
      r = randn(1,cols_B);
      
      % currently weight is left as the identity ****(COULD UPDATE)****
      weight_inv = zeros(expt,expt);
      for i = 1:expt
        weight_inv(i,i) = V;
      end
     
      LB_min = [2,2;2,2;2,2;2,2;2,2];
      UB_max = [12,12;12,12;12,12;12,12;12,12];
      LB = max([CI(:,1)';LB_min]);
      UB = min([CI(:,2)';UB_max]);

      weight = weight_inv^(-1);
      options = optimset('MaxIter',1e10,'MaxFunEvals',500,'FunValCheck','on','TolX',1e-40,'TolFun',1e-40,'Algorithm','sqp','Display','off');
      % Calculate new optimized theta parameters
      theta_0 = theta;
      [theta, fval] = fmincon(@(theta) maxLikelihoodEstimates2(theta,B,weight,prevExp),theta_0,Aineq,Bineq,Aeq,Beq,LB,UB,nonlcon,options);
       B1 = toc(B1);
  fprintf('%d\n',B1);
  end
  
fprintf('\n');
fprintf('%d %d %d %d %d %d %d %d %d %d\n',theta);
fprintf('\n');

figure(1)
scatter3(prevExp(numModelDis+1:end,1),prevExp(numModelDis+1:end,2),determinatVal,'filled')
xlabel('Residence Time (S)','fontsize',16);
ylabel('Temperature (C)','fontsize',16);
title('Log of D-Optimal Design Criterion','fontsize',18);
%colormap(jet);
%colorbar('location','eastoutside');
% figure(2)
% scatter3(prevExp(5:numModelDis,1),prevExp(5:numModelDis,2),discrVal,'filled')
% xlabel('Residence Time (s)','fontsize',16);
% ylabel('Temperature (C)','fontsize',16);
% title('Discrimination value','fontsize',18);
%colormap(jet);
%colorbar('location','eastoutside');
end

function [V] = calc_cov_(theta,exp_param,B)

[N_expts,N_resp] = size(exp_param); %determine number of experiments

%Determine model predictions for each experiment
for i = 1:N_expts
  mod_pred(i,:)=sing_react_oracle(exp_param(i,:),theta);
end

for i = 1:N_expts
  y_hat1(4*i-3:4*i,1) = mod_pred(i,[1,2,6,7])';
  y1(4*i-3:4*i,1) = B(i,:);
end

% Compute matrix of residuals
Z = y1 - y_hat1;

% Divide by the degrees of freedom to return the response covariance matrix
V = Z'*Z/(N_expts - 1);

end

function bol = isPreviousExperiment(expParam, prevExps,tau_int,Box)
    ind = find(prevExps(:,2) == expParam(2));
    bol = false;
    if ind
        numInd = length(ind);
        tau = expParam(1);
        for i =1:numInd
            lowerTau = prevExps(i,1) - tau_int/2;
            upperTau = lowerTau + tau_int;
            if lowerTau < Box(1)
                lowerTau = Box(1);
                upperTau = lowerTau + tau_int;
            elseif upperTau > Box(2)
                upperTau = Box(2);
                lowerTau = upperTau - tau_int;
            end
            if tau <= upperTau && tau >= lowerTau
                bol = true;
                break;
            end 
        end
    else
       bol = false; 
    end
end

function D = determinantFisherInfo(Exp_param,modNum,theta, V_inv,V_theta_inv,numParm)
    xn1 = specModelSens(theta,Exp_param);
    xn1 = reshape(xn1(:,1,:), [1,numParm]);
    M1_temp = V_theta_inv + xn1'*V_inv*xn1;
    D = log(det(inv(M1_temp)));
end

function Dis_pts=enumeration_grid(Param_bound)

% Generates enumerated matrix of experimental conditions
% Input
%   Param_bound is the lower and upper bounds on each experimental
%   parameter and the spacing between those bounds
% Output
%   Dis_pts is the matrix of possible experimental conditions

CA_min=Param_bound(1,1); CA_max=Param_bound(1,2); CA_int=Param_bound(1,3);
CB_min=Param_bound(2,1); CB_max=Param_bound(2,2); CB_int=Param_bound(2,3);

if CA_min == CA_max
    CA_span = CA_min;
    Na = 1;
else
    CA_span=[CA_min:CA_int:CA_max]; Na=length(CA_span); %vector of experimental concentrations, A
end

if CB_min == CB_max
    CB_span = CB_min;
    Nb = 1;
else
    CB_span=[CB_min:CB_int:CB_max]; Nb=length(CB_span); %vector of experimental concentrations, B
end

q=1;

for i=1:Nb
    for j=1:Na
      Dis_pts(q,:)=[CA_span(j) CB_span(i)];
      q=q+1;
    end
end

end

function  [x,n, f,g, opts] = check(fun,par,x0,opts0)
%  Check function call
   sx = size(x0);   n = max(sx);
   if  (min(sx) > 1)
       error('x0  should be a vector'), end
   x = x0;   [f g] = feval(fun,x,par);
   sf = size(f);   sg = size(g);
   if  any(sf-1) | ~isreal(f)
       error('f  should be a real valued scalar'), end
   if  any(sg - sx)
       error('g  should be a vector of the same type as  x'), end

   so = size(opts0);
   if  (min(so) ~= 1) | (max(so) < 9) | any(~isreal(opts0(1:9)))
       error('opts  should be a real valued vector of length 9'), end
   opts = opts0(1:9);   opts = opts(:).';
   i = find(opts(1:2) > 2);
   if  length(i)    % Set default values
     d = [2  2];   opts(i) = d(i);
   end
   i = find(opts(1:6) <= 0);
   if  length(i)    % Set default values
     d = [2  2  1  1e-4*norm(g, inf)  1e-6  100];
     opts(i) = d(i);
   end
   i = find(opts(7:9) <= 0);
   if  length(i)    % Set default values
     d = [1e-6  1e-6  10; 1e-1  1e-2  10];
     opts(6+i) = d(opts(2),i);
   end
end

function dFi_dTheta = specModelSens(theta,Exp_param)
   [M,N]=size(Exp_param);
   h = .000001;
   [temp,N1]=size(theta);
   dFi_dTheta = zeros(4,M,N1);%(# resp, # exp, # parms)
   model = str2func(strcat('model',num2str(modnum)));
   for j = 1:N1
     theta2 = theta;
     theta2(1,j) = theta2(1,j)+h;
     mod_pred1 = sing_react_oracle(theta,Exp_param);
     mod_pred2 = sing_react_oracle(theta2,Exp_param);
       
     dFi_dTheta(1,:,j) = (mod_pred2(:,1) - mod_pred1(:,1))./h;
     dFi_dTheta(2,:,j) = (mod_pred2(:,2) - mod_pred1(:,2))./h;
     dFi_dTheta(3,:,j) = (mod_pred2(:,6) - mod_pred1(:,6))./h;
     dFi_dTheta(4,:,j) = (mod_pred2(:,7) - mod_pred1(:,7))./h;
   end

end

function C = model1(theta,Exp_param)
  [M,N]=size(Exp_param); %determine number of experiments
  
  C = zeros(M,1);
  A1 = exp(theta(1));
  A2 = exp(theta(3));
  E1 = theta(2)*1000;
  E2 = theta(4)*1000;

  for expt = 1:M
    T = Exp_param(expt,2);
    tau = Exp_param(expt,1);
    C0 = [1 1 0 0];
    k1 = A1*exp(-E1/T);
    k2 = A2*exp(-E2/T);
    options = odeset('RelTol',1e-8);
    [t_out,C_out] = ode15s(@model1_odefun,[0 tau],C0,options,[k1 k2]);
    C(expt,1) = C_out(end,4);
  end
end

function dC = model1_odefun(t,Y,theta)
  dC1 = -theta(1)*Y(1)*Y(2);
  dC2 = -theta(1)*Y(1)*Y(2);
  dC3 = -theta(2)*Y(3)+theta(1)*Y(1)*Y(2);
  dC4 = theta(2)*Y(3);
  dC = [dC1 dC2 dC3 dC4]';
end

function Sum = maxLikelihoodEstimates2(theta, C, weight, exp_param)
global G_temp
numCond = length(C(:,1));
for j = 1:numCond
    %param = [C(j,2) C(j,1)];
    G_temp(j,:) = sing_react_oracle(exp_param,theta);
end

for i = 1:numCond
    y_hat1(4*i-3:4*i,1) = G_temp(i,[1,2,6,7])';
    y1(4*i-3:4*i,1) = C(i,:);
end

Z = y1 - y_hat1;

Sum = Z'*weight*Z;
Sum = abs(Sum);
end

function C = sing_react_oracle(param,rate_const)
    a = rate_const(1,1); b = rate_const(1,2);
  a1 = rate_const(2,1); b1 = rate_const(2,2); a2 = rate_const(3,1); b2 = rate_const(3,2);
  a3 = rate_const(4,1); b3 = rate_const(4,2);a4 = rate_const(5,1); b4 = rate_const(5,2);
  theta_true = [a b a1 b1 a2 b2 a3 b3 a4 b4];
    C = single_reactor_function(param, theta_true);
end

function C = single_reactor_function(param, theta)
    %reactor_lumped_model
  T_1 = param(1)+ 273.15;
  t = param(2)*60;
  C = [1 1 0 0 0 1 0 0];
   
  A1 = 10^(theta(1));
  E1 = theta(2)*1000;
  A2 = 10^(theta(3));
  E2 = theta(4)*1000;
  A3 = 10^(theta(5));
  E3 = theta(6)*1000;
  A4 = 10^(theta(7));
  E4 = theta(8)*1000;
  A5 = 10^(theta(9));
  E5 = theta(10)*1000;
  k1 = A1*exp(-E1/T_1);
  k2 = A2*exp(-E2/T_1);
  k3 = A3*exp(-E3/T_1);
  k4 = A4*exp(-E4/T_1);
  k5 = A5*exp(-E5/T_1);
  options = odeset('RelTol',1e-10,'NonNegative', [1 2 4 5 6 7 8]); 
 
  [t_out,C_out] = ode15s(@reactor2_odefun,[0 t],C(1:8),options,[k1 k2 k3 k4 k5]);
  
  C = C_out(end,:);
end

function dC = reactor1_odefun(t,Y,theta)
  dC1 = -(theta(1)+theta(2))*Y(1)*Y(2);
  dC2 = -(theta(1)+theta(2))*Y(1)*Y(2);
  dC3 = theta(1)*Y(1)*Y(2)-theta(3)*Y(3)*Y(2);
  dC4 = theta(2)*Y(1)*Y(2);
  dC5 = theta(3)*Y(3)*Y(2);
  dC = [dC1 dC2 dC3 dC4 dC5]';
end

function dC = reactor2_odefun(t,Y,theta)
  dC1 = -(theta(1)+theta(2))*Y(1)*Y(2);
  dC2 = -(theta(1)+theta(2))*Y(1)*Y(2);
  dC3 = theta(1)*Y(1)*Y(2)-theta(3)*Y(3)*Y(2)-theta(4)*Y(3)*Y(6);
  dC4 = theta(2)*Y(1)*Y(2);
  dC5 = theta(3)*Y(3)*Y(2);
  dC6 = -theta(4)*Y(3)*Y(6);
  dC7 = theta(4)*Y(3)*Y(6)-theta(5)*Y(7);
  dC8 = theta(5)*Y(7);
  dC = [dC1 dC2 dC3 dC4 dC5 dC6 dC7 dC8]';
end