-- node_distance_hud: HUD distance + /distance on|off/<range>
-- MIT License

local hud_ids = {}
local enabled_map = {}
local range_map = {}         -- portée personnalisée par joueur (m)
local timer = 0

local UPDATE_INTERVAL   = 0.10       -- ~10 Hz
local DEFAULT_RANGE     = 12         -- si l'objet tenu n'a pas de 'range'
local HUD_COLOR         = 0xFFFFFF   -- blanc
local DEFAULT_ENABLED   = true       -- HUD actif par défaut
local MAX_RANGE         = 200        -- sécurité: portée max autorisée

-- Utilitaires -----------------------------------------------------------------

local function get_eye_pos(player)
    local p = vector.copy(player:get_pos())
    local props = player:get_properties() or {}
    local eye_height = props.eye_height or 1.47
    p.y = p.y + eye_height
    return p
end

local function set_enabled(player, enable)
    local name = player:get_player_name()
    enabled_map[name] = not not enable
    player:get_meta():set_string("node_distance_hud_enabled", enable and "1" or "0")
    local id = hud_ids[name]
    if id and not enable then
        player:hud_change(id, "text", "")
    end
end

local function get_enabled(player)
    local name = player:get_player_name()
    local cached = enabled_map[name]
    if cached ~= nil then return cached end
    local s = player:get_meta():get_string("node_distance_hud_enabled")
    if s == "" then
        set_enabled(player, DEFAULT_ENABLED)
        return DEFAULT_ENABLED
    end
    local enable = (s == "1" or s == "true")
    enabled_map[name] = enable
    return enable
end

local function set_range(player, r)
    local name = player:get_player_name()
    -- clamp et normalisation
    r = math.max(0.5, math.min(MAX_RANGE, r))
    range_map[name] = r
    player:get_meta():set_string("node_distance_hud_range", tostring(r))
    return r
end

local function get_custom_range(player)
    local name = player:get_player_name()
    local cached = range_map[name]
    if cached ~= nil then return cached end
    local s = player:get_meta():get_string("node_distance_hud_range")
    if s ~= "" then
        local r = tonumber(s)
        if r and r > 0 then
            range_map[name] = r
            return r
        end
    end
    return nil
end

local function get_effective_range(player)
    local r = get_custom_range(player)
    if r then return r end
    local def = player:get_wielded_item():get_definition() or {}
    return def.range or DEFAULT_RANGE
end

-- HUD -------------------------------------------------------------------------

minetest.register_on_joinplayer(function(player)
    local id = player:hud_add({
        hud_elem_type = "text",
        position      = { x = 0.5, y = 0.5 },
        offset        = { x = 0, y = 24 },   -- juste sous la croix
        text          = "",
        alignment     = { x = 0, y = 0 },
        number        = HUD_COLOR,
        scale         = { x = 100, y = 20 },
        z_index       = 100,
    })
    hud_ids[player:get_player_name()] = id
    -- initialise caches depuis les metas
    get_enabled(player)
    get_custom_range(player)
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    hud_ids[name] = nil
    enabled_map[name] = nil
    range_map[name] = nil
end)

-- Boucle principale -----------------------------------------------------------

minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local hud_id = hud_ids[name]
        if not hud_id then goto continue end

        if not get_enabled(player) then
            player:hud_change(hud_id, "text", "")
            goto continue
        end

        local eye_pos = get_eye_pos(player)
        local dir = player:get_look_dir()
        local range = get_effective_range(player)
        local end_pos = vector.add(eye_pos, vector.multiply(dir, range))

        -- Raycast: nodes uniquement (ignorer objets), liquides inclus
        local ray = minetest.raycast(eye_pos, end_pos, false, true)

        local shown_text = ""
        for pointed in ray do
            if pointed.type == "node" then
                local hitpos = pointed.intersection_point
                if not hitpos and pointed.under then
                    hitpos = vector.add(pointed.under, { x = 0.5, y = 0.5, z = 0.5 })
                end
                if hitpos then
                    local dist = vector.distance(eye_pos, hitpos)
                    shown_text = string.format("%.1f m", dist)
                end
                break
            end
        end

        player:hud_change(hud_id, "text", shown_text)
        ::continue::
    end
end)

-- Commande /distance on|off|<range> ------------------------------------------

minetest.register_chatcommand("distance", {
    params = "<on|off|<range>>",
    description = "Active/désactive le HUD ou règle la portée en mètres",
    privs = {},  -- accessible à tous
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Joueur introuvable." end

        param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local lower = param:lower()

        if lower == "" then
            local enabled = get_enabled(player)
            local custom = get_custom_range(player)
            local eff = get_effective_range(player)
            if enabled then
                if custom then
                    return true, string.format("HUD actif. Portée: %.1f m (personnalisée).", eff)
                else
                    return true, string.format("HUD actif. Portée: %.1f m (outil ou défaut).", eff)
                end
            else
                return true, "HUD inactif. Utilise /distance on pour activer."
            end
        elseif lower == "on" then
            set_enabled(player, true)
            return true, "Distance HUD activée."
        elseif lower == "off" then
            set_enabled(player, false)
            return true, "Distance HUD désactivée."
        else
            local val = tonumber(param)
            if val and val > 0 then
                local r = set_range(player, val)
                return true, string.format("Portée du HUD réglée à %.1f m (prioritaire sur la portée de l'objet).", r)
            else
                return false, "Valeur invalide. Usage: /distance on|off|<portée en mètres>"
            end
        end
    end
})

