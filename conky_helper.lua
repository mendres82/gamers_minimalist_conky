--[[
# Gamer's Minimalist Conky 1.55
# Author : mendres
# Release date : 5 May 2026
# Tested on : openSUSE Tumbleweed - GNOME Desktop
# Feel free to modify this script!
]]

local SENSORS_BIN = '/usr/bin/sensors'
local AMDGPU_TOP_PATH = '/tmp/amdgpu_top.tmp'
local AMDGPU_GPU_TOP_PATH = '/tmp/amdgpu_gpu_top.tmp'
local VERSION_ID_PATH = '/tmp/version_id.tmp'
local RESOLV_PATH = '/etc/resolv.conf'
local REFRESH_IN_SECONDS = 60

local last_sensors_refresh_second = -1
local last_periodic_refresh = 0

local function fopen(path)
    local file = io.open(path, 'r')
    if not file then
        return nil
    end
    local content = file:read('*a') or ''
    file:close()
    return content
end

local function popen(cmd)
    local process = io.popen(cmd)
    if not process then
        return ''
    end
    local output = process:read('*a') or ''
    process:close()
    return output
end

local function reader(data, field)
    return function()
        return data[field]
    end
end

local function trim(text)
    if not text then
        return ''
    end
    return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function unquote(text)
    text = trim(text or '')
    text = text:gsub('^"', '')
    text = text:gsub('"$', '')
    return trim(text)
end

local function join(fields)
    local field2, field3 = fields[2], fields[3]
    if not field2 then
        return ''
    end
    if field3 then
        return field2 .. ' ' .. field3
    end
    return field2
end

local function indexed(list, index)
    index = tonumber(index) or 1
    index = math.floor(index)
    if index < 1 then
        index = 1
    end
    local value = (type(list) == 'table') and list[index] or nil
    return value or ''
end

local version = {
    os_pretty_name = '',
    snapshot_version = '',
    latest_snapshot_version = '',
    is_latest_snapshot_version = '1',
}

local function version_refresh()
    version.os_pretty_name = ''
    version.snapshot_version = ''
    version.latest_snapshot_version = trim(fopen(VERSION_ID_PATH) or '')
    version.is_latest_snapshot_version = '1'

    local os_release = fopen('/etc/os-release')
    if os_release then
        for line in os_release:gmatch('[^\r\n]+') do
            local key, value = line:match('^%s*([%w_]+)%s*=%s*(.*)$')
            if key == 'PRETTY_NAME' and value then
                version.os_pretty_name = unquote(value)
            end
            if key == 'VERSION_ID' and value then
                local version_id_text = unquote(value)
                local snapshot_version = version_id_text:match('^(%d+)$')
                    or version_id_text:match('(%d+)')
                if snapshot_version then
                    version.snapshot_version = snapshot_version
                end
            end
            if version.os_pretty_name ~= '' and version.snapshot_version ~= '' then
                break
            end
        end
    end

    local snapshot_version = tonumber(version.snapshot_version)
    local latest_snapshot_version = tonumber(version.latest_snapshot_version)
    if snapshot_version and latest_snapshot_version then
        version.is_latest_snapshot_version = (snapshot_version >= latest_snapshot_version) and '1' or '0'
    end
end

local sensors = {
    tctl = '',
    junction = '',
    fan2 = '',
    fan1 = '',
    ppt = '',
    in0 = '',
    vddgfx = '',
    composite = '',
    cpu_temperature = nil,
    gpu_temperature = nil,
}

local function sensors_refresh()
    local current_second = os.time()
    if current_second == last_sensors_refresh_second then
        return
    end
    last_sensors_refresh_second = current_second

    sensors.tctl = ''
    sensors.junction = ''
    sensors.fan2 = ''
    sensors.fan1 = ''
    sensors.ppt = ''
    sensors.in0 = ''
    sensors.vddgfx = ''
    sensors.composite = ''
    sensors.cpu_temperature = nil
    sensors.gpu_temperature = nil

    local sensors_output = popen('LC_ALL=C.UTF-8 ' .. SENSORS_BIN .. ' 2>/dev/null')
    if sensors_output == '' then
        return
    end

    local fan1_count = 0
    for line in sensors_output:gmatch('[^\r\n]+') do
        local fields = {}
        for field in line:gmatch('%S+') do
            fields[#fields + 1] = field
        end
        local label = fields[1] or ''

        if label:match('^Tctl:?$') then
            sensors.tctl = fields[2] or ''
            sensors.cpu_temperature = fields[2] and tonumber(fields[2]:match('[+-]?%d+%.?%d*')) or nil
        elseif label:match('^junction:?') then
            sensors.junction = fields[2] or ''
            sensors.gpu_temperature = fields[2] and tonumber(fields[2]:match('[+-]?%d+%.?%d*')) or nil
        elseif label:match('^fan2:?') then
            sensors.fan2 = join(fields)
        elseif label:match('^fan1:?') then
            fan1_count = fan1_count + 1
            if fan1_count == 2 then
                sensors.fan1 = join(fields)
            end
        elseif label:match('^PPT:?') then
            sensors.ppt = join(fields)
        elseif label:match('^in0:?') and sensors.in0 == '' then
            sensors.in0 = join(fields)
        elseif label:match('^vddgfx:?') then
            sensors.vddgfx = join(fields)
        elseif label:match('^Composite:?') then
            sensors.composite = fields[2] or ''
        end
    end
end

function conky_sensors_graph_cpu()
    return sensors.cpu_temperature or 0
end

function conky_sensors_graph_gpu()
    return sensors.gpu_temperature or 0
end

local amdgpu = {
    core_ghz = '0.00',
    gpu_percent = '0',
    vram_ghz = '0.00',
    vram_usage_gib = '0.00',
    vram_percent = '0',
    gpu_bar = 0,
    vram_bar = 0,
}

local function amdgpu_refresh()
    amdgpu.core_ghz = '0.00'
    amdgpu.gpu_percent = '0'
    amdgpu.vram_ghz = '0.00'
    amdgpu.vram_usage_gib = '0.00'
    amdgpu.vram_percent = '0'
    amdgpu.gpu_bar = 0
    amdgpu.vram_bar = 0

    local line = fopen(AMDGPU_TOP_PATH)
    if not line then
        return
    end

    local gpu, vram_used, vram_total, sclk, mclk =
        line:match('^([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)')
    gpu, vram_used, vram_total, sclk, mclk =
        tonumber(gpu), tonumber(vram_used), tonumber(vram_total), tonumber(sclk), tonumber(mclk)
    -- gpu == 0 is valid (idle); only abort when the line did not parse
    if gpu == nil or vram_used == nil or vram_total == nil or sclk == nil or mclk == nil then
        return
    end

    amdgpu.gpu_percent = string.format('%.2f', gpu)
    amdgpu.gpu_bar = math.min(100, math.max(0, math.floor(gpu + 0.5)))
    amdgpu.vram_usage_gib = string.format('%.2f', vram_used / 1024)
    if vram_total > 0 then
        local vram_percent = (vram_used / vram_total) * 100
        amdgpu.vram_percent = string.format('%.0f', vram_percent)
        amdgpu.vram_bar = math.min(100, math.max(0, math.floor(vram_percent + 0.5)))
    end
    amdgpu.core_ghz = string.format('%.2f', sclk / 1000)
    amdgpu.vram_ghz = string.format('%.2f', mclk / 1000)
end

local gpu_top = {
    names = {},
    percents = {},
}

local TOP_NAME_WIDTH = 15

local function pad_top_name(name)
    if not name or name == '' then
        return ''
    end
    if #name > TOP_NAME_WIDTH then
        return name:sub(1, TOP_NAME_WIDTH)
    end
    return name .. string.rep(' ', TOP_NAME_WIDTH - #name)
end

local function gpu_top_refresh()
    gpu_top.names = {}
    gpu_top.percents = {}
    local content = fopen(AMDGPU_GPU_TOP_PATH) or ''
    for line in content:gmatch('[^\r\n]+') do
        local name, value = line:match('^([^\t]+)\t(.*)$')
        local percent = tonumber(value)
        if name and percent ~= nil then
            gpu_top.names[#gpu_top.names + 1] = pad_top_name(name)
            -- Match ${top cpu}: fixed-width, 2 decimals
            gpu_top.percents[#gpu_top.percents + 1] = string.format('%6.2f%%', percent)
        end
    end
end

function conky_gpu_top_name(index)
    return indexed(gpu_top.names, index)
end

function conky_gpu_top_percent(index)
    return indexed(gpu_top.percents, index)
end

local network = {
    ipv4s = {},
    ipv4_count = '0',
    ula6 = '',
    global_ipv6 = '',
    gateway1 = '',
    gateway2 = '',
    default_route_count = '0',
    dns = {},
    dns_count = '0',
    dns_domain = '',
}

local function ipv6_is_ula(ip)
    ip = trim((ip or '')):lower()
    local hextet = ip:match('^([0-9a-f]+):')
    if not hextet then
        return false
    end
    local n = tonumber(hextet, 16)
    return n ~= nil and n >= 0xfc00 and n <= 0xfdff -- fc00::/7
end

local function network_refresh()
    network.ipv4s = {}
    network.ipv4_count = '0'
    network.ula6 = ''
    network.global_ipv6 = ''
    network.gateway1 = ''
    network.gateway2 = ''
    network.default_route_count = '0'
    network.dns = {}
    network.dns_count = '0'
    network.dns_domain = ''

    local ipv4s = popen('LC_ALL=C ip -o -4 addr 2>/dev/null')
    local ipv6s = popen('LC_ALL=C ip -o -6 addr 2>/dev/null')
    local route = popen('LC_ALL=C ip route 2>/dev/null')

    local seen_ipv4 = {}
    for line in ipv4s:gmatch('[^\r\n]+') do
        local iface, ipv4 = line:match('^%d+:%s+(%S+)%s+inet%s+([%d%.]+)/')
        if iface and ipv4 and iface ~= 'lo' and not seen_ipv4[ipv4] then
            seen_ipv4[ipv4] = true
            network.ipv4s[#network.ipv4s + 1] = ipv4
        end
    end
    network.ipv4_count = tostring(#network.ipv4s)

    for line in ipv6s:gmatch('[^\r\n]+') do
        local has_mngtmpaddr = line:find('mngtmpaddr', 1, true) ~= nil
        if has_mngtmpaddr and line:find('scope%s+global') ~= nil then
            local ipv6 = line:match('inet6%s+([^%s]+)/')
            if ipv6 then
                if ipv6_is_ula(ipv6) then
                    if network.ula6 == '' then
                        network.ula6 = ipv6
                    end
                else
                    if network.global_ipv6 == ''
                        and line:find('deprecated', 1, true) == nil then
                        network.global_ipv6 = ipv6
                    end
                end
            end
        end
    end

    local gateways = {}
    for line in route:gmatch('[^\r\n]+') do
        local gateway = line:match('^default%s+via%s+(%S+)')
        if gateway then
            gateways[#gateways + 1] = gateway
        end
    end
    network.default_route_count = tostring(#gateways)
    network.gateway1 = gateways[1] or ''
    network.gateway2 = gateways[2] or ''

    local resolv = fopen(RESOLV_PATH) or ''
    local nameserver = {}
    for line in resolv:gmatch('[^\r\n]+') do
        local trimmed_line = trim(line)
        if trimmed_line ~= '' and not trimmed_line:match('^#') and not trimmed_line:match('^;') then
            local nameserver_entry = trimmed_line:match('^nameserver%s+(%S+)')
            if nameserver_entry then
                nameserver[#nameserver + 1] = nameserver_entry
            end
            if network.dns_domain == '' then
                local dns_domain_entry = trimmed_line:match('^search%s+(%S+)')
                if dns_domain_entry then
                    network.dns_domain = dns_domain_entry
                end
            end
        end
    end
    network.dns = nameserver
    network.dns_count = tostring(#nameserver)
end

function conky_network_ipv4(index)
    return indexed(network.ipv4s, index)
end

function conky_network_dns(index)
    return indexed(network.dns, index)
end

function conky_helper_refresh()
    sensors_refresh()
    amdgpu_refresh()
    gpu_top_refresh()
    local current_time = os.time()
    if last_periodic_refresh > 0 and (current_time - last_periodic_refresh) < REFRESH_IN_SECONDS then
        return
    end
    last_periodic_refresh = current_time
    version_refresh()
    network_refresh()
end

conky_os_pretty_name = reader(version, 'os_pretty_name')
conky_snapshot_version = reader(version, 'snapshot_version')
conky_is_latest_snapshot_version = reader(version, 'is_latest_snapshot_version')

conky_sensors_tctl = reader(sensors, 'tctl')
conky_sensors_junction = reader(sensors, 'junction')
conky_sensors_fan1 = reader(sensors, 'fan1')
conky_sensors_fan2 = reader(sensors, 'fan2')
conky_sensors_ppt = reader(sensors, 'ppt')
conky_sensors_in0 = reader(sensors, 'in0')
conky_sensors_vddgfx = reader(sensors, 'vddgfx')
conky_sensors_composite = reader(sensors, 'composite')

conky_radeon_core_ghz = reader(amdgpu, 'core_ghz')
conky_radeon_gpu_percent = reader(amdgpu, 'gpu_percent')
conky_radeon_gpu_bar = reader(amdgpu, 'gpu_bar')
conky_radeon_vram_ghz = reader(amdgpu, 'vram_ghz')
conky_radeon_vram_usage_gib = reader(amdgpu, 'vram_usage_gib')
conky_radeon_vram_percent = reader(amdgpu, 'vram_percent')
conky_radeon_vram_bar = reader(amdgpu, 'vram_bar')

conky_network_ula6 = reader(network, 'ula6')
conky_network_ipv4_count = reader(network, 'ipv4_count')
conky_network_global_ipv6 = reader(network, 'global_ipv6')
conky_network_gateway1 = reader(network, 'gateway1')
conky_network_gateway2 = reader(network, 'gateway2')
conky_network_default_route_count = reader(network, 'default_route_count')
conky_network_dns_count = reader(network, 'dns_count')
conky_network_dns_domain = reader(network, 'dns_domain')
