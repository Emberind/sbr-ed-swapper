function_name = "Overwrite ED";
function_description = "Replaces the ED with a different given one";

require("karaskel");

local edStart = 1327 * 1000;
local edLength = 90 * 1000;

function overwrite_ed(subtitles)
    local meta, styles = karaskel.collect_head(subtitles, true);
    local subtitle_count = #subtitles;

    -- Remove all lines played during the ED
    local to_remove = {};
    for idx, line in ipairs(subtitles) do
        if line.class == "dialogue" and not line.comment then
            karaskel.preproc_line(subtitles, meta, styles, line);

            if (line.start_time >= edStart) and (line.end_time <= edStart + edLength) then
                aegisub.log(4, "Removing line %d: '%s'\n", idx, line.text);
                table.insert(to_remove, idx);
            end
        end

        aegisub.progress.set(100 * idx / subtitle_count);
    end

    subtitles.delete(to_remove);
end

function overwrite_ed_filter(subtitles, settings)
    overwrite_ed(subtitles);
end

aegisub.register_filter(function_name, function_description, 100, overwrite_ed_filter, nil);
