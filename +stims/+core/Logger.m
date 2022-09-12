% stims.core.Logger -- log stimulus data into specified DataJoint tables

% -- Dimitri Yatsenko, 2012

classdef Logger < handle
    
    properties(SetAccess=private)
        % DataJoint tables for session information. Structure with fields
        % 'trial', 'condition', 'paramaters'
        condTable
        trialTable
        scanConditionTable
        sessionKey
        scanKey
        trialIdx
        unsavedTrials
        currentConditions
    end
    
    methods
        function self = Logger(condTable, trialTable)
            self.trialTable = trialTable;
            self.condTable = condTable;
        end
        
        
        function init(self, sessionKey, scanConditionTable)
            if ~isempty(self.sessionKey)
                disp 'logger already initialized'
            else
                self.sessionKey = sessionKey;
                self.scanConditionTable = scanConditionTable ;
                self.currentConditions = [] ;
                disp **logged**
                disp(self.sessionKey)
            end
            % always get the next trial_id from database
            nextId = max(fetchn(self.trialTable & sessionKey, 'trial_idx'))+1;  %autoincrement
            if isempty(nextId), nextId = 1; end
            self.trialIdx = nextId;
        end
        
        
        function lastFlip = getLastFlip(self)
            
            % flip counts are unique per animal
            lastFlip = max(fetchn(self.trialTable & rmfield(self.sessionKey,'psy_id'), 'last_flip_count')); % Flips are unique to the animal
            if isempty(lastFlip)
                lastFlip = 0;
            end
        end
        
        % run once per session
        function conditions = logConditions(self, conditions, paramTable)
            lastCond = max(fetchn(self.condTable & self.sessionKey, 'cond_idx'));
            if isempty(lastCond)
                lastCond = 0;
            end
            [conditions(:).cond_idx] = deal(nan);
            for iCond = 1:length(conditions)
                condIdx = iCond + lastCond;
                conditions(iCond).cond_idx = condIdx;
                self.currentConditions = [self.currentConditions condIdx] ; % keep the condition indices in this object
                tuple = self.sessionKey;
                tuple.cond_idx = condIdx;
                self.condTable.insert(tuple);
                attrs = [paramTable.primaryKey paramTable.nonKeyFields];
                paramTable.insert(dj.struct.join(tuple, dj.struct.pro(conditions(iCond), attrs{:})))
            end
        end
        
        
        % run each time a scan is started
        function logScanConditions(self)
            if (~isempty(self.scanConditionTable))
                for iCond = 1:length(self.currentConditions)
                    tuple = self.sessionKey;
                    tuple.cond_idx = self.currentConditions(iCond);
                    tuple.session = self.scanKey.session ;
                    tuple.scan_idx = self.scanKey.scan_idx ;
                    insert(self.scanConditionTable,tuple) ;
                end
            end
        end
        
        
        function logTrial(self, tuple)
            key = self.sessionKey;
            key.trial_idx =self.trialIdx;
            tuple = dj.struct.join(key, tuple);
            self.trialTable.insertParallel(tuple)
 %           self.trialTable.insert(tuple)
            self.trialIdx = self.trialIdx + 1;
        end
        
        
        % need the last trial to send it to network
        function trial = nextTrial(self)
            trial = self.trialIdx ;
        end ;
        
        % set scan key
        function setScanKey(self,scanKey)
            self.scanKey = scanKey ;
        end
    end
end