function_name = "Overwrite ED";
function_description = "Replaces the ED with a different given one";

require("karaskel");

local dialogueRe = "Dialogue: ([^,]*),(%d+):(%d+):(%d+).(%d+),(%d+):(%d+):(%d+).(%d+),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)";
local styleRe = "Style: ([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)";

function get_line_object(lineString)
    local classEnd = string.find(lineString, ':');
    if (classEnd == nil) then return end
    local class = string.sub(lineString, 1, classEnd - 1);

    if class == "Dialogue" then
        local
            layer,
            start_time_h, start_time_m, start_time_s, start_time_c,
            end_time_h, end_time_m, end_time_s, end_time_c,
            style,
            actor,
            margin_l,
            margin_r,
            margin_v,
            effect,
            text
            = lineString:match(dialogueRe);

        return {
            class = "dialogue",
            raw = lineString,
            section = "[Events]",
            comment = false,
            layer = tonumber(layer),
            start_time = (((tonumber(start_time_h) * 60 + tonumber(start_time_m)) * 60 + tonumber(start_time_s)) * 100 + tonumber(start_time_c)) * 10,
            end_time = (((tonumber(end_time_h) * 60 + tonumber(end_time_m)) * 60 + tonumber(end_time_s)) * 100 + tonumber(end_time_c)) * 10,
            style = style,
            actor = actor,
            margin_l = tonumber(margin_l),
            margin_r = tonumber(margin_r),
            margin_t = tonumber(margin_v),
            margin_b = tonumber(margin_v),
            effect = effect,
            userdata = nil,
            text = text
        };
    elseif class == "Style" then
        local
            name,
            fontname,
            fontsize,
            color1,
            color2,
            color3,
            color4,
            bold,
            italic,
            underline,
            strikeout,
            scale_x,
            scale_y,
            spacing,
            angle,
            borderstyle,
            outline,
            shadow,
            align,
            margin_l,
            margin_r,
            margin_v,
            encoding
            = lineString:match(styleRe);

        return {
            class = "style",
            raw = lineString,
            section = "[V4+ Styles]",
            name = name,
            fontname = fontname,
            fontsize = tonumber(fontsize),
            color1 = color1,
            color2 = color2,
            color3 = color3,
            color4 = color4,
            bold = tonumber(bold) > 0,
            italic = tonumber(italic) > 0,
            underline = tonumber(underline) > 0,
            strikeout = tonumber(strikeout) > 0,
            scale_x = tonumber(scale_x),
            scale_y = tonumber(scale_y),
            spacing = tonumber(spacing),
            angle = tonumber(angle),
            borderstyle = tonumber(borderstyle),
            outline = tonumber(outline),
            shadow = tonumber(shadow),
            align = tonumber(align),
            margin_l = tonumber(margin_l),
            margin_r = tonumber(margin_r),
            margin_t = tonumber(margin_v),
            margin_b = tonumber(margin_v),
            encoding = tonumber(encoding),
            relative_to = nil,
            vertical = nil
        };
    end

    return nil;
end

function overwrite_ed(subtitles, ed_subs_path, ed_start_time)
    local meta, styles = karaskel.collect_head(subtitles, true);
    local subtitle_count = #subtitles;

    local ed_end_time = ed_start_time + 90;

    -- Remove all lines played during the ED
    local to_remove = {};
    for idx, line in ipairs(subtitles) do
        if line.class == "dialogue" and not line.comment then
            karaskel.preproc_line(subtitles, meta, styles, line);

            if (line.start_time / 1000 >= ed_start_time) and (line.end_time / 1000 <= ed_end_time) then
                aegisub.log(4, "Removing line %d: '%s'\n", idx, line.text);
                table.insert(to_remove, idx);
            end
        end

        aegisub.progress.set(100 * idx / subtitle_count);
    end

    subtitles.delete(to_remove);

    for line in io.lines(ed_subs_path) do
        lineObject = get_line_object(line);

        if lineObject ~= nil then
            if lineObject.class == "dialogue" then
                aegisub.log(4, "Appending line: %s\n", lineObject.text);

                lineObject.start_time = lineObject.start_time + ed_start_time * 1000;
                lineObject.end_time = lineObject.end_time + ed_start_time * 1000;

            elseif lineObject.class == "style" then
                aegisub.log(4, "Appending style: %s\n", lineObject.name);
            else
                aegisub.log(2, "Appending unrecognized line: %s\n", lineObject.raw);
            end

            subtitles.append(lineObject);
        end
    end
end

function overwrite_ed_macro(subtitles, selected_lines, active_line)
    accepted, settings = aegisub.dialog.display({
        {
            class = "label",
            label = "ED start time [s]",
            x = 0, y = 0
        },
        {
            class = "floatedit",
            name = "ed_start_time",
            value = 0.0,
            min = 0.0, max = 60 * 60 * 60, step = 0.01,
            x = 1, y = 0, width = 10
        }
    });

    if accepted then
        local ed_subs_path = aegisub.dialog.open("Select ED subtitle file", "", "", "*.ass");

        overwrite_ed(subtitles, ed_subs_path, settings.ed_start_time)
    end
end

function overwrite_ed_filter(subtitles, settings)
    overwrite_ed(subtitles, settings.ed_subs_path, settings.ed_start_time);
end

function get_overwrite_ed_config_panel(subtitles, old_settings)
    return {
        {
            class = "label",
            label = "ED subs path",
            x = 0, y = 0
        },
        {
            class = "edit",
            name = "ed_subs_path",
            hint = "Absolute path to the ED ASS file",
            value = old_settings.ed_subs_path,
            x = 1, y = 0, width = 30
        },
        {
            class = "label",
            label = "ED start time [s]",
            x = 0, y = 1
        },
        {
            class = "floatedit",
            name = "ed_start_time",
            value = old_settings.ed_start_time,
            min = 0.0, max = 60 * 60 * 60, step = 0.01,
            x = 1, y = 1, width = 10
        }
    };
end

aegisub.register_macro(function_name, function_description, overwrite_ed_macro);
aegisub.register_filter(function_name, function_description, 100, overwrite_ed_filter, get_overwrite_ed_config_panel);
