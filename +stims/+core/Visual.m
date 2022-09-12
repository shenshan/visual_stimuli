classdef Visual < handle
    % stims.core.Visual is an abstract class from which visual stimuli are derived
    % A stims.core.Visual object manages the graphics window, iterates through
    % trial conditions and calls the showTrial method for each trial.
    % The object optionally logs the data into datajoint tables.
    
    % -- Dimitri Yatsenko, 2012-2015
    
    properties(Constant)
        DEBUG = true
        screen = stims.core.Screen   % all stimuli share one static screen object
    end
    
    properties(Dependent)
        win
        rect
    end
    
    properties(SetAccess=protected)
        params          % structure of cell arrays from which conditions will be derived
        conditions     % list of conditions derived from params
        constants       % fields to be inserted into the session table
    end
    
    properties(Access=protected)
        paramTable 
    end
    
    
    methods(Abstract)
        showTrial(self, condition)  % implement a trial block in subclass
    end
    
    
    methods(Access = protected)
        
        function prepare(self, constants)
            % override this function to do extra work before logging conditions. 
            % For example this could compute a lookup table that the
            % condition table will then reference.
            % This callback is called when self.conditions have been
            % generated but not logged yet.
            % Here, populate tables that psy.Condition (or similar) can
            % refer to.
            
            % do nothing by default.
        end
        
    end
    
    methods
        
        function win = get.win(self)
            win = self.screen.win;
        end
        
        
        function rect = get.rect(self)
            rect = self.screen.rect;
        end
        
        
        function init(self, logger,constants)
            if isempty(self.conditions)
                % not yet initialized
                assert(~isempty(self.params), 'Use setParams first')
                disp 'generating conditions'
                self.conditions = stims.core.makeFactorialConditions(self.params);
                self.constants = constants;
                self.prepare()
                if ~isempty(logger)
                    % assign cond_idx to each condition
                    self.conditions = logger.logConditions(self.conditions, self.paramTable);
                end
                disp 'conditions ready'
            end
        end
        
        
        function self = setParams(self, paramTable, varargin)
            % set parameters for generating the conditions
            self.paramTable = paramTable;
            self.params = struct(varargin{:});
        end
    end
    
end




