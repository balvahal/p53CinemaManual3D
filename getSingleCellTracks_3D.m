function singleCellTracks = getSingleCellTracks_3D(rawdatapath, database, group, position, channel, centroids, ff_offset, ff_gain, blurRadius)
    trackedCells = centroids.getTrackedCellIds;
    numTracks = length(trackedCells);
    numTimepoints = length(centroids.singleCells);
        
    singleCellTracks = -ones(numTracks, numTimepoints);
    progress = 0;
    for i=1:numTimepoints
        if(i/numTimepoints * 100 > progress)
            fprintf('%d ', progress);
            progress = progress + 10;
        end
        [currentCentroids_original, validCells] = centroids.getCentroids(i);
        currentZs = centroids.getZs(i);
        [~, validCells_all] = ismember(validCells, trackedCells);
        
        if(isempty(validCells))
            continue;
        end
        
        unique_zs = unique(currentZs);
        for j=1:length(unique_zs)
            filename = getDatabaseFile_z(database, group, channel, position, i, unique_zs(j));
            validCells = currentZs == unique_zs(j);
            if(isempty(filename))
                continue;
            end
            YFP = double(imread(fullfile(rawdatapath, filename)));
            if(~isempty(ff_gain))
                YFP = flatfield_correctImage(YFP, ff_offset, ff_gain);
            end
            
            YFP_background = imbackground(YFP, 2, 20);
            scalingFactor = 1;
            currentCentroids_original(validCells,1) = min(ceil(currentCentroids_original(validCells,1) * scalingFactor), size(YFP,1));
            currentCentroids_original(validCells,2) = min(ceil(currentCentroids_original(validCells,2) * scalingFactor), size(YFP,2));
            
            currentCentroids = sub2ind(size(YFP), currentCentroids_original(validCells,1), currentCentroids_original(validCells,2));
            diskMask = getnhood(strel('disk',blurRadius));
            diskMask = diskMask / sum(diskMask(:));
            diskFilteredImage = imfilter(YFP_background, diskMask, 'replicate');
            
            singleCellTracks(validCells_all(validCells),i) = diskFilteredImage(currentCentroids);
        end
        
    end
    fprintf('%d\n', progress);
end