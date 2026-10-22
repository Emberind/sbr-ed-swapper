function_name = "Overwrite ED";
function_description = "Replaces the ED with a different given one";

require("karaskel");
re = require("aegisub.re");

local edStart = 1327 * 1000;
local edLength = 90 * 1000;

local songSubsFile = "../Wanted Dead or Alive.ass";

local dialogueRe = re.compile(
    "^Dialogue: ([^,]*),(\\d+):(\\d{2}):(\\d{2}).(\\d{2})\\d*,(\\d+):(\\d{2}):(\\d{2}).(\\d{2})\\d*,([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$");
local styleRe = re.compile(
    "^Style: ([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$");

function get_line_object(string)
    local class = re.split(string, ":")[1];

    if class == "Dialogue" then
        local data = dialogueRe:match(string);

        return {
            class = "dialogue",
            raw = string,
            section = "[Events]",
            comment = false,
            layer = tonumber(data[2]["str"]),
            start_time = (((tonumber(data[3]["str"]) * 60 + tonumber(data[4]["str"])) * 60 + tonumber(data[5]["str"])) * 100 + tonumber(data[6]["str"])) * 10,
            end_time = (((tonumber(data[7]["str"]) * 60 + tonumber(data[8]["str"])) * 60 + tonumber(data[9]["str"])) * 100 + tonumber(data[10]["str"])) * 10,
            style = data[11]["str"],
            actor = data[12]["str"],
            margin_l = tonumber(data[13]["str"]),
            margin_r = tonumber(data[14]["str"]),
            margin_t = tonumber(data[15]["str"]),
            margin_b = tonumber(data[15]["str"]),
            effect = data[16]["str"],
            userdata = nil,
            text = data[17]["str"]
        };
    elseif class == "Style" then
        local data = styleRe:match(string);

        return {
            class = "style",
            raw = string,
            section = "[V4+ Styles]",
            name = data[2]["str"],
            fontname = data[3]["str"],
            fontsize = tonumber(data[4]["str"]),
            color1 = data[5]["str"],
            color2 = data[6]["str"],
            color3 = data[7]["str"],
            color4 = data[8]["str"],
            bold = tonumber(data[9]["str"]) > 0,
            italic = tonumber(data[10]["str"]) > 0,
            underline = tonumber(data[11]["str"]) > 0,
            strikeout = tonumber(data[12]["str"]) > 0,
            scale_x = tonumber(data[13]["str"]),
            scale_y = tonumber(data[14]["str"]),
            spacing = tonumber(data[15]["str"]),
            angle = tonumber(data[16]["str"]),
            borderstyle = tonumber(data[17]["str"]),
            outline = tonumber(data[18]["str"]),
            shadow = tonumber(data[19]["str"]),
            align = tonumber(data[20]["str"]),
            margin_l = tonumber(data[21]["str"]),
            margin_r = tonumber(data[22]["str"]),
            margin_t = tonumber(data[23]["str"]),
            margin_b = tonumber(data[23]["str"]),
            encoding = tonumber(data[24]["str"]),
            relative_to = nil,
            vertical = nil
        };
    end

    return nil;
end

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

    for line in io.lines(songSubsFile) do
        lineObject = get_line_object(line);

        if lineObject ~= nil then
            if lineObject.class == "dialogue" then
                aegisub.log(4, "Appending line: %s\n", lineObject.text);
            elseif lineObject.class == "style" then
                aegisub.log(4, "Appending style: %s\n", lineObject.name);
            else
                aegisub.log(2, "Appending unrecognized line: %s\n", lineObject.raw);
            end

            subtitles.append(lineObject);
        end
    end
end

function overwrite_ed_filter(subtitles, settings)
    overwrite_ed(subtitles);
end

aegisub.register_filter(function_name, function_description, 100, overwrite_ed_filter, nil);
