-- node_distance_hud: HUD distance + type de node + /distance on|off/<range> + /distance name on|off/toggle
-- MIT License

local hud_ids = { dist = {}, node = {} }
local enabled_map = {}
local range_map = {}          -- portée personnalisée par joueur (m)
local show_name_map = {}      -- afficher la 2e ligne (nom/description du node)
local timer = 0

local UPDATE_INTERVAL   = 0.10       -- ~10 Hz
local DEFAULT_RANGE     = 12         -- si l'objet tenu n'a pas de 'range'
local HUD_COLOR         = 0xFFFFFF   -- blanc
local DEFAULT_ENABLED   = true       -- HUD actif par défaut
local DEFAULT_SHOW_NAME = true       -- nom du node affiché par défaut
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
    local idd, idn = hud_ids.dist[name], hud_ids.node[name]
    if (idd or idn) and not enable then
        if idd then player:hud_change(idd, "text", "") end
        if idn then player:hud_change(idn, "text", "") end
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

local function set_show_name(player, show)
    local name = player:get_player_name()
    show_name_map[name] = not not show
    player:get_meta():set_string("node_distance_hud_showname", show and "1" or "0")
    if not show then
        local idn = hud_ids.node[name]
        if idn then player:hud_change(idn, "text", "") end
    end
end

local function get_show_name(player)
    local name = player:get_player_name()
    local cached = show_name_map[name]
    if cached ~= nil then return cached end
    local s = player:get_meta():get_string("node_distance_hud_showname")
    if s == "" then
        set_show_name(player, DEFAULT_SHOW_NAME)
        return DEFAULT_SHOW_NAME
    end
    local show = (s == "1" or s == "true")
    show_name_map[name] = show
    return show
end

-- HUD -------------------------------------------------------------------------

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()

    -- Ligne 1 : distance
    local id_dist = player:hud_add({
        hud_elem_type = "text",
        position      = { x = 0.5, y = 0.5 },
        offset        = { x = 0, y = 24 },   -- juste sous la croix
        text          = "",
        alignment     = { x = 0, y = 0 },
        number        = HUD_COLOR,
        scale         = { x = 100, y = 20 },
        z_index       = 100,
    })
    hud_ids.dist[name] = id_dist

    -- Ligne 2 : type de node
    local id_node = player:hud_add({
        hud_elem_type = "text",
        position      = { x = 0.5, y = 0.5 },
        offset        = { x = 0, y = 42 },   -- sous la distance
        text          = "",
        alignment     = { x = 0, y = 0 },
        number        = HUD_COLOR,
        scale         = { x = 100, y = 20 },
        z_index       = 100,
    })
    hud_ids.node[name] = id_node

    -- initialise caches depuis les metas
    get_enabled(player)
    get_custom_range(player)
    get_show_name(player)
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    hud_ids.dist[name] = nil
    hud_ids.node[name] = nil
    enabled_map[name] = nil
    range_map[name] = nil
    show_name_map[name] = nil
end)

-- Boucle principale -----------------------------------------------------------

minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local idd = hud_ids.dist[name]
        local idn = hud_ids.node[name]
        if not (idd and idn) then goto continue end

        if not get_enabled(player) then
            player:hud_change(idd, "text", "")
            player:hud_change(idn, "text", "")
            goto continue
        end

        local eye_pos = get_eye_pos(player)
        local dir = player:get_look_dir()
        local range = get_effective_range(player)
        local end_pos = vector.add(eye_pos, vector.multiply(dir, range))

        local ray = minetest.raycast(eye_pos, end_pos, false, true)

        local text_dist = ""
        local text_node = ""
        local want_name = get_show_name(player)

        for pointed in ray do
            if pointed.type == "node" then
                -- Distance
                local hitpos = pointed.intersection_point
                if not hitpos and pointed.under then
                    hitpos = vector.add(pointed.under, { x = 0.5, y = 0.5, z = 0.5 })
                end
                if hitpos then
                    local dist = vector.distance(eye_pos, hitpos)
                    text_dist = string.format("%.1f m", dist)
                end
                -- Nom/description si demandé
                if want_name and pointed.under then
                    local node = minetest.get_node_or_nil(pointed.under)
                    if node and node.name then
                        local def = minetest.registered_nodes[node.name]
                        local desc = def and def.description
                        if desc and desc ~= "" then
                            text_node = desc
                        else
                            text_node = node.name
                        end
                    end
                end
                break
            end
        end

        player:hud_change(idd, "text", text_dist)
        player:hud_change(idn, "text", want_name and text_node or "")
        ::continue::
    end
end)

-- Commande /distance ----------------------------------------------------------

minetest.register_chatcommand("distance", {
    params = "<on|off|<range>> | name [on|off]",
    description = "Active/désactive le HUD, règle la portée (m), ou affiche/masque le nom du node",
    privs = {},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Joueur introuvable." end

        param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local lower = param:lower()

        -- Sous-commande "name"
        if lower:sub(1, 4) == "name" then
            local arg = lower:sub(5):gsub("^%s+", "")
            if arg == "" or arg == "toggle" then
                local new = not get_show_name(player)
                set_show_name(player, new)
                return true, new and "Nom du node: affiché." or "Nom du node: masqué."
            elseif arg == "on" or arg == "show" then
                set_show_name(player, true)
                return true, "Nom du node: affiché."
            elseif arg == "off" or arg == "hide" then
                set_show_name(player, false)
                return true, "Nom du node: masqué."
            else
                return false, "Usage: /distance name [on|off] (ou sans argument pour basculer)"
            end
        end

        if lower == "" then
            local enabled = get_enabled(player)
            local custom = get_custom_range(player)
            local eff = get_effective_range(player)
            local name_flag = get_show_name(player) and "affiché" or "masqué"
            if enabled then
                if custom then
                    return true, string.format("HUD actif. Portée: %.1f m (personnalisée). Nom du node: %s.", eff, name_flag)
                else
                    return true, string.format("HUD actif. Portée: %.1f m (outil ou défaut). Nom du node: %s.", eff, name_flag)
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
                return false, "Valeur invalide. Usage: /distance on|off|<range> ou /distance name [on|off]"
            end
        end
    end
})

