-- Mozbugbox's Lua scripts for mpv 
-- Copyright (c) 2015-2018 mozbugbox@yahoo.com.au
-- Licensed under GPL version 3 or later
--
-- Test mpv video filters(vf), including ffmpeg filters
-- mpv vf: https://github.com/mpv-player/mpv/blob/master/DOCS/man/vf.rst
-- FFmpeg filter: https://ffmpeg.org/ffmpeg-filters.html
-- Depends: yad: Yet Another Dialog
--
-- Usage: insert the line to input.conf:
--     F script-message filter-test
--

local o = {
    bin = "/usr/bin/yad",
    mpv_vf_url = '<a href="https://github.com/mpv-player/mpv/blob/master/DOCS/man/vf.rst">MPV Video Filters Manpage</a>',
    ffmpeg_url = '<a href="https://ffmpeg.org/ffmpeg-filters.html">FFmpeg Filters Documentation</a>',

    use_lavfi = true,
}

local msg = require "mp.msg"
local utils = require "mp.utils" -- utils.to_string()

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

-- print a lua table
function print_table(tbl)
    msg.info(utils.to_string(tbl))
end

local FILTER_HISTORY = {"curves=m='0/0 0.129/0.204 0.784/0.784 1/1'"}
function get_filter()
    -- get filter text using `yad`
    local cmd = {}
    local isep = "|"
    cmd.args = {
        o.bin, "--title", "Enter Filter", "--width", "600",
        "--mouse",
        "--form", "--output-by-row", "--item-separator", isep,
        "--field", "Filter::CBE", "--field", "Lavfi:CHK",
        "--field", string.format(" * %s:LBL", o.mpv_vf_url),
        "--field", string.format(" * %s:LBL", o.ffmpeg_url),
        table.concat(FILTER_HISTORY, isep), tostring(o.use_lavfi),
    }

    -- print_table(cmd)
    local res = utils.subprocess(cmd)
    -- print_table(res)
    local content
    if res.status == 0 and res.error == nil then
        content = {}
        for s in res.stdout:gmatch("([^%|]+)%|") do 
            table.insert(content, s)
        end
    else 
        content = nil
    end
    return content
end

function filter_test()
    -- Add a testing vf filter
    local filter_info = get_filter()
    -- print_table(filter_info)
    local label = "@mozbugFilterTester"
    if filter_info == nil then 
        -- user cancelled
        return 
    elseif #filter_info == 1 then 
        -- not filter string, del old label
        mp.command(string.format("vf del %s", label))
        return 
    end

    local filter_str = filter_info[1]
    local lavfi_flag = filter_info[2]
    local cmd
    
    table.insert(FILTER_HISTORY, 1, filter_str)
    o.use_lavfi = lavfi_flag == "TRUE"
    if o.use_lavfi then 
        o.use_lavfi = true
        cmd = string.format('%s:lavfi=[%s]', label, filter_str)
    else
        cmd = string.format("%s:%s", label, filter_str)
    end
    msg.info(cmd)
    mp.commandv("vf", "add", cmd)
    -- mp.commandv("vf", "add", "lavfi=[curves=blue='0/0 1/1']")
end

mp.register_script_message("filter-test", filter_test)

