-- Mozbugbox's lua utilities for mpv
-- Copyright (c) 2015-2018 mozbugbox@yahoo.com.au
-- Licensed under GPL version 3 or later

--[[
Manipulate the FFmpeg curves filter to adjust video color
Usage:
  * copy script file to ~/.config/mpv/scripts/
  * Add following lines to ~/.config/mpv/input.conf

        b osd-msg script-message curves-brighten-show
        y osd-msg script-message curves-cooler-show

  * In mpv, press `b`, `y` keys to start manipulating color curves
  * Use arrow keys to move the point in curve up/down/left/right
  * `r`: reset curves state
  * `d`: delete the filter
  * press `b`, `y` keys again to exist the curves modes.

script commands:
  * curves-brighten-show: Switch on bright manipulate mode, use arrow keys
  * curves-cooler-show: Switch on temperature manipulate mode, use arrow keys

  * curves-brighten: Adjust brightness of video. Param: +/-1
  * curves-brighten-tone: Change the tone base (the x-coord) Param: +/-1
  * curves-temp-cooler: Adjust the temperature by change r,b,g curve values
  * curves-temp-tone: Change the tone base (the x-coord)
--]]

local msg = require "mp.msg"
local utils = require "mp.utils" -- utils.to_string()
local ass_start = mp.get_property_osd("osd-ass-cc/0")
local curvesdraw = require "curvesdraw"

-- Class creation function
function class_new(klass)
    -- Simple Object Oriented Class constructor
    local klass = klass or {}
    function klass:new(o)
        local o = o or {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
    return klass
end

-- print content of a lua table
function print_table(tbl)
    msg.info(utils.to_string(tbl))
end

-- return the first non-nil arguments
function first_not_nil(a, b)
    local r = a == nil and b or a
    return r
end

-- Bind keys in a specific mode
-- methods: array of {name="func-name", func=func, key="bind_key"}
function toggle_key_mode(self, methods, keys)
    local keys0 = {"left", "right", "up", "down", "space"}
    keys = first_not_nil(keys, keys0)
    -- print_table(meth)
    if self.gShow then
        self.gShow = false
        for i = 1, #methods do
            local meth = methods[i]
            mp.remove_key_binding(meth.name)
        end
    else
        self.gShow = true
        local REP = {repeatable = true}
        for i = 1, #methods do
            local meth = methods[i]
            local key = first_not_nil(meth.key, keys[i])
            mp.add_forced_key_binding(key, meth.name, meth.func, REP)
        end
    end
end

-- Change brightness with curves filter
local CurvesBrighten = class_new ({
    filter_tag = "@mozbugBrighten",
    upper_point = {0.82, 0.77},
    x_base = 0.140,
    m_base = 0.01,  -- delta from x_current

    x_current = 0,
    current = 0,
})

function CurvesBrighten:do_step(step)
    local stride = 0.005
    local xval = self.x_base + self.x_current

    self.current = self.current + step * stride
    local val = xval + self.m_base + self.current

    -- msg.info(self.current)
    if val < 0 or val > 1 then
        self.current = self.m_base
        mp.commandv("vf", "del", self.filter_tag)
        mp.osd_message("C Brighten: +0")
    else
        cmd = string.format("%s:lavfi=[curves=m='0/0 %.3f/%.3f %.3f/%.3f 1/1']",
            self.filter_tag, xval, val,
            self.upper_point[1], self.upper_point[2])
        msg.info(cmd)
        mp.commandv("vf", "add", cmd)
    end
    self:draw_curves()
end

function CurvesBrighten:change_xbase(step)
    local stride = 0.005
    local x_current = self.x_current + stride * step
    local xval = self.x_base + x_current

    -- msg.info(xval)
    if 0.05 < xval and xval < 0.8 then
        self.x_current = x_current
    elseif xval >= 0.8 then
        self.x_current = 0
    else
        self.x_current = 0.7 - self.x_base
    end
    -- msg.info("CurvesBrighten x_current", self.x_current)
    self:do_step(0)
end

-- draw curves onto OSD
function CurvesBrighten:draw_curves()
    if self.gShow then
        local xval = self.x_base + self.x_current
        local yval = xval + self.m_base + self.current
        local points = {{0, 0}, {xval, yval}, self.upper_point, {1, 1}}
        curvesdraw.draw_curves(points)
    else
        mp.set_osd_ass(1280, 720, "")
    end
end

function CurvesBrighten:delete_filter()
    mp.commandv("vf", "del", self.filter_tag)
end

local cbrighten_obj = CurvesBrighten:new()
-- step can be 1/-1
function curves_brighten(step)
    step = step == nil and 1 or tonumber(step)
    cbrighten_obj:do_step(step)
end

-- step can be 1/-1
function curves_brighten_tone(step)
    step = step == nil and 1 or tonumber(step)
    cbrighten_obj:change_xbase(step)
end

function curves_brighten_reset()
    cbrighten_obj.x_current = 0
    cbrighten_obj.current = 0
    cbrighten_obj:do_step(0)
end

function curves_brighten_delete()
    cbrighten_obj:delete_filter()
end

function curves_brighten_show()
    local methods = {
        {name="tonedown", func=function() curves_brighten_tone(-1) end},
        {name="toneup", func=function() curves_brighten_tone(1) end},
        {name="bright", func=function() curves_brighten(1) end},
        {name="dark", func=function() curves_brighten(-1) end},
        {name="reset", func=curves_brighten_reset, key="r"},
        {name="delete", func=curves_brighten_delete, key="d"},
    }
    toggle_key_mode(cbrighten_obj, methods)
    if cbrighten_obj.gShow then
        mp.osd_message("C Brighten ON\n←→↑↓ keys change Brightness", 3)
    else
        mp.osd_message("C Brighten OFF")
    end
    cbrighten_obj:draw_curves()
end

-- Change color temperature with curves filter
local CurvesTemperature = class_new ({
    filter_tag = "@mozbugTemperature",
    upper_point_r = {0.82, 0.85},
    upper_point_g = {0.82, 0.77},
    upper_point_b = {0.82, 0.77},

    x_base = 0.24,
    r_base = -0.03, -- delta from x_current
    g_base = 0.04,
    b_base = 0.12,

    x_current = 0,
    current = 0,
})

function CurvesTemperature:do_step(step)
    local stride = 0.005
    local xval = self.x_base + self.x_current

    self.current = self.current + step * stride
    local rv = xval + self.r_base - self.current
    local gv = xval + self.g_base + self.current
    local bv = xval + self.b_base + self.current
    -- msg.info(rv, gv, bv, self.current)
    if rv < 0 or gv < 0 or bv < 0 or rv > 1 or gv > 1 or bv > 1 then
        self.current = 0
        mp.commandv("vf", "del", self.filter_tag)
        mp.osd_message("Cooler: +0")
    else
        local rc = string.format("'0/0 %.3f/%.3f %.3f/%.3f 1/1'", xval, rv,
            self.upper_point_r[1], self.upper_point_r[2])
        local gc = string.format("'0/0 %.3f/%.3f %.3f/%.3f 1/1'", xval, gv,
            self.upper_point_g[1], self.upper_point_g[2])
        local bc = string.format("'0/0 %.3f/%.3f %.3f/%.3f 1/1'", xval, bv,
            self.upper_point_b[1], self.upper_point_b[2])
        cmd = string.format("%s:lavfi=[curves=r=%s:g=%s:b=%s]",
            self.filter_tag, rc, gc, bc)

        msg.info(cmd)
        mp.commandv("vf", "add", cmd)
    end
    self:draw_curves()
end

function CurvesTemperature:change_xbase(step)
    local stride = 0.005
    local x_current = self.x_current + stride * step
    local xval = self.x_base + x_current

    if 0.05 < xval and xval < .8 then
        self.x_current = x_current
    elseif xval >= 0.8 then
        self.x_current = 0
    else
        self.x_current = .7 - self.x_base
    end
    -- msg.info(self.x_current)
    self:do_step(0)
end

-- draw curves onto OSD
function CurvesTemperature:draw_curves()
    if self.gShow then
        local xval = self.x_base + self.x_current
        local rv = xval + self.r_base - self.current
        local gv = xval + self.g_base + self.current
        local bv = xval + self.b_base + self.current

        local points_r = {{0, 0}, {xval, rv}, self.upper_point_r, {1, 1}}
        local points_g = {{0, 0}, {xval, gv}, self.upper_point_g, {1, 1}}
        local points_b = {{0, 0}, {xval, bv}, self.upper_point_b, {1, 1}}
        curvesdraw.draw_curves(nil, points_r, points_g, points_b)
    else
        mp.set_osd_ass(1280, 720, "")
    end
end

function CurvesTemperature:delete_filter()
    mp.commandv("vf", "del", self.filter_tag)
end

local ctemperature_obj = CurvesTemperature:new()
function curves_temp_cooler(step)
    step = step == nil and 1 or tonumber(step)
    ctemperature_obj:do_step(step)
end

function curves_temp_tone(step)
    step = step == nil and 1 or tonumber(step)
    ctemperature_obj:change_xbase(step)
end

function curves_temp_reset()
    ctemperature_obj.x_current = 0
    ctemperature_obj.current = 0
    ctemperature_obj:do_step(0)
end

function curves_temp_delete()
    ctemperature_obj:delete_filter()
end

function curves_cooler_show()
    local methods = {
        {name="tonedown", func=function() curves_temp_tone(-1) end},
        {name="toneup", func=function() curves_temp_tone(1) end},
        {name="cooler", func=function() curves_temp_cooler(1) end},
        {name="warmer", func=function() curves_temp_cooler(-1) end},
        {name="reset", func=curves_temp_reset, key="r"},
        {name="delete", func=curves_temp_delete, key="d"},
    }
    toggle_key_mode(ctemperature_obj, methods)
    if ctemperature_obj.gShow then
        mp.osd_message("C Temp ON\n←→↑↓ keys change color temperature", 3)
    else
        mp.osd_message("C Temp OFF")
    end
    ctemperature_obj:draw_curves()
end

--------------------------------------------------------------------
-- register script messages usable in input.conf
-- For example, in ~/.config/mpv/input.conf, add a line like:
--     r script_message rotate-video
-- to map "r" key to rotate video by 90 degree
--------------------------------------------------------------------

mp.register_script_message("curves-brighten", curves_brighten)
mp.register_script_message("curves-brighten-tone", curves_brighten_tone)
mp.register_script_message("curves-temp-cooler", curves_temp_cooler)
mp.register_script_message("curves-temp-tone", curves_temp_tone)

mp.register_script_message("curves-brighten-show", curves_brighten_show)
mp.register_script_message("curves-cooler-show", curves_cooler_show)
