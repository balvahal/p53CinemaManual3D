%% p53Cinema Data in source object
% The data captured in a set of images is used to create many data features
% including the signal traces of a cell, spatial tracking information, and
% in silico temporal based synchronization. A source object will contain
% all the data extracted from a set of images in format that is most
% convenient with the method used to generate the data. From the source
% object, derivative data organization or presentation schemes can be
% derived that make the data convenient to interact with.
classdef p53CinemaManual3D_object_imageViewer < handle
    properties
        gui_imageViewer;
        gui_contrast;
        gui_zoomMap;
        obj_cellTracker;
        master;
        
        isMyButtonDown = false;
        shift_ON = 0;
        
        imageOrigin;
        displaySize;
        
        image_width;
        image_height;
        image_widthChar;
        image_heightChar;
        
        imageBuffer;
        currentImage;
        currentTimepoint;
        currentZ;
        currentChannel;
        currentFrame = 1;
        pixelRowCol;
        pixelxy;
        imageResizeFactor;
        normalizationFactor;
        
        selectedCell;
        potentialMergeCell;
        
        contrastHistogram;
        
        zoomArray = [1, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1];
        zoomIndex = 1;
        display_resolution;
        buffer_resolution;
    end
    events
        
    end
    methods
        %% object constructor
        %
        function obj = p53CinemaManual3D_object_imageViewer(master)
            obj.master = master;
            fileManagerHandles = guidata(obj.master.obj_fileManager.gui_fileManager);
            obj.currentChannel = master.obj_fileManager.selectedChannel;
            %% get image info from first image
            %
            IM = imread(fullfile(obj.master.obj_fileManager.rawdatapath,obj.master.obj_fileManager.database.filename{1}));
            obj.imageResizeFactor = obj.master.obj_fileManager.imageResizeFactor;
            IM = imresize(IM, obj.imageResizeFactor);
            obj.image_width = size(IM,2);
            obj.image_height = size(IM,1);
            obj.image_widthChar = obj.image_width/master.ppChar(1);
            obj.image_heightChar = obj.image_height/master.ppChar(2);
            obj.obj_cellTracker = p53CinemaManual3D_object_cellTracker(master);
            %% Preload images
            %
            
            % Read an image in the center of the sequence to determine
            % normalization factor
            referenceImage = imresize(obj.readImage(round(obj.master.obj_fileManager.numImages), 1), obj.imageResizeFactor);
            obj.normalizationFactor = double(quantile(referenceImage(:), 1));
            
            % Check if the preprocessing mode is 'Prediction'. If so,
            % import corresponding mat file in the prediction folder
            predictionMode = getCurrentPopupString(fileManagerHandles.hpopupPredictionMode);
            obj.buffer_resolution = 'uint8';
            obj.display_resolution = 8;
            
            obj.selectedCell = 0;
            obj.potentialMergeCell = 0;
            obj.currentZ = obj.master.obj_fileManager.min_z;
            obj.currentChannel = obj.master.obj_fileManager.selectedChannel;
            
            if(~obj.master.obj_fileManager.preallocateMode && ~obj.master.obj_fileManager.preprocessMode)
                return
            end
            
            if(strcmp(predictionMode, 'Prediction'))
                load(fullfile('Prediction', sprintf('wellsss_s%d.mat', obj.master.obj_fileManager.selectedPosition)));
            end
            if(strcmp(predictionMode, 'Precomputed'))
                load(fullfile('Precomputed', sprintf('%s_s%d_centroidsLocalMaxima.mat', obj.master.obj_fileManager.selectedGroup, obj.master.obj_fileManager.selectedPosition)));
            end
            
            obj.master.obj_fileManager.setProgressBar(1,obj.master.obj_fileManager.numImages,'Loading status');
            
            if(obj.master.obj_fileManager.preallocateMode)
                obj.imageBuffer = cast(zeros(obj.image_height, obj.image_width, obj.master.obj_fileManager.numImages, obj.master.obj_fileManager.numZ), obj.buffer_resolution);
            end
            maxPossibleValue = 2^obj.display_resolution - 1;
            
            for i=1:obj.master.obj_fileManager.numImages
                for j=obj.master.obj_fileManager.min_z:obj.master.obj_fileManager.numZ
                    
                    obj.master.obj_fileManager.setProgressBar(i,obj.master.obj_fileManager.numImages*obj.master.obj_fileManager.numZ,'Loading status');
                    
                    if(obj.master.obj_fileManager.preallocateMode || (obj.master.obj_fileManager.preprocessMode && ~strcmp(predictionMode, 'Precomputed')))
                        OriginalImage = imresize(obj.readImage(i,j), obj.imageResizeFactor);
                        
                        if(get(fileManagerHandles.hcheckboxPrimaryBackground, 'Value'))
                            referenceImage = imbackground(OriginalImage, 10, 100);
                            referenceImage = double(referenceImage) / obj.normalizationFactor;
                            referenceImage = medfilt2(referenceImage, [2,2]);
                        end
                        if(obj.master.obj_fileManager.preallocateMode)
                            obj.imageBuffer(:,:,i,j) = cast(double(OriginalImage) / obj.normalizationFactor * maxPossibleValue, obj.buffer_resolution);
                        end
                    end
                    % Preprocess and find local maxima
                    if(obj.master.obj_fileManager.preprocessMode)
                        timepoint = obj.master.obj_fileManager.currentImageTimepoints(i);
                        if(~strcmp(obj.master.obj_fileManager.maximaChannel, obj.master.obj_fileManager.selectedChannel))
                            referenceImage = obj.readImageChannel(i,j,master.obj_fileManager.maximaChannel);
                            referenceImage = medfilt2(referenceImage, [3,3]);
                            referenceImage = imbackground(referenceImage, 10, 100);
                            referenceImage = imresize(referenceImage, obj.imageResizeFactor);
                        end
                        
                        % Get preprocess mode
                        switch predictionMode
                            case 'Intensity'
                                localMaxima = getImageMaxima_Intensity(referenceImage, obj.master.obj_fileManager.cellSize);
                            case 'Shape'
                                localMaxima = getImageMaxima_Shape(referenceImage, obj.master.obj_fileManager.cellSize);
                            case 'Prediction'
                                localMaxima = fliplr(round(wellsss{timepoint}(:,1:2))* obj.imageResizeFactor);
                            case 'Precomputed'
                                localMaxima = centroidsLocalMaxima{j}.getCentroids(i);
                        end
                        
                        if(~isempty(localMaxima))
                            obj.obj_cellTracker.centroidsLocalMaxima{j}.insertCentroids(timepoint, localMaxima);
                        end
                    end
                end
            end
            
            obj.master.obj_fileManager.setProgressBar(0,obj.master.obj_fileManager.numImages,'Loading status');
            
        end
        %% getPixelxy
        % Find the location of mouse relative to the image in the viewer.
        % This function takes into account that the axes YDir is reversed
        % and that the point on the disply may not be 1:1 with the pixels
        % of the image.
        function out = getPixelxy(obj)
            myCurrentPoint = get(obj.gui_imageViewer,'CurrentPoint');
            handles = guidata(obj.gui_imageViewer);
            axesOrigin = get(handles.axesImageViewer,'Position');
            myRelativePoint = myCurrentPoint - axesOrigin([1,2]);
            if any(myRelativePoint<0) || ...
                    myRelativePoint(1) > axesOrigin(3) || ...
                    myRelativePoint(2) > axesOrigin(4)
                obj.pixelxy = [];
                obj.pixelRowCol = [];
            else
                myXLim = get(handles.axesImageViewer,'XLim');
                myYLim = get(handles.axesImageViewer,'YLim');
                
                x = myRelativePoint(1)/axesOrigin(3)*(myXLim(2)-myXLim(1))+myXLim(1);
                y = (axesOrigin(4)-myRelativePoint(2))/axesOrigin(4)*(myYLim(2)-myYLim(1))+myYLim(1);

                obj.pixelxy = [x,y];
                obj.pixelxy = ceil(obj.pixelxy);
                obj.pixelRowCol = fliplr(obj.pixelxy);
                
            end
            out = obj.pixelxy;
        end
        %% getPixelRowCol
        % Find the location of mouse relative to the image in the viewer.
        % This function takes into account that the axes YDir is reversed
        % and that the point on the disply may not be 1:1 with the pixels
        % of the image.
        function out = getPixelRowCol(obj)
            myCurrentPoint = get(obj.gui_imageViewer,'CurrentPoint');
            handles = guidata(obj.gui_imageViewer);
            axesOrigin = get(handles.axesImageViewer,'Position');
            myRelativePoint = myCurrentPoint - axesOrigin([1,2]);
            if any(myRelativePoint<0) || ...
                    myRelativePoint(1) > axesOrigin(3) || ...
                    myRelativePoint(2) > axesOrigin(4)
                obj.pixelRowCol = [];
                obj.pixelxy = [];
            else
                myXLim = get(handles.axesImageViewer,'XLim');
                myYLim = get(handles.axesImageViewer,'YLim');
                
                x = myRelativePoint(1)/axesOrigin(3)*(myXLim(2)-myXLim(1))+myXLim(1);
                y = (axesOrigin(4)-myRelativePoint(2))/axesOrigin(4)*(myYLim(2)-myYLim(1))+myYLim(1);
                obj.pixelRowCol = [y,x];
                obj.pixelRowCol = ceil(obj.pixelRowCol);
                obj.pixelxy = fliplr(obj.pixelRowCol);
                
            end
            out = obj.pixelRowCol;
        end
        
        %% Autocontrast
        %
        function obj = autoContrast(obj)
            maxPossibleValue = 2^obj.display_resolution - 1;
            handles = guidata(obj.gui_contrast);
            if(obj.master.obj_fileManager.preallocateMode)
                randomSample = obj.imageBuffer(ceil(rand(1,10000) * (size(obj.imageBuffer,1) * size(obj.imageBuffer,2) - 1) + 1));
                minValue = min(randomSample(randomSample > quantile(randomSample, 0.01)));
                maxValue = max(randomSample(randomSample < quantile(randomSample(:), 0.99999)));
            else
                minValue = min(obj.currentImage(:));
                maxValue = max(obj.currentImage(:));
            end
            set(handles.sliderMin,'Value', double(minValue)/maxPossibleValue);
            set(handles.sliderMax,'Value', double(maxValue)/maxPossibleValue);
            obj.newColormapFromContrastHistogram;
        end

        %% resetContrast
        % Set the contrast to reflect the full uint8 range, i.e. 0-255.
        function obj = resetContrast(obj)
            handles = guidata(obj.gui_imageViewer);
            colormap(handles.axesImageViewer,gray(255));
        end
        %% findImageHistogram
        % Assumes image is uint8 0-255.
        function obj = findImageHistogram(obj)
            maxPossibleValue = 2^obj.display_resolution - 1;
            obj.contrastHistogram = hist(reshape(obj.currentImage,1,[]),-0.5:1:(maxPossibleValue + 0.5));
        end
        %% newColormapFromContrastHistogram
        % Assumes image is uint8 0-255.
        function obj = newColormapFromContrastHistogram(obj)
            maxPossibleValue = 2^obj.display_resolution - 1;
            
            handles = guidata(obj.gui_contrast);

            sstep = get(handles.sliderMin,'SliderStep');
            mymin = ceil(get(handles.sliderMin,'Value')/sstep(1));
            mymax = ceil(get(handles.sliderMax,'Value')/sstep(1));
            cmap = colormap(gray(mymax-mymin+1));
            cmap = vertcat(zeros(mymin,3),cmap,ones(maxPossibleValue-mymax,3));
            handles2 = guidata(obj.gui_imageViewer);
            colormap(handles2.axesImageViewer,cmap);
            handles3 = guidata(obj.gui_zoomMap);
            colormap(handles3.axesZoomMap,cmap);
        end
        %% findImageHistogram
        % Assumes image is uint8 0-255.
        function obj = updateContrastHistogram(obj)
            obj.findImageHistogram;
            handles = guidata(obj.gui_contrast);
            plot(handles.axesContrast,log(obj.contrastHistogram+1));
        end
        %% launchImageViewer
        % A indiosyncrasy of using an object wrapper for guis is that the
        % object must be constructed before the guis can have access to its
        % properties. Therefore this method should be called immediately
        % following the construction of the object.
        function obj = launchImageViewer(obj)
            %% Launch the gui
            %
            obj.gui_imageViewer = p53CinemaManual3D_gui_imageViewer(obj.master, obj.master.obj_fileManager.maxHeight);
            obj.gui_contrast = p53CinemaManual_gui_contrast(obj.master);
            obj.gui_zoomMap = p53CinemaManual_gui_zoomMap(obj.master);
            obj.setFrame(1, 1);
            obj.autoContrast;
        end
        
        function newFrame = validateFrame(obj, frame)
            newFrame = min(max(frame,1), obj.master.obj_fileManager.numImages);
        end
        
        function tracked_z = getSelectedCellZ(obj, frame)
            frame = obj.validateFrame(frame);
            selected_cell = obj.selectedCell;
            if(selected_cell > 0)
                nextTimepoint = obj.master.obj_fileManager.currentImageTimepoints(frame);
                my_z = obj.obj_cellTracker.centroidsTracks.getZ(nextTimepoint, selected_cell);
            else
                my_z = 0;
            end
            if(my_z > 0 && ~obj.obj_cellTracker.isTracking)
                tracked_z = my_z;
            else
                tracked_z = obj.currentZ;
            end
        end
        
        %% Frame switching functions
        function setFrame(obj, frame, z)
            previousFrame = obj.currentFrame;
            previousTimepoint = obj.currentTimepoint;
            previousZ = obj.currentZ;
            
            frame = obj.validateFrame(frame);
            z = min(max(z,obj.master.obj_fileManager.min_z), obj.master.obj_fileManager.max_z);
                        
            obj.currentFrame = frame;
            obj.currentTimepoint = obj.master.obj_fileManager.currentImageTimepoints(frame);
            obj.currentZ = z;
            
            imageViewerHandles = guidata(obj.gui_imageViewer);
            set(imageViewerHandles.htextFrameNumber, 'String', ['Timepoint:', num2str(obj.currentTimepoint), '/', num2str(obj.master.obj_fileManager.maxTimepoint), ', Z:', num2str(obj.currentZ), '/', num2str(obj.master.obj_fileManager.numZ)]);
            
            sliderStep = get(imageViewerHandles.hsliderExploreStack,'SliderStep');
            if(length(obj.master.obj_fileManager.currentImageTimepoints) > 1)
                set(imageViewerHandles.hsliderExploreStack,'Value',sliderStep(1)*(obj.currentFrame-1));
            end
            
            sliderStep = get(imageViewerHandles.hsliderExploreZ,'SliderStep');
            if(obj.master.obj_fileManager.numZ > 1)
                set(imageViewerHandles.hsliderExploreZ,'Value',sliderStep(1)*(obj.currentZ-1));
            end
            
            if(obj.master.obj_fileManager.preallocateMode && strcmp(obj.master.obj_fileManager.selectedChannel, obj.currentChannel))
                obj.currentImage = obj.imageBuffer(:,:,frame,z);
            else
                maxPossibleValue = 2^obj.display_resolution - 1;
                IM = obj.readImage(frame, z);
                if(~isempty(IM))
                    IM = imresize(IM, obj.imageResizeFactor);
                    %IM = imnormalize_quantile(IM, 1) * maxPossibleValue;
                    IM = double(IM) / obj.normalizationFactor * maxPossibleValue;
                    if(get(imageViewerHandles.hcheckboxPreprocessFrame, 'Value'))
                        IM = medfilt2(IM, [3,3]);
                        IM = imbackground(IM, 10, 100);
                        IM = cast(IM, obj.buffer_resolution);
                    end
                    obj.currentImage = IM;
                end
            end
            
            % Predictive tracking
            if(obj.master.obj_fileManager.preprocessMode && obj.obj_cellTracker.isTracking && obj.selectedCell && ~obj.obj_cellTracker.centroidsTracks.getValue(obj.currentTimepoint, obj.selectedCell))
                previousCentroid = obj.obj_cellTracker.centroidsTracks.getCentroid(previousTimepoint, obj.selectedCell);
                                
                % Check centroids that are occupied in the current frame.
                % This is agnostic of the current z position. 
                % TO DO: In the future, it may be a good idea to exclude centroids within
                % the range of the current occupied centroids in all
                % z-slices
                [occupiedCentroids, occupied_id, occupiedZ] = obj.obj_cellTracker.centroidsTracks.getCentroids(obj.currentTimepoint);
                subset_occupied_centroids = occupied_id ~= obj.selectedCell;
                occupiedCentroids = occupiedCentroids(subset_occupied_centroids,:);
                occupiedZ = occupiedZ(subset_occupied_centroids);
                
                referenceTimepoint = previousTimepoint;               
                referenceCentroid = obj.obj_cellTracker.centroidsTracks.getCentroid(referenceTimepoint, obj.selectedCell);
                [predictedCentroids, ~, distance] = obj.obj_cellTracker.centroidsLocalMaxima{obj.currentZ}.getCentroidsInRange(obj.currentTimepoint, referenceCentroid, obj.obj_cellTracker.getDistanceRadius);
                if(~isempty(predictedCentroids))
                    if(~isempty(occupiedCentroids))
                        notOccupied = ~ismember(predictedCentroids, occupiedCentroids, 'rows');
                        predictedCentroids = predictedCentroids(notOccupied,:);
                        distance = distance(notOccupied);
                    end
                    closestCentroidIndex = find(distance == min(distance), 1, 'first');
                    prediction1 = predictedCentroids(closestCentroidIndex,:);
                    d1 = distance(closestCentroidIndex);
                    obj.obj_cellTracker.centroidsTracks.setCentroid(obj.currentTimepoint, obj.selectedCell, prediction1, 0, obj.currentZ);
                end
            end
            
            handlesZoomMap = guidata(obj.gui_zoomMap);

            set(imageViewerHandles.sourceImage,'CData',obj.currentImage);
            set(handlesZoomMap.sourceImage,'CData',obj.currentImage);

            obj.setImage;
            %obj.autoContrast;
        end
        
        function nextFrame(obj)
            newFrame = obj.validateFrame(obj.currentFrame + 1);
            newZ = obj.getSelectedCellZ(newFrame);
            obj.setFrame(newFrame, newZ);
            obj.setImage;
        end
        
        function previousFrame(obj)
            newFrame = obj.validateFrame(obj.currentFrame - 1);
            newZ = obj.getSelectedCellZ(newFrame);
            obj.setFrame(newFrame, newZ);
            obj.setImage;
        end
        
        function nextZ(obj)
            obj.setFrame(obj.currentFrame, obj.currentZ + 1);
            obj.setImage;
        end
        
        function previousZ(obj)
            obj.setFrame(obj.currentFrame, obj.currentZ - 1);
            obj.setImage;
        end
        
        function setSelectedCell(obj, selectedCell)
            obj.selectedCell = selectedCell;
        end
        
        function deleteSelectedCellTrack(obj)
            obj.obj_cellTracker.deleteCellData(obj.selectedCell);
            obj.setSelectedCell(0);
            obj.obj_cellTracker.setAvailableCells;
            obj.obj_cellTracker.firstClick = 1;
            obj.setImage;
        end

        function deleteSelectedCellForward(obj)
            obj.obj_cellTracker.deleteCellTimepoints(obj.selectedCell, obj.currentTimepoint:max(obj.master.obj_fileManager.currentImageTimepoints));
            obj.setImage;
        end
        
        function deleteSelectedCellBackwards(obj)
            obj.obj_cellTracker.deleteCellTimepoints(obj.selectedCell, min(obj.master.obj_fileManager.currentImageTimepoints):obj.currentTimepoint);
            obj.setImage;
        end
       
        %% Image manipulation
        function IM = readImage(obj, frame, z)
            IM = obj.readImageChannel(frame, z, obj.master.obj_fileManager.selectedChannel);
        end
        
        function IM = readImageChannel(obj, frame, z, channel_name)
            fileManager = obj.master.obj_fileManager;
            timepoint = fileManager.currentImageTimepoints(frame);
            [targetFile, z_index] = fileManager.getFilename(fileManager.selectedPosition, channel_name, timepoint, z);
            fname = fullfile(fileManager.rawdatapath,targetFile);
            IM = imread(fname, z_index);
        end
        
        function setImage(obj)
            pause(0.001);
            handles = guidata(obj.gui_imageViewer);
            cellTrackerHandles = guidata(obj.obj_cellTracker.gui_cellTracker);

            set(handles.currentCellTrace, 'xdata', [], 'ydata', []);
            
            % Set tracked centroids patch
            [trackedCentroids, currentFrameCentroids] = obj.obj_cellTracker.centroidsTracks.getCentroids(obj.currentTimepoint);
            tracked_Zs = obj.obj_cellTracker.centroidsTracks.getZs(obj.currentTimepoint);
            validCentroids = tracked_Zs == obj.currentZ;
            
            maxTimepoint = obj.currentTimepoint;
            [~, maxTimepointCentroids] = obj.obj_cellTracker.centroidsTracks.getCentroids(maxTimepoint);
            set(handles.trackedCellsPatch, 'XData', trackedCentroids(ismember(currentFrameCentroids, maxTimepointCentroids),2), 'YData', trackedCentroids(ismember(currentFrameCentroids, maxTimepointCentroids),1));
                                   
            % Set the completed centroids patch
            [~, firstFrameCentroids] = obj.obj_cellTracker.centroidsTracks.getCentroids(min(obj.master.obj_fileManager.currentImageTimepoints));
            [~, lastFrameCentroids] = obj.obj_cellTracker.centroidsTracks.getCentroids(max(obj.master.obj_fileManager.currentImageTimepoints));
            completedCells = ismember(currentFrameCentroids, intersect(firstFrameCentroids, lastFrameCentroids));
            set(handles.completeCellsPatch, 'XData', trackedCentroids(completedCells,2), 'YData', trackedCentroids(completedCells,1));
            
            if(obj.master.obj_fileManager.preprocessMode)
                lookupRadius = obj.obj_cellTracker.getDistanceRadius;
                currentPoint = obj.pixelxy;
                if(~isempty(currentPoint))
                    highlightedCentroids = obj.obj_cellTracker.centroidsLocalMaxima{obj.currentZ}.getCentroidsInRange(obj.currentTimepoint, fliplr(currentPoint), lookupRadius);
                    if(~isempty(highlightedCentroids))
                        set(handles.cellsInRangePatch, 'XData', highlightedCentroids(:,2), 'YData', highlightedCentroids(:,1));
                    end
                    closestCentroid = obj.obj_cellTracker.centroidsLocalMaxima{obj.currentZ}.getClosestCentroid(obj.currentTimepoint, fliplr(currentPoint), lookupRadius);
                    set(handles.closestCellPatch, 'XData', closestCentroid(:,2), 'YData', closestCentroid(:,1));
                end
            end
            
            % Set division event patch
            [divisionCentroids, dividingCells] = obj.obj_cellTracker.centroidsDivisions.getCentroids(obj.currentTimepoint);
            [deathCentroids, dyingCells] = obj.obj_cellTracker.centroidsDeath.getCentroids(obj.currentTimepoint);
            set(handles.divisionEventPatch, 'XData', divisionCentroids(:,2), 'YData', divisionCentroids(:,1));
            set(handles.deathEventPatch, 'XData', deathCentroids(:,2), 'YData', deathCentroids(:,1));

            cellFateEventPatch = handles.cellFateEventPatch;
            for i=1:length(cellFateEventPatch)
                [~, cellFateIndexes] = obj.obj_cellTracker.centroidsTracks.getAnnotations(obj.currentTimepoint, i);
                set(handles.cellFateEventPatch(i), 'XData', trackedCentroids(ismember(currentFrameCentroids, cellFateIndexes),2), 'YData', trackedCentroids(ismember(currentFrameCentroids, cellFateIndexes),1));
            end
            
            if(obj.selectedCell == 0)
                return;
            end
            
            currentCentroid = obj.obj_cellTracker.centroidsDivisions.getCentroid(obj.currentTimepoint, obj.selectedCell);
            if(ismember(currentCentroid, trackedCentroids(ismember(currentFrameCentroids,dividingCells),:), 'rows'))
                set(cellTrackerHandles.trackSisterPushbutton, 'Enable', 'on');
            else
                set(cellTrackerHandles.trackSisterPushbutton, 'Enable', 'off');
            end
            
            % Set sister cell path
            set(handles.sisterCellPatch, 'XData', [], 'YData', []);
            if(~isempty(dividingCells))
                divisionCentroids = trackedCentroids(ismember(currentFrameCentroids, dividingCells),:);
                [uniqueDivisions, ~, indexes] = unique(divisionCentroids, 'rows');
                centroidFreq = tabulate(indexes);
                repeatedDivisions = uniqueDivisions(centroidFreq(centroidFreq(:,2) == 2,1),:);
                if(~isempty(repeatedDivisions))
                    set(handles.sisterCellPatch, 'XData', repeatedDivisions(:,2), 'YData', repeatedDivisions(:,1));
                    if(ismember(currentCentroid, repeatedDivisions))
                        set(cellTrackerHandles.trackSisterPushbutton, 'Enable', 'off');
                    end
                end
            end
            
            if(obj.selectedCell)
                % Set selected cell patch
                selectedCentroid = obj.obj_cellTracker.centroidsTracks.getCentroid(obj.currentTimepoint, obj.selectedCell);
                selectedZ = obj.obj_cellTracker.centroidsTracks.getZ(obj.currentTimepoint, obj.selectedCell);
                if(selectedZ == obj.currentZ)
                    set(handles.selectedCellPatch, 'XData', selectedCentroid(:,2), 'YData', selectedCentroid(:,1));
                else
                    set(handles.selectedCellPatch, 'XData', [], 'YData', []);
                end
                if(selectedCentroid(1) > 0 && get(cellTrackerHandles.hcheckboxAutoCenter, 'Value'))
                    obj.zoomRecenter(selectedCentroid);
                end
                
                dividingCell = any(obj.obj_cellTracker.centroidsDivisions.getCentroid(obj.currentTimepoint, obj.selectedCell) > 0);
                deathCell = any(obj.obj_cellTracker.centroidsDeath.getCentroid(obj.currentTimepoint, obj.selectedCell) > 0);
                
                currentTrack = obj.obj_cellTracker.centroidsTracks.getCellTrack(obj.selectedCell);
                % Show active track
                if(get(handles.hcheckboxShowTrack, 'Value'))
                    set(handles.currentCellTrace, 'xdata', currentTrack(currentTrack(:,2) > 0,2), 'ydata', currentTrack(currentTrack(:,2) > 0,1));
                end
                if(sum(obj.obj_cellTracker.centroidsTracks.getCentroid(obj.currentTimepoint, obj.selectedCell) == 0) > 0)
                    set(handles.currentCellTrace, 'color', 'green');
                else
                    set(handles.currentCellTrace, 'color', 'red');
                end
                
                currentTrackLength = sum(currentTrack(:,1) > 0);
                if(currentTrackLength >= 3 && any(selectedCentroid > 0))
                    obj.obj_cellTracker.setEnableSplit('on');
                else
                    obj.obj_cellTracker.setEnableSplit('off');
                end
                
                % Reset potential merge prompts
                set(handles.mergeEventPatch, 'XData', [], 'YData', []);
                obj.obj_cellTracker.setEnableMerge('off');
                obj.potentialMergeCell = 0;
                set(handles.neighborCellTrace, 'xdata', [], 'ydata', []);
                % Try to find potential neighbors to merge to selected cell
                if(~dividingCell && ~deathCell)
                    [neighborCentroid, neighborCell, distance] = obj.obj_cellTracker.centroidsTracks.getCentroidsInRange(obj.currentTimepoint, selectedCentroid, 3);
                    targetNeighbor = find(neighborCell ~= obj.selectedCell);
                    
                    if(~isempty(targetNeighbor))
                        closestNeighbor = find(distance(targetNeighbor) == min(distance(targetNeighbor)), 1, 'first');
                        neighborCentroid = neighborCentroid(targetNeighbor(closestNeighbor),:); 
                        neighborCell = neighborCell(targetNeighbor(closestNeighbor));
                        
                        dividingCell = any(obj.obj_cellTracker.centroidsDivisions.getCentroid(obj.currentTimepoint, neighborCell) > 0);
                        deathCell = any(obj.obj_cellTracker.centroidsDeath.getCentroid(obj.currentTimepoint, neighborCell) > 0);

                        if(~dividingCell && ~deathCell)
                            set(handles.mergeEventPatch, 'XData', [neighborCentroid(:,2), selectedCentroid(:,2)], 'YData', [neighborCentroid(:,1), selectedCentroid(:,1)]);
                            % Set potential link and activate merge button
                            obj.obj_cellTracker.setEnableMerge('on');
                            obj.potentialMergeCell = neighborCell;
                            neighborTrack = obj.obj_cellTracker.centroidsTracks.getCellTrack(neighborCell);
                            %set(handles.neighborCellTrace, 'xdata', neighborTrack(neighborTrack(:,2) > 0,2), 'ydata', neighborTrack(neighborTrack(:,2) > 0,1));
                            set(handles.neighborCellTrace, 'xdata', [], 'ydata', []);
                        end
                    end
                end
            end            
        end
        
        %%
        %
        function obj = zoomIn(obj)
            if obj.zoomIndex < length(obj.zoomArray)
                obj.zoomIndex = obj.zoomIndex + 1;
            else
                return
            end
            %%
            % get the patch position
            newHalfWidth = obj.image_width*obj.zoomArray(obj.zoomIndex)/2;
            newHalfHeight = obj.image_height*obj.zoomArray(obj.zoomIndex)/2;
            handles = guidata(obj.gui_zoomMap);
            set(handles.zoomMapRect,'Visible','off');
            myVertices = get(handles.zoomMapRect,'Vertices');
            myCenter = (myVertices(3,:)-myVertices(1,:))/2+myVertices(1,:);
            myVertices(1,:) = round(myCenter + [-newHalfWidth,-newHalfHeight]);
            myVertices(2,:) = round(myCenter + [newHalfWidth,-newHalfHeight]);
            myVertices(3,:) = round(myCenter + [newHalfWidth,newHalfHeight]);
            myVertices(4,:) = round(myCenter + [-newHalfWidth,newHalfHeight]);
            set(handles.zoomMapRect,'Vertices',myVertices);
            set(handles.zoomMapRect,'Visible','on');
            obj.zoomPan;
        end
        %%
        %
        function obj = zoomOut(obj)
            if obj.zoomIndex > 2
                obj.zoomIndex = obj.zoomIndex - 1;
            elseif obj.zoomIndex == 2
                obj.zoomTop;
                return
            else
                return
            end
            %%
            % get the patch position
            newHalfWidth = obj.image_width*obj.zoomArray(obj.zoomIndex)/2;
            newHalfHeight = obj.image_height*obj.zoomArray(obj.zoomIndex)/2;
            handles = guidata(obj.gui_zoomMap);
            set(handles.zoomMapRect,'Visible','off');
            myVertices = get(handles.zoomMapRect,'Vertices');
            myCenter = (myVertices(3,:)-myVertices(1,:))/2+myVertices(1,:);
            %%
            % make sure the center does not move the rectangle |off screen|
            if myCenter(1) - newHalfWidth < 1
                myCenter(1) = newHalfWidth + 1;
            elseif myCenter(1) + newHalfWidth > obj.image_width
                myCenter(1) = obj.image_width - newHalfWidth;
            end
            
            if myCenter(2) - newHalfHeight < 1
                myCenter(2) = newHalfHeight + 1;
            elseif myCenter(2) + newHalfHeight > obj.image_height
                myCenter(2) = obj.image_height - newHalfHeight;
            end
            
            myVertices(1,:) = round(myCenter + [-newHalfWidth,-newHalfHeight]);
            myVertices(2,:) = round(myCenter + [newHalfWidth,-newHalfHeight]);
            myVertices(3,:) = round(myCenter + [newHalfWidth,newHalfHeight]);
            myVertices(4,:) = round(myCenter + [-newHalfWidth,newHalfHeight]);
            set(handles.zoomMapRect,'Vertices',myVertices);
            set(handles.zoomMapRect,'Visible','on');
            obj.zoomPan;
        end
        %%
        %
        function obj = zoomTop(obj)
            obj.zoomIndex = 1;
            handles = guidata(obj.gui_zoomMap);
            set(handles.zoomMapRect,'Visible','off');
            set(handles.zoomMapRect,'Vertices',[1, 1;obj.image_width, 1;obj.image_width, obj.image_height;1, obj.image_height])
            obj.zoomPan;
        end
        %%
        %
        function obj = zoomPan(obj)
            % Adjust the imageViewer limits to reflect the zoomMapRect
            % position
            handles = guidata(obj.gui_zoomMap);
            myVertices = get(handles.zoomMapRect,'Vertices');
            handles2 = guidata(obj.gui_imageViewer);
            newXLim = [myVertices(1,1)-0.5,myVertices(3,1)+0.5];
            newYLim = [myVertices(1,2)-0.5,myVertices(3,2)+0.5];
            set(handles2.axesImageViewer,'XLim',newXLim);
            set(handles2.axesImageViewer,'YLim',newYLim);
        end
        %%
        %
        function obj = zoomRecenter(obj, centroid)
            % The centroid received should be in the [centroid_row,
            % centroid_col] format
            % Check that the centroid does not go out of the boundaries of
            % the image given the zoom.
            newHalfWidth = obj.image_width*obj.zoomArray(obj.zoomIndex)/2;
            newHalfHeight = obj.image_height*obj.zoomArray(obj.zoomIndex)/2;
            centroid(2) = max(centroid(2), newHalfWidth);
            centroid(2) = min(centroid(2), obj.image_width-newHalfWidth);
            centroid(1) = max(centroid(1), newHalfHeight);
            centroid(1) = min(centroid(1), obj.image_height-newHalfHeight);
            
            % Define new vertices
            handles = guidata(obj.gui_zoomMap);
            newVertices = [centroid(2) - newHalfWidth, centroid(1) - newHalfHeight; ...
                centroid(2) + newHalfWidth-1, centroid(1) - newHalfHeight; ...
                centroid(2) + newHalfWidth-1, centroid(1) + newHalfHeight-1; ...
                centroid(2) - newHalfWidth, centroid(1) + newHalfHeight-1];
            set(handles.zoomMapRect,'Vertices', newVertices);
            guidata(obj.gui_zoomMap, handles);
            obj.zoomPan;
        end
        %% Delete function
        function delete(obj)
            obj.obj_cellTracker.delete;
            delete(obj.gui_contrast);
            delete(obj.gui_imageViewer);
            delete(obj.gui_zoomMap);
        end
        %%
        function str = getCurrentPopupString(hh)
            %# getCurrentPopupString returns the currently selected string in the popupmenu with handle hh
            
            %# could test input here
            if ~ishandle(hh) || strcmp(get(hh,'Type'),'popupmenu')
                error('getCurrentPopupString needs a handle to a popupmenu as input')
            end
            
            %# get the string - do it the readable way
            list = get(hh,'String');
            val = get(hh,'Value');
            if iscell(list)
                str = list{val};
            else
                str = list(val,:);
            end
        end

    end
end