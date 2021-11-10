function [] = precomputeCentroids(database, experimentPath, rawdatapath, channel_name, blurRadius, timepointLimit)
    unique_groups = unique(database.group_label);
    numZ = max(database.z);
    maxTimepoint = max(database.timepoint);
    
    if(~exist(fullfile(experimentPath, 'Precomputed'), 'dir'))
        mkdir(fullfile(experimentPath, 'Precomputed'));
    end
    
    channel_filter = strcmp(database.channel_name, channel_name);
    for g=1:length(unique_groups)
        currentGroup = unique_groups{g};
        group_filter = strcmp(database.group_label, currentGroup);
        unique_positions = unique(database.position_number(group_filter));
        for s=1:length(unique_positions)
            currentPosition = unique_positions(s);
            position_filter = database.position_number == currentPosition;
            
            centroidsLocalMaxima = cell(numZ, 1);
            for z=1:numZ
                centroidsLocalMaxima{z} = CentroidTimeseries3D_withAnnotations(maxTimepoint, 10000, {});
            end
            
            fprintf(sprintf('Group: %s Position: %d: ', currentGroup, currentPosition))
            
            unique_z = unique(database.z(group_filter & position_filter & channel_filter));
            for z=1:length(unique_z)
                currentZ = unique_z(z);
                fprintf('Z %d: ', currentZ);
                z_filter = database.z == currentZ;
                unique_timepoints = unique(database.timepoint(group_filter & position_filter & channel_filter & z_filter));
                if(~isinf(timepointLimit))
                    unique_timepoints = unique_timepoints(unique_timepoints <= timepointLimit);
                end
                for t=1:length(unique_timepoints)
                    currentTimepoint = unique_timepoints(t);
                    fprintf('%d ', currentTimepoint);
                    timepoint_filter = database.timepoint == currentTimepoint;
                    file_index = group_filter & position_filter & channel_filter & z_filter & timepoint_filter;
                    filename = fullfile(rawdatapath, database.filename{file_index});
                    z_index = database.z_index(file_index);
                    IM = imread(filename, z_index);
                    IM = imbackground(IM, 10, 100);
                    IM = double(IM);
                    IM = medfilt2(IM, [2,2]);
                    localMaxima = getImageMaxima_Intensity(IM, blurRadius);
                    centroidsLocalMaxima{currentZ}.insertCentroids(currentTimepoint, localMaxima);
                end
                fprintf('\n');
            end
            % Save centroids file
            outputFile = fullfile(experimentPath, 'Precomputed', sprintf('%s_s%d_centroidsLocalMaxima.mat', currentGroup, currentPosition));
            save(outputFile, 'centroidsLocalMaxima', '-v7.3');
            fprintf('\n');
        end
    end
end