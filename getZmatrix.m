function zMatrix = getZmatrix(centroidsTracks)
    trackedCells = centroidsTracks.getTrackedCellIds;
    zMatrix = zeros(length(trackedCells), length(centroidsTracks.singleCells));
    for t = 1:length(centroidsTracks.singleCells)
        [values, validCells] = centroidsTracks.getZs(t);
        [~, validCells] = ismember(validCells, trackedCells);
        zMatrix(validCells,t) = values;
    end
end