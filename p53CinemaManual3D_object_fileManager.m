%%
%
classdef p53CinemaManual3D_object_fileManager < handle
    properties
        gui_fileManager;
        master;
        
        database;
        mainpath;
        databaseFilename;
        rawdatapath;
        
        selectedGroup;
        selectedPosition;
        selectedChannel;
        maximaChannel;
        
        currentImageTimepoints;
        numImages;
        numZ;
        min_z;
        max_z;
        maxTimepoint;
        timepointRange;
        
        preallocateMode;
        preprocessMode;
        
        imageResizeFactor;
        cellSize;
        maxHeight;
        
        additionalAnnotation;
        additionalAnnotationNumeric;
    end
    events
        
    end
    methods
        %% Constructor
        function obj = p53CinemaManual3D_object_fileManager(master)
            obj.gui_fileManager = p53CinemaManual3D_gui_fileManager(master);
            obj.master = master;
        end
        
        %% Set variables
        function setDatabase(obj, database)
            obj.database = database;
            obj.master.data.database = database;
            obj.numZ = max(obj.database.z);
            obj.min_z = min(obj.database.z);
            obj.max_z = obj.numZ;
        end
        function setRawDataPath(obj, rawdatapath)
            obj.rawdatapath = rawdatapath;
            obj.master.data.imagepath = rawdatapath;
        end
        function setSelectedGroup(obj, selectedGroup)
            obj.selectedGroup = selectedGroup;
        end
        function setSelectedPosition(obj, selectedPosition)
            obj.selectedPosition = selectedPosition;
        end
        function setSelectedChannel(obj, selectedChannel)
            obj.selectedChannel = selectedChannel;
        end
        function setMaximaChannel(obj, selectedChannel)
            obj.maximaChannel = selectedChannel;
        end
        function setPreprocessMode(obj, value)
            obj.preprocessMode = value;
        end
        function setPreallocateMode(obj, value)
            obj.preallocateMode = value;
        end
        function setImageResize(obj, value)
            obj.imageResizeFactor = value;
        end
        function setCellSize(obj, value)
            obj.cellSize = value;
        end
        function setMaxHeight(obj, value)
            obj.maxHeight = value;
        end
        
        function setProgressBar(obj, value, maxValue, message)
            handles = guidata(obj.master.obj_fileManager.gui_fileManager);
            set(handles.hprogressbarhandleLoadingBar, 'Maximum', maxValue);
            set(handles.hprogressbarhandleLoadingBar, 'Value', value);
            set(handles.htextLoadingBar, 'String', message);
        end
        
        function setTimepointRange(obj, from, to, by)
            from = str2double(from);
            to = str2double(to);
            by = str2double(by);
            from = floor(max(1, from));
            to = floor(min(max(obj.database.timepoint), to));
            by = ceil(by);
            obj.timepointRange = [from, to, by];
        end
        
        %% Generate image sequence
        function generateImageSequence(obj)
            if(~iscell(obj.database.channel_name))
                channel_filter = obj.database.channel_name == str2double(obj.selectedChannel);
            else
                channel_filter = strcmp(obj.database.channel_name, obj.selectedChannel);
            end
            example_z = obj.min_z;
            timepoint_filter = ismember(obj.database.timepoint, obj.timepointRange(1):obj.timepointRange(3):obj.timepointRange(2));
            z_filter = obj.database.z == example_z;
            group_filter = strcmp(obj.database.group_label, obj.selectedGroup);
            position_filter = obj.database.position_number == obj.selectedPosition;
            relevantImageIndex = group_filter & channel_filter & timepoint_filter & position_filter & z_filter;
            
            obj.currentImageTimepoints = obj.database.timepoint(relevantImageIndex);
            [~, orderIndex] = sort(obj.currentImageTimepoints);
                        
            obj.currentImageTimepoints = obj.currentImageTimepoints(orderIndex);
            obj.maxTimepoint = max(obj.database.timepoint(strcmp(obj.database.group_label, obj.selectedGroup) & obj.database.position_number == obj.selectedPosition));
            obj.numImages = length(obj.currentImageTimepoints);
        end
        
        function [filename, z_index] = getFilename(obj, position, channel, timepoint, z)
            [filename, z_index] = getDatabaseFile_z(obj.database, obj.selectedGroup, channel, position, timepoint, z);
        end
        
        %% Delete function
        function delete(obj)
            delete(obj.gui_fileManager);
        end
    end
end