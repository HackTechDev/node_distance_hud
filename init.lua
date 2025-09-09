-- node_distance_hud: affiche la distance jusqu'au node visé
-- MIT License

local hud_ids = {}
local timer = 0
local UPDATE_INTERVAL = 0.10       -- secondes entre mises à jour (~10 Hz)
local DEFAULT_RANGE = 12           -- portée si l'objet tenu n'en définit pas
local HUD_COLOR = 0xFFFFFF         -- blanc

-- Ajoute un élément HUD à chaque joueur
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
end)

minetest.register_on_leaveplayer(function(player)
    hud_ids[player:get_player_name()] = nil
end)

-- Petite utilité: position de l’œil du joueur
local function get_eye_pos(player)
    local p = vector.copy(player:get_pos())
    local props = player:get_properties() or {}
    local eye_height = props.eye_height or 1.47
    p.y = p.y + eye_height
    return p
end

-- Boucle principale: calcule la distance vers le node visé et l'affiche
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < UPDATE_INTERVAL then return end
    timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local hud_id = hud_ids[name]
        if not hud_id then goto continue end

        -- Position/visée
        local eye_pos = get_eye_pos(player)
        local dir = player:get_look_dir()
        -- Portée: prend celle de l’objet tenu si dispo, sinon défaut
        local def = player:get_wielded_item():get_definition() or {}
        local range = def.range or DEFAULT_RANGE
        local end_pos = vector.add(eye_pos, vector.multiply(dir, range))

        -- Raycast: on ne vise que les nodes (pas les objets), liquides inclus
        local ray = minetest.raycast(eye_pos, end_pos, false, true)

        local shown_text = ""
        for pointed in ray do
            if pointed.type == "node" then
                -- Point d'intersection (précis) si dispo, sinon centre du node visé
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

        -- Met à jour/efface le HUD
        player:hud_change(hud_id, "text", shown_text)

        ::continue::
    end
end)

