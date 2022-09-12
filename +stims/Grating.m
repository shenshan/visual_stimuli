classdef Grating < stims.core.Visual
    
    properties(Access=private)
        % textures
        grating
        mask
    end
    
    
    methods
        
        function d = degPerPix(self)
            % assume isometric pixels
            d = 180/pi*self.constants.monitor_size*2.54/norm(self.rect(3:4))/self.constants.monitor_distance;
        end
        
        function showTrial(self, cond)
            % execute a single trial with a single cond
            % See PsychToolbox DriftDemo4.m for API calls
            assert(~isnan(self.constants.monitor_distance), 'monitor distance is not set')
            
            % second_photodiode_time should be zero when second_photodiode is zero
            assert(cond.second_photodiode || ~cond.second_photodiode_time)
            assert(cond.second_photodiode_time<cond.trial_duration)
            assert(cond.pre_blank >= -cond.second_photodiode_time)
            % initialized grating
            radius = inf;
            if cond.aperture_radius
                radius = cond.aperture_radius * norm(self.rect(3:4))/2;
            end
            self.grating = CreateProceduralSineGrating(self.win, self.rect(3), self.rect(4), [0.5 0.5 0.5 0.0], radius);
            
            self.screen.setContrast(cond.luminance, cond.contrast, strcmp(cond.grating,'sqr'))
            phase = cond.init_phase;
            freq = cond.spatial_freq * self.degPerPix;  % cycles per pixel
            if cond.pre_blank>0
                if cond.second_photodiode
                    % display black photodiode rectangle during the pre-blank
                    rectSize = [0.05 0.06].*self.rect(3:4);
                    rect = [self.rect(3)-rectSize(1), 0, self.rect(3), rectSize(2)];
                    Screen('FillRect', self.win, 0, rect);
                end
                self.screen.flip(false, false, true)
                WaitSecs(cond.pre_blank + min(0, cond.second_photodiode_time));
                
                if cond.second_photodiode
                    % display black photodiode rectangle during the pre-blank
                    rectSize = [0.05 0.06].*self.rect(3:4);
                    rect = [self.rect(3)-rectSize(1), 0, self.rect(3), rectSize(2)];
                    color = (cond.second_photodiode+1)/2*255;
                    Screen('FillRect', self.win, color, rect);
                    if cond.second_photodiode_time < 0
                        self.screen.flip(true, false, true)
                    end
                end                
                WaitSecs(max(0, -cond.second_photodiode_time));
            end
            
            % update direction to correspond to 0=north, 90=east, 180=south, 270=west
            direction = cond.direction + 90;
                        
            % display drifting grating
            driftFrames1 = floor(cond.trial_duration * (1-cond.phase2_fraction) * self.screen.fps);
            driftFrames2 = floor(cond.trial_duration * cond.phase2_fraction * self.screen.fps);
            phaseIncrement1 = cond.temp_freq/self.screen.fps;
            phaseIncrement2 = cond.phase2_temp_freq/self.screen.fps;
            offset = [cond.aperture_x cond.aperture_y]*norm(self.rect(3:4))/2;
            destRect = self.rect + [offset offset];
            
            % display phase1 grating
            for frame = 1:driftFrames1
                if self.screen.escape, break, end
                Screen('DrawTexture', self.win, self.grating, [], destRect, direction, [], [], [], [], ...
                    kPsychUseTextureMatrixForRotation, [phase*360, freq, 0.495, 0]);
                if ~isempty(self.mask)
                    Screen('DrawTexture', self.win, self.mask);
                end
                if cond.second_photodiode
                    rectSize = [0.05 0.06].*self.rect(3:4);
                    rect = [self.rect(3)-rectSize(1), 0, self.rect(3), rectSize(2)];
                    if frame/self.screen.fps >= cond.second_photodiode_time
                        color = (cond.second_photodiode+1)/2*255;
                        Screen('FillRect', self.win, color, rect);
                    else
                        Screen('FillRect', self.win, 0, rect);
                    end
                end
                phase = phase + phaseIncrement1;
                self.screen.flip(false, false, frame==1)
            end
            
            % display phase2 grating
            for frame = 1:driftFrames2
                if self.screen.escape, break, end
                Screen('DrawTexture', self.win, self.grating, [], destRect, direction, [], [], [], [], ...
                    kPsychUseTextureMatrixForRotation, [phase*360, freq, 0.495, 0]);
                if ~isempty(self.mask)
                    Screen('DrawTexture', self.win, self.mask);
                end
                phase = phase + phaseIncrement2;
                self.screen.flip(false, false, frame==1)
            end
        end
    end
end