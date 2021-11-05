function [filename, z_index] = getDatabaseFile_z(database, group, channel, position, timepoint, z)
if(~iscell(database.channel_name))
    channel_filter = database.channel_name == str2double(channel);
else
    channel_filter = strcmp(database.channel_name, channel);
end

if(~iscell(database.group_label))
    group_filter = database.group_label == str2double(group);
else
    group_filter = strcmp(database.group_label, group);
end

z_filter = database.z == z;

fileIndex = channel_filter & database.position_number == position & database.timepoint == timepoint & group_filter & z_filter;

if(sum(fileIndex) > 0)
    filename = database.filename{fileIndex};
    z_index = database.z_index(fileIndex);
else
    filename = [];
    z_index = [];
end