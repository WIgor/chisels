-- Chisel description
description = "Draw latencies between request and responce, to choosen ip or/and port"
short_description = "Sockets request/responce latency"
category = "Network"

-- Chisel argument list
args =
{
    {
        name = "direction",
        description = "in/out",
        argtype = "string"
    },
    {
        name = "ip",
        description = "Target IP",
        argtype = "string",
        optional = true
    },
    {
        name = "port",
        description = "Target port",
        argtype = "int",
        optional = true
    },
    {
        name = "refresh_time",
		description = "Chart refresh time in milliseconds",
		argtype = "int",
		optional = true
    },
}

require "common"
terminal = require "ansiterminal"
terminal.enable_color(true)

write_etypes = {}
write_etypes["sendto"] = true
write_etypes["writev"] = true
write_etypes["write"] = true
write_etypes["pwrite"] = true

read_etypes = {}
read_etypes["recvfrom"] = true
read_etypes["readv"] = true
read_etypes["read"] = true
read_etypes["pread"] = true

refresh_time = 1000000000
refresh_per_sec = 1000000000 / refresh_time

time_map = {}

frequencies = {}
freq_version = 0

colpalette = {22, 28, 64, 34, 2, 76, 46, 118, 154, 191, 227, 226, 11, 220, 209, 208, 202, 197, 9, 1}
ip = ""
port = 0

-- Argument notification callback
function on_set_arg(name, val)
    if name == "direction" then
        direction = val
        return true
    elseif name == "ip" then
        ip = val
        return true
    elseif name == "port" then
        port = val
        return true
    elseif name == "refresh_time" then
		refresh_time = parse_numeric_input(val, name) * 1000000
		refresh_per_sec = 1000000000 / refresh_time
		return true
	end
    return false
end

-- Initialization callback
function on_init()
    if (port == nil or port == 0) and (ip == nil or ip == "") then
        print("IP or port, or both must be selected")
		return false
    end

    is_tty = sysdig.is_tty()

    if not is_tty then
		print("This chisel only works on ANSI terminals. Aborting.")
		return false
	end

    tinfo = sysdig.get_terminal_info()
	w = tinfo.width
	h = tinfo.height

    terminal.hidecursor()

    -- Request the fileds that we need
    field_pid = chisel.request_field("proc.pid")
    field_fdnum = chisel.request_field("fd.num")
    field_etype = chisel.request_field("evt.type")
    field_etime = chisel.request_field("evt.rawtime")
    field_edir = chisel.request_field("evt.dir")

    local filter = "evt.is_io=true and fd.type=ipv4"

    if port ~= nil and port ~= 0 then
        filter = filter .. " and fd.port=" .. port
    end

    if ip ~= nil and ip ~= "" then
        filter = filter .. " and fd.ip=" .. ip
    end

    chisel.set_filter(filter)
	return true
end

-- Final chisel initialization
function on_capture_start()
	chisel.set_interval_ns(refresh_time)
	return true
end

function update_frequency(pid, fdnum, etype, etime, edir)
    if time_map[pid] ~= nil and time_map[pid][fdnum] ~= nil then
        local llatency = math.log10(time_map[pid][fdnum].stop - time_map[pid][fdnum].start)

        if(llatency > 11) then
            llatency = 11
        end

        local norm_llatency = math.floor(llatency * w / 11) + 1

        if time_map[pid][fdnum].freq_version ~= freq_version then
            time_map[pid][fdnum].freq_version = freq_version
        else
            if frequencies[time_map[pid][fdnum].platency] ~= nil then
                frequencies[time_map[pid][fdnum].platency] = frequencies[time_map[pid][fdnum].platency] - 1
            end
        end
        if frequencies[norm_llatency] == nil then
            frequencies[norm_llatency] = 1
        else
            frequencies[norm_llatency] = frequencies[norm_llatency] + 1
        end
        time_map[pid][fdnum].platency = norm_llatency
    end
end

-- Event parsing callback
function on_event()
    local pid = evt.field(field_pid)
    local fdnum = evt.field(field_fdnum)
    local etype = evt.field(field_etype)
    local etime = evt.field(field_etime)
    local edir = evt.field(field_edir)

    if  (direction == "out" and write_etypes[etype] == true and edir == ">") or
        (direction == "in" and read_etypes[etype] == true and edir == ">") then
            if time_map[pid] == nil then
                time_map[pid] = {}
            end

            if time_map[pid][fdnum] ~= nil then
                update_frequency(pid, fdnum, etype, etime, edir)

                time_map[pid][fdnum].platency = 0
                time_map[pid][fdnum].start = etime
                time_map[pid][fdnum].stop = etime
            else
                time_map[pid][fdnum] = {
                    start = etime,
                    stop = etime,
                    platency = 0,
                    freq_version = freq_version
                }
            end
    elseif  (direction == "out" and read_etypes[etype] == true and edir == "<") or
            (direction == "in" and write_etypes[etype] == true and edir == "<") then
            if time_map[pid] ~= nil and time_map[pid][fdnum] ~= nil then
                update_frequency(pid, fdnum, etype, etime, edir)

                time_map[pid][fdnum].stop = etime
            end
    end

    return true
end

function mkcol(n)
	local col = math.floor(math.log10(n * refresh_per_sec + 1) / math.log10(1.6))

	if col < 1 then
		col = 1
	end

	if col > #colpalette then
		col = #colpalette
	end

	return colpalette[col]
end

-- Periodic timeout callback
function on_interval(ts_s, ts_ns, delta)
	terminal.moveup(1)

	for x = 1, w do
		local fr = frequencies[x]
		if fr == nil or fr == 0 then
			terminal.setbgcol(0)
		else
			terminal.setbgcol(mkcol(fr))
		end

		io.write(" ")
	end

	io.write(terminal.reset .. "\n")

	local x = 0
	while true do
		if x >= w then
			break
		end

		local curtime = math.floor(x * 11 / w)
		local prevtime = math.floor((x - 1) * 11 / w)

		if curtime ~= prevtime then
			io.write("|")
			local tstr = format_time_interval(math.pow(10, curtime))
			io.write(tstr)
			x = x + #tstr + 1
		else
			io.write(" ")
			x = x + 1
		end
	end

	io.write("\n")

	frequencies = {}
    freq_version = ts_ns

	return true
end

-- Called by the engine at the end of the capture (Ctrl-C)
function on_capture_end(ts_s, ts_ns, delta)
	if is_tty then
		-- Include the last sample
		on_interval(ts_s, ts_ns, 0)

		-- reset the terminal
		print(terminal.reset)
		terminal.showcursor()
	end

	return true
end
