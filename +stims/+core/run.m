function run(menu, key,constants)

global rsg_mode ;
global rsg_event_q ;
global rsg_animal_id ;
global old_func ;
global old_var;
global rsg_running ;
global rsg_next_trial ;
global rsg_session_id ;
global rsg_scan_id ;

scanConditionTable = vis.ScanConditions ;

% blank the screen and set default luminance
stims.core.Visual.screen.open;
stims.core.Visual.screen.setContrast(3, 0.5);

% insert new session
rect = stims.core.Visual.screen.rect;
if ~stims.core.Visual.DEBUG && any([constants.resolution_x constants.resolution_y] ~= rect(3:4))
    disp 'Mismatching screen size'
    fprintf('Stimulus specifies [%d,%d]\n', constants.resolution_x, constants.resolution_y)
    fprintf('Screen resolution is [%d,%d]\n', rect(3), rect(4))
    stims.core.Visual.screen.close
    error 'incorrect screen resolution'
end
key = logSession(key,constants);
% get user input
if (rsg_mode == 0) % manual mode
    ch = ' ';
    protocol = [];
    while ch~='q'
        FlushEvents
        ch = GetChar;
        fprintf('Pressed %c\n', ch)
        if ch=='q'
            break
        elseif ismember(ch, '1':char('0'+length(menu)))
            protocol = menu(str2double(ch));
            fprintf('Selected stimulus %c\n', ch);
            initProtocol(protocol, key,constants, []);
            disp 'ready to run'
        elseif ch=='r' && ~isempty(protocol)
            runProtocol(protocol);
        end
    end
else % remote control
    logger = @() stims.core.Logger(vis.Condition, vis.Trial);
    protocol = [];
    endcode = 0 ;
    rsg_running = 1 ;
    while (endcode==0)
        if (rsg_event_q.size > 0)
            elem = rsg_event_q.pop ;
            if strcmp(elem.command,'STOP_SESSION')
                break ;
            elseif strcmp(elem.command,'ABORT_STIMULATOR')
                rsg_animal_id = -2 ;
                break ;
            elseif strcmp(elem.command, 'SET_SCANID')
                rsg_scan_id = sscanf(char(elem.param), '%d') ;
            elseif strcmp(elem.command, 'SET_SESSIONID')
                rsg_session_id = sscanf(char(elem.param), '%d') ; % experiment session
            elseif strcmp(elem.command,'SELECT_EXPERIMENT')
                
                sp = strsplit(elem.param, ';') ;
                
                % find file
                if ~isempty(fileparts(char(sp{1}))) % if specified use specified path
                    func = getLocalPath(char(sp{1}));
                    exists = exist(func,'file') ;
                    var = file2Var(func);
                    old_func = ''; % always initiate with unversioned file
                    old_var = ''; % always initiate with unversioned file
                else
                    func = sprintf('stims.conf.%s.%s', char(sp{2}), char(sp{1}));
                    func = func(1:end-2);
                    if  ~exist(which(func),'file') % check default directory
                        func = sprintf('stims.conf.%s', char(sp{1}));
                        func = func(1:end-2);
                    end
                    exists = exist(which(func),'file');
                    var = file2Var(which(func));
                end
                
                % check if exists
                if ~exists
                    error(fprintf('Parameter file %s does not exist!',char(sp{1})))
                end
                
                % check if filename is called before
                if ~strcmp(old_func,func) || ~exist(old_var,'var')
                    newfilename = true;
                else
                    newfilename = false;
                end
                
                if newfilename ||  exist(var,'var')~=1 % setup a new protocol if does not exist
                    try
                        run(func); % logger used here   
                    catch
                        eval(func);
                    end
                    old_func = (func);
                    old_var = var;
                end
                
                protocol = eval(var);
                initProtocol(protocol, key,constants, scanConditionTable);
                rsg_next_trial = protocol.logger.nextTrial ; % get the first trial used by this run
                scanKey.session = rsg_session_id ;
                scanKey.scan_idx = rsg_scan_id ;
                setScanKey(protocol.logger, scanKey) ;
                
                fprintf('ready to run\n') ;
            elseif strcmp(elem.command,'RUN_EXPERIMENT') && ~isempty(protocol)
                fprintf('experiment started...\n') ;
                endcode = runProtocol(protocol);
                fprintf('experiment stopped...\n');
            end ;
        end ;
        pause(0.01) ;
    end
end

stims.core.Visual.screen.close

end


function initProtocol(protocol, key, constants, scanConditionTable)
init(protocol.logger, key, scanConditionTable);
assert(iscell(protocol.stim), 'protocol.stim must be a cell array of structures')
for stim = protocol.stim(:)'
    stim{1}.init(protocol.logger,constants)
end

end

function key = logSession(key,constants)

global rsg_psy_id ;

assert(~isfield(key,'psy_id'))

nextId = max(fetchn(vis.Session & key, 'psy_id'))+1;  %autoincrement
if isempty(nextId), nextId = 1; end
key.psy_id = nextId;
rsg_psy_id = nextId ;
insert(vis.Session, dj.struct.join(key, constants))

disp('**Session logged**')
disp(key)
end



function endcode = process_net_command()

global rsg_event_q ;
global rsg_running ;
global rsg_animal_id ;

paused = false ;
endcode = -1 ;
while (true)
    if (rsg_event_q.size > 0)
        elem = rsg_event_q.pop ;
        if strcmp(elem.command,'STOP_SESSION')
            endcode = 1 ;
            break ;
        elseif strcmp(elem.command,'ABORT_STIMULATOR')
            endcode = 1 ;
            rsg_animal_id = -2 ;
            break ;
        elseif strcmp(elem.command,'STOP_EXPERIMENT')
            endcode = 0 ;
            break ;
        elseif strcmp(elem.command,'PAUSE_EXPERIMENT')
            paused = true ;
            rsg_running = 3 ;
            fprintf('experiment paused\n') ;
        elseif strcmp(elem.command,'RESUME_EXPERIMENT')
            paused = false ;
            rsg_running = 2 ;
            fprintf('experiment resumed\n') ;
            break ;
        end
    else
        if (~paused)
            break ;
        else
            pause(0.01) ;
        end
    end
end
end



function endcode=runProtocol(protocol)

global rsg_mode ;
global rsg_running ;

screen = stims.core.Visual.screen;

% open parallel pool for trial inserts
if isempty(gcp('nocreate'))
    parpool('local', 2);
end

if ~stims.core.Visual.DEBUG
    HideCursor;
    Priority(MaxPriority(screen.win)); % Use realtime priority for better temporal precision:
end

% merge conditions from all display classes into one array and
% append field obj_ to conditions to point back to the displaying class
allConditions = cellfun(@(stim) arrayfun(@(r) r, ...
    dj.struct.join(stim.conditions, struct('obj_', stim)), ...
    'uni', false), protocol.stim, 'uni', false);
allConditions = cat(1, allConditions{:});

% log condition indices and scan index in ScanCondition table
logScanConditions(protocol.logger) ;

% configure photodiode flips
screen.clearFlipTimes;   % just in case
screen.setFlipCount(protocol.logger.getLastFlip)

%initialize sound
InitializePsychSound(1);
%pahandle=PsychPortAudio('Open');
pahandle = PsychPortAudio('Open', [], [], 0, 44100, 2); % previous call crashes on 2p1, 44100 seems to work on 2p1, 2p3
sound = 2*ones(2,1000);
%sound(:,1:350) = 0; % used in 2p3 to align onset of photodiode signal with
%onset of sound signal
PsychPortAudio('FillBuffer',pahandle,sound);
PsychPortAudio('Volume',pahandle,2);
screen.escape;   % clear the escape
endcode = -1 ;

rsg_running = 2 ;
for iBlock = 1:protocol.blocks
    for iCond = randperm(length(allConditions))
        cond = allConditions{iCond};
        screen.frameStep = 1;  % reset to full frame rate
        if screen.escape&&rsg_mode==0, break, end
        PsychPortAudio('Start',pahandle,1,0); %%%%% trigger audio
        cond.obj_.showTrial(cond)     %%%%%% SHOW STIMULUS
        if screen.escape&&rsg_mode==0, break, end
        fprintf .
        protocol.logger.logTrial(struct(...
            'cond_idx', cond.cond_idx, ...
            'flip_times', screen.clearFlipTimes, ...
            'last_flip_count', screen.flipCount)) ;
        if (rsg_mode==1)
            %           check for commands (e.g. pause)
            endcode = process_net_command() ;
            if endcode==0||endcode==1, break, end
        end ;
    end
    screen.flip(true,false,true);
    screen.clearFlipTimes;   % clean up in case of interrupted trial
    if screen.escape&&rsg_mode==0, break, end
    if endcode==0||endcode==1, break, end
end

if (endcode==-1)
    endcode=0 ; % finished experiment
end ;
rsg_running = 1 ;

% close audio
PsychPortAudio('Close')

% restore normal function
Priority(0);
ShowCursor;
end
