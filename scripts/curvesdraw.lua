local msg = require "mp.msg"
local utils = require "mp.utils" -- utils.to_string()
-- print content of a lua table
function print_table(tbl)
    msg.info(utils.to_string(tbl))
end

-- find line between 2 points
function opposed_line(p1, p2)
    local len_x = p2[1] - p1[1]
    local len_y = p2[2] - p1[2]
    local line = {
        length=math.sqrt(len_x^2 + len_y^2),
        angle=math.atan2(len_y, len_x),
    }
    return line
end

-- Find control point for endpoint for smooth bezier link
-- Reverse indicate the direction of the control point
-- The line b/w ctr, current point should be parallel to the line b/w prev,
-- next points. The line length should be decided by parallel line and a
-- smooth factor.
function control_point(point_ls, idx, reverse, smooth)
    local cur = point_ls[idx]
    -- if not prev or next, set it as current point
    local prev = idx == 1 and cur or point_ls[idx-1]
    local nex = idx == #point_ls and cur or point_ls[idx+1]
    local oline = opposed_line(prev, nex)
    -- for end-control-point, add PI to the angle will go backward
    local angle = oline.angle + (reverse == true and math.pi or 0)
    line_length = oline.length * smooth
    local x = cur[1] + math.cos(angle) * line_length
    local y = cur[2] + math.sin(angle) * line_length
    return {x, y}
end

-- calc points for draw bezier. Return ctr1, ctr2, endpoint(=point_ls[idx])
function bezier_points(point_ls, idx, smooth)
    res = {
        control_point(point_ls, idx-1, false, smooth),
        control_point(point_ls, idx, true, smooth),
        point_ls[idx],
    }
    return res
end

-- Plot the color curves on mpv OSD
function draw_curves(points_m, points_r, points_g, points_b)
    -- (0, 0) at top-left corner
    local assdraw = require 'mp.assdraw'

    local canvas_w = 1280
    local canvas_h = 720
    local dw, dh, da = mp.get_osd_size()
    if dw ~= nil and dw > 0 and dh > 0 then
        canvas_w = dw / dh * canvas_h  -- Fix aspect?
    end

    local margin = 6
    local size_ratio = 1 / 3
    local dim = canvas_h * size_ratio
    local o_x = canvas_w - dim - margin
    local o_y = margin
    local ass = assdraw.ass_new()
    ass.scale = 1

    -- border color: in BGR order <BBGGRR>. alpha: 00 - FF
    function set_style(color, alpha, border)
        local style = ""
        if color ~= nil then
            style = string.format("%s\\3c&H%s&", style, color)
        end
        if alpha ~= nil then
            style = string.format("%s\\alpha&H%s&", style, alpha)
        end
        if border ~= nil then
            style = string.format("%s\\bord%.3f", style, border)
        end
        ass:append(string.format("{%s}", style))
    end

    smooth = 0.2
    -- convert curve point to ass point in dim
    function fix_cpoint(p)
        local px = math.floor(p[1] * dim + 0.5)
        local py = math.floor((1 - p[2]) * dim + 0.5)
        return {px, py}
    end

    function draw_bezier(x0, y0, points, color)
        local p0, p1, p2, p3
        ass:new_event()
        p0 = fix_cpoint(points[1])
        ass:pos(x0, y0)
        set_style(color, "00", 0.5)
        ass:draw_start()

        ass:move_to(p0[1], p0[2])
        local rpoints = {}
        for i = 2, #points do
            bzs = bezier_points(points, i, smooth)
            p0 = fix_cpoint(points[i-1])
            p1 = fix_cpoint(bzs[1])
            p2 = fix_cpoint(bzs[2])
            p3 = fix_cpoint(bzs[3])
            ass:bezier_curve(p1[1], p1[2], p2[1], p2[2], p3[1], p3[2])
            table.insert(rpoints, {p2, p1, p0})
        end
        -- reverse draw, close the drawing
        for i = #rpoints, 1, -1 do
            p1 = rpoints[i][1]
            p2 = rpoints[i][2]
            p3 = rpoints[i][3]
            ass:bezier_curve(p1[1], p1[2], p2[1], p2[2], p3[1], p3[2])
        end

        -- draw points on curves
        local psize = 2
        for i = 2, #points - 1 do
            p0 = fix_cpoint(points[i])
            ass:rect_cw(p0[1]-psize/2, p0[2]-psize/2, p0[1]+psize, p0[2]+psize)
        end
        ass:draw_stop()
    end

    ass:new_event()
    set_style(nil, "C0", 0)
    ass:pos(o_x, o_y)
    ass:draw_start()
    ass:rect_cw(0, 0, dim, dim)
    ass:draw_stop()

    -- points_m = {{0, 0}, {0.33, 0.22}, {0.5, 0.7}, {1, 1}}
    if points_m ~= nil then
        draw_bezier(o_x, o_y, points_m, "666666")
    end
    if points_r ~= nil then
        draw_bezier(o_x, o_y, points_r, "0000ff")
    end
    if points_g ~= nil then
        draw_bezier(o_x, o_y, points_g, "00ff00")
    end
    if points_b ~= nil then
        draw_bezier(o_x, o_y, points_b, "ff0000")
    end
    -- msg.info(ass.text)
    mp.set_osd_ass(canvas_w, canvas_h, ass.text)
end

return {draw_curves = draw_curves}
