function Obj_out = sofaFit2Grid(Obj_in, out_pos, varargin)
% Converte posi��es de HRIRs SOFA �s posi��es especificadas em 'out_pos'
% Davi R. Carvalho @UFSM - Engenharia Acustica - julho/2020

%  ~Input Parameters:
%    Obj_in:     Objeto de HRTFs SOFA com coordenadas esf�ricas 
%                azi:    0� -> 360�     
%                elev: -90� -> 90� 
%                (com o �ltimo update, talvez funcione com outros sistemas de coordenadas)
%    out_pos:    Nx3 matrix de posi��es desejadas, em que N corresponde ao 
%                n�mero total de posi��es, e as colunas correspondem a azimute,
%                eleva��o e raio respectivamente.

%  ~Output Parameters:
%     Obj_out:   Objeto de HRTFs SOFA com as caracter�stica 
%                de medi��o do dataset CIPIC.

%  ~Optional Parameters:     
%    'adapt':    Seleciona as posicoes mais proximas do grid objetivo e
%                for�a a assumirem suas coordenadas.
%    'hybrid':   Faz a adapta��o como em 'adapt', mas posi��es do grid
%                original escolhidas para mais de uma posi��o objetivo 
%                s�o determinadas por interpola��o (Metodo Padrao).
%    'vbap':     Interpola��o vbap caso selecionado 'interp' ou 'hybrid'.
%    'bilinear': Interpola��o bilinear caso selecionado 'interp' ou 'hybrid'
%
%    'Fs':       Transforma��o da taxa de amostragem no objeto de sa�da 
%                (Padrao: original do objeto).

% Exemplo: Obj_out = sofaFit2Grid(Obj_in, out_pos, 'bilinear', 'Fs', 48000)
%
% Matlab R2020a
%% Parse Arguments
% M�todo de processamento
defaultMethod = 'adapt';
validMethods = {'adapt','hybrid', 'vbap', 'bilinear'};
checkMethod = @(x) any(validatestring(x,validMethods));

% Op��es de taxa de amostragem
paramName = 'Fs';
defaultVal = Obj_in.Data.SamplingRate;

%Verificar entradas
p = inputParser;
addRequired(p,'Obj_in',@isstruct);
addOptional(p,'method',defaultMethod,checkMethod)
addParameter(p,paramName,defaultVal)
parse(p,Obj_in,varargin{:})


%% Sample rate match
if Obj_in.Data.SamplingRate ~= p.Results.Fs
    Obj_in = sofaResample(Obj_in, p.Results.Fs);
end


%% Find new grid positions ('ADAPT')
switch p.Results.method
    case {validMethods{1}, validMethods{2}}              
        meta.pos = Obj_in.SourcePosition;
        idx_adapt = zeros(length(out_pos), 1);
        meta.fittedPOS = zeros(size(out_pos));
        for zz = 1:length(out_pos) 
            % Calculo do erro entre posi��o objetivo e posi��es disponiveis
            tsqr = sqrt((meta.pos(:,1)-out_pos(zz,1)).^2 + (meta.pos(:,2)-out_pos(zz,2)).^2);
            [~, idx_adapt(zz,1)] = min(tsqr); 
            idx_adapt(zz,2) = zz; %salvar indice da posi��o objetivo
            
            % Posicoes selecionadas no grid original (util para visualiza��o)
%             meta.fittedPOS(zz,:) = Obj_in.SourcePosition(idx_adapt(zz, 1),:);            
        end
        % (caso for visualizar as posi��es selecionadas, comentar a linha abaixo)
        meta.fittedPOS = out_pos; % <-------
        meta.fittedIR  = Obj_in.Data.IR(idx_adapt(:,1), :, :);
        
        %% Modelo Hibrido ('HYBRID') 
        if any(strcmp(validMethods{2}, p.Results.method)) 
            % selecionar apenas valores repetidos 
            idx_hybrid = idx_adapt;
            [~,ind_uniq] = unique(idx_adapt(:,1));
            idx_hybrid = removerows(idx_hybrid, 'ind', ind_uniq);
             if isempty(idx_hybrid) %sem indice repetido, sem interpolacao
        %         warning('Nenhum �ndice repetido identificado, m�todo apenas adaptativo.')
             else         
                meta.fittedIR(idx_hybrid(:,2),:,:) = NaN; % to be filled later           
                % interpolar valores limpos
                des_hybrid = out_pos(idx_hybrid(:,2),:);
                IR_temp = miinterpolateHRTF(Obj_in.Data.IR, meta.pos(:,[1,2]), des_hybrid(:,[1,2]), ...
                                          'Algorithm','bilinear');   
                meta.fittedIR(idx_hybrid(:,2),:,:) = IR_temp;
             end
        end

%% Interpolar posicoes ('INTERP')
    case {validMethods{3}, validMethods{4}}
        meta.fittedIR = zeros(length(out_pos), 2, size(Obj_in.Data,3));
        meta.pos = Obj_in.SourcePosition;
        meta.fittedIR = miinterpolateHRTF(Obj_in.Data.IR, meta.pos(:,[1,2]), out_pos(:,[1,2]),...
                                       'Algorithm', p.Results.method);   
        meta.fittedPOS = out_pos;

%% Interpolar por harmonicos esf�ricos
    case {validMethods{5}}
        IR_interp = sofa_SphInterp(Obj_in, out_pos(:, [1,2]));
        meta.fittedIR = IR_interp;
        meta.fittedPOS = out_pos;
end 



%% OUTPUT data (assembly and metadata) 
Obj_out = SOFAgetConventions('SimpleFreeFieldHRIR');
Obj_out.Data.IR = meta.fittedIR;
Obj_out.SourcePosition = meta.fittedPOS;
Obj_out.Data.SamplingRate = p.Results.Fs;

warning('off','SOFA:upgrade');
Obj_out = SOFAupgradeConventions(Obj_out);
Obj_out = SOFAupdateDimensions(Obj_out);


%% Plots
% ri = Obj_in.SourcePosition(1,3);
% %%% plot input %%%
% Obj_in.SourceView = Obj_in.SourcePosition;
% Obj_in.SourceView_Type = 'spherical';
% Obj_in.API.Dimensions.SourceView  = 'MC';
% SOFAplotGeometry(Obj_in)
% 
% view([35 20])
% % xlabel('X [m]')
% % ylabel('Y [m]')
% % zlabel('Z [m]')
% % xticks([-ri, 0, ri])
% % yticks([-ri, 0, ri])
% % zticks([-ri, 0, ri])
% % xticklabels([-ri, 0, ri])
% % yticklabels([-ri, 0, ri])
% % zticklabels([-ri, 0, ri])
% set(gca,'XColor', 'none','YColor','none', 'ZColor','none')
% name = 'CIPIC';
% title(name)
% legend off
% axis tight
% export_fig([pwd, '\Images\English\' name ], '-pdf', '-transparent');

% % %%% plot output %%%ri = Obj_in.SourcePosition(1,3);
% ro = Obj_in.SourcePosition(1,3);
% Obj_out.SourceView = Obj_out.SourcePosition;
% Obj_out.SourceView_Type = 'spherical';
% Obj_out.API.Dimensions.SourceView  = 'MC';
% SOFAplotGeometry(Obj_out)
% view([35 20])
% xlabel('X [m]')
% ylabel('Y [m]')
% zlabel('Z [m]')
% xticks([-ro, 0, ro])
% yticks([-ro, 0, ro])
% zticks([-ro, 0, ro])
% xticklabels([-ro, 0, ro])
% yticklabels([-ro, 0, ro])
% zticklabels([-ro, 0, ro])
% title('')
% legend off
% % axis tight
% % export_fig([pwd, '\Images\3dITAout' ], '-pdf', '-transparent');


         
% % plot error (Mapa 2d sobreposto) %--------------------------------------
% in_pos = Obj_in.SourcePosition(idx_adapt(:,1), :);
% figure()
% scatter(out_pos(:,1), out_pos(:,2), 27,'k', 'filled'); hold on 
% scatter(in_pos(:,1), in_pos(:,2), 25, 'r', 'filled', 'square'); hold off
% xlabel('Azimute [grau]')
% ylabel('Eleva��o [grau]')
% legend('Objetivo', 'Original', 'location', 'southeast')
% axis tight
% set(gca,'FontSize',12)
        

end




%% INTERNAL FUNCTIONS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function Obj = sofaResample(Obj, Fs)
% Muda resolu��o aparente de objeto SOFA para valor especificado
% e faz zero padding para 2^nextpow2(N)
%  ~Input Parameters:
%    Obj:        Objeto de HRTFs SOFA
%    Fs:         Taxa de amostragem Objetivo
%  ~Output Parameters:
%     Obj_out:   Objeto de HRTFs SOFA com a taxa de amostragem Fs

N = ceil( (Fs/Obj.Data.SamplingRate) * size(Obj.Data.IR, 3) ); % length after resample
Nintp = 2^nextpow2(N); % output length
zpad = zeros((Nintp - N), 1);
% options
[p,q] = rat(Fs / Obj.Data.SamplingRate);
normFc = .98 / max(p,q);
order = 256 * max(p,q);
beta = 12;
%%% Cria um filtro via Least-square linear-phase FIR filter design
lpFilt = firls(order, [0 normFc normFc 1],[1 1 0 0]);
lpFilt = lpFilt .* kaiser(order+1,beta)';
lpFilt = lpFilt / sum(lpFilt);
% multiply by p
lpFilt = p * lpFilt;
% Resample
for k = 1:size(Obj.Data.IR, 1)
    for l = 1:size(Obj.Data.IR, 2)
        IRpre(k, l, :) = resample(Obj.Data.IR(k, l, :),p,q,lpFilt);
        IR(k, l, :) = [squeeze(IRpre(k, l, :)); zpad];
    end 
end
%%% Output
Obj.Data.IR = IR;
Obj.Data.SamplingRate = Fs; %new sample rate
end